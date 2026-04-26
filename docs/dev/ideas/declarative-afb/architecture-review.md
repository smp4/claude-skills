# Architecture Review: AFB architecture.md (rev 4)

> Date: 2026-04-26
> Reviewed by: Beck, Farley, Ford/Parsons, Kua lenses
> Feathers lens: limited applicability (greenfield, no legacy). Seam/testability observations folded into other sections.
> Scope: architecture.md only. No backwards-compatibility constraints.

---

## Beck Lens — Simple Design

### Findings

1. **Speculative generality — FS port** (lines 132-139): The `FS` interface wraps `os.ReadFile`, `os.WriteFile`, `os.MkdirAll`, etc. The stated purpose is unit testing with in-memory FS. But Go's `testing/fstest.MapFS` already exists for read paths, and composition logic that writes to disk can be tested by writing to `os.MkdirTemp` — no interface needed. An interface that mirrors the stdlib 1:1 is not an abstraction; it's a pass-through that adds indirection without reducing concepts.
   - **Suggestion**: Delete the `FS` port. Use `os` directly. Unit-test composition with temp dirs. If a genuine need for FS abstraction emerges (e.g., remote storage), add it then.

2. **Speculative generality — SyncCommand port** (lines 126-129): Two methods (`Run`, `Validate`) that shell out to a configurable command. The "swappability" is already achieved by the `[sync].command` config field — it's a string the user changes. The port interface adds a Go-level abstraction on top of a config-level abstraction. Both serve the same purpose.
   - **Suggestion**: Shell out to `[sync].command` directly. The port buys nothing that the config field doesn't already provide.

3. **Line-by-line Containerfile generation vs templates** (lines 356-357): "Generated line by line from parsed manifest data, not templated. This avoids template-language complexity." But the generated Containerfile (lines 311-354) is 90% static text with variable insertions. Line-by-line string concatenation in Go for a document that's inherently a template is more code, harder to read, and harder to maintain than a simple `text/template` with `{{.BaseImage}}` slots. The complexity being avoided is Go's stdlib.
   - **Suggestion**: Use `text/template` for Containerfile and compose.yaml generation. It's stdlib, zero dependencies, and the output format *is* a template.

4. **YAGNI — commands for v1** (lines 786-805): `afb push`, `afb shell`, `afb layer pull` — these are thin wrappers around `git push`, `podman exec -it`, and `git pull`. They add CLI surface area without adding value. A user who can run `afb build` can run `git push`. The architecture doc should distinguish v1 commands from future convenience commands.
   - **Suggestion**: Cut v1 CLI to: `init`, `sync`, `build`, `up`, `down`, `rebuild`, `doctor`, `diff`, `validate`, `run`, `lock`. Add wrappers later if users ask.
> COMMENT: disagree. afb push is a convenience, especially in early days when config, settings are going to be getting iterated upon quickly and often across layers. also git pull for each layer, after the clone, is tedious having to move between all layers and run git pull each time. nice just to have layer push and pull in one place. agree that perhaps afb shell could be deferred to next version - afb does not need to dsicover harnesses in first release.
5. **Good: opaque component model** (lines 599-612): Components as arbitrary named commands with only `install` required. Simplest thing that works. No type hierarchy, no plugin system.

6. **Good: variable expansion** (lines 626-635): Simple string substitution, no template language, no conditionals. Correct level of simplicity.

7. **Concern: afb.local.toml deep merge** (lines 614-620): Same merge rules as layers applied to user overrides. The typical use cases listed (mount_workspace, local paths) are all flat scalar overrides. Deep merge machinery is overkill. A simpler model — local.toml values override at the top-level key — would cover stated use cases with less complexity.
   - **Suggestion**: Start with shallow merge for local overrides. Add deep merge if real use cases demand it.

### Summary

The architecture mostly follows "simplest thing that could work" for domain logic (components, variables, composition), but adds structural complexity at the infrastructure layer (ports for FS and SyncCommand, line-by-line generation instead of templates) that doesn't pay for itself. Two of five ports are premature abstractions. The CLI surface area is larger than v1 needs justify.

---

## Farley Lens — Verification Architecture

### Findings

