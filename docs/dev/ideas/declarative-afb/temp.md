> COMMENT: second contributor is claude! lefthook protects linting errors from getting to CI. lefthook and linting stay early. ok to add CI later. justfile as we go, ok. OK for changelog later. boilerplate needed early.

> COMMENT: OK

> COMMENT: OK

> COMMENT: ok, fix it. cover the full vertical slice

> COMMENT: split phase 5 as sync pipeline, phase 6 as lockfile (all).

> COMMENT: fine as is, will be converted to beads for execution possibly with multiple agents. every bead will need to be self standing. beads will be updated during execution.

> COMMENT: add the DSL package. note domain.md document.


> COMMENT: agree, this is contrived. fine as an architectural concern test but should not be included or named anywhere that implies it is e2e or ATDD


> COMMENT: compare the options you present, make a selection, justify it, write an ADR justifying it, and justifying why other paths not taken. update the plan and ATDD

> COMMENT: add it

> COMMENT: option a, do it


> COMMENT: add the golden-file comparison 

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

7. **Three-tier strategy is well-designed** (architecture.md lines 974-981): Unit (pure domain, no deps), Integration (git, lnai), E2E (podman). Clear tier isolation. The fitness function "unit tests run with no external tools" is the right guard. But how is it enforced? If someone adds an `os/exec` call to a domain package, what catches it?
   - **Suggestion**: The "tier isolation" fitness function needs a mechanism. Options: (a) CI job runs domain tests in a container with no git/podman installed, (b) `go vet` custom analyzer, (c) grep for `os/exec` in `internal/domain/`. Option (a) is strongest.
> COMMENT: option a, do it
8. **Verification gap — generated Containerfile semantic correctness**: hadolint checks syntax. `podman-compose config` checks compose syntax. But nothing verifies that the generated Containerfile actually installs the declared components. A manifest with 3 components should produce a Containerfile with 3 RUN install lines. This is a golden-file test opportunity.
   - **Suggestion**: Unit 2.1 tests (lines 234-239) cover individual assertions but consider a golden-file comparison for the full generated output. Catches unintended ordering changes, missing sections, etc.
> COMMENT: add the golden-file comparison 
### Summary

The ATDD structure is strong — each phase has a meaningful acceptance test, and Phase 4's composition test is exemplary. The main gap is the missing DSL layer, which couples all acceptance tests to CLI output format. Two spec requirements (FR7 observability, FR11 remote compatibility) have no verification at all. The tier isolation fitness function needs an enforcement mechanism, not just a statement.

---
