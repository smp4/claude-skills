# Plan Review: AFB Implementation Plan — 2026-04-27

## Reviewer Panel

| Reviewer | Persona        | Dimension                                                                 |
| -------- | -------------- | ------------------------------------------------------------------------- |
| A        | Ford + Parsons | Evolvability, fitness functions, implicit bets                            |
| B        | Kua            | Decision reversibility, ADR quality, deferral attractors                  |
| C        | Farley         | Releasability, pipeline assumptions, ATDD integrity, DSL-domain alignment |
| D        | Feathers       | Testability, seam quality, DSL-domain consistency                         |

---

## Findings by Reviewer

### Reviewer A — Ford/Parsons: Evolvability

#### Fitness Function Audit

| Characteristic                 | Status         | Issue                                                                                                                                                                                                        |
| ------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Composition idempotency        | measurable     | SHA-256 per-file in CI (ADR-028). Byte-identical threshold. CI-enforced. Solid.                                                                                                                              |
| Containerfile validity         | measurable     | hadolint, zero errors, CI-enforced.                                                                                                                                                                          |
| Compose spec validity          | measurable     | `podman-compose config --quiet`, exit 0, CI-enforced.                                                                                                                                                        |
| Unit test speed                | measurable     | < 5s threshold, `time` wrapper in CI.                                                                                                                                                                        |
| Tier isolation (domain purity) | measurable     | grep for `os/exec` in `internal/domain/` + container image check.                                                                                                                                            |
| Sync idempotency               | measurable     | CI runs sync twice.                                                                                                                                                                                          |
| Build reproducibility          | **unmeasured** | Flagged as "aspirational" in risk register. Listed as acceptance criterion but has no enforcement mechanism. A fitness function ghost — appears as pass/fail but will not actually fail CI.                  |
| `.ai/` format contract         | **vague**      | Unit 5.5 characterization test passes if `lnai sync` exits 0. No assertion on what format version means structurally, no backward compatibility check. LNAI may degrade gracefully through breaking changes. |
| Layer merge correctness        | **vague**      | Golden files in unit tier against synthetic fixtures only. No corpus-based fitness function. Mergo spike is one-time, not a blocking CI gate.                                                                |
| CLI startup time               | **unmeasured** | NFR4 says "seconds" — no measurement, no threshold, no CI enforcement.                                                                                                                                       |
| Cross-machine reproducibility  | **unmeasured** | Key use case (Mac + Linux). Acknowledged aspirational. No fitness function.                                                                                                                                  |

> COMMENT: Defer build reproducibility as acceptance criteria. put it in future work list. 
> COMMENT: How to solve the .ai/ format contract vagueness? i think this is fine for now, we just need to start prototyping. 
> COMMENT: defer CLI startup time as a fitness function to future work list. defer cross-machine reproduceability fitness function to future work list. 

#### Coupling Concerns

- **LNAI version pinning absent**: `lnai sync` is called in Unit 5.5 with no version pin. LNAI upgrading in CI can silently change what the characterization test certifies. The single-command abstraction gives runtime swappability but no protection against contract erosion in CI.
> COMMENT: i realise lnai is just another component, but we treat it as a core dependency. would have been more consistent to extract it as a component. add this to the future work list. for now, let's pin LNAI version. when afb uses lnai functions, it should first call its version and make sure it matches the expected number. 
- **Sync command and drift detection are tightly coupled**: `afb diff` Stage 2 (Unit 8.2) runs the sync command in a temp HOME to derive expected runtime state. The diff result is a function of sync command version and behavior. If LNAI is upgraded, the diff baseline changes silently. The plan treats this as "sync-command-agnostic" but it is actually sync-command-version-coupled. Unacknowledged.
> COMMENT: then acknowledge it. is this a risk?
- **`RUN afb sync` bootstrap coupling**: The Containerfile bakes in `RUN afb sync`, which runs the version of AFB installed inside the container. That version must be schema-compatible with the manifest it finds. If AFB gains a new manifest field, the version inside the container must be updated first or the build fails. No versioning policy or compatibility check exists. **Highest-priority unresolved concern.**
> COMMENT: afb.toml must have a schema version field, and each release of afb must know with which schema versions it is compatible with. if it finds a schema version it is not cmpatible with, it shall issue an error to the user, stating that the afb version must be updated, and to check the schema version definition in the manifest file.
- **podman-compose version not pinned**: `podman-compose config` validates spec compliance but not behavioral compatibility. Minor podman-compose releases can change behavior for used features while passing the config check. Partially acknowledged, version-pinning gap is not resolved.
> COMMENT: Then resolve the version pin gap, update architecture.md and plan.md as needed. shall we add a requirement to spec.md that afb dependencies need to be version pinned?
- **mergo pin exists but no upgrade policy**: characterization tests will catch a version bump regression, but there is no policy preventing `go get -u` from bumping the pin.
> COMMENT: Fix it
- **`.ai-format-version` is write-only**: AFB writes it; nothing reads and acts on it. The contract is versioned in name only — no consumer rejects an incompatible version.
> COMMENT: what should consume it? or shall we just remove this feature?
#### Implicit Bets Extracted

