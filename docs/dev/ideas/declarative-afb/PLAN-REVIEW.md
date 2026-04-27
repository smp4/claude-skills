# PLAN.md Review — AFB Implementation Plan

> Reviewed: 2026-04-27
> Artefact: docs/dev/ideas/declarative-afb/PLAN.md
> Companion artefacts consulted: spec.md, architecture.md, domain.md
> Context: Complete greenfield. No backwards compatibility constraints.

---

## Beck Lens — Simple Design

**Heuristics applied**: simplest thing, YAGNI, vertical slices, demo-able units, ordering, test-list-as-design.

### Findings

1. **Phase 0 is 7 units of pure infrastructure** (lines 67-148): No user-facing behavior until Unit 0.1's `afb version`. Units 0.2-0.7 (CI, lefthook, justfile, linting, changelog, boilerplate) are horizontal infrastructure, not vertical slices. None can be "demonstrated" to a user. Beck would do Unit 0.1, then move to Phase 1 and add CI/hooks/linting incrementally as the codebase demands them.
   - **Suggestion**: Collapse Phase 0 to Unit 0.1 only. Add CI after Phase 1 when there's something to lint and test. Add lefthook when the first contributor arrives (solo dev — who is the hook protecting you from?). Justfile accumulates as commands appear.
> COMMENT: second contributor is claude! lefthook protects linting errors from getting to CI. lefthook and linting stay early. ok to add CI later. justfile as we go, ok. OK for changelog later. boilerplate needed early.
2. **Units 1.3 and 1.4 are YAGNI at Phase 1** (lines 187-205): Local manifest merge and variable expansion are consumed first by `afb sync` (Phase 5). Building them in Phase 1 means they sit untested-in-context for 3 phases. The acceptance test for Phase 1 (`afb validate`) doesn't exercise either feature.
   - **Suggestion**: Move Unit 1.3 to Phase 5 (sync needs it). Move Unit 1.4 to Phase 2 (where `${version_spec}` is first needed in component install commands). Build things when they're needed.
> COMMENT: OK
3. **Phase 2 acceptance test avoids the hard part** (lines 220-228): `--generate-only` means the acceptance test validates file generation but never builds a container. The actual podman adapter (Unit 2.3) is integration-tested separately. The phase acceptance test doesn't cover the full vertical slice.
   - **Suggestion**: The e2e variant (line 227) should be the primary acceptance test. `--generate-only` is a useful CI shortcut but shouldn't be how you define "Phase 2 is done."
> COMMENT: ok, fix it. cover the full vertical slice
4. **Lockfile logic is split across Phases 5 and 6** (lines 386-488): Phase 5 has lockfile read/write (Unit 5.1), Phase 6 has staleness check (Unit 6.2) and `afb lock` commands (Unit 6.4). These are conceptually one feature. The split means Phase 5's sync writes a lockfile but can't check if it's stale — that's half a feature.
   - **Suggestion**: Either merge Phase 6 into Phase 5, or redefine: Phase 5 = sync pipeline (no lockfile), Phase 6 = lockfile (all of it). Don't split a concept across phases.
> COMMENT: split phase 5 as sync pipeline, phase 6 as lockfile (all).
5. **Test lists are excellent** (throughout): Every unit has "Tests first" with specific named test functions and clear behavioral descriptions. The test names read as specifications (`TestValidate_DuplicateLayerPriority`, `TestDeepMerge_IncomingWinsAtLeaf`). This is the test list driving design, not an afterthought. Strong alignment with Beck.

6. **Unit 4.2 (mergo characterization tests) is the right call** (lines 339-351): Tests-as-deliverable, establishing trust in a dependency before building on it. Textbook Beck — understand the thing before you use the thing.