1. **No executable specification** (entire document): The architecture defines what AFB does but never states measurable acceptance criteria. What does "correct composition" mean? What constitutes a valid Containerfile? The test strategy (lines 907-948) describes *tiers* and *what's tested* but not *what correct behaviour looks like*. Without acceptance criteria, tests verify implementation, not specification.
   - **Suggestion**: Define acceptance criteria for the core operations: (a) composition with N layers produces expected file tree, (b) generated Containerfile builds successfully with podman AND docker, (c) generated compose.yaml passes `docker-compose config` validation, (d) `afb sync` is idempotent (running twice produces identical output).

2. **Verification bottleneck at E2E tier** (lines 936-948): The most critical question — "does the generated container actually work?" — is only answerable at the E2E tier, which requires a container runtime, is slow, and is recommended to run only on merge to main. This means the most important verification runs least often.
   - **Suggestion**: Add a mid-tier validation step: generated Containerfile is parsed by a Dockerfile linter (hadolint), generated compose.yaml is validated by `docker-compose config --quiet`. These run without a container runtime and catch structural errors at the unit/integration boundary.

3. **Deep merge is high-risk, test strategy is thin** (lines 749-756): The merge semantics table defines 4 rules. The test notes say "edge cases: nil vs empty maps, typed vs untyped interfaces, TOML's array/table-array types." This is the right list but it's a comment, not a test plan. mergo's behaviour with these cases is not documented — it must be characterized.
   - **Suggestion**: Write characterization tests for mergo with every combination: nil src + populated dst, empty map src + populated dst, TOML table-array + YAML array, mixed-type leaf conflicts. These are the tests that will prevent production bugs.

4. **Sync command tested by mocking** (lines 929-930): "Full sync workflow: parse -> clone -> compose -> validate (mock sync command)." The sync command IS the critical integration point — mocking it tests that AFB calls a function, not that the function produces correct output. The mock hides the most failure-prone boundary.
   - **Suggestion**: Integration tests must run real `lnai sync` (or the configured sync command). If lnai isn't available in CI, the test should be tagged and run in an environment that has it. The mock is useful for unit tests of AFB's orchestration logic, but an integration test that mocks the integration point isn't an integration test.

5. **No verification of Containerfile correctness short of building** (lines 907-920): Unit tests "generate Containerfile strings, assert content." String comparison is fragile — it tests formatting, not semantics. A Containerfile with a valid string representation can still fail to build.
   - **Suggestion**: See finding 2 — add hadolint or equivalent as a verification layer between string assertion and full container build.

6. **Good: three-tier structure** (lines 907-915): Unit/integration/E2E with clear boundaries, build tags, and CI matrix. The structure is sound; the gaps are in what's verified at each tier.

### Summary

The test *structure* is well-designed. The test *content* has gaps at the boundaries that matter most: deep merge edge cases, sync command integration, and Containerfile validity. The verification strategy over-relies on E2E tests for correctness that could be caught earlier and cheaper.

---

## Ford/Parsons Lens — Evolutionary Architecture

### Fitness Function Audit

| Characteristic           | Status     | Issue                                                                       |
| ------------------------ | ---------- | --------------------------------------------------------------------------- |
| Composition correctness  | Unmeasured | No threshold for "correct." No automated check beyond string diff           |
| Build time               | Unmeasured | "Image build time" listed as risk (line 1150) but no target, no measurement |
| Container startup time   | Unmeasured | Not mentioned                                                               |
| Drift detection accuracy | Unmeasured | afb diff exists but no fitness function for false positive/negative rate    |
| LNAI compatibility       | Unmeasured | No version compatibility matrix or automated check                          |
| Compose spec compliance  | Unmeasured | Generated compose.yaml assumed valid; no validation step in build pipeline  |

No architectural characteristic in this document has a measurable threshold, a measurement mechanism, or an owner. All are prose.

### Coupling Concerns

1. **`.ai/` directory format** (lines 59-67): AFB generates this format. LNAI reads it. The format is an implicit contract with no schema, no version, no compatibility check. If LNAI changes what it expects in `.ai/`, AFB breaks silently — composed output passes AFB's validation but fails at sync time. This coupling is not acknowledged in the architecture.
   - **Suggestion**: Define `.ai/` as an explicit, versioned contract. Even if just a comment in a file: `# .ai format v1`. Test LNAI's expectations as a characterization test.

2. **Compose spec version** (lines 363-395): Generated compose.yaml depends on Compose Specification v3 features (external networks, named volumes, build args). This is stable but not acknowledged as a coupling. Podman-compose's Compose spec support is incomplete — some v3 features work, some don't.
   - **Suggestion**: Add to ADR-015 (Podman preferred): explicitly state which Compose spec features are required and test both runtimes against them in CI.