| Bet                                          | Assumption                                                                                              | Reversibility                                                 | Risk Level         |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------ |
| LNAI stays alive and compatible              | 239-star project will not break `.ai/` contract across plan timeline                                    | Cheap to swap command; expensive if format diverges           | **High**           |
| podman-compose feature-stable                | Feature subset (external networks, stdin_open/tty) behaves consistently across versions without pinning | Medium — needs version pin                                    | **Medium**         |
| `RUN afb sync` is self-consistent            | AFB version inside container always compatible with manifest                                            | Expensive — requires versioning policy + compatibility matrix | **High**           |
| Array-replace default universally understood | All layer authors understand replace-not-extend; `merge_arrays=append` escape hatch not overused        | Expensive to reverse (ADR-006 self-acknowledges)              | **Medium**         |
| mergo characterization is one-time           | Spike result is durable given locked version                                                            | Cheap — re-run if version bumped                              | Low                |
| Solo dev scale is permanent                  | Atomic `.ai/` replace, no incremental composition, no caching — sized for 1-2 devs                      | Expensive — composition algorithm baked in                    | Low (stated scope) |
| `.ai/` is the only integration contract      | LNAI needs no additional inputs beyond `.ai/`                                                           | Cheap if true; expensive if LNAI requires side inputs         | Low                |
| Gas City will not conflict with AFB layers   | Gas City pack system and AFB layer system write to different namespaces                                 | Unknown — flagged as "Unknown" in risk register               | **Medium**         |

#### Evolution Blockers

- **Atomic `.ai/` replacement prevents incremental optimisation**: Full delete-and-replace on every sync. Every future optimisation (incremental composition, caching, parallel layer processing) requires redesigning the core algorithm and all related tests. Cost to address now: document the invariant explicitly. Cost later: high-friction refactor against real user layer repos.
> COMMENT: I dont understand the cause and effect or nature of this problem. explain it to me.
- **Containerfile template will resist change**: Single-stage template with growing conditionals (`RUN afb sync`, workspace mount, base image type). Each addition adds template complexity testable only via golden file. In 12-24 months this template becomes a maintenance liability unless decomposed into composable sub-templates.
> COMMENT: Defer solution to this to v2. put it in future work list
- **Shallow merge for `afb.local.toml` is a backward-compatibility commitment, not a deferral**: If a user overrides one field in `afb.local.toml`, they must reproduce the entire section. When the base manifest adds new fields, local overrides silently drop them. By the time "real use cases demand deep merge," users already have shallow-merge-dependent files. This is irreversible behavior being called a deferral.
> COMMENT: we just want the simplest approach for first dogfooding. can improfe in v2. add to future work list.
- **No schema migration path**: `schema_version = 1` is validated but there is no `afb migrate`, no reader that upgrades v1 manifests. First breaking schema change requires all existing manifests to be manually updated. Low risk solo; blocks any sharing.
> COMMENT: add migration to v2. for the moment, we will only have one final schema version by the time we make the first prototpye list. add afb migrate to future work list.
- **LNAI characterization test is not a blocking gate**: Unit 5.5 checks `lnai sync` exit code without a pinned LNAI version. This is the primary mechanism against contract drift, and it does not actually enforce the contract it is designed to protect.
> COMMENT: related comment above, fix it.
#### Missing Fitness Criteria

- **Layer composition completeness**: No fitness function asserts all files in all layer dirs appear in `.ai/`. Idempotency confirms run-2 == run-1; it does not confirm run-1 == expected.
> COMMENT: fix it
- **Exit code contract**: No fitness function enforces that exit codes match the spec. Easy to silently return wrong code in a new error path.
> COMMENT: fix it
- **CLI surface stability**: DSL harness absorbs output format changes but does not detect flag renames or subcommand renames between phases.
> COMMENT: defer to v2 once we have dogfood ed. add to future work list.
- **Binary size budget**: NFR3 ("single binary") has no size bound. Go binaries grow monotonically.
> COMMENT: defer to v2 once we have dogfood ed. add to future work list.
- **Security posture of generated Containerfile**: `extra_run` is user-supplied content passed through. No fitness function distinguishes AFB-controlled content from user-supplied shell commands.
> COMMENT: defer to v2 once we have dogfood ed. add to future work list.

#### Summary Verdict

Strong evolvability fundamentals: lean port interfaces, explicit decision reversibility costs, real fitness functions for composition correctness. Two blocking concerns before Phase 5: (1) `RUN afb sync` bootstrap coupling — no versioning policy for AFB self-install inside containers; (2) LNAI characterization test — the primary contract protection depends on an unpinned dependency. Both are high-risk and effectively irreversible once containers are being built and distributed.

---

### Reviewer B — Kua: Decision Reversibility

#### Decision Inventory