7. **30+ units across 10 phases for a solo dev** (overall): The plan is thorough but risks becoming a bureaucratic weight. Each unit has files, tests, implementation notes, traces — valuable for a team, overhead for one person. The plan knows more about the system than anyone needs to before writing the first line.
   - **Suggestion**: Not necessarily wrong, but acknowledge that the plan is a living document. Units will merge, split, and disappear during implementation. Don't treat unit boundaries as sacred.
> COMMENT: fine as is, will be converted to beads for execution possibly with multiple agents. every bead will need to be self standing. beads will be updated during execution.
### Summary

The plan is well-structured and test-driven — test lists drive design, units trace to spec, ordering is mostly logical. The main Beck concern is premature horizontal infrastructure (Phase 0) and features built before they're needed (Units 1.3, 1.4). The plan is more detailed than a solo greenfield project typically needs, which creates a risk of plan-adherence overriding discovery during implementation.

---

## Farley Lens — Verification Architecture

**Heuristics applied**: ATDD planning, four-layer model, verification coverage, separation of what from how.

### Findings

1. **No DSL layer in the test architecture** (lines 59-63, acceptance test convention): All acceptance tests exercise the compiled `afb` binary via `os/exec`. This is Layer 3 (protocol driver) talking directly to Layer 4 (SUT). There is no Layer 2 (DSL) abstracting domain operations from their CLI expression. Every acceptance test is coupled to CLI output format — if `afb validate` changes its output from `"valid"` to `"ok"`, `TestPhase1_Validate` breaks.
   - **Suggestion**: Introduce a thin test DSL package in `test/acceptance/` that wraps CLI invocations. Something like `harness.Validate(dir).ExpectSuccess()` instead of raw `exec.Command("afb", "validate", path)` + string matching. The DSL absorbs CLI output format changes. Acceptance test readability improves. Cost: one small package. Payoff: acceptance tests survive CLI UX changes.
> COMMENT: add the DSL package. note domain.md document.
2. **Acceptance test for Phase 0 tests tooling, not behavior** (line 71): `TestPhase0_Version` asserts `afb version` outputs a semver string. This verifies the build pipeline works, not that AFB does anything useful. It's a canary, not a specification.
   - **Suggestion**: Acceptable as a smoke test. Just don't count it as meaningful verification coverage. Phase 1 is where real ATDD starts.
> COMMENT: agree, this is contrived. fine as an architectural concern test but should not be included or named anywhere that implies it is e2e or ATDD
3. **Phase 4 acceptance test is the strongest** (lines 316-325): Concrete layer setup, specific merge assertions (`{a: 1, b: 3, c: 5}`), propagation checks, format version check. This test IS the specification for composition behavior. If this test passes, composition works. Exemplary ATDD.

4. **Phase 5 idempotency check is critical but under-specified** (line 393): "Modify nothing. `afb sync` again → .ai/ byte-identical (idempotency check via checksum)." How is byte-identity checked? File-by-file hash? Directory tree hash? Timestamp comparison is not sufficient (file content same, mtime different). This needs to be explicit because it becomes a CI fitness function.
   - **Suggestion**: Specify the mechanism: SHA-256 of each file in `.ai/`, sorted, compared. Or `tar` the directory and hash it. The mechanism matters because it's reused in the fitness function.
> COMMENT: compare the options you present, make a selection, justify it, write an ADR justifying it, and justifying why other paths not taken. update the plan and ATDD
5. **FR11 (remote/session compatibility) has no acceptance test** (spec lines 166-172): The spec says AFB must work over SSH, in tmux, with no interactive prompts. No phase tests this. This is a "verify by inspection" requirement — exactly what Farley rejects.
   - **Suggestion**: Add a verification step: one e2e test that runs `afb sync` with `TERM=dumb` and no TTY attached, asserts no ANSI codes in output and exit 0. Cheap test, catches the common failure mode (colored output breaking in pipes/tmux).