> COMMENT: for v1, we only need to support podman. defer docker. 
3. **TOML manifest schema** (lines 487-597): No schema version field. No migration mechanism. Adding a field is backwards-compatible; renaming or removing one is not. As the tool evolves, manifest schema drift is inevitable.
   - **Suggestion**: Add `schema_version = 1` to afb.toml. Validate on parse. Enables future migration logic.

### Implicit Bets Extracted

| Bet                                    | Assumption                                                                | Reversibility                                                                 | Risk Level                                               |
| -------------------------------------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------- |
| TOML as manifest format                | TOML expressiveness sufficient for all manifest needs                     | Expensive (all manifests need migration)                                      | Low — TOML covers the use cases shown                    |
| Compose networking for MCP sharing     | Container networking sufficient for MCP transport at single-machine scale | Cheap (MCP servers can switch to host networking)                             | Low                                                      |
| Single-machine scale                   | 1-2 machines, 2-10 containers. No multi-machine orchestration needed      | Expensive (would require k8s or similar)                                      | Medium — explicitly deferred, but if wrong, major rework |
| Priority-based layer composition       | Integer priorities + deep merge is the right composition model            | Expensive (changes merge semantics, breaks all existing layer configurations) | Medium — no real-world validation yet                    |
| mergo handles all edge cases           | mergo's override semantics match AFB's stated merge rules                 | Cheap (replace mergo with custom merge)                                       | Medium — edge case risk is real (finding 3 in Farley)    |
| macOS container performance acceptable | Podman/Docker on macOS is fast enough for dev workflow                    | Cheap (heavy workloads on Linux, as noted)                                    | Low                                                      |
| AgentGateway stability                 | Linux Foundation backing = maintained                                     | Cheap (fallback to in-container stdio)                                        | Low                                                      |
| `.ai/` format stability                | LNAI won't change expected `.ai/` directory structure                     | Expensive (AFB's composition output must change)                              | Medium-High — 239-star project, breaking changes likely  |

### Evolution Blockers

1. **`.ai/` directory format is unversioned** (lines 59-67): This is the primary integration surface between AFB and LNAI. Not versioned, not schema'd, not tested as a contract. When LNAI changes, AFB's composition output becomes wrong with no detection mechanism. This is the single highest-risk coupling in the system.
   - Cost to address now: low (add format marker + characterization test)
   - Cost to address later: high (debug mysterious sync failures)
> COMMENT: fix it
2. **afb.toml has no schema version** (lines 487-597): Schema changes will happen. Without a version field, AFB can't distinguish between "old manifest, needs migration" and "malformed manifest."
   - Cost to address now: trivial (one field)
   - Cost to address later: moderate (retroactive migration without version indicator)
> COMMENT: fix it
3. **No mechanism to pin compose spec features**: Podman-compose and docker-compose have different Compose spec support levels. Generated compose.yaml may use features that work in one but not the other. The CI matrix tests both runtimes but doesn't test *which spec features* are used.
   - Cost to address now: low (document required features, add compose config validation to build)
   - Cost to address later: moderate (debug runtime-specific failures)
> COMMENT: address now
### Missing Fitness Criteria

- **Testability**: mentioned in test strategy but no fitness function (e.g., "unit tests run in < 5s", "no test requires container runtime except E2E tier")
- **Build reproducibility**: lockfile exists but no fitness function verifying that same lockfile + same manifest = same image digest
- **Composition idempotency**: no fitness function verifying `afb sync` twice = same output
> COMMENT: add the criteria
### Summary Verdict

The architecture is reasonably evolvable at the port/adapter level — swapping container runtimes or sync commands is cheap. The dangerous coupling is at the format level: `.ai/` directory structure and afb.toml schema are unversioned implicit contracts. These are the surfaces most likely to break and hardest to debug. Adding version markers and characterization tests is low-cost now and high-value later.

---

## Kua Lens — Decision Quality

### Decision Inventory

