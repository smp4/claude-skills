---
name: new-task
description: >
  Execute implementation work from a spec and plan. Reads SPEC.md and
  PLAN.md from a GitHub issue or local docs directory, creates a git
  worktree with a feature branch, implements units using strict TDD
  (red-green-refactor), verifies against the spec, and submits via PR
  or commit. Use when the user says "new task", "pick up the plan",
  "implement unit N", "start work on <feature>", or passes an issue
  number or docs path. Pairs with /new-plan for planning.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# /new-task — Load Plan → Worktree → TDD → Verify → Docs → Submit

## Overview

This command executes implementation work that was planned by `/new-plan`
(or any equivalent process that produced a SPEC.md and PLAN.md). All work ALWAYS
happens in an isolated git worktree, even for small changes. Submission is via PR or commit.

## Usage

```
/new-task #42                             # from GitHub issue
/new-task dev-docs/user-auth/             # from local docs directory
/new-task dev-docs/user-auth/ --unit 3   # specific unit only
/new-task dev-docs/user-auth/ --continuous  # run all units without handoff pause
```

The `$ARGUMENTS` value is parsed as:

- Starts with `#` → GitHub issue number
- Otherwise → path to directory containing SPEC.md and PLAN.md
- `--unit N` → execute only unit N (default: stop after each unit and write handoff)
- `--continuous` → run all units sequentially without stopping; no handoff docs written

## Workflow phases

Copy this checklist and update it as you progress:

```
Task Progress:
- [ ] Phase 0: Load (read spec + plan from source)
- [ ] Phase 1: Setup (create worktree + feature branch)
- [ ] Phase 2: Execute (TDD per unit — red/green/refactor)
- [ ] Phase 3: Verify (code satisfies spec)
- [ ] Phase 4: Doc sync (update project docs in the same branch)
- [ ] Phase 5: Submit (PR or commit) + cleanup
```

---

## Phase 0 — Load

**Goal**: Retrieve SPEC.md and PLAN.md from the specified source.

### From GitHub issue

```bash
# Get issue body (contains links to SPEC.md and PLAN.md)
gh issue view <number> --json body --jq '.body'
```

The issue body (created by `/new-plan`) contains a `## Docs` table with
links to SPEC.md and PLAN.md on the feature branch. Follow those links
to read the files directly from the repo. The files live at:
```
dev-docs/<slug>/SPEC.md
dev-docs/<slug>/PLAN.md
```

### From local docs directory

```bash
# Verify the source files exist
ls $ARGUMENTS/SPEC.md $ARGUMENTS/PLAN.md
```

Read both files directly.

### Issue number extraction

Parse the frontmatter of SPEC.md for the driving issue number:

```yaml
---
issue: "#N"
slug: <feature-slug>
---
```

Store as `$ISSUE_NUM` (e.g. `42`). If the `issue:` field is absent or
this is a local-only repo, set `$ISSUE_NUM=""` — all `gh issue comment`
steps below are silently skipped when `$ISSUE_NUM` is empty.

### Load validation

Before proceeding, validate that upstream artefacts have the expected
structure from `/new-plan`:

**SPEC.md checks:**
- [ ] File exists
- [ ] Contains `## 4. Functional requirements` with FR-x entries
- [ ] Contains `## 8. Acceptance criteria checklist` with AC-x entries

**PLAN.md checks:**
- [ ] File exists
- [ ] Contains `## Implementation units` with numbered units
- [ ] Each unit has a `**Tests first**` section
- [ ] Each unit has a `**Traces to**` line referencing FR-x or AC-x

If validation fails, tell the user what's missing:

```
PLAN.md is missing "Tests first" in Unit 3, and SPEC.md has no AC-x entries.
These are required for TDD execution.

Fix options:
  /new-plan dev-docs/<slug>/ — re-run planning to fill gaps
  Fix manually              — add the missing sections, then re-run /new-task
```

### Argument parsing

Parse flags from `$ARGUMENTS`:

- `--unit N` → set `$TARGET_UNIT=N`, run only that unit
- `--continuous` → set `$CONTINUOUS=true`
- Neither → set `$TARGET_UNIT=""`, `$CONTINUOUS=false` (default: stop after each unit)

### Unit selection

If `$TARGET_UNIT` is set, identify that unit from PLAN.md.
If no unit specified, present the unit list:

```
Found N implementation units:
  Unit 1: [name] — [goal]
  Unit 2: [name] — [goal]
  ...

Mode: stop-after-each-unit (default) — write handoff-unit-N.md after each unit.
Use --continuous to run all units without pausing.
```

---

## Phase 1 — Setup

**Goal**: Create an isolated worktree and feature branch for this work.

See [reference/worktree-guide.md](reference/worktree-guide.md) for
detailed worktree management procedures.

### 1a — Detect environment

```bash
# Are we in a git repo?
git rev-parse --is-inside-work-tree 2>/dev/null

# Is there a GitHub remote?
git remote get-url origin 2>/dev/null

# What branch are we on?
git branch --show-current
```

Record:
- `HAS_GIT`: true/false
- `HAS_GITHUB`: true/false
- `BASE_BRANCH`: current branch (usually main/master)
- `SUBMIT_MODE`: "pr" if HAS_GITHUB, else "commit"

If NOT in a git repo, skip worktree setup — work in the current directory
and set SUBMIT_MODE to "local-only".

### 1b — Create worktree

Derive branch name and worktree path from the feature slug:

```bash
FEATURE_SLUG="<derived-from-spec-feature-name>"
BRANCH_NAME="feat/${FEATURE_SLUG}"
WORKTREE_PATH="../worktrees/${FEATURE_SLUG}"

# Create the worktree with a new branch
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"
```

### 1c — Enter worktree

**All subsequent work happens exclusively in the worktree.**

```bash
cd "$WORKTREE_PATH"
```

Confirm the working directory before proceeding. Do NOT modify files in
the original checkout.

### 1d — Initial commit (empty)

Create a clean starting point:
```bash
git commit --allow-empty -m "chore(${FEATURE_SLUG}): begin implementation

Spec source: [GH issue #N / dev-docs/<slug>/]
Plan: N units to implement"
```

---

## Phase 2 — Execute

**Goal**: Implement each unit using strict Red → Green → Refactor.

For TDD methodology, see `../shared/reference/tdd-guide.md`.

### Persona loading

Read `../shared/reference/personas/beck.md` — section
"Mode: TDD Session". Apply those strategy-selection and design heuristics
throughout TDD.

**When modifying existing code** (files that already exist with production
logic): also read `../shared/reference/personas/feathers.md` —
section "Mode: Modifying Existing Code". Apply the legacy code change
algorithm: characterize before changing, find seams, use sprout/wrap.

### Per-unit cycle

For each unit (or the single unit if `--unit N`):

```
Unit N: [name]
- [ ] 2a. Read unit spec (tests-first list + implementation notes)
- [ ] 2b. Write failing tests (RED)
- [ ] 2c. Write minimum code to pass (GREEN)
- [ ] 2d. Refactor for clarity (REFACTOR)
- [ ] 2e. Run full test suite — no regressions
- [ ] 2f. Commit the unit
- [ ] 2g. Update SPEC.md if behaviour diverged
- [ ] 2h. Write handoff doc and stop (skip if --continuous or last unit)
```

### 2a — Read unit spec

From PLAN.md, extract for the current unit:
- **Delivers**: what should work after this unit
- **Files**: what to create or modify
- **Tests first**: the test list (this drives everything)
- **Traces to**: which FR-x and AC-x are covered

### 2b — RED: Write failing tests

- Write the test names from the plan's "Tests first" list
- Implement each test body one at a time
- Run each test — confirm it fails for the right reason
- Use naming: `test_[unit]_[scenario]_[expected_outcome]`

### 2c — GREEN: Minimum code to pass

- Write the simplest, most direct code that makes the test pass
- No cleverness, no generalisation, no "while I'm here"
- Run the test — confirm it passes
- Run the full suite — confirm no regressions

### 2d — REFACTOR: Clean up

- Remove duplication
- Improve names
- Split long functions
- Full suite must stay green after each change

### 2e — Full test suite

```bash
# Adapt to project's test runner
pytest -v --tb=short 2>&1 || npm test 2>&1 || cargo test 2>&1
```

If regressions are found, fix them before proceeding.

### 2f — Commit the unit

```bash
git add -A
git commit -m "feat(${FEATURE_SLUG}): implement unit N — [unit name]

Traces to: FR-x, FR-y, AC-z
Tests: N passing, 0 failing"
```

Use conventional commit format. Reference requirement IDs.

### 2g — Spec drift check

