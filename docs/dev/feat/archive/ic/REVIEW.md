# afb — Review (beck, farley, ford-parsons, kua)

Reviewed: SPEC.md + PLAN.md in `docs/dev/feat/ic/`

---

## Beck Lens — Simple Design / Plan Review

### Findings

1. **Scope creep** (PLAN.md lines 128-171): Unit 5 (rate monitoring) is half the plan's surface area and entirely new functionality — not consolidation of existing scripts. Introduces OAuth token extraction, API calls, header parsing, JSON status files, platform-native daemons.
   - **Suggestion**: Split rate monitoring into separate spec/plan. Ship Units 1-4+6 first (the consolidation promise), layer rate as follow-on.
> COMMENT: i want it in this plan. get all this done together.
2. **Speculative generality** (PLAN.md lines 162-170): `lib/daemon.sh` is a dedicated module for what amounts to one crontab line (Linux) and one plist file (macOS).
   - **Suggestion**: If rate stays in scope, inline daemon management into `rate.sh`. Two functions, not a separate file.
> COMMENT: OK, inline it.
3. **Tests test implementation, not behaviour** (PLAN.md lines 57-66): `test_install_creates_symlinks`, `test_install_creates_settings_json` test mechanics rather than user-visible behaviour. `afb check` already covers the behaviour.
   - **Suggestion**: Reduce install tests to: (a) install then check exits 0, (b) install --copy then files are real not symlinks, (c) uninstall then check exits 1. Let `afb check` be the assertion.
> COMMENT: agree
4. **Meaningless doc tests** (PLAN.md lines 183-187): `test_docs_install_exists` passes even if the file is wrong.
   - **Suggestion**: Either skip testing docs (review manually) or test for specific required content sections.
> COMMENT: skip doc tests. doesnt make sense.
5. **Good vertical slices** — each unit is demoable after completion. Dependency graph is clean. Test-list-as-design approach is solid. No issues.

---

## Farley Lens — Verification Architecture / ATDD Planning

### Findings

1. **No acceptance test layer** (PLAN.md, entire document): All tests are unit-level checks on individual functions. No outer acceptance test exercises the CLI end-to-end. For a bash CLI, the acceptance test IS the CLI.
   - **Suggestion**: Add acceptance-level test per unit exercising the real `afb` binary in a temp environment. For Unit 2: create temp accounts.json, run `afb install`, run `afb check`, assert exit 0. This catches integration bugs between common.sh and install.sh.
> COMMENT: do it.
2. **Rate test verification gap** (PLAN.md lines 137-141): `test_rate_refresh_writes_status` says "valid schema" but doesn't state how. Real API needs credentials; mocked curl doesn't test parsing.
   - **Suggestion**: State strategy explicitly: fixture-based tests (canned curl response headers) for parsing, separate manual smoke test against real API.
> COMMENT: do it.
3. **No automated parity verification** (SPEC.md line 168, AC-1): AC-1 requires identical results to `install.sh`. Plan's verification section mentions side-by-side comparison but no test automates it. Highest-risk acceptance criterion has no automated coverage.
   - **Suggestion**: Add parity test: run `install.sh` in temp dir A, run `afb install` in temp dir B, diff results.
> COMMENT: do it for now, but we dont need to keep install.sh around forever. it is available in the git history
4. **Platform-conditional tests unaddressed** (PLAN.md lines 143-146): macOS-specific tests (Keychain, launchd) and Linux-specific tests (cron, .credentials.json) — no strategy for running on a single-platform dev machine.
   - **Suggestion**: State strategy: skip platform-mismatched tests, or mock the platform boundary. Either is fine, but the plan should say which.
> COMMENT: mock the platform boundary
---

## Ford-Parsons Lens — Evolvability / Implicit Bets

### Fitness Function Audit

| Characteristic                    | Status         | Issue                                                        |
| --------------------------------- | -------------- | ------------------------------------------------------------ |
| Startup time (NFR-3: < 50ms)      | **vague**      | No measurement mechanism. How will you know if it regresses? |
| Functional parity with install.sh | **unmeasured** | AC-1 stated but no automated fitness function                |
| Rate API compatibility            | **unmeasured** | Beta headers could break any time; no canary check           |

### Coupling Concerns

- **`lib/work.sh` -> `lib/wt.sh`**: Acknowledged in dependency graph. Fine — natural dependency.
- **`afb` -> `python3`**: Every subcommand sources `common.sh` which uses python3 for JSON parsing. If python3 startup is slow, NFR-3 (50ms dispatch) may fail for the no-op case. Preflight catches absence but not latency.
> COMMENT: add a timeout?
### Implicit Bets Extracted

| Bet                          | Assumption                                               | Reversibility                                               | Risk                                                         |
| ---------------------------- | -------------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------ |
| Undocumented rate headers    | `anthropic-ratelimit-unified-*` headers persist          | cheap (error handling exists)                               | **med** — acknowledged, well-mitigated                       |
| Keychain service name        | `"Claude Code-credentials"` stable across Claude updates | cheap (one string)                                          | **low**                                                      |
| `~/.local/bin` convention    | Users accept this PATH location                          | cheap                                                       | **low**                                                      |
| python3 for all JSON         | python3 always available and fast enough                 | expensive (pervasive)                                       | **med** — "already a dependency" but startup cost unverified |
| Deleting install.sh and c.sh | No users depend on these scripts by path                 | **expensive** — users may have sourced c.sh in shell config | **med**                                                      |
| `.claude/worktrees/` path    | Compatible with Claude Code's own worktree convention    | cheap                                                       | **low**                                                      |