| Decision                                     | Explicit?    | Reversibility                                     | ADR?    | Quality                                                                          |
| -------------------------------------------- | ------------ | ------------------------------------------------- | ------- | -------------------------------------------------------------------------------- |
| Go language                                  | Yes          | Effectively irreversible                          | ADR-001 | Good — alternatives considered, rationale clear                                  |
| LNAI for config translation                  | Yes          | Cheap (configurable command)                      | ADR-002 | Good — alternatives considered, supersedes prior work                            |
| Clone layers to gitignored dir               | Yes          | Cheap                                             | ADR-003 | Good                                                                             |
| mergo for deep merge                         | Yes          | Cheap                                             | ADR-004 | Thin — no alternatives text beyond "custom merge code"                           |
| Shell out to git                             | Yes          | Cheap                                             | ADR-005 | Adequate but terse                                                               |
| Array replace default                        | Yes          | Expensive (changes merge semantics for all users) | ADR-006 | Missing: what problems does this create? When would you reconsider?              |
| Container-first isolation                    | Yes          | Expensive                                         | ADR-007 | Good — has revision history, supersedes prior design                             |
| .afb/project/ as authored config             | Yes          | Cheap                                             | ADR-008 | Adequate                                                                         |
| Integer priority ordering                    | Yes          | Expensive (all manifests use priorities)          | ADR-009 | Missing: alternatives considered (directory ordering, explicit dependency graph) |
| Opaque component model                       | Yes          | Cheap                                             | ADR-010 | Good — has revision history                                                      |
| Structured logging                           | Yes          | Cheap                                             | ADR-011 | Adequate                                                                         |
| Configurable sync command                    | Yes          | Cheap                                             | ADR-012 | Good                                                                             |
| No Temporal/Redis/ChromaDB                   | Yes          | Cheap                                             | ADR-013 | Good                                                                             |
| Generate + delegate to compose               | Yes          | Cheap                                             | ADR-014 | Good                                                                             |
| Podman preferred, Docker compatible          | Yes          | Cheap                                             | ADR-015 | Good                                                                             |
| No Kubernetes                                | Yes          | Expensive if wrong                                | ADR-016 | Adequate but thin — "sufficient" isn't analysis                                  |
| AgentGateway                                 | Yes          | Cheap                                             | ADR-017 | Good — comparison table                                                          |
| Ports & Adapters                             | Yes          | Cheap                                             | ADR-018 | Good                                                                             |
| No uninstall command                         | Yes          | Cheap                                             | ADR-019 | Good                                                                             |
| Composable component commands                | Yes          | Cheap                                             | ADR-020 | Good                                                                             |
| afb doctor replaces status/health            | Yes          | Cheap                                             | ADR-021 | Good                                                                             |
| extra_packages + extra_run                   | Yes          | Cheap                                             | ADR-022 | Good — comparison table                                                          |
| Compose project naming                       | Yes          | Cheap                                             | ADR-023 | Adequate                                                                         |
| **TOML as manifest format**                  | **Implicit** | Expensive                                         | **No**  | **Missing — format choice undocumented**                                         |
| **`.ai/` directory structure**               | **Implicit** | Expensive                                         | **No**  | **Missing — primary integration contract**                                       |
| **afb.toml schema (no versioning)**          | **Implicit** | Moderate                                          | **No**  | **Missing — version field not considered**                                       |
| **text/template vs line-by-line generation** | **Implicit** | Cheap                                             | **No**  | **Stated in prose, not as a decision**                                           |

### Reversibility Flags

- **ADR-006 (array replace)**: Classified implicitly as cheap. Actually expensive — every layer configuration depends on this semantic. Changing it after real users have layers = breaking change.
- **ADR-009 (integer priority)**: Classified implicitly as cheap. Actually expensive — all manifests and documentation assume numeric priority ordering.
- **TOML manifest format**: Not classified at all. Effectively irreversible once users have manifests.

### Context Gaps

- **ADR-004 (mergo)**: "Eliminates external tool dependencies and custom merge code" — but what were the specific alternatives? Why not Go maps + custom 30-line recursive merge? What does mergo buy that custom code doesn't?
- **ADR-009 (integer priority)**: No alternatives listed. Directory-name alphabetical ordering? Explicit dependency declarations? Why integers specifically?
- **ADR-016 (no k8s)**: "Sufficient" is a claim, not analysis. Sufficient for what? What would trigger reconsideration?

### Deferral Attractors

| Deferred Decision                     | Trigger Specified? | Risk                                                                       |
| ------------------------------------- | ------------------ | -------------------------------------------------------------------------- |
| Shared services management (UQ 1)     | No                 | Low — convention works until it doesn't                                    |
| Per-file merge strategy (UQ 2)        | No                 | Medium — users will hit this; when they do, what's the escalation path?    |
| SPC metrics (UQ 3)                    | No                 | Low — nice to have                                                         |
| AgentGateway config generation (UQ 4) | No                 | Medium — needed before anyone uses shared MCP servers                      |
| afb.local.toml edge cases (UQ 5)      | No                 | Medium — deep merge of local overrides has real ambiguity                  |
| Gas City overlap (future work table)  | "Phase 3"          | Medium — if Gas City subsumes layer config, AFB's composition is redundant |