| Decision                                                          | Explicit?                  | Reversibility                                                         | ADR exists? |
| ----------------------------------------------------------------- | -------------------------- | --------------------------------------------------------------------- | ----------- |
| Go as implementation language                                     | Yes                        | Expensive                                                             | ADR-001     |
| TOML manifest format                                              | Yes                        | Irreversible                                                          | ADR-024     |
| Ports & Adapters architecture                                     | Yes                        | Expensive                                                             | ADR-018     |
| mergo for deep merge                                              | Yes                        | Expensive                                                             | ADR-004     |
| Array replace as merge default                                    | Yes                        | Expensive                                                             | ADR-006     |
| Integer priority ordering                                         | Yes                        | Expensive                                                             | ADR-009     |
| Container-first isolation                                         | Yes                        | Expensive                                                             | ADR-007     |
| Shell out to git CLI                                              | Yes                        | Cheap                                                                 | ADR-005     |
| text/template for generation                                      | Yes                        | Cheap                                                                 | ADR-026     |
| Podman only (v1)                                                  | Yes                        | Cheap (port exists)                                                   | ADR-015     |
| LNAI as sync delegate                                             | Yes                        | Cheap (configurable)                                                  | ADR-002     |
| ATDD black-box tests via os/exec                                  | Yes                        | Moderate                                                              | ADR-027     |
| Per-file SHA-256 for idempotency                                  | Yes                        | Cheap                                                                 | ADR-028     |
| `.ai/` as versioned integration contract                          | Yes                        | Expensive                                                             | ADR-025     |
| Clone layers to `.afb/layers/` (gitignored)                       | Yes                        | Moderate                                                              | ADR-003     |
| Components as opaque lifecycle hooks                              | Yes                        | Moderate                                                              | ADR-010     |
| **Test harness DSL package**                                      | Implicit                   | Moderate — all acceptance tests couple to this API                    | **None**    |
| **`afb doctor`/`afb diff` run inside container**                  | Implicit                   | Expensive — determines path resolution, test fixtures, user workflows | **None**    |
| **AFB binary self-install via `go install` inside Containerfile** | Implicit                   | Moderate — pins AFB versioning to Go module proxy                     | **None**    |
| **No lockfile before Phase 6**                                    | Implicit                   | Moderate — Phases 3-5 ship without reproducibility                    | **None**    |
| **`afb.local.toml` shallow merge**                                | Implicit                   | Moderate-to-expensive                                                 | **None**    |
| **`afb.lock` uses TOML**                                          | Implicit                   | Moderate                                                              | **None**    |
| **Exit code scheme (0/1/2/3/4)**                                  | Implicit (in architecture) | Moderate — public API for scripts/CI                                  | **None**    |

#### Reversibility Flags

- **`afb.local.toml` shallow merge**: No ADR, treated as deferral. Actually moderate-to-expensive. If users build workflows depending on shallow merge, changing to deep merge is a semantic breaking change. Must carry an ADR before Phase 1.
> COMMENT: no big workflows will be built on v1. fine to defer to v2
- **Sync execution context (inside container)**: The decision that `afb doctor` and `afb diff` run inside the container is structurally irreversible after users build workflows around it. Affects every command's path resolution, every test fixture, every user interaction flow. Not flagged in reversibility table, no ADR.
> COMMENT: Add ADR with justification, and list alternatives not taken. 
- **AFB self-install inside Containerfile**: Creating version coupling between the AFB release and container rebuild. Not classified as a decision at all. Moderate-to-expensive: users on older images get older AFB with potentially different behavior. No migration path.
> COMMENT: It seems that we should version AFB itself in the afb.toml manifest, as that will dictate which version of AFB goes into the image. if we do this, and define afb.toml schema version in the manifest, then afb can already validate that the manifest and the installed version of AFB are compatible. 
- **Test DSL package API**: No stability contract. Organic growth means refactoring later requires changing all acceptance tests. Not treated as a decision.
> COMMENT: The test DSL's purpose is to avoid mass refactorings if names change. what is going wrong here?
- **Exit code scheme**: Scripts and CI pipelines will depend on these. Changing them is a breaking change. No ADR. Implicit.
> COMMENT: add ADR
#### Context Gaps

- **ADR-004 (mergo)**: Does not document what happens if `WithOverwriteWithEmptyValue` proves unreliable. The spike anticipates a custom transformer fallback, but the ADR doesn't record this decision gate. Future engineer reading ADR-004 in isolation cannot reconstruct the rationale.
> COMMENT: fix the ADR
- **ADR-007 (container-first)**: "Auth per-container mitigated by named volumes" — if base image changes `HOME`, named volume mount path may silently break. Failure mode undocumented.
> COMMENT: fix the ADR

- **ADR-017 (AgentGateway)**: Justification is "star count + foundation." Doesn't address: silent failure if gateway is down when agents start; whether tool federation is needed at v1 scale; why stdio-inside-container is insufficient. The "why not the simpler option" is absent.
> COMMENT: fix the ADR. tool federation is indeed needed in v1, i will use it to build afb. 

