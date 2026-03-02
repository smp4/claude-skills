# Worktree Guide — Reference

## Why worktrees?

Git worktrees let you check out multiple branches simultaneously in
separate directories. For `/new-task` this means:

- **Isolation**: Work doesn't touch the main checkout
- **Safety**: If something goes badly wrong, remove the worktree
- **Parallelism**: Multiple tasks can run in separate worktrees
- **Clean diffs**: The worktree starts clean from the base branch

## Creating a worktree

### Standard flow

```bash
# Derive names
FEATURE_SLUG="user-auth"
BRANCH_NAME="feature/${FEATURE_SLUG}"
BASE_BRANCH=$(git symbolic-ref --short HEAD)  # usually main or master
WORKTREE_PATH="../worktrees/${FEATURE_SLUG}"

# Create worktree with new branch
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"

# Enter the worktree
cd "$WORKTREE_PATH"
```

### Naming conventions

| Item | Pattern | Example |
|------|---------|---------|
| Feature slug | lowercase-hyphens | `csv-import` |
| Branch | `feature/<slug>` | `feature/csv-import` |
| Worktree path | `../worktrees/<slug>` | `../worktrees/csv-import` |

The `../worktrees/` directory sits alongside (not inside) the main
checkout. This avoids nested git repo confusion.

### If worktree already exists

```bash
# Check existing worktrees
git worktree list

# If the branch/worktree exists from a previous attempt:
git worktree remove "$WORKTREE_PATH" 2>/dev/null
git branch -D "$BRANCH_NAME" 2>/dev/null

# Then create fresh
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"
```

## Working in the worktree

### Golden rule

**All file operations happen in the worktree directory.** Never `cd` back
to the main checkout during execution. The only exception is the final
merge in Path B (commit-only) submission.

### Verifying you're in the worktree

```bash
# Should show the worktree path
pwd

# Should show the feature branch
git branch --show-current

# Should show as a linked worktree
git worktree list | grep "$(pwd)"
```

### Installing dependencies

The worktree is a full checkout but may need dependency installation:

```bash
# Node.js
[ -f package.json ] && npm install

# Python
[ -f requirements.txt ] && pip install -r requirements.txt
[ -f pyproject.toml ] && pip install -e .

# Rust
[ -f Cargo.toml ] && cargo build
```

## Committing in the worktree

Commits in the worktree go to the feature branch automatically:

```bash
git add -A
git commit -m "feat(<slug>): implement unit N — [name]

Traces to: FR-1, AC-2
Tests: 5 passing, 0 failing"
```

### Conventional commit format

```
<type>(<scope>): <short description>

<body — traces, test counts, notes>
```

Types:
- `feat` — new functionality
- `fix` — bug fix during implementation
- `test` — test-only changes
- `refactor` — restructuring without behaviour change
- `docs` — documentation updates
- `chore` — tooling, config, setup

## Submitting from the worktree

### PR flow (GitHub)

```bash
# Push from inside the worktree
git push -u origin "$BRANCH_NAME"

# Create PR (gh CLI works from worktrees)
gh pr create \
  --title "feat(${FEATURE_SLUG}): [feature name]" \
  --body-file /tmp/pr-body.md \
  --base "$BASE_BRANCH"
```

### Merge flow (no GitHub)

```bash
# Go back to main checkout
cd "<original-repo-path>"

# Merge feature branch with no-ff for clean history
git merge "$BRANCH_NAME" --no-ff \
  -m "feat(${FEATURE_SLUG}): [feature name]"
```

## Cleaning up worktrees

After the work is merged:

```bash
# Remove the worktree directory
git worktree remove "$WORKTREE_PATH"

# Delete the feature branch (only if merged)
git branch -d "$BRANCH_NAME"

# Prune any stale worktree references
git worktree prune
```

### If cleanup fails

```bash
# Force remove if worktree is dirty (data loss — use carefully)
git worktree remove --force "$WORKTREE_PATH"

# If branch won't delete, check if it was merged
git branch --merged | grep "$BRANCH_NAME"
```

## Edge cases

### No git repo at all

Skip worktree setup entirely. Work in the current directory.
Set SUBMIT_MODE to "local-only".

### Detached HEAD

If the repo is in detached HEAD state:
```bash
BASE_BRANCH=$(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD")
```

### Dirty working directory

If the main checkout has uncommitted changes:
```bash
# Stash them before creating worktree
git stash push -m "stash before /new-task"
git worktree add -b "$BRANCH_NAME" "$WORKTREE_PATH" "$BASE_BRANCH"
# Remind user to pop stash later
```

### Multiple tasks in parallel

Each task gets its own worktree and branch. They don't interfere:
```
../worktrees/
├── user-auth/          ← /new-task for user-auth feature
├── csv-import/         ← /new-task for csv-import feature
└── realtime-notifs/    ← /new-task for notifications feature
```