If implementation revealed that a requirement was ambiguous, impossible,
or needed adjustment:
1. Note the change
2. Update the local copy of SPEC.md
3. Flag it for the user in Phase 4

### 2h — Handoff (default) or continue (`--continuous`)

**Skip this step entirely if:**
- `$CONTINUOUS=true`, OR
- This is the only unit in the plan, OR
- This is the last unit in the plan (proceed to Phase 3 instead)

Otherwise, write `dev-docs/${FEATURE_SLUG}/handoff-unit-N.md` with the
following content, then stop and tell the user what to do next.

#### Handoff document template

```markdown
# Handoff: Unit N -> Unit N+1

## Session bootstrap
- **Worktree**: <worktree-path>
- **Branch**: feat/<slug>
- **Test command**: <project test runner invocation, e.g. pytest tests/ -x>
- **Docs**: dev-docs/<slug>/

## Next command

    /new-task dev-docs/<slug>/ --unit <N+1>

## Unit N complete: [name]
- **Tests added**: [count] passing
- **Key files changed**: [list with one-line descriptions]
- **Key decisions**: [choices made during implementation, tradeoffs]
- **Traces to**: FR-x, AC-x

## Deviations from plan
- [deviation + rationale, or "None"]

## Plan assumptions that changed
- [things PLAN.md says about future units that are now wrong, or "None"]

## Known issues / deferred items
- [items punted, or "None"]

## Next unit: [N+1 name]
- **Goal**: [one-line goal from plan]
- **Entry point**: [first test to write]
- **Watch out for**: [anything non-obvious the next session should know]
```

Commit the handoff doc:

```bash
git add dev-docs/${FEATURE_SLUG}/handoff-unit-N.md
git commit -m "docs(${FEATURE_SLUG}): handoff unit N -> N+1"
```

Then stop and output:

```
Unit N complete — [name]

Handoff written: dev-docs/<slug>/handoff-unit-N.md

To continue in a fresh session:
  1. Run /clear (or start a new conversation)
  2. Paste: /new-task dev-docs/<slug>/ --unit <N+1>
```

**Do NOT proceed to Unit N+1 or Phase 3. Stop here.**

---

## Phase 3 — Verify

**Goal**: Confirm the implementation satisfies the specification.

For verification methodology, see
`../shared/reference/verification-guide.md`.

Read `../shared/reference/personas/farley.md` — section
"Mode: Verification". Apply Farley's trust formula: DSL contract +
acceptance tests + all green + static analysis.

```
Verification:
- [ ] 3a. Walk through every AC-x — does it pass?
- [ ] 3b. Full test suite — all green?
- [ ] 3c. Check spec accuracy
- [ ] 3d. Generate VERIFICATION.md
```

### 3a — Acceptance criteria sweep

For each AC-x in SPEC.md:
1. Identify the covering test(s)
2. Confirm they pass
3. Record the mapping

### 3b — Full suite

Run the full test suite one final time.

### 3c — Spec accuracy

If SPEC.md or PLAN.md were modified during execution, ensure
the changes are consistent and documented.

### 3d — Generate VERIFICATION.md

Create VERIFICATION.md (in the worktree) with the traceability matrix,
test summary, and any open items. Use the template from the shared
verification guide.

```bash
git add VERIFICATION.md
git commit -m "docs(${FEATURE_SLUG}): add verification report

All acceptance criteria satisfied.
Tests: N passing, 0 failing"
```

If `$ISSUE_NUM` is set, add a comment to the driving issue:

```bash
REPO_URL=$(gh repo view --json url -q .url)
gh issue comment $ISSUE_NUM --body "## Verification report ready

| Document | Link |
|---|---|
| Verification | [VERIFICATION.md](${REPO_URL}/blob/feat/${FEATURE_SLUG}/dev-docs/${FEATURE_SLUG}/VERIFICATION.md) |"
```

---

## Phase 4 — Doc Sync

**Goal**: Ensure project documentation is accurate and consistent with
the implementation, in the same branch before submission.

See [reference/doc-sync-guide.md](reference/doc-sync-guide.md) for
drift patterns, tone-matching rules, proposal templates, and ADR format.

```
Doc Sync:
- [ ] 4a. Discover existing project docs
- [ ] 4b. Audit for drift between docs and implementation
- [ ] 4c. Propose changes (explain why, ask permission for new files)
- [ ] 4d. Apply approved changes and commit
```

### 4a — Discover existing docs

