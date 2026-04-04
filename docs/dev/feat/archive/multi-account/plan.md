# Plan: Multi-account Claude Code setup tool

## Context

Multiple Claude accounts on one machine each need their own `CLAUDE_CONFIG_DIR`. Common config (skills, hooks, commands, CLAUDE.md, settings) should be maintained in this repo and synced to all accounts.

---

## Step 0 — Populate `dot_claude/` (one-time manual bootstrap)

Before running `install.sh`, copy the following from `~/.claude/` into `dot_claude/`:

```
~/.claude/CLAUDE.md                     → dot_claude/CLAUDE.md
~/.claude/hooks/warn-sensitive-files.sh → dot_claude/hooks/warn-sensitive-files.sh
~/.claude/statusline-command.sh         → dot_claude/statusline-command.sh
~/.claude/settings.json                 → extract into dot_claude/settings.json.template
                                           (replace all hardcoded paths with {{CLAUDE_HOME}})
```

Also move all skill directories from repo root into `dot_claude/skills/`:

```
adversarial-plan-review/ → dot_claude/skills/adversarial-plan-review/
domain-interview/        → dot_claude/skills/domain-interview/
new-plan/                → dot_claude/skills/new-plan/
new-task/                → dot_claude/skills/new-task/
pr-cleanup/              → dot_claude/skills/pr-cleanup/
review/                  → dot_claude/skills/review/
shared/                  → dot_claude/skills/shared/
sysmlv2/                 → dot_claude/skills/sysmlv2/
write-docs/              → dot_claude/skills/write-docs/
```

This is committed once and all machines get content via `git pull`.

**IMPORTANT**: copy, do NOT move or modify anything under `~/.claude/` directly.

---

## Symlink scope — what can and cannot be shared

**Safe to symlink**:
| File/dir | Strategy |
|---|---|
| `skills/<skill>` | per-skill symlinks → `<repo>/dot_claude/skills/<skill>` |
| `hooks/` | symlink dir → `<repo>/dot_claude/hooks/` |
| `commands/` | symlink dir → `<repo>/dot_claude/commands/` |
| `CLAUDE.md` | symlink file → `<repo>/dot_claude/CLAUDE.md` |
| `statusline-command.sh` | symlink file → `<repo>/dot_claude/statusline-command.sh` |
| `settings.json` | **generated** from template (see below) |

**`commands/` write behaviour**: Claude Code writes new skills, subagents, and commands here at runtime. All accounts share the same `dot_claude/commands/` via symlink — writes from any account appear in all accounts. This is intentional. install.sh must run `chmod u+w <repo>/dot_claude/commands` during setup to guarantee the directory is writable.

**NOT shared (writable at runtime — each account keeps its own)**:
`backups/`, `cache/`, `debug/`, `downloads/`, `file-history/`, `history.jsonl`, `ide/`, `mcp-needs-auth-cache.json`, `paste-cache/`, `plans/`, `plugins/`, `projects/`, `read-once/`, `session-env/`, `sessions/`, `shell-snapshots/`, `stats-cache.json`, `tasks/`, `telemetry/`, `todos/`

**`plugins/` specifically**: actively written by plugin processes (caches, state). Each account keeps its own.

**`settings.json`**: cannot be symlinked because:
1. Contains hardcoded absolute paths (`/Users/sean/.claude/hooks/...`) that differ per account
2. Claude Code writes to it at runtime (effort level, etc.) — a symlink would couple all accounts' runtime state

Solution: `dot_claude/settings.json.template` with `{{CLAUDE_HOME}}` placeholder; generate per account on install.

---

## Repo structure

```
claude-skills/
├── dot_claude/                          # all files symlinked/generated into each account's dir
│   ├── CLAUDE.md
│   ├── hooks/
│   │   └── warn-sensitive-files.sh
│   ├── commands/
│   │   └── .gitkeep
│   ├── statusline-command.sh
│   ├── settings.json.template           # {{CLAUDE_HOME}} replaces all hardcoded paths
│   └── skills/                          # actual skill dirs live here (no inner symlinks)
│       ├── adversarial-plan-review/
│       ├── domain-interview/
│       ├── new-plan/
│       ├── new-task/
│       ├── pr-cleanup/
│       ├── review/
│       ├── shared/
│       ├── sysmlv2/
│       └── write-docs/
├── accounts.json                        # gitignored — user's local account list
├── accounts.json.example                # committed
├── aliases.sh                           # gitignored — generated shell aliases
└── install.sh                           # rewritten
```