> COMMENT: add it
6. **FR7 (observability) has no acceptance test** (spec lines 127-129): Structured logging is mentioned but never verified. No test checks that `afb sync` produces structured JSON on stderr when `AFB_LOG_LEVEL=debug`.
   - **Suggestion**: One test in Phase 5: run `afb sync` with `AFB_LOG_LEVEL=debug`, capture stderr, assert each line parses as valid JSON. Catches regressions where someone uses `fmt.Println` instead of zerolog.
> COMMENT:
7. **Three-tier strategy is well-designed** (architecture.md lines 974-981): Unit (pure domain, no deps), Integration (git, lnai), E2E (podman). Clear tier isolation. The fitness function "unit tests run with no external tools" is the right guard. But how is it enforced? If someone adds an `os/exec` call to a domain package, what catches it?
   - **Suggestion**: The "tier isolation" fitness function needs a mechanism. Options: (a) CI job runs domain tests in a container with no git/podman installed, (b) `go vet` custom analyzer, (c) grep for `os/exec` in `internal/domain/`. Option (a) is strongest.
> COMMENT: option a, do it
8. **Verification gap — generated Containerfile semantic correctness**: hadolint checks syntax. `podman-compose config` checks compose syntax. But nothing verifies that the generated Containerfile actually installs the declared components. A manifest with 3 components should produce a Containerfile with 3 RUN install lines. This is a golden-file test opportunity.
   - **Suggestion**: Unit 2.1 tests (lines 234-239) cover individual assertions but consider a golden-file comparison for the full generated output. Catches unintended ordering changes, missing sections, etc.

### Summary

The ATDD structure is strong — each phase has a meaningful acceptance test, and Phase 4's composition test is exemplary. The main gap is the missing DSL layer, which couples all acceptance tests to CLI output format. Two spec requirements (FR7 observability, FR11 remote compatibility) have no verification at all. The tier isolation fitness function needs an enforcement mechanism, not just a statement.

---

## Ford-Parsons Lens — Evolutionary Architecture

**Heuristics applied**: fitness function audit, coupling analysis, implicit bet extraction, evolution blocker scan, missing fitness criteria.

### Fitness Function Audit

| Characteristic           | Status                    | Issue                                                                                                                                                                                                                                                          |
| ------------------------ | ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Composition idempotency  | Measurable                | CI job, runs `afb sync` twice, diffs output. Solid.                                                                                                                                                                                                            |
| Containerfile validity   | Measurable                | hadolint in CI. Clear pass/fail.                                                                                                                                                                                                                               |
| Compose spec validity    | Measurable                | `podman-compose config --quiet`. Clear pass/fail.                                                                                                                                                                                                              |
| Unit test tier isolation | **Vague**                 | "No git/podman/network" stated as a property, but no enforcement mechanism. How does CI detect a violation? No test runs in a stripped-down environment. No static check for `os/exec` in domain packages. This is a prose aspiration, not a fitness function. |
| Conventional commits     | Measurable                | Lefthook regex. Enforced locally.                                                                                                                                                                                                                              |
| Lint clean               | Measurable                | golangci-lint in CI + pre-commit.                                                                                                                                                                                                                              |
| Unit test speed          | **Unmeasured**            | "< 5s" threshold stated (architecture.md) but no CI step asserts this. Regressions will be noticed by feel, not by a gate.                                                                                                                                     |
| Build reproducibility    | **Unmeasured**            | "Same lockfile + same manifest = same image digest" stated as acceptance criterion (architecture.md) but no phase tests it and no CI job verifies it. Container image reproducibility is notoriously hard — this criterion may be aspirational.                |
| Sync idempotency         | Measurable (Phase 5 test) | Tested once in Phase 5 acceptance test. Listed as a CI fitness function (line 666) but no detail on how the CI job is structured.                                                                                                                              |
> COMMENT: unit test tier isolation - add the os/exec static check in CI. i think we commented on another solution with beck or farley too. build reproducibility - note it as a risk in architecture.md with your conclusion here, we will defer mitigation. unit te_t speed: add a CI step to fix. sync idempotency: add dewtail on CI job structure. 
### Coupling Concerns