- **ADR-025 (`.ai/` contract)**: No contingency for LNAI format change. Implicit response ("bump format version") is not specified.
> COMMENT: the contingency is "update afb as needed to suit"
- **No ADR for `afb.local.toml` merge semantics**: Architecture doc discusses it; no single source of truth for why shallow was chosen over deep.
> COMMENT: update the ADR. Rationale is fast to dogfooding, then fix in v2. we only have 1 user fo rnow. fine if their workflow needs to update
#### Deferral Attractors
- **AgentGateway config generation**: Trigger is "when first shared MCP server is configured." Gap between "AgentGateway is in compose" and "its config is manual" will persist through all phases. No concrete evaluation milestone. **True indefinite deferral.**

- **`afb.local.toml` deep merge**: Trigger is "when a user needs to override a nested key." This will happen in Dogfood Milestone 1 dogfooding. It is not a future use case — it is a near-certain early pain. This is not a deferral; it is an unresolved design gap.

- **Build reproducibility**: Acceptance criterion 6 ("same lockfile = same image digest") and the risk table entry ("aspirational, deferred") directly contradict each other. Not a deferral — a contradiction. Must be resolved before plan is committed.

- **`afb shell` command**: No measurable trigger. Users will work around with `podman ps`. True indefinite deferral.

- **Statistical process control metrics**: Circular — data only available if someone looks for it. No collection mechanism. Indefinite deferral.

- **Per-file merge strategy overrides**: Observable user pain but not a formal review trigger. Medium deferral risk.

#### Technology Radar Gaps
- **AgentGateway**: Suggested radar position **Trial** — new enough, failure mode (silent MCP tool loss) severe enough to warrant characterization before architectural commitment.

- **podman-compose**: No version pin in CI, no minimum version documented. `config --quiet` validation is spec compliance only. Suggested **Assess** — plan's compliance table is good but needs version pin and documented minimum.

- **mergo**: Version-pinned correctly. Upgrade policy undocumented. Characterization tests must be re-run on any version bump. Suggested **Adopt with pin** — mature but with documented behavioral dependency.

- **zerolog**: `TestFR7_StructuredLogs` makes JSON log schema a hard dependency. If zerolog changes output schema, downstream consumers break silently while the test passes. Suggested **Adopt** — but document that JSON log schema is a public interface.

#### Priority Actions

1. **Create ADR for `afb.local.toml` merge semantics** before Phase 1. Resolve the deferral attractor simultaneously — the "nested key override" scenario will occur in Dogfood Milestone 1.
> COMMENT: thin i agreed above
2. **Resolve build reproducibility contradiction** — remove from acceptance criteria or accept as out of scope. Do not ship Phase 6 with an unresolvable acceptance criterion.
> COMMENT: as elsewhere commented, remove this as acceptance criteria. defer to v2
3. **Create ADR for sync-inside-container execution context** — structurally irreversible; drift detection architecture depends entirely on this. Without an ADR, a future engineer may build a host-side doctor requiring a completely different approach.
> COMMENT: commented elsewhere, agree to add ADR
4. **Specify AgentGateway config generation trigger concretely** — replace indefinite deferral with a milestone: "At Dogfood Milestone 2, evaluate shared MCP access; if needed, implement AgentGateway config generation in Phase 6."
> COMMENT: shared MCP access is needed. it is the point of LLM memory. agentgateway is needed. shall be implemented, after dogfood milestone 2 is ok
5. **Document AFB binary versioning inside Containerfile** — how is the version determined? Is it the same version running `afb build`? What does a user do when upgrading AFB?
> COMMENT: does my suggestion to pin afb version in afb.toml work?
6. **Add version pin and minimum version for podman-compose** to `afb doctor` (host context) and to CI setup.
> COMMENT: OK
7. **Add ADR for exit code scheme** — public API, breaking change to alter post-v1.
> COMMENT: OK
---

### Reviewer C — Farley: Releasability

#### ATDD Integrity

The outer loop is structurally correct: each phase has one acceptance test, described as starting red, with unit TDD filling the inner loop. The convention is sound.

**Phase 0 gap**: `TestPhase0_Version` is labeled "smoke test — not ATDD." The plan doesn't clarify whether it is written before any code exists. If not, the ATDD discipline breaks at the foundation.
> COMMENT: it is correct what the plan says. nothing to change. 
**DSL maintenance gap**: The plan does not state who is responsible for keeping the DSL current as new phases add CLI operations. Without a rule like "every new CLI command gets a DSL method before its phase's acceptance test," later phases will bypass the DSL with raw `exec.Command`, defeating its purpose.
> COMMENT: OK, fix it. the DSL shall be updated in each phase as needed, and domain.md shall be updated in line with it. make these steps part of the plan for each phase.
**Phase 8 ambiguity**: `TestPhase8_Doctor` mixes composition drift and runtime drift in one test. These are distinct failure modes (Units 8.1 vs 8.2). A failing test gives ambiguous signal about which path failed.
> COMMENT: fix it.
#### DSL-Domain Alignment

