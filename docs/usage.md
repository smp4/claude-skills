# afb usage reference

## Command summary

```
afb install [--copy] [--force] [--skip-diff]
afb uninstall
afb check
afb work [<name>]
afb wt create <name>
afb wt list
afb wt clean <name> [--force]
afb rate [--refresh] [--self-test]
afb rate --daemon install
afb rate --daemon remove
```

---

## afb install / uninstall / check

### install

Sets up all accounts in `accounts.json`: creates symlinks from `dot_claude/` into each account's config dir, generates `settings.json` from template, generates `aliases.sh`, and symlinks `afb` into `~/.local/bin/afb`.

```bash
afb install              # symlink mode
afb install --copy       # copy files instead of symlinking
afb install --force      # overwrite real files/dirs with symlinks
afb install --skip-diff  # skip settings.json diff prompt
```

### uninstall

Removes all managed symlinks, restores `settings.json` from backup, removes daemon, removes `~/.local/bin/afb`.

```bash
afb uninstall
```

### check

Read-only sync verification. Exits 0 if all managed items match the repo. Exits 1 if any diverge.

```bash
afb check
```

---

## afb work

Interactive tmux session management. Without a name, shows a numbered menu of existing sessions and options to create new ones.

```bash
afb work           # interactive menu
afb work foo       # create worktree feat/foo + tmux session foo + launch claude
afb work "My Bug"  # slugified: worktree my-bug, session my-bug
```

When called with a name, `afb work <name>`:
1. Creates git worktree `.claude/worktrees/<slug>` with branch `feat/<slug>`
2. Creates tmux session `<slug>` in the worktree directory
3. Launches `claude` in the session
4. Attaches (or switches if already in tmux)

---

## afb wt

Git worktree and branch lifecycle.

```bash
afb wt create foo           # create .claude/worktrees/foo + feat/foo branch
afb wt create "My Feature"  # slugified: my-feature
afb wt list                 # list all worktrees
afb wt clean foo            # remove worktree + branch (fails if dirty)
afb wt clean foo --force    # remove even with uncommitted changes
```

Worktrees are created at `.claude/worktrees/<slug>` relative to the repo root, with branch `feat/<slug>`. This convention is compatible with Claude Code's own worktree usage.

---

## afb rate

Rate limit monitoring for all accounts. Uses cached status files — no API calls.

```bash
afb rate                # display rate status from cached files
afb rate --refresh      # check API for all accounts, update status files
afb rate --self-test    # check that recent refreshes returned data (not errors)
```

Output format (table):

```
Account         Session    Weekly     Status       Last check
-------         -------    ------     ------       ----------
claudea         42%        15%        active       2026-04-05 10:00:00
claudeb         no data    no data    -            run --refresh
```

### Per-account status files

Status is written to `${claude_home}/afb/rate-status.json` per account. Claude skills running inside sandboxed sessions can read this file without filesystem traversal.

### Rate check interval

Add `rate_interval` to `accounts.json` (minutes, default 10):

```json
{ "name": "claudea", "claude_home": "~/.claude/.claudea", "rate_interval": 15 }
```

`afb rate --refresh` skips accounts checked within their interval.

### Daemon

```bash
afb rate --daemon install   # install platform-native scheduler (launchd/cron)
afb rate --daemon remove    # remove scheduler
```

On macOS: installs a launchd plist at `~/Library/LaunchAgents/com.afb.rate-monitor.plist`.
On Linux: adds crontab entries (one per account at its configured interval).

Both prompt for confirmation before installing.

---

## Warning: rate monitoring uses undocumented API headers

> **The rate monitoring feature relies on undocumented beta API headers** (`anthropic-beta: oauth-2025-04-20`, `anthropic-ratelimit-unified-*`). These were discovered via reverse-engineering and are **not in Anthropic's public API documentation**. They may change or disappear without notice.
>
> `afb` handles this gracefully: header parse failures are logged in the status file (`"error": "rate headers not present — beta API may have changed"`) and do not crash the CLI. Use `afb rate --self-test` to detect when headers have stopped working.

---

## accounts.json

```json
{
  "accounts": [
    {
      "name": "claudea",
      "claude_home": "~/.claude/.claudea",
      "default": true,
      "rate_interval": 10
    }
  ]
}
```

Fields: `name` (required), `claude_home` (required, `~` expanded), `default` (boolean, exactly one true), `rate_interval` (minutes, optional, default 10).

`accounts.json` is gitignored — each machine maintains its own.