- **AFB ↔ `.ai/` directory format** (architecture.md §.ai/ Directory Contract): AFB produces `.ai/`, LNAI consumes it. The `.ai-format-version` marker is a good coupling management mechanism. But: no test verifies that LNAI actually accepts what AFB produces. The plan says "characterized by tests against LNAI's expectations" (architecture.md line 93) — this is an integration test, but it's not in any phase's unit list. When does this test get written?
  - **Suggestion**: Add a characterization test in Phase 5 (when `lnai sync` is first invoked) that asserts LNAI accepts the composed `.ai/` directory. This is the contract test.
> COMMENT: do it
- **AFB ↔ mergo** (Phase 4): mergo is load-bearing — the entire composition algorithm depends on its merge semantics. The characterization tests (Unit 4.2) are the correct mitigation. But the coupling runs deeper: if mergo's `WithOverwriteWithEmptyValue` is unreliable, the fallback is "implement custom transformer." That's a significant scope change mid-Phase-4, with no time estimate or risk buffer.
  - **Suggestion**: Run the mergo characterization tests as a spike BEFORE Phase 4, during Phase 1 or even Phase 0. If the custom transformer is needed, you want to know early, not mid-composition-implementation.
> COMMENT: seems sensible to do it even before phase 1. in phase 1 we already start toml parsing, ready for merge. need to know if mergo has toml limitations before then. do it between phases 0 and 1
- **AFB ↔ podman-compose feature set** (architecture.md §Compose Spec Compliance): Coupling is intentional and well-documented. The safe subset table is exactly the kind of coupling management Ford-Parsons values. The `podman-compose config` fitness function validates it. Well done.

### Implicit Bets Extracted

| Bet                                                              | Assumption                                                                               | Reversibility                                           | Risk Level                                                                                                                                                                      |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Go as implementation language                                    | Solo dev (Python-strongest) can be productive in Go for a multi-phase CLI project        | Effectively irreversible (rewrite)                      | **High** — ADR-001 acknowledges the trade-off but the plan has 30+ units of Go. If Go productivity is lower than expected, every phase takes longer. No checkpoint to reassess. |
| LNAI remains viable                                              | 239-star project won't break or be abandoned mid-project                                 | Cheap (configurable sync command)                       | Low — coupling well-managed                                                                                                                                                     |
| mergo handles zero-values correctly (or transformer is feasible) | `WithOverwriteWithEmptyValue` works OR custom transformer is tractable                   | Expensive (composition logic depends on merge behavior) | **Medium** — unknown until characterization tests run                                                                                                                           |
| `text/template` suffices for Containerfile generation            | No conditional logic beyond loops needed in templates                                    | Cheap (swap template engine)                            | Low                                                                                                                                                                             |
| Solo dev will maintain 30+ unit plan                             | One person can hold the full system in their head and maintain momentum across 10 phases | N/A                                                     | **Medium** — plan scope vs. available effort. No phased descoping strategy.                                                                                                     |
| Podman-compose is stable enough                                  | Feature subset works reliably across macOS + Linux                                       | Moderate (Docker adapter exists as port)                | Low-Medium                                                                                                                                                                      |
| Container rebuild latency is acceptable                          | Editing `afb.toml` + `afb rebuild` is fast enough for iterative development              | Expensive (fundamental architecture choice)             | **Medium** — image build times with component installs could be minutes. No caching strategy beyond Docker layer cache.                                                         |
> COMMENT: container rebuild latency comment is fair, and annoying. can we do something with caching strategy, locally for afb dev, and also to help afb users in production?
### Evolution Blockers

- **TOML manifest format** (ADR-024, irreversible): Acknowledged. Once users have manifests, migration is painful. Acceptable — TOML is a reasonable bet.