```bash
find . -maxdepth 3 -type f \( \
  -name "*.md" -o -name "*.rst" -o -name "*.txt" -o -name "*.adoc" \
\) | grep -viE '(node_modules|vendor|\.git|SPEC\.md|PLAN\.md|VERIFICATION\.md)' \
  | head -50
```

If no project docs exist, skip to Phase 5.

### 4b — Audit for drift

For each relevant doc, compare against what was built. Check for stale
information, missing capabilities, broken examples, and dead references.

**Critical rules:**
- **Only document what exists.** If it doesn't pass a test, it doesn't
  go in the docs. Never document planned or aspirational features.
- **Match the existing tone.** Read the surrounding text. Mirror length,
  person, formality, structure, and code example style.
- **Don't restructure docs you didn't break.** Fix only what your change
  made inaccurate.

### 4c — Propose changes

For each affected file, present: what's there now, what needs to change,
and **why** (traced to requirement IDs where possible).

- **Updates to existing files**: apply unless the user objects
- **New files**: always ask for explicit permission first
- **When writing new docs (or significantly rewriting existing)**: run
  `/write-docs` — it detects Diátaxis usage, classifies the content if
  applicable, and enforces style. If content would span multiple quadrants,
  propose splitting before asking user permission.
- **Never propose docs for behaviour that isn't implemented and tested**

Wait for user approval before applying.

### 4c+ — Domain drift check

**When**: a DOMAIN.md exists (`dev-docs/domain/DOMAIN.md` or
`dev-docs/domain/*/DOMAIN.md`) AND a DSL interfaces file exists
(`acceptance_tests/dsl/interfaces.py` or `acceptance-tests/dsl/interfaces.ts`).

**Skip** if either file is missing.

1. Read both files
2. List all DSL interface methods
3. List all glossary entries with non-TODO DSL mappings
4. Collect discrepancies:
   - Glossary mapping references a method that doesn't exist in DSL
   - DSL method has no corresponding glossary entry
   - Naming mismatches (semantic, not case convention)
5. Present a **single batched summary** of all findings
6. Let the user decide which to fix before submitting
7. Apply approved fixes to DOMAIN.md on the feature branch

Do NOT interrupt per-violation. Collect everything, report once.

Note: `snake_case` (Python) vs "Title Case" (glossary) is a convention
difference, not drift. The DSL mapping field bridges this.

See [reference/doc-sync-guide.md](reference/doc-sync-guide.md) for
domain drift detection patterns and resolution rules.

### 4d — Apply and commit

```bash
git add -A
git commit -m "docs(${FEATURE_SLUG}): update project docs for [feature]

All documented behaviour is tested and verified."
```

This commit is on the feature branch — included in the PR or merge.

---

## Phase 5 — Submit + Cleanup

**Goal**: Submit the work, get user sign-off, and clean up artefacts.

### 5a — Present results

```
## Task Complete — [feature name]

**Branch**: feature/<slug>  |  **Tests**: X passing, 0 failing
**Units completed**: N of M  |  **Verification**: all AC satisfied
**Docs synced**: [list of updated doc files]
**Handoff docs**: [N handoff-unit-*.md files on branch / none (--continuous mode)]

### Changes summary
- [files created/modified, with brief descriptions]

### Spec changes (if any)
- [list any requirements adjusted during execution]

Ready to submit?
```

**Wait for user approval before submitting.**

### 5b — Submit

#### Path A — Pull request (GitHub repo)

```bash
git push -u origin "$BRANCH_NAME"

# Append VERIFICATION.md to PR body if it exists
if [ -f VERIFICATION.md ]; then
  echo "" >> /tmp/pr-body.md
  echo "---" >> /tmp/pr-body.md
  echo "" >> /tmp/pr-body.md
  cat VERIFICATION.md >> /tmp/pr-body.md
fi

# If source was a GH issue, fetch its labels and apply to PR
# Step 1: get labels from source issue
ISSUE_LABELS=$(gh issue view <ISSUE_NUMBER> --json labels --jq '.labels[].name' | tr '\n' ',' | sed 's/,$//')

# Step 2: build label flags (one --label per value)
LABEL_FLAGS=""
if [ -n "$ISSUE_LABELS" ]; then
  while IFS=',' read -ra LBLS; do
    for lbl in "${LBLS[@]}"; do
      LABEL_FLAGS="$LABEL_FLAGS --label \"$lbl\""
    done
  done <<< "$ISSUE_LABELS"
fi

# Step 3: create PR with labels
eval gh pr create \
  --title "feat(${FEATURE_SLUG}): [feature name]" \
  --body-file /tmp/pr-body.md \
  --base "$BASE_BRANCH" \
  $LABEL_FLAGS
```