---

## accounts.json

`accounts.json.example`:
```json
{
  "accounts": [
    { "name": "claudea", "claude_home": "~/.claude/.claudea", "default": true },
    { "name": "claudeb", "claude_home": "~/.claude/.claudeb" }
  ]
}
```

- `claude_home` may use `~`; install.sh expands to `$HOME` via python3 explicitly
- Exactly one account should have `"default": true`; if none, first account is used
- install.sh warns if two accounts resolve to the same `claude_home`

---

## install.sh behaviour

**If `accounts.json` absent**, auto-create with one default account:
```json
{ "accounts": [{ "name": "default", "claude_home": "~/.claude", "default": true }] }
```

**Parse `accounts.json`** via python3: extract name, claude_home (with `~` expanded to `$HOME`), and which is default.

For each account:

1. `mkdir -p <claude_home>/skills`
2. **Migration**: if any `<claude_home>/skills/<skill>` is a per-skill symlink from the old install, remove it and print `Migrating: removed old symlink skills/<name>` before proceeding
3. Per-skill symlinks: for each skill in `dot_claude/skills/`, create `<claude_home>/skills/<skill>` → `<repo>/dot_claude/skills/<skill>`
   - If target is a symlink pointing to wrong destination: update silently
   - If target is a real file/dir (not managed by this repo): warn and skip unless `--force`
4. Symlink `<claude_home>/hooks` → `<repo>/dot_claude/hooks`
5. Symlink `<claude_home>/commands` → `<repo>/dot_claude/commands`
6. Symlink `<claude_home>/CLAUDE.md` → `<repo>/dot_claude/CLAUDE.md`
7. Symlink `<claude_home>/statusline-command.sh` → `<repo>/dot_claude/statusline-command.sh`
8. Generate `<claude_home>/settings.json`:
   - **First install** (no `settings.json` and no `settings.json.original`):
     - Write `settings.json.original` — the unmodified original; **never overwritten again**
     - Write `settings.json` from template
   - **Subsequent install**:
     - **Backup**: overwrite `settings.json.bak` (keep only last 1)
     - **Smart diff**: hydrate template (sed `{{CLAUDE_HOME}}` → actual path). Normalise existing settings.json by replacing actual claude_home with `{{CLAUDE_HOME}}`. Compare **controlled fields** — derived from the top-level keys present in the template — between normalised existing and template. If true differences found, print diff and prompt user to continue [y/N] (default N, exit). Skip with `--skip-diff`.
     - **Merge + write**: use template values for controlled fields; preserve all other fields from existing settings.json (e.g. `effortLevel`, user-added keys)
   - Smart diff + merge via inline python3 script
   - **`--uninstall`**: restore `settings.json.original` as `settings.json`; delete `settings.json.bak`; do not delete `settings.json.original`

**Symlink safety**: same rules for all symlinked items (hooks, commands, CLAUDE.md, statusline-command.sh): if target is a real file/dir, warn and skip unless `--force`.

**Shell aliases**: after all accounts processed, generate `aliases.sh` in repo root (gitignored):
```bash
# source this file from ~/.profile (or ~/.zshrc / ~/.bashrc)
alias claudea='CLAUDE_CONFIG_DIR=~/.claude/.claudea claude'
alias claudeb='CLAUDE_CONFIG_DIR=~/.claude/.claudeb claude'
alias claude='CLAUDE_CONFIG_DIR=~/.claude/.claudea claude'   # default account
```

Notes on alias behaviour:
- Aliases only expand in interactive shells. Scripts using `#!/bin/bash` are unaffected.
- If `CLAUDE_CONFIG_DIR` is set in the environment before calling `claude` interactively, the alias will override it — document this caveat in README.

Also print instructions pointing user to `source <repo>/aliases.sh` from `~/.profile`.

**Preflight guard**: if `dot_claude/skills/` does not exist, print error and exit 1 — Step 0 was not completed.

**accounts.json validation** (`validate_accounts` function): run before processing any account. Checks:
- Valid JSON (python3 parse, exit 1 on failure)
- Each entry has `name` and `claude_home` fields
- No two entries resolve to the same expanded `claude_home` (warn, continue)
- At most one entry has `"default": true` (warn if none — first used; error if >1)

**Migration logging**: when removing an old per-skill symlink, print one line per removal: `Migrating: removed old symlink skills/<name>`.

