---
name: pr-cleanup
description: >
  Run after /new-task has pushed a PR and the PR has been merged on GitHub.
  Proves the PR is merged to main (GitHub API + remote ancestry check), pulls
  main, deletes local and remote feature branches, and removes the local
  worktree. Use when the user says "pr-cleanup", "clean up the branch",
  "clean up after merge", or references cleanup of a feature branch after merging.
---

# /pr-cleanup — Verify Merge → Pull Main → Remove Branch + Worktree

## Overview

Runs after `/new-task` has pushed a PR and you have merged it on GitHub. Verifies the merge definitively before touching anything, then cleans up local and remote artefacts.

## Usage

```
/pr-cleanup                      # auto-detect from worktrees + recent merged PRs
/pr-cleanup feat/csv-import      # by branch name
/pr-cleanup csv-import           # by slug (expands to feat/<slug>)
/pr-cleanup 42                   # by PR number
```

---

## Phase 1 — Identify target

Parse `$ARGUMENTS`:

| Input | Treatment |
|---|---|
| Numeric (e.g. `42`) | PR number — fetch branch with `gh pr view 42 --json headRefName -q .headRefName` |
| Starts with `feat/` | Branch name directly |
| Non-empty string | Slug — prepend `feat/` |
| Empty | Auto-detect (see below) |

**Auto-detect (empty args):**

```bash
git worktree list --porcelain
```

Collect all worktrees whose branch matches `feat/*`. Then:
- Exactly one found → use it
- Multiple found → list them and stop; ask user to specify which
- None found → fall back:

```bash
gh pr list --state merged --author @me --limit 5 --json number,headRefName,title
```

Show the list and ask user to pick.

Resolve these variables before proceeding:

```
BRANCH_NAME      feat/<slug>
FEATURE_SLUG     <slug>
WORKTREE_PATH    ../worktrees/<slug>
PR_NUMBER        <number>
BASE_BRANCH      main  (or master — read from gh pr view)
```

If any variable cannot be resolved, stop and tell the user what's missing.

---

## Phase 2 — Verify merge

**This is a hard gate. Do not touch any branches or worktrees until all checks pass.**

### Check A — GitHub API (required)

```bash
gh pr view "$PR_NUMBER" --json state,mergedAt,baseRefName
```

Required:
- `state` = `"MERGED"` (not `CLOSED`, not `OPEN`)
- `mergedAt` non-null
- `baseRefName` = `"$BASE_BRANCH"`

If any condition fails, stop immediately:

```
ABORT: PR #<N> is not merged.
  state    : <value>
  mergedAt : <value>

Do not run /pr-cleanup until the PR is merged on GitHub.
```

### Check B — Remote ancestry (informational)

```bash
git fetch origin
BRANCH_TIP=$(git rev-parse "origin/$BRANCH_NAME" 2>/dev/null)
git merge-base --is-ancestor "$BRANCH_TIP" "origin/$BASE_BRANCH"
```

- Exit 0 → branch tip is reachable from `origin/main`. Full confirmation:

```
PR #<N> (feat/<slug>) confirmed merged.
  GitHub state : MERGED  (merged at <mergedAt>)
  Remote check : branch tip reachable from origin/<base> ✓
```

- Exit 1 → expected for squash/rebase merges (the original tip won't be in main). Show:

```
PR #<N> state from GitHub: MERGED (merged at <mergedAt>)
Remote ancestry check: branch tip NOT found in origin/<base>
  (This is normal for squash or rebase merges.)

GitHub confirms the PR is merged, but the original commits are not
in origin/main as-is. If you used squash or rebase merge, this is expected.

Proceed with cleanup? [y/N]
```

Stop and wait for explicit `y` before continuing. Any other input aborts.

- If `origin/$BRANCH_NAME` does not exist (remote branch already deleted), skip Check B and note it.

---

## Phase 3 — Pull main

```bash
git checkout "$BASE_BRANCH"
git pull origin "$BASE_BRANCH"
```

Show the resulting HEAD:

```
Local main updated → <short-sha> <commit message>
```

---

## Phase 4 — Cleanup

Each step is idempotent: if the target is already gone, log it and continue.

### 4a — Remove worktree

```bash
# Check existence first
git worktree list | grep "$WORKTREE_PATH"
```

If found:
```bash
git worktree remove "$WORKTREE_PATH"
git worktree prune
```

If not found: `  (skipped — worktree already removed)`

### 4b — Delete local branch

Use safe delete only (`-d`, never `-D` without prompting):

```bash
git branch -d "$BRANCH_NAME"
```

If `-d` fails (git says not fully merged — happens with squash merges):

```
Local branch feat/<slug> could not be deleted safely (git -d).
  This is expected after a squash/rebase merge.
  Force delete? [y/N]
```

Wait for explicit `y`. If confirmed:
```bash
git branch -D "$BRANCH_NAME"
```

If not found: `  (skipped — local branch already deleted)`

### 4c — Delete remote branch

```bash
git push origin --delete "$BRANCH_NAME"
```

If remote branch is already deleted (error contains "remote ref does not exist"): `  (skipped — remote branch already deleted)`

### 4d — Final report

```
Cleanup complete for feat/<slug>:
  ✓ Local main updated   → <sha> <message>
  ✓ Worktree removed     ../worktrees/<slug>
  ✓ Local branch deleted   feat/<slug>
  ✓ Remote branch deleted  origin/feat/<slug>
```

Replace any skipped step with `  (skipped — already removed)`.
