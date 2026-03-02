# Claude Code Skills: /new-plan + /new-task

A paired skill set for disciplined feature development with Claude Code.

## Architecture

```
/new-plan (planning)              /new-task (execution)
┌──────────────────────┐         ┌──────────────────────────┐
│ Phase 0: Interview   │         │ Phase 0: Load spec+plan  │
│ Phase 1: Spec        │──────▶  │ Phase 1: Worktree setup  │
│ Phase 2: Plan        │  hands  │ Phase 2: TDD per unit    │
│ Phase 3: Handoff     │  off    │ Phase 3: Verify vs spec  │
│   → GH issue or docs │         │ Phase 4: PR or commit    │
└──────────────────────┘         └──────────────────────────┘
                    ▲                        ▲
                    │   shared/reference/    │
                    └────── tdd-guide.md ────┘
                    └── verification-guide.md┘
```

## Workflow

1. **`/new-plan`** — Interviews you, produces SPEC.md + PLAN.md, gets your
   approval, hands off via GitHub issue or `docs/<feature>/` directory.

2. **`/new-task #42`** or **`/new-task docs/my-feature/`** — Picks up the
   plan, creates a git worktree, implements units using strict TDD
   (red → green → refactor), verifies against the spec, submits via PR
   or commit.

## Installation

```bash
chmod +x install.sh

# Symlink mode (recommended) — skills stay in sync with this repo
./install.sh

# Copy mode — standalone snapshot, no sync
./install.sh --copy

# Uninstall
./install.sh --uninstall
```

### Staying in sync

With symlink mode (the default), your workflow is:

```bash
# Edit skills directly (either location works — they're the same files)
vim ~/.claude/skills/new-plan/SKILL.md
# or
vim ~/repos/claude-skills/new-plan/SKILL.md

# Commit and push from the repo
cd ~/repos/claude-skills
git add -A && git commit -m "improve interview questions" && git push

# On another machine, pull to update
git pull   # skills update immediately via symlinks
```

Restart Claude Code after pulling changes to reload skill metadata.

## File layout

```
~/.claude/skills/
├── new-plan/
│   ├── SKILL.md                    # 322 lines — planning workflow
│   └── reference/
│       ├── interview-guide.md      # Question bank + anti-patterns
│       ├── planning-guide.md       # Kent Beck decomposition heuristics
│       └── handoff-guide.md        # GH issue vs local docs packaging
├── new-task/
│   ├── SKILL.md                    # 416 lines — execution workflow
│   └── reference/
│       └── worktree-guide.md       # Git worktree management
└── shared/
    └── reference/
        ├── SKILL.md                # Discovery-only (disabled for auto-invoke)
        ├── tdd-guide.md            # Red-green-refactor, test naming, Beck rules
        └── verification-guide.md   # Spec compliance, traceability matrix
```

## Design decisions

- **Skills, not commands**: Uses the newer Agent Skills format with YAML
  frontmatter, progressive disclosure, and model-invoked triggering.
- **Separated concerns**: Planning and execution are independent skills
  that compose through SPEC.md + PLAN.md as the contract.
- **Shared references**: TDD and verification guides live in
  `shared/reference/` with `disable-model-invocation: true` to avoid
  phantom triggering.
- **Graceful degradation**: Both skills detect git/GitHub availability
  and fall back to local-only workflows.