### Evolution Blockers

- **`install.sh` deletion (Unit 6)**: If any user has `source /path/to/c.sh` in `.zshrc`, deleting it breaks their shell. No deprecation step or migration check in the plan.
  - **Suggestion**: Keep `install.sh` and `c.sh` as thin wrappers that print deprecation notice and delegate to `afb`. Or at minimum grep common shell rc files for references before deleting.
> COMMENT: i have c in my profile. i will remove it. dont worry about this. install.sh is not in any paths. neither c.sh or install.sh are in prod.
### Missing Fitness Criteria

- **Parity regression**: No automated check that `afb install` output matches `install.sh`.
> COMMENT: this is only needed for the first migration right? then we can drop it. we are trying to migrate away from install.sh, no one is relying on it, it isnt in prod. 
- **Rate API canary**: Silent errors in status files when beta headers disappear. Consider `afb rate --self-test` or warning when headers haven't returned data in N cycles.
> COMMENT: self test looks good
### Summary Verdict

Consolidation (Units 1-4) is straightforward, low-risk, well-structured. Rate monitoring (Unit 5) doubles surface area and introduces the only external API dependency. Biggest evolution concern: implicit bet on deleting `install.sh`/`c.sh` without deprecation path.

---

## Kua Lens — Decision Quality / Reversibility

### Decision Inventory

| Decision                                       | Explicit?      | Reversibility                  | ADR? |
| ---------------------------------------------- | -------------- | ------------------------------ | ---- |
| Bash-only implementation                       | yes (NFR-1)    | expensive (rewrite)            | no   |
| python3 for JSON parsing                       | yes (NFR-1)    | expensive (pervasive)          | no   |
| `~/.local/bin/afb` symlink location            | yes (FR-4)     | cheap                          | no   |
| launchd on macOS, cron on Linux                | yes (non-goal) | cheap per platform             | no   |
| Delete install.sh + c.sh                       | yes (Unit 6)   | **expensive**                  | no   |
| Undocumented API headers for rate              | yes (Notes)    | cheap (graceful degradation)   | no   |
| Single crontab entry at GCD of intervals       | implicit       | cheap                          | no   |
| OAuth token from Keychain vs .credentials.json | yes (FR-25/26) | cheap                          | no   |
| `accounts.json` at repo root (no change)       | implicit       | expensive (schema is contract) | no   |

> COMMENT: record major non-reversable decisions in docs/dev/adr dir, with options, decision, justification, justification why not others.

### Reversibility Flags

- **Delete install.sh + c.sh**: Implicitly treated as cheap ("just delete files") but actually **expensive** — users may have shell config referencing these paths, no migration detection.
> COMMENT: see comments above, its cheap, not in prod
- **Bash-only implementation**: Stated as a goal, not a decision. Effectively irreversible — porting to Python/Go is a full rewrite. Reasoning ("already bash") is sufficient but should be stated as conscious decision, not inherited inertia.
> COMMENT: add ADR. justification is to have minimal dependencies. 
### Context Gaps

- **Why `~/.local/bin`?** Not `/usr/local/bin`, not a PATH-injecting wrapper? Decision stated but not motivated.
> COMMENT: i dont know the trade between the two locations, so cannot justify.
- **Why GCD for cron interval?** (PLAN.md line 240) Accounts with intervals 10 and 7 → GCD is 1 → daemon fires every minute. Likely unintentional.
> COMMENT: correct this is unintentional. change the logic to create a cron entry per account at the given interval per account. then we dont have this problem. 
### Deferral Attractors

- **"Windows deferred"** (SPEC.md line 24): No trigger specified. Classic attractor, not urgent.
> COMMENT: rather, windows is just not expected to be needed. will not be triggered.
- **"No single-account refresh for now"** (PLAN.md line 240): No trigger for when this becomes needed.


### Priority Actions

1. Add deprecation wrappers for `install.sh`/`c.sh` instead of deleting outright
2. Fix GCD cron interval logic (or document as "minimum of all intervals")
3. State bash-only as conscious decision with reasoning

---

## Alignment Critique (SPEC + PLAN)

**Traceability is good.** Every plan unit has "Traces to" with specific FR/AC numbers. Spot-check confirms correct mapping.

**Gap: AC-17 timing.** AC-17 says "install.sh and c.sh can be removed after migration verified." Plan deletes them in Unit 6 but doesn't define what "migration verified" means concretely. Who verifies? On how many systems?
> COMMENT: as above, we can delete immediately, not in prod, i will look after shell cleanup, scripts will still be in git

**Mild over-engineering**: `lib/daemon.sh` as separate module for ~40 lines of platform-specific code. Minor.

**No missing trace**: FR-10 (auto-create accounts.json) covered by Unit 2 test list (line 66).

---

## Consolidated Summary

The consolidation core (Units 1-4, 6) is well-structured, right-scoped, and clearly traced. Top concerns:

| #   | Finding                                                         | Lenses               | Severity |
| --- | --------------------------------------------------------------- | -------------------- | -------- |
| 1   | Rate monitoring inflates scope — new feature, not consolidation | Beck, Ford-Parsons   | high     |
| 2   | No acceptance-level integration tests                           | Farley               | high     |
| 3   | Deleting install.sh/c.sh riskier than acknowledged              | Ford-Parsons, Kua    | med      |
| 4   | GCD cron interval logic likely buggy                            | Kua                  | med      |
| 5   | Functional parity (AC-1) has no automated verification          | Farley, Ford-Parsons | med      |
| 6   | Platform-conditional test strategy unstated                     | Farley               | low      |