- **Array replace as merge default** (ADR-006, expensive): Every layer's content assumes arrays replace. If users later need array-append, every existing layer needs updating. The plan has no escape hatch (e.g., per-field merge annotations). This is the riskiest merge decision.
  - **Cost to address now**: Add a `merge_arrays` field (`replace` | `append`) per layer. Cost: one extra field in validation + one branch in merge logic.
  - **Cost to address later**: Every existing layer + documentation + user expectations assumes replace. Migration guide + deprecation period.
> COMMENT: ok to add the merge_arrays field. it should be optional, with default as array replace.
- **No descoping strategy**: The plan is 10 phases, 30+ units, with dogfood milestones at Phase 3 and Phase 5. But there's no "minimum viable AFB" definition. If time/energy runs out after Phase 5, what's shippable? The plan reads as all-or-nothing.
  - **Suggestion**: Define what's shippable at each dogfood milestone. Phase 3 milestone = "manually-configured container harness" is useful. Phase 5 milestone = "declarative config + sync" is the core value prop. Phases 7-9 are polish. Name this explicitly so you can stop without feeling incomplete.
> COMMENT: ok update plan
### Missing Fitness Criteria

- **Build time**: Mentioned in risks ("image build time") but not measured. A fitness function like "full `afb build` from cold cache < 5 minutes" would catch regression when components are added.
- **CLI startup time**: Go is fast, but cobra + TOML parsing + zerolog init adds up. No threshold stated. "< 100ms for `afb version`" is a cheap fitness function.
> COMMENT: this is not driving at this stage. add as a risk to user dissatisfcation, note no mitigations yet
- **Domain package purity**: The claim that `internal/domain/` has no external deps is an architectural characteristic that needs enforcement, not just prose.
> COMMENT: then add a fitness function to govern it
### Summary Verdict

The plan is unusually strong on evolutionary architecture fundamentals — explicit decision reversibility table, ADRs for significant choices, fitness functions defined. The main concern is implicit bets around solo-dev productivity in Go and container rebuild latency, plus the absence of a descoping strategy. The mergo zero-value risk should be retired early via a spike, not discovered mid-Phase-4. Array-replace-as-default is the costliest merge decision and deserves a per-field escape hatch before real layers exist.

---

## Kua Lens — Decision Quality

**Heuristics applied**: decision inventory, reversibility audit, context quality, deferral audit, technology radar positions.

### Decision Inventory

| Decision                            | Explicit?                    | Reversibility | ADR?    | Assessment                                                                                                                               |
| ----------------------------------- | ---------------------------- | ------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Go as language                      | Yes                          | Irreversible  | ADR-001 | Good context. Alternatives listed.                                                                                                       |
| TOML manifest                       | Yes                          | Irreversible  | ADR-024 | Good context. Norway problem cited.                                                                                                      |
| LNAI for sync                       | Yes                          | Cheap         | ADR-002 | Replaceability well-designed.                                                                                                            |
| Ports & Adapters                    | Yes                          | Moderate      | ADR-018 | Reduced port count (rev 2) shows learning.                                                                                               |
| mergo for merge                     | Yes                          | Moderate      | ADR-004 | Risk acknowledged.                                                                                                                       |
| Array replace default               | Yes                          | Expensive     | ADR-006 | Reconsider-trigger stated.                                                                                                               |
| Integer priority                    | Yes                          | Expensive     | ADR-009 | Reconsider-trigger stated.                                                                                                               |
| Podman only (v1)                    | Yes                          | Cheap         | ADR-015 | Docker deferred with trigger.                                                                                                            |
| Container-first isolation           | Yes                          | Expensive     | ADR-007 | Rev 2 — shows iteration.                                                                                                                 |
| No uninstall command                | Yes                          | Cheap         | ADR-019 | Container disposability justifies.                                                                                                       |
| Composable commands                 | Yes                          | Cheap         | ADR-020 | Good: most composable design.                                                                                                            |
| text/template for generation        | Yes                          | Cheap         | ADR-026 | Stdlib, no dep.                                                                                                                          |
| AgentGateway for MCP                | Yes                          | Cheap         | ADR-017 | Alternatives evaluated.                                                                                                                  |
| **Acceptance tests via os/exec**    | **Implicit**                 | Moderate      | No      | All acceptance tests shell out to binary. This is a testing architecture decision that shapes every phase. Not documented as a decision. |
| **Phase 0 as infrastructure-first** | **Implicit**                 | Cheap         | No      | Ordering choice: tooling before features. Trades early feedback for early polish.                                                        |
| **zerolog for logging**             | **Implicit**                 | Cheap         | No      | Mentioned in Unit 0.1 implementation notes but no decision record. Low risk, low stakes — ADR not required.                              |
| **lefthook for git hooks**          | Yes (in reversibility table) | Cheap         | No      | Correctly classified as cheap to reverse. No ADR needed.                                                                                 |
> COMMENT: add ADR for acceptance tests via os/exec. ignore the pahse 0 as infra first, no need for an ADR, we will be past it quickly. 
### Reversibility Flags

