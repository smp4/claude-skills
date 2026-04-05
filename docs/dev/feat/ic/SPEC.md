# afb (Agentic Flight Bag) — Specification

## 1. Problem statement

Claude Code infrastructure management is split across loose scripts (`install.sh`, `c.sh`) with no shared structure, no discoverability, and no room to grow. Users must know which script does what, source functions manually, and have no unified CLI for multi-account config management, parallel development sessions, or rate limit monitoring. `afb` consolidates these into a single extensible bash CLI.

## 2. Goals and non-goals

### Goals

- Single CLI entrypoint for all Claude Code infrastructure tasks
- Drop-in replacement for `install.sh` (multi-account config management)
- Drop-in replacement for `c.sh` (tmux session management)
- Git worktree+branch lifecycle management (`feat/<slug>`)
- Per-account rate limit monitoring with platform-native daemon (launchd/cron)
- Per-account state files readable from inside sandboxed Claude sessions
- User-facing docs (install, usage, uninstall)

### Non-goals

- Remote/k8s deployment
- GUI or TUI beyond simple numbered menus
- Non-bash implementation
- Non-macOS/Linux platform support (Windows deferred)
- launchd on Linux or cron on macOS (use platform-native scheduler)
- Replacing Claude Code itself or wrapping its CLI

## 3. User stories

- As a user, I want `afb install` to set up my Claude accounts so I don't manage symlinks manually.
- As a user, I want `afb work` to show me active sessions and let me attach or create new ones so I can context-switch fast.
- As a user, I want `afb work <name>` to create a worktree, branch, tmux session, and launch claude in one command.
- As a user, I want `afb wt create <name>` to set up a worktree+branch without tmux when I just need the branch.
- As a user, I want `afb wt clean <name>` to tear down worktrees safely, warning me about uncommitted changes.
- As a user, I want `afb rate` to show me rate limit status across all accounts without hitting the API.
- As a user, I want `afb rate --daemon install` to set up periodic rate checks that keep my session windows counting down.
- As a Claude skill running inside a sandboxed session, I want to read my account's rate status from a local file without filesystem traversal.

## 4. Functional requirements

### Install / config management (from install.sh)

- FR-1: `afb install` creates symlinks from `dot_claude/` into each account's `claude_home` (skills, hooks, commands, CLAUDE.md, statusline-command.sh)
- FR-2: `afb install` generates `settings.json` from template with `{{CLAUDE_HOME}}` hydration and controlled-field merging
- FR-3: `afb install` generates `aliases.sh` with per-account aliases
- FR-4: `afb install` symlinks `afb` itself into `~/.local/bin/afb` (or user-configurable path)
- FR-5: `afb install --copy` copies instead of symlinking (standalone snapshot)
- FR-6: `afb install --force` overwrites real files/dirs with symlinks
- FR-7: `afb install --skip-diff` skips settings.json diff prompt
- FR-8: `afb uninstall` removes all managed symlinks, restores `settings.json.original`, removes daemon (launchd plist or crontab entry), removes `afb` PATH symlink
- FR-9: `afb check` performs read-only sync verification, exits 1 on divergence
- FR-10: `afb install` auto-creates `accounts.json` with single default account if absent
- FR-11: All non-install subcommands exit with setup instructions if `accounts.json` is missing

### Session management (from c.sh)

- FR-12: `afb work` (no args) shows interactive menu: list existing tmux sessions to attach, option to create new session in cwd, option to create new session with worktree
- FR-13: `afb work <name>` creates worktree+branch `feat/<slug>`, tmux session, launches `claude` inside it
- FR-14: When already inside tmux, use `switch-client` instead of `attach-session`
- FR-15: Session names are slugified (spaces → hyphens, lowercased)

### Worktree management (new)

- FR-16: `afb wt create <name>` creates git worktree at `.claude/worktrees/<slug>` with branch `feat/<slug>`
- FR-17: `afb wt list` lists active worktrees with branch and path
- FR-18: `afb wt clean <name>` removes worktree and branch; warns and exits if uncommitted changes present
- FR-19: `afb wt clean <name> --force` removes worktree and branch even with uncommitted changes

### Rate monitoring (new, inspired by claude-rate-monitor)

- FR-20: `afb rate` displays rate status for all accounts from cached status files
- FR-21: `afb rate --refresh` performs live API check for all accounts, updates status files
- FR-22: `afb rate --daemon install` installs platform-native scheduled task (launchd plist on macOS, cron on Linux) with user approval prompt
- FR-23: `afb rate --daemon remove` removes the scheduled task
- FR-24: Daemon runs `afb rate --refresh` at each account's configured interval (default 10min)
- FR-25: On macOS, extract OAuth token from Keychain via `security` command
- FR-26: On Linux, read OAuth token from `${claude_home}/.credentials.json`
- FR-27: Rate check makes minimal API call (1 max token) to `api.anthropic.com/v1/messages` with `anthropic-beta: oauth-2025-04-20` header
- FR-28: Parse `anthropic-ratelimit-unified-*-utilization` and status headers from response
- FR-29: Write status to `${claude_home}/afb/rate-status.json`
- FR-30: On header parse failure, log error in status file (`"error": "<message>"`), do not crash