The single DSL example — `harness.Validate(dir).ExpectSuccess()` — maps to the domain.md "Validate" term. That one example is consistent.

Domain.md Processes lists 7 verbs: Compose, Sync, Build, Lock, Doctor, Diff, Validate. Status of each:

| Domain Verb | Acceptance Test | DSL Method                 | Alignment                    |
| ----------- | --------------- | -------------------------- | ---------------------------- |
| Validate    | Phase 1         | `harness.Validate` (shown) | Clean                        |
| Build       | Phase 2         | `harness.Build` (implied)  | Clean                        |
| Sync        | Phase 5         | `harness.Sync` (implied)   | Clean                        |
| Lock        | Phase 6         | `harness.Lock` (implied)   | Clean                        |
| Doctor      | Phase 8         | `harness.Doctor` (implied) | Clean                        |
| **Diff**    | **None**        | `harness.Diff` (implied)   | **Gap — no acceptance test** |
| **Compose** | Phase 4         | **Unclear**                | **Structural problem**       |

**Compose structural problem**: Domain.md defines Compose as "Part of `afb sync`" with no standalone CLI command. `TestPhase4_Compose` exercises composition in isolation, but the plan never specifies which CLI invocation drives it as a black-box test. If there is no `afb compose` command (correct per domain.md), the Phase 4 acceptance test cannot be a true black-box test. Either there is an undocumented CLI surface, or Phase 4 cannot be tested as ATDD specifies.
> COMMENT: domain.md is lagging here, it needs to be updated to catch up to architecture.md and plan.md. update it. 
**Diff gap**: `afb diff` is a standalone command (Phase 8, Unit 8.4), but it has no dedicated acceptance test. Phase 8's acceptance test covers `afb doctor` only. The domain term Diff has no black-box verification.
> COMMENT: update th eplan for afb diff black box verification. does it need golden files?
**Terminology collision**: The plan's Architecture Overview uses "sync command" to mean both the external tool (`lnai sync`) and the AFB operation (`afb sync`). Domain.md distinguishes these. The conflation will cause confusion in code and documentation.
> COMMENT: yes they shall be separately distinguished. lnai already uses sync. afb should use a different term. suggestion something, update the docs as needed.
#### Pipeline Assumptions

1. **CI workflow deferred past Phase 0**: `.github/workflows/ci.yml` is deferred until "after Phase 1." But Phase 0's smoke test is introduced before CI exists. There is no CI to run it on. The plan claims CI is green from Phase 0 — this is not true if CI doesn't exist until Phase 1.
> COMMENT: can we just add a very simple CI workflow to build and run all tests as part of phase 0? add it back in. 
2. **`hadolint` not described in CI setup**: Required by Phase 2 acceptance test. If not installed on runner, the test fails for infrastructure reasons. No setup step documented.
> COMMENT: This would need to be added to the CI workflow mentioned in the comment above.
3. **`lnai` not described in CI setup**: Required by Unit 5.5. No mock strategy for CI environments without `lnai`. If not on PATH, the test silently skips or fails to start rather than failing on AFB behavior.
> COMMENT: This would need to be added to the CI workflow mentioned in the comment above.

4. **`webgtx/setup-podman-compose@v1` unpinned**: Third-party action with no version pin (no SHA). A breaking change in that action silently breaks CI.
> COMMENT: RULE!!! ALL GITHUB ACTIONS SHALL COME FROM ESTABLISHED PARTIES like redhat and microsoft, with version pins. if you cannot find an action that satisfies these constraints, use regular bash commands instead
5. **E2E gate on release path unspecified**: Phase 3 and Phase 5 acceptance tests are tagged `//go:build e2e`. If CI skips e2e on the release branch, "shippable" cannot be verified from the pipeline.
> COMMENT: then...can we just not skip e2e on the release path please?
#### Releasability Assessment

The dogfood milestones table is the strongest element from a CD perspective. Three milestones, each genuinely adding value. Correct.

- **Phase 3 milestone**: Genuinely releasable as-is. Earliest valid release point.
- **Phase 5 milestone** (minimum viable AFB): Depends on Phase 4, which has a structural acceptance test problem. Phase 4's unit tests passing does not constitute black-box verification. Phase 5's acceptance test then carries simultaneous responsibility for composition + sync + idempotency. A failing test gives weak signal.
- **Phase 5.4 coupling**: Adding `RUN afb sync` to the Containerfile template retroactively changes Phase 2 acceptance test assertions. The plan notes updating unit tests but does not call out that `TestPhase2_Build` also checks Containerfile content and will break. This is backward breakage of a passing test — opposite of intended direction.

#### Coupling Concerns

1. **Phase 5.4 breaks Phase 2's acceptance test**: Containerfile template change updates assertions in Phase 2. Not called out explicitly.
> COMMENT: update the phase 5.4 plan to note that it might need toupdate assertions from phase 2 then (reference the assertion names it will ahve to change)
2. **LNAI as external contract**: Unit 5.5 characterizes the contract but only if it runs in CI. If it does not run on every push, LNAI contract drift is silent.