**Flags**:
- `(none)` — install/update all accounts
- `--check` — read-only sync check; for each account: verify all symlinks point to correct targets, compare settings.json controlled fields vs template (error if diverged), compare other fields vs template (warning if diverged); exit 1 if any errors
- `--copy` — copy files instead of symlinking; use `cp -RL` to dereference symlinks for a true standalone snapshot (note: capital `-R` required for macOS BSD `cp`)
- `--uninstall` — remove all managed symlinks for all accounts; restore `settings.json.original` as `settings.json`; delete `settings.json.bak`
- `--force` — overwrite real files with symlinks without prompting
- `--skip-diff` — bypass smart diff prompt during settings.json generation

---

## README.md update

Add section **Multi-account setup** covering:
- **Step 0**: bootstrap `dot_claude/` and move skills (one-time manual step)
- Why: multiple Claude Code accounts on one machine, one common config
- How: clone repo → complete Step 0 → create `accounts.json` → run `./install.sh` → source `aliases.sh` from `~/.profile`
- Alias caveat: `claude` aliases to default account; explicit `CLAUDE_CONFIG_DIR` in interactive shell will be overridden by the alias
- Updating common config: edit files in `dot_claude/`, commit, pull on other machines, re-run `./install.sh`
- Single-account use: works as before; `accounts.json` auto-created pointing at `~/.claude`

---

## Critical files

- `/Users/sean/Projects/claude-skills/install.sh` — rewrite
- `/Users/sean/Projects/claude-skills/dot_claude/settings.json.template` — create (from `~/.claude/settings.json`)
- `/Users/sean/Projects/claude-skills/dot_claude/hooks/warn-sensitive-files.sh` — create (copy)
- `/Users/sean/Projects/claude-skills/dot_claude/statusline-command.sh` — create (copy)
- `/Users/sean/Projects/claude-skills/dot_claude/CLAUDE.md` — create (copy)
- `/Users/sean/Projects/claude-skills/dot_claude/skills/` — create (move skill dirs here)
- `/Users/sean/Projects/claude-skills/accounts.json.example` — create
- `/Users/sean/Projects/claude-skills/.gitignore` — add `accounts.json`, `aliases.sh`

## .gitignore additions

- `accounts.json`
- `aliases.sh`

---

## Verification

1. `bash -n install.sh` — syntax check
2. Create `accounts.json` with two test entries: `~/.claude/testA` (default) and `~/.claude/testB`
3. Run `./install.sh`
4. Check `~/.claude/testA/skills/adversarial-plan-review` → `<repo>/dot_claude/skills/adversarial-plan-review` (single hop, no chain)
5. Check `~/.claude/testA/hooks` symlink → `<repo>/dot_claude/hooks`
6. Check `~/.claude/testA/settings.json` contains resolved paths (no `{{CLAUDE_HOME}}` remaining)
7. Check `~/.claude/testA/settings.json.bak` exists; run again → `.bak` is overwritten (only one kept)
8. Run `./install.sh` again — idempotent, no errors, no false diff alert
9. Modify a controlled field in `~/.claude/testA/settings.json`, re-run — smart diff triggers warning; re-run with `--skip-diff` — proceeds without prompt
10. Verify `aliases.sh` has `claude` → default account alias, named aliases for both accounts
11. `CLAUDE_CONFIG_DIR=$HOME/.claude/testA claude` launches with correct config and skills visible
12. `./install.sh --uninstall` — removes managed symlinks; `settings.json` is restored from `settings.json.original`; `settings.json.bak` deleted; `settings.json.original` kept; dirs not deleted
13. Run old-style install (individual skill symlinks in `~/.claude/testA/skills/`), then run new install — migration removes old symlinks cleanly, prints one log line per removed symlink
14. Test `--copy`: verify `~/.claude/testA/skills/adversarial-plan-review` is a real directory (symlinks dereferenced), not a chain
15. Run `./install.sh` with `dot_claude/skills/` absent — exits 1 with "Step 0 not completed" message
16. Feed malformed `accounts.json` — exits 1 with parse error
17. Set two accounts to `"default": true` — exits 1 with error
18. Modify a non-controlled field in `settings.json` and run `--check` — prints warning (not error), exits 0
19. Modify a controlled field and run `--check` — prints error, exits 1
20. Verify `dot_claude/commands/` is writable and a file written via symlink appears in the repo dir