- **"cobra for CLI: Moderate"** (line 683): Overclassified. Cobra commands are thin wiring in `cmd/afb/`. Core logic is in `internal/`. Swapping CLI framework changes ~10 files in `cmd/`, zero in domain. This is **cheap**.

- **"mergo for deep merge: Moderate"** (line 684): Underclassified. The composition algorithm, characterization tests, and custom transformer (if needed) all bind to mergo's specific behavior. Replacing mergo means re-verifying all merge semantics. This is closer to **expensive** than moderate.

- **Container-first isolation** (ADR-007): Classified as accepted but the plan doesn't surface the cost clearly. Every `afb.toml` change requires `afb rebuild` — a container image build. If build takes 3+ minutes with component installs, the iteration loop is painfully slow. The `mount_workspace` escape hatch helps for code changes but not for harness config changes. This is effectively irreversible once workflows depend on containers.
> COMMENT: ok, then correct plan.md per the above. for the container-first isolation gripe, it seems the caching straight/ speedup is important. i realise now that every time the user changes the agent runtime target configs, technically this is a new version of the harness. the user does afb diff, checks if any of the harness config has changed, cherry picks changes up into .afb/, pushes the changes out to the layer/ git repos, which will update their version then runs afb sync. sync presumably uses the local versions of th elayer dirs. but if the user triggers a validation from afb.toml level, if they have pinned versions of the layer repos in afb.toml, the pinned versions will still be the old versions, and the locally changed layer dirs will be overwritten with content from the older layer version. it means when the user afb pushes changes from their local layer dirs up to the layer repos, afb push should also get back the commit of the updated layer repo and use it to update the pinned version of the layer in afb.toml, to stay consistent. it also means the container will be a new version, and its version tag no longer consistent? that new version of the container wont be propagated up/ out to a location where that latest version of the container can be pulled down to another/ new project. consider this problem, think deeply about it, decide if it is a problem, if so, propose a solution in architecture.md with justification, then update the plan.md as well.
### Context Gaps

- **ADR-001 (Go)**: Says "user accepted trade-off of less familiarity for long-term fit." But doesn't record how much less familiar. Is this "knows some Go" or "never written Go"? The risk profile is very different. A 30+ unit plan in a language you're learning is a different proposition than one in your primary language.
> COMMENT: ignored for now. yolo claude
- **Acceptance test architecture**: No decision record for how acceptance tests work. The convention (line 59-63) just states "black box via `os/exec`." This is a load-bearing choice — it determines test fragility, DSL requirements, and CI complexity. Worth documenting why this approach over testing domain functions directly at the acceptance level.
> COMMENT: add the documentation as an ADR. make sure it is best practice for ATDD with go
### Deferral Attractors