### accounts.json extensions

- FR-31: Support optional `rate_interval` field per account (minutes, default 10)
- FR-32: Daemon skips accounts whose `last_check` + `rate_interval` hasn't elapsed

## 5. Non-functional requirements

- NFR-1: bash + python3 only (python3 for JSON parsing, already a dependency)
- NFR-2: No external package managers or pip installs
- NFR-3: Subcommand dispatch in < 50ms (no heavy startup)
- NFR-4: Rate API call costs ~$0.001 per check — acceptable on Pro subscription
- NFR-5: All user-facing output to stdout; errors/warnings to stderr
- NFR-6: Exit codes: 0 success, 1 error, 2 user setup required

## 6. Interface contracts

### CLI interface

```
afb install [--copy] [--force] [--skip-diff]
afb uninstall
afb check
afb work [<name>]
afb wt create <name>
afb wt list
afb wt clean <name> [--force]
afb rate [--refresh]
afb rate --daemon install
afb rate --daemon remove
```

### rate-status.json schema

```json
{
  "last_check": "ISO-8601 timestamp",
  "session": {
    "utilization": 0.0-1.0,
    "status": "active|warning|rate_limited",
    "resets_at": "ISO-8601 timestamp"
  },
  "weekly": {
    "utilization": 0.0-1.0,
    "status": "active|warning|rate_limited",
    "resets_at": "ISO-8601 timestamp"
  },
  "error": "string or null"
}
```

### accounts.json schema (extended)

```json
{
  "accounts": [
    {
      "name": "string (required)",
      "claude_home": "string — path with ~ expansion (required)",
      "default": "boolean (optional, exactly one true)",
      "rate_interval": "integer — minutes between checks (optional, default 10)"
    }
  ]
}
```

## 7. Edge cases and error handling

| Edge case | Expected behaviour |
|---|---|
| `accounts.json` missing, non-install command | Exit 2 with setup instructions |
| `accounts.json` invalid JSON | Exit 1 with parse error |
| Keychain entry missing (macOS) | Log error in status file, continue other accounts |
| `.credentials.json` missing (Linux) | Log error in status file, continue other accounts |
| Rate API returns no utilization headers | Set `"error": "rate headers not present — beta API may have changed"` in status file |
| Rate API network failure | Set `"error": "network error: <detail>"` in status file |
| `afb wt clean` with uncommitted changes | Warn, exit 1, tell user to use `--force` |
| `afb wt create` when worktree already exists | Exit 1 with message |
| Worktree dir exists but git worktree doesn't know about it | Detect and warn |
| `afb rate --daemon install` when daemon already exists | Update interval, re-approve |
| `afb install` when `~/.local/bin` doesn't exist | Create it, warn user to add to PATH if not present |
| tmux not installed | Exit 1 with install instructions (work/session commands only) |
| Not in a git repo | Exit 1 for wt commands; other commands work fine |

## 8. Acceptance criteria checklist

- [ ] AC-1: `afb install` produces identical symlinks and settings.json as current `install.sh`
- [ ] AC-2: `afb uninstall` removes all managed items including daemon and PATH symlink
- [ ] AC-3: `afb check` exits 0 when synced, 1 when diverged — same as `install.sh --check`
- [ ] AC-4: `afb work` (no args) shows menu matching c.sh behavior plus worktree option
- [ ] AC-5: `afb work foo` creates `feat/foo` branch, `.claude/worktrees/foo` worktree, tmux session `foo`, claude running inside
- [ ] AC-6: `afb wt create foo` creates worktree+branch without tmux
- [ ] AC-7: `afb wt list` shows all worktrees with branch names
- [ ] AC-8: `afb wt clean foo` refuses on dirty worktree, succeeds on clean or `--force`
- [ ] AC-9: `afb rate` reads and displays status files without API calls
- [ ] AC-10: `afb rate --refresh` hits API, writes valid `rate-status.json` per account
- [ ] AC-11: macOS uses Keychain for token, Linux uses `.credentials.json`
- [ ] AC-12: `afb rate --daemon install` creates launchd plist (macOS) or crontab entry (Linux) after user approval
- [ ] AC-13: `afb rate --daemon remove` cleanly removes scheduled task
- [ ] AC-14: Rate header failure logged in status file, does not crash
- [ ] AC-15: Per-account `rate_interval` respected by daemon
- [ ] AC-16: Non-install commands exit 2 with instructions when `accounts.json` missing
- [ ] AC-17: `install.sh` and `c.sh` can be removed after migration verified
- [ ] AC-18: docs/install.md, docs/usage.md, docs/uninstall.md exist and are accurate
- [ ] AC-19: docs note that rate monitoring uses beta/undocumented headers that may break

## Notes

- Rate monitoring uses **undocumented beta API headers** (`anthropic-beta: oauth-2025-04-20`, `anthropic-ratelimit-unified-*`). These are not in Anthropic's public API docs and were discovered via reverse-engineering. They may change or disappear without notice. `afb` handles this gracefully but users should expect occasional breakage.