3. **Lockfile coupling between Phases 5 and 6**: Phase 5 acceptance test doesn't mention a lockfile. Phase 6 says "`afb sync` → lockfile written." If Phase 6 retrofits lockfile writing into sync (which Phase 5 already implements), it changes Phase 5 behavior retroactively. The plan does not clarify whether a stub is written in Phase 5.
> COMMENT: fix the plan
4. **`afb doctor` calls `afb diff` internally**: No standalone acceptance test for `afb diff`. Doctor/diff failures are indistinguishable at the acceptance test level.
> COMMENT: as i commented elsewhere, need afb diff black box test
#### Summary

Correct CD instincts — dogfood milestones, ATDD, black-box testing via compiled binary. Principal releasability risk: Phase 4 (Compose) has no standalone CLI command, so its acceptance test has undefined semantics as a black-box test, and Phase 5's acceptance test carries too much simultaneous responsibility. Resolve before implementation: either add a temporary `afb compose` development command (removed post-Phase 5), or designate Phase 4 as an integration test (not black-box). Secondary risk: CI infrastructure dependencies (`hadolint`, `lnai`, `webgtx/setup-podman-compose`) are undescribed or unpinned.

---

### Reviewer D — Feathers: Testability & Seams

#### Seam Inventory

| Seam                                     | Rating     | Notes                                                                                                                                                                                                                                                                                                           |
| ---------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Git port (`ports.Git`)                   | **Strong** | Explicitly defined interface, injected via constructor, composing packages accept the interface. Best seam in the plan.                                                                                                                                                                                         |
| ContainerRuntime port                    | **Strong** | Same pattern. `generate.Containerfile(m, w)` writes to `io.Writer` — no runtime needed for generation tests.                                                                                                                                                                                                    |
| Harness DSL (`test/acceptance/harness/`) | **Strong** | Thin wrapper, `TestMain` builds binary once. Correct pattern.                                                                                                                                                                                                                                                   |
| Filesystem                               | **Weak**   | `os.MkdirTemp` throughout. Sensitive to permissions, path separators, cleanup. `compose.Run` atomic replace tests are verbose to set up correctly.                                                                                                                                                              |
| Sync command                             | **Absent** | Raw `os/exec` in `sync.Run`. No port interface, no injected executor. The acceptance test uses "mock sync command (script)" — a real subprocess on disk, not an injected seam. Orchestration control-flow (exit codes 0/1/2/3, flag behavior, validation-failure-blocks-sync) cannot be exercised at unit tier. |
| `afb validate` LNAI delegation           | **Absent** | Phase 1 acceptance test only validates manifest schema. LNAI delegation half has no seam. "Validation failed → sync does not run" invariant cannot be tested at unit tier without lnai present.                                                                                                                 |
| Doctor orchestrator                      | **Weak**   | `doctor.Run` calls runtime diff (real sync command in temp HOME) with no injection point. `TestDoctor_ProjectContext_ComponentDoctorFails` requires an actual failing component doctor — mechanism unspecified.                                                                                                 |

#### Coupling Concerns

- **`sync.Run` does too much without seams**: Orchestrates manifest merge (seamed), layer clone/pull (seamed via Git port), composition (pure, seamed), validation (lnai, **unseamed**), sync command (lnai, **unseamed**), lockfile write (pure, seamed). The unseamed middle makes the orchestrator's entire control-flow logic only testable as integration. By Phase 6 this function also orchestrates version hooks and install failure handling. Complexity grows, unit testability does not.

- **`internal/runner/` has no injection**: `runner.Script` and `runner.ComponentCommand` both call `os/exec` directly. Tests require real shell scripts on disk (testdata fixtures). Fine now; if runner functions are called from more complex orchestration later, the pattern propagates — every caller becomes integration-testable only.

- **`diff.Runtime` embeds real sync command execution**: The temp HOME approach is justified but produces a function testable only against a real sync command or a fixture subprocess. If the sync command changes behavior, integration tests may silently return wrong results with no characterization test for the diff output format.

#### DSL-Domain Consistency

Domain.md Processes lists 7 verbs: **Compose, Sync, Build, Lock, Doctor, Diff, Validate**. The plan's acceptance tests imply the following DSL methods:

| Phase | Implied DSL Method                              | In Domain.md Processes?                                  |
| ----- | ----------------------------------------------- | -------------------------------------------------------- |
| 1     | `harness.Validate`                              | Yes                                                      |
| 2     | `harness.Build`                                 | Yes                                                      |
| 3     | `harness.Up`, `harness.Down`, `harness.Rebuild` | **No**                                                   |
| 4     | unclear                                         | Compose = "Part of sync", no standalone command          |
| 5     | `harness.Sync`, `harness.LayerPull`             | Sync yes; LayerPull **No**                               |
| 6     | `harness.Lock`, `harness.LockCheck`             | Lock yes                                                 |
| 7     | `harness.Init`, `harness.InitWithTemplate`      | **No**                                                   |
| 8     | `harness.Doctor`                                | Yes; but `harness.Diff` implied — **no acceptance test** |
| 9     | `harness.Run`, `harness.Push`                   | **No**                                                   |