| Deferred Decision                   | Trigger Specified?                                            | Risk                                                                                                                                                                                                                                                                |
| ----------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Docker adapter                      | Yes ("user request or deployment target")                     | Low — clear trigger                                                                                                                                                                                                                                                 |
| afb.local.toml deep merge           | Yes ("when user needs nested key override")                   | Low                                                                                                                                                                                                                                                                 |
| `afb shell` command                 | Yes ("when AFB needs to manage running containers from host") | Low                                                                                                                                                                                                                                                                 |
| Per-file merge strategy overrides   | **No** — listed as unresolved question (spec line 256)        | **Medium** — "per-layer sufficient?" is a question, not a trigger. If users hit this, they'll work around it with extra layers (accidental complexity). Define trigger: "when a user creates a layer solely to get different merge strategies for different files." |
| Statistical process control metrics | **No** — "what to track, how to couple" (spec line 257)       | Low — genuinely unknown until operational data exists                                                                                                                                                                                                               |
| Shared services management          | **No** — "leaning convention" (spec line 255)                 | **Medium** — convention vs. built-in command has UX implications. Trigger: "when second project on same machine needs shared services and convention causes confusion."                                                                                             |
| AgentGateway config generation      | **Weak** — "investigate config format" (spec line 258)        | Low — can be manual initially                                                                                                                                                                                                                                       |
> COMMENT: "leaning convention" line: we should not build in a convention. the user shall be able to entirely specify their own naming and organisation for shared services. the point of afb is not to be opinionated about how users build their harness (except, for the very strong opinion that harnesses run in a container). 

> COMMENT: if, after reading my comments and answers in this doc, anything i the above table is still open, then add the triggers as suggested
### Technology Radar Positions

| Technology                          | Plan's Assessment                     | Suggested Radar Position                              | Gap                                                                                                                                                                                                                                                                                                                         |
| ----------------------------------- | ------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| LNAI (239 stars)                    | Risk acknowledged, coupling minimized | **Trial** — viable but unproven at scale, replaceable | None — well-assessed                                                                                                                                                                                                                                                                                                        |
| mergo (9k stars)                    | Stable with known zero-value risk     | **Adopt** — mature, well-understood                   | None                                                                                                                                                                                                                                                                                                                        |
| AgentGateway (2.3k stars, LF, v1.0) | Selected after comparison             | **Trial** — v1.0 is young despite LF backing          | None — alternatives evaluated                                                                                                                                                                                                                                                                                               |
| Gas City                            | "Evaluate at Phase 3"                 | **Assess** — not yet trialed                          | **Gap**: No maturity/fit assessment at all. What if Gas City is immature or architecturally incompatible? The plan assumes it can be "installed as a component" but doesn't assess whether Gas City's pack system conflicts with AFB's layer system. Trigger for evaluation exists (Phase 3) but no criteria for pass/fail. |
| podman-compose                      | Feature subset documented             | **Adopt** (for safe subset)                           | None — compliance table is excellent                                                                                                                                                                                                                                                                                        |
> COMMENT: gas city is a component that any user might add to their harness or not. it is not a required part of afb itself. gas city should have nothing to do with teh development of afb itself in this plan. 
### Priority Actions

1. **Retire mergo risk early**: Run characterization tests as a spike before Phase 4, not during it. If custom transformer is needed, that's scope expansion you want to size before committing to Phase 4's timeline.

2. **Document acceptance test architecture as a decision**: The os/exec black-box approach is load-bearing and shapes every phase. Make it an explicit choice with rationale.

3. **Add descoping triggers**: Define what's shippable at each dogfood milestone. "If I stop after Phase 5, here's what works and what doesn't."

4. **Specify trigger for per-file merge strategy**: Convert from unresolved question to deferred decision with a named trigger.

5. **Assess Gas City before Phase 3**: Even a lightweight "is this architecturally compatible?" check would prevent discovering a conflict mid-Phase-3. The pack system / layer system overlap is flagged in the risk register but not assessed.
> COMMENT: all these actions should be covered byother comments
---