None of the five unresolved questions have triggers. "Phase 3" is a sequence label, not a trigger event. These will drift indefinitely without explicit conditions for revisiting.

### Technology Radar Gaps

| Technology     | Radar Position                             | Assessment                                                                                                      |
| -------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| LNAI           | Assess (239 stars, few maintainers)        | Acknowledged as risk, mitigated by configurable command. Position should be explicit.                           |
| AgentGateway   | Trial (v1.0, Linux Foundation, 2.3k stars) | Good assessment in ADR-017.                                                                                     |
| mergo          | Adopt (9k+ stars, mature)                  | No assessment. Stars != quality for a merge library — edge case behaviour matters more than popularity.         |
| podman-compose | Trial (less mature than docker-compose)    | Acknowledged in risks table but not assessed as a technology bet. Compose spec support gaps are a real concern. |

### Priority Actions

1. **Write ADR for TOML manifest format choice** — this is effectively irreversible and undocumented.
2. **Add `schema_version` to afb.toml** — trivial now, painful to retrofit.
3. **Define `.ai/` directory format as explicit contract** — primary integration surface, currently implicit.
4. **Add review triggers to all deferred decisions** — convert "unresolved questions" into "deferred with trigger."
5. **Reclassify ADR-006 and ADR-009 reversibility** — both are more expensive to reverse than currently acknowledged.
> COMMENT: do all this
---

## Cross-Lens Observations

### Agreements across lenses

All lenses flag the **`.ai/` directory format** as a gap — Beck sees an implicit contract that should be explicit, Farley sees an untested integration boundary, Ford/Parsons sees an evolution blocker, Kua sees a missing ADR.

All lenses agree the **deep merge semantics are high-risk** — Beck questions whether full deep merge is needed for local overrides, Farley wants characterization tests, Ford/Parsons flags mergo as an implicit bet.

### Tensions between lenses

- **Beck says delete the FS and SyncCommand ports; Ford/Parsons values the evolvability they provide.** Resolution: Beck wins for v1. Ports can be added when a second implementation exists. Go interfaces are cheap to introduce later.
> COMMENT: agree
- **Beck says cut CLI commands for v1; Kua wants all commands documented as decisions.** Resolution: both are right. Cut the commands AND document why they were deferred.
> COMMENT: ok, see also the relevant comment above
### Top 5 actions before implementation

1. Add `schema_version = 1` to afb.toml spec
2. Define `.ai/` directory format as versioned contract + write characterization tests against LNAI's expectations
3. Write mergo characterization tests for all stated edge cases before writing composition logic
4. Use `text/template` for Containerfile and compose.yaml generation (simpler than line-by-line)
5. Cut v1 CLI to essential commands; defer `push`, `shell`, `layer pull` with explicit triggers

### Unresolved questions from review

- Line-by-line Containerfile gen: has this been prototyped? How many LOC vs a template approach?
> COMMENT: have not prototyped it. are there other (established, mature) projects that generate a containerfile from a higher level abstraction manifest/ similar file? how do they do the generation? we dont need to re-invent the wheel, we can steal ideas from known good solutions. 
- mergo edge cases: has TOML table-array + mergo been tested at all? mergo docs say nothing about TOML-specific types.
> COMMENT: not tested at all. investigate if it is actually useful for toml. if not, we need to use yaml? (toml preferred, but simplicity and speed to a solution is more valuable in v1)
- `.ai/` format: does LNAI document what it expects, or is the format only discoverable by running it?
> COMMENT: see the docs https://lnai.sh/getting-started/introduction/ and source code https://github.com/KrystianJonca/lnai
- Compose spec: which specific v3 features does the generated compose.yaml require? Has podman-compose been tested with external networks + named volumes?
> COMMENT: not tested. is there a compose spec that has max known compatibility between podman and docker? i cant imagine we need exotic features for our solutions here. and if we just go with v3, and find problems, we can always switch to docker instead of problem quite quickly i assume. 
- Priority integers: what happens on priority collision? Error? Undefined order? Not specified.
> COMMENT: this should be caught by a manifest lint/ validation step, throw error to user before proceeding.