**The plan states "See domain.md for canonical terminology used in DSL method names." This is not true for at least 7 implied DSL methods: Init, Up, Down, Rebuild, LayerPull, Run, Push.** Either domain.md must be extended or the claim must be revised.

**Diff gap**: "Diff" is a domain.md Process term with a CLI command (`afb diff`, Phase 8 Unit 8.4). No acceptance test covers it as a standalone command. Phase 8's acceptance test exercises `afb doctor` only. Domain term Diff is unverified at black-box level.

**Compose ambiguity**: Domain.md says Compose is "Part of `afb sync`" with no standalone CLI. `TestPhase4_Compose` is described as a black-box acceptance test — but what CLI invocation drives it? The plan says "Run composition" without specifying. If no `afb compose` command exists (correct per domain.md), this cannot be a black-box test.

#### Testability Gaps

- **`TestSync_ValidationFailure` and `TestSync_SyncCmdFailure`**: Tagged integration. The behavior under test (pure orchestration logic: "if validation exits non-zero, do not run sync command") should be testable at unit tier with an injected executor. Without a seam, every orchestration path requires integration infrastructure.

- **`TestSync_FullPipeline`**: Described as integration, but uses a "mock sync command (script)." A mock sync command is not testing the real integration point. This is a partially-mocked integration test — terminology is muddled and the test tier is wrong in both directions.

- **`TestDoctor_ProjectContext_ComponentDoctorFails`**: No specification of what fixture produces a failing doctor command. Real binary? Shell script in testdata? Unspecified.

- **`TestRuntimeDiff_Clean` and `TestRuntimeDiff_ModifiedRuntimeConfig`**: Require real sync command in temp HOME. Which sync command — real lnai or stub? If real lnai, lnai-dependent. If stub, same contradiction as above.

- **`TestPodmanBuild_ValidContainerfile`** (Unit 2.3): Tagged integration but requires podman. By the plan's own three-tier definition, podman-dependent tests are E2E. Misclassified.

#### Legacy Entanglement Risk

- **`sync.Run` accumulates shell-outs with no seams**: Each new orchestration step added in Phase 6 (version hooks, install failure handling, lockfile write) adds untestable branches at unit tier. This is compounding technical debt in the most business-critical function. Any bug in sync orchestration is only catchable in integration tests.

- **`internal/sync/sync.go` orchestrates 7+ concerns by Phase 6**: manifest merge, layer clone/pull, composition, validation, sync command, version hook execution, install failure handling, lockfile write. No decomposition proposed. Refactoring requires re-running all integration tests.

- **Containerfile template syntax errors only caught at runtime**: No `TestContainerfile_TemplateParses` test. Malformed Go template syntax in `containerfile.tmpl` fails only when `generate.Containerfile` is called, not at test initialization.

#### Summary

Strong seams where they count most — Git port, ContainerRuntime port, domain package purity, harness DSL. Significant testable gap in the sync orchestrator: validation and sync-command invocations have no injection points, forcing all orchestration control-flow tests into the integration tier. DSL-domain consistency claim is not met: 7 implied DSL method names are absent from domain.md's canonical Processes table, and the domain term "Diff" has no acceptance-level coverage. Biggest risk: whether `sync.Run`'s unseamed exec calls are acceptable (needs explicit documentation as a testability constraint), or whether a thin `CommandExecutor` interface should be added. That decision will determine how testable the system remains as Phase 6 adds complexity to the same function.
> COMMENT: update the plan to solve the biggest problems here and defer the rest to v2
---

## Cross-Cutting Patterns

*Findings flagged by 2 or more reviewers — highest priority.*

### 1. Phase 4 Compose acceptance test is structurally undefined (Farley + Feathers)

`TestPhase4_Compose` is described as a black-box acceptance test, but domain.md defines Compose as "Part of `afb sync`" with no standalone CLI command. Both Farley and Feathers independently identified that no CLI invocation is specified for this test. If there is no `afb compose` command, the Phase 4 acceptance test cannot be a true black-box test. This must be resolved before implementation: either add a temporary `afb compose` command (removed post-Phase 5), or reclassify Phase 4's test as an integration test.
> COMMENT: this must be fixed. fix it.
### 2. `afb diff` has no standalone acceptance test (Farley + Feathers)

"Diff" is a canonical domain.md Process term with a dedicated CLI command (`afb diff`). Neither Farley nor Feathers found an acceptance test covering it as a standalone command. Phase 8's `TestPhase8_Doctor` exercises `afb doctor` only; diff is exercised only through doctor's internal logic. A bug in `afb diff` as a standalone command would not be caught at the acceptance tier.
> COMMENTED: i have commented elsewhere
### 3. DSL method names are inconsistent with domain.md (Farley + Feathers)

