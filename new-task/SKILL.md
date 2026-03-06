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
/new-task #42                        # from GitHub issue
/new-task docs/user-auth/            # from local docs directory
/new-task docs/user-auth/ --unit 3   # specific unit only
```

The `$ARGUMENTS` value is parsed as:

- Starts with `#` → GitHub issue number
- Otherwise → path to directory containing SPEC.md and PLAN.md
- `--unit N` → execute only unit N (default: all units sequentially)

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
# Extract spec and plan from issue body
gh issue view <number> --json body --jq '.body' > /tmp/issue-body.md
```

Parse the issue body to extract the Specification and Implementation Plan
sections. If the issue was created by `/new-plan`, these sections are
clearly delimited by `## Specification` and `## Implementation Plan`
headings.

Save them locally for reference during execution:
```bash
mkdir -p .task-context
# Extract and save each section
```

### From local docs directory

```bash
# Verify the source files exist
ls $ARGUMENTS/SPEC.md $ARGUMENTS/PLAN.md
```

Read both files directly.

### Load validation

Before proceeding, confirm:
- SPEC.md exists and contains numbered requirements (FR-x, AC-x)
- PLAN.md exists and contains numbered implementation units
- Each unit has a "Tests first" section

If validation fails, tell the user what's missing and suggest they run
`/new-plan` to generate proper deliverables.

### Unit selection

If `--unit N` was specified, identify Unit N from PLAN.md.
If no unit specified, present the unit list and ask:

```
Found N implementation units:
  Unit 1: [name] — [goal]
  Unit 2: [name] — [goal]
  ...

Execute all units sequentially, or a specific unit?
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

Spec source: [GH issue #N / docs/<slug>/]
Plan: N units to implement"
```

---

## Phase 2 — Execute

**Goal**: Implement each unit using strict Red → Green → Refactor.

For TDD methodology, see `~/.claude/skills/shared/reference/tdd-guide.md`.

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

---

## Phase 3 — Verify

**Goal**: Confirm the implementation satisfies the specification.

For verification methodology, see
`~/.claude/skills/shared/reference/verification-guide.md`.

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
- **Never propose docs for behaviour that isn't implemented and tested**

Wait for user approval before applying.

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


#### Path B — Commit only (no GitHub)

```bash
cd -
git merge "$BRANCH_NAME" --no-ff \
  -m "feat(${FEATURE_SLUG}): [feature name]

Implements spec from docs/<slug>/
All acceptance criteria verified."
```

#### Path C — Local only (no git)

Report the list of files created/modified and the verification status.

### 5c — Artefact cleanup

After submission, the code and tests are the living specification. Offer
to clean up:

```
The spec and plan have served their purpose. The GH issue / git history
preserves them.

Would you like to:
1. Clean up planning artefacts (delete SPEC.md, PLAN.md, VERIFICATION.md)
2. Generate an ADR first, then clean up
3. Keep everything as-is
```

**Option 1 — cleanup:**
```bash
rm -f "docs/${FEATURE_SLUG}"/{SPEC,PLAN,VERIFICATION}.md
rmdir "docs/${FEATURE_SLUG}/" 2>/dev/null
git add -A && git commit -m "chore(${FEATURE_SLUG}): remove planning artefacts"
```

**Option 2 — ADR + cleanup:**
See [reference/doc-sync-guide.md](reference/doc-sync-guide.md) for ADR
format and when to propose one. Create the ADR, commit, then run cleanup.

If Path A, push the cleanup/ADR commit and update the PR.

### 5d — Worktree cleanup

```bash
git worktree remove "$WORKTREE_PATH"
git branch -d "$BRANCH_NAME"  # only if merged
```

After the PR is merged, tell the user to delete the remote branch:

```
Once you've merged the PR, delete the remote branch to keep the repo clean:

  git push origin --delete ${BRANCH_NAME}
```

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