## Alignment Critique (SPEC ↔ PLAN)

### Coverage

All functional requirements (FR1-FR11) have corresponding plan phases:

| Spec Requirement                   | Plan Phase(s)     | Coverage                                  |
| ---------------------------------- | ----------------- | ----------------------------------------- |
| FR1: Manifest-driven components    | 1, 5, 6           | Full                                      |
| FR2: Layered composition           | 4, 5              | Full                                      |
| FR3: Drift detection               | 8                 | Full                                      |
| FR4: Upstream push                 | 9                 | Full                                      |
| FR5: Script runner                 | 9                 | Full                                      |
| FR6: Container isolation           | 2, 3, 7           | Full                                      |
| FR7: Observability                 | 0 (zerolog setup) | **Partial** — setup only, no verification |
| FR8: Component commands            | 9                 | Full                                      |
| FR9: Validation                    | 1, 5              | Full                                      |
| FR10: Container build/lifecycle    | 2, 3              | Full                                      |
| FR11: Remote/session compatibility | —                 | **Not covered** — no phase tests this     |

### Over-Engineering Risks

- **Phase 0 scope**: 7 units of project infrastructure before a single feature exists. The spec doesn't require CI, lefthook, or a justfile — those are implementation choices. The plan treats them as features.

- **Phase 8 runtime diff** (Unit 8.2): Composing to a temp dir, running sync in a temp HOME, and diffing output is a complex mechanism. The spec requires drift detection, but this implementation approach has multiple failure modes (temp HOME doesn't match real HOME, sync command behaves differently in temp context). Consider whether this complexity is justified by actual user need or is theoretical completeness.
> COMMENT: what is the simpler alternative?
### Gaps

- **Spec verification criterion 3**: "Shared config change propagates via `afb layer pull` + `afb sync`." The plan has `afb layer pull` in the CLI commands table (architecture.md) but no phase implements or tests it. It's not in Phase 4 (composition) or Phase 5 (sync).
  - **Suggestion**: Add `afb layer pull` implementation to Phase 4 or Phase 5.
> COMMENT: do it, seems early phase 5 is best
- **Spec verification criterion 6**: "All stateful components have backup via `afb run <component>.backup`." No phase verifies this end-to-end. Phase 9 tests `afb run` but doesn't test a backup/restore cycle.

---

## Consolidated Summary

**Strengths**:
- Test-first throughout. Test names read as specifications. Best practice.
- Explicit decision inventory with reversibility classifications — rare and valuable.
- Fitness functions defined and mostly measurable.
- Dependency coupling well-managed (LNAI via configurable command, container runtime via port).
- mergo characterization tests before composition logic — correct risk mitigation ordering.
- Dogfood milestones create natural checkpoints.

**Highest-Priority Concerns**:

1. **Mergo spike should happen before Phase 4, not during it.** The zero-value risk is the biggest technical unknown. Discovering it mid-composition-implementation creates unplanned scope. Run Unit 4.2 as a standalone spike early.

2. **No descoping strategy.** 10 phases, 30+ units, solo dev. What's shippable if you stop at Phase 5? Phase 3? Name it explicitly.

3. **Missing acceptance test DSL layer.** All acceptance tests coupled to CLI output format via `os/exec`. One thin DSL package insulates tests from CLI UX changes. Cheap now, expensive to retrofit.

4. **Phase 0 is infrastructure theater.** Solo greenfield project doesn't need CI, lefthook, justfile, editorconfig, and a changelog before writing its first feature. Build infrastructure when the codebase needs it.

5. **Two spec requirements unverified**: FR7 (observability) and FR11 (remote/session compatibility) have no tests at all.

---

Review complete.

Next steps:
  Address findings above, then:
  /new-task docs/dev/ideas/declarative-afb/     — implement the plan
  /review docs/dev/ideas/declarative-afb/ --lens <other>  — review with a different lens (metz, feathers, architecture, resilience)