PR body must include: summary, "Closes #N" (if GH issue source), spec
reference, implementation units checklist, doc updates, verification
status, and test results. VERIFICATION.md is appended after `---`.

If units were implemented across sessions (handoff docs exist): add a
note — "Implemented across N sessions; handoff-unit-*.md files on branch
serve as session transfer records."


#### Path B — Commit only (no GitHub)

```bash
cd -
git merge "$BRANCH_NAME" --no-ff \
  -m "feat(${FEATURE_SLUG}): [feature name]

Implements spec from dev-docs/<slug>/
All acceptance criteria verified."
```

#### Path C — Local only (no git)

Report the list of files created/modified and the verification status.

### 5c — Archive planning artefacts

After the PR is merged (or the commit lands on main), move the feature
docs directory to `dev-docs/archive/`. This preserves them for reference
without cluttering the active `dev-docs/` space.

**Wait for the user to confirm the PR is merged before running this step.**

```bash
# On the base branch (main/master), after merge
git checkout "$BASE_BRANCH"
git pull

git mv "dev-docs/${FEATURE_SLUG}/" "dev-docs/archive/${FEATURE_SLUG}/"
git commit -m "archive(${FEATURE_SLUG}): move planning docs to dev-docs/archive"
```

**Before pushing, show the user the commit and ask for confirmation:**

```
Ready to push archive commit to origin:

  git mv dev-docs/${FEATURE_SLUG}/ dev-docs/archive/${FEATURE_SLUG}/
  commit: archive(${FEATURE_SLUG}): move planning docs to dev-docs/archive

Push now?
```

Only push after explicit confirmation:
```bash
git push origin "$BASE_BRANCH"
```

After push, if `$ISSUE_NUM` is set, add a final comment to the driving issue:

```bash
REPO_URL=$(gh repo view --json url -q .url)
gh issue comment $ISSUE_NUM --body "## Implementation complete — docs archived to main

| Document | Link |
|---|---|
| Specification | [SPEC.md](${REPO_URL}/blob/main/dev-docs/archive/${FEATURE_SLUG}/SPEC.md) |
| Plan | [PLAN.md](${REPO_URL}/blob/main/dev-docs/archive/${FEATURE_SLUG}/PLAN.md) |
| Verification | [VERIFICATION.md](${REPO_URL}/blob/main/dev-docs/archive/${FEATURE_SLUG}/VERIFICATION.md) |"
```

Leave the issue open — the user decides when to close it.

**If an ADR is warranted:**
See [reference/doc-sync-guide.md](reference/doc-sync-guide.md) for ADR
format and when to propose one. Create the ADR in `dev-docs/archive/${FEATURE_SLUG}/`
or `dev-docs/adr/` before the archive commit, then include it in the same push.

### 5d — Worktree cleanup

```bash
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH_NAME"  # only if merged
```

After the PR is merged, tell the user:

```
Implementation complete.

Next steps (run /review in a NEW conversation — so the reviewer hasn't seen this session):
  /review src/<path>/ --lens beck         — review the code for simple design
  /review src/<path>/ --lens metz         — review for OO design quality
  /review src/<path>/ --lens feathers     — review for legacy code safety (if modifying existing)

Cleanup:
  git push origin --delete <branch>       — clean up remote branch after merge

If domain artefacts exist, /review will also check for domain term drift.
```

Replace paths and branch with actual values.

---

## Quick reference: When to go back

| Current Phase | Trigger | Go back to |
|---------------|---------|------------|
| Phase 0 | Source missing or invalid | Ask user for correct source |
| Phase 1 | Not a git repo | Skip worktree, work in place |
| Phase 2 | Test reveals design flaw | Update plan, re-do unit |
| Phase 2 | Spec gap discovered | Note it, flag in Phase 4 |
| Phase 3 | AC fails | Phase 2 (fix that unit) |
| Phase 4 | Docs reference unimplemented feature | Remove it — never doc what doesn't exist |
| Phase 4 | User rejects doc change | Drop that change, proceed |
| Phase 5 | User requests changes | Phase that owns the change |
| Phase 5 | PR creation fails | Path B or C fallback |