Both reviewers independently found that the plan claims "domain.md provides canonical terminology for DSL method names" but at least 7 implied DSL methods (Init, Up, Down, Rebuild, LayerPull, Run, Push) have no corresponding entry in domain.md's Processes table. Either domain.md must be updated to include these operations, or the claim must be revised. This also means DOMAIN.md is incomplete relative to the implemented CLI surface.
> COMMENTED: i have commented that domain.md is lagging and must be caught up. interview me if something is not clear from the existing docs
### 4. LNAI not version-pinned in CI (Ford/Parsons + Farley + Kua)

Three reviewers flagged this. Unit 5.5 (`TestLNAIContract_AcceptsComposedAIDir`) is described as the primary protection against `.ai/` contract drift, but LNAI is not version-pinned in CI. An LNAI upgrade can silently change what the characterization test certifies. Farley additionally noted that `lnai` is not described in CI setup at all. Kua noted the absence of a trigger for LNAI version review.

### 5. `RUN afb sync` bootstrap coupling (Ford/Parsons + Kua)

Both identified the implicit decision that AFB self-installs inside the containers it generates. The version of AFB inside the container must be schema-compatible with the manifest it syncs at build time. If AFB gains a new mandatory manifest field, the version inside an existing container will fail. Ford/Parsons rated this high-risk and effectively irreversible. Kua noted there is no ADR for this decision and no documented versioning policy.

### 6. `sync.Run` has no testable seams for orchestration logic (Feathers + Farley)

Feathers identified the absent seam explicitly (sync command and validation delegation are raw `os/exec` with no port). Farley's coupling concern about LNAI as external contract reaches the same root cause. The result: control-flow paths in `sync.Run` (validation failure → no sync, sync command failure → exit code 3) cannot be exercised at unit tier. As Phase 6 adds more complexity to this function, the gap compounds.
> COMMENT: fix it, add the seams in the plan and architecture
### 7. Build reproducibility is simultaneously an acceptance criterion and "aspirational" (Ford/Parsons + Kua)

Ford/Parsons found it unmeasured and enforcement-free. Kua identified the direct contradiction between acceptance criterion 6 ("same lockfile + same manifest = same image digest") and the risk register entry ("aspirational, deferred"). This is not a deferral — it is a contradiction. One of the two must be corrected before Phase 6.
> COMMENT: deferred
### 8. `afb.local.toml` shallow merge is a backward-compatibility commitment disguised as a deferral (Ford/Parsons + Kua)

Both identified this. Kua: no ADR, no trigger, will be hit in Dogfood Milestone 1. Ford/Parsons: by the time "real use cases demand deep merge," users have existing files depending on shallow merge semantics. This is an irreversible behavioral commitment being deferred as if it were a non-urgent choice.

---

## Synthesis Prompt

The following questions require decisions before this plan proceeds:

1. **Phase 4 Compose acceptance test**: What CLI command drives `TestPhase4_Compose` as a black-box test? Add `afb compose` temporarily, reclassify as integration test, or restructure Phase 4 and Phase 5 boundary?
> COMMENT: i have addressed this. come back to me if you  need more direction
2. **`sync.Run` seam decision**: Is the absence of a `CommandExecutor` interface (for validation and sync-command invocations) a deliberate documented constraint, or should a thin interface be added? This determines whether orchestration control-flow is unit-testable or permanently integration-only.
> COMMENT: needs a seem. sync should be swappable in future iterations
3. **LNAI version in CI**: How is `lnai` installed in CI for Unit 5.5? What version is pinned? Without answers, the characterization test is not a reliable contract gate.
> COMMENT: Addressed in comments elsewhere
4. **`RUN afb sync` versioning policy**: How is the AFB version inside the generated Containerfile determined and kept compatible with the manifest? This must be specified before Phase 5 implementation.
> COMMENT: addressed in comments elsewhere
5. **Build reproducibility**: Accept criterion 6 ("same lockfile = same image digest") as out of scope and remove from verification criteria, or specify an implementation path in Phase 6? Cannot remain contradicted by the risk register.
> COMMENT: addressed in comments elsewhere

6. **`afb.local.toml` merge semantics**: Write the ADR now (before Phase 1). Is shallow merge the permanent decision, or is deep merge planned with a specific trigger? The deferral framing is not safe — the first dogfooding user will hit this.
> COMMENT: addressed in comments elsewhere

7. **domain.md completeness**: Does domain.md need to be updated to include Init, Up, Down, Rebuild, LayerPull, Run, Push as canonical process terms, so that the DSL-domain alignment claim holds? Or should the claim be revised?
> COMMENT: addressed in comments elsewhere

8. **`afb diff` acceptance test**: Add a `TestPhase8_Diff` acceptance test for `afb diff` as a standalone command, or accept that it is only tested indirectly through `afb doctor`?
> COMMENT: addressed in comments elsewhere

No automated verdict is produced. The above questions are what the review has determined require your judgment.
