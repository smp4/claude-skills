# afb (Agentic Flight Bag) — Implementation Plan

## Architecture overview

```
afb                          # entrypoint — subcommand dispatcher
lib/
  common.sh                  # shared: accounts parsing, slugify, platform detect, preflight
  install.sh                 # install/uninstall/check logic (from current install.sh)
  work.sh                    # tmux session menu + launch (from c.sh)
  wt.sh                      # git worktree+branch lifecycle
  rate.sh                    # rate monitoring, API check, status file I/O
  daemon.sh                  # launchd plist / cron management
docs/
  install.md                 # how to install afb
  usage.md                   # subcommand reference + examples
  uninstall.md               # how to remove afb and all managed state
```

`afb` is a thin dispatcher: parse subcommand, source the relevant `lib/*.sh`, call its entrypoint. `lib/common.sh` is sourced by all.

No changes to `dot_claude/`, `accounts.json`, or `accounts.json.example` structure — they stay at repo root. `afb` and `lib/` live at repo root alongside them.

## Implementation units

### Unit 1: Scaffold + common.sh + dispatcher

**Delivers**: `afb` entrypoint that dispatches to subcommands. `lib/common.sh` with shared utilities. Running `afb` with no args prints help. Running `afb <unknown>` exits 1.

**Files**: `afb` (new), `lib/common.sh` (new)

**Tests first**:
- test_afb_no_args_prints_help — `afb` with no args exits 0, prints usage
- test_afb_unknown_command_exits_1 — `afb bogus` exits 1
- test_slugify — "My Feature Name" → "my-feature-name"
- test_platform_detect — returns "macos" or "linux"
- test_preflight_no_accounts_json — exits 2 with setup message
- test_accounts_parsing — reads accounts.json, outputs name|home|is_default lines

**Implementation notes**:
- `afb` is `#!/usr/bin/env bash`, sources `lib/common.sh`, dispatches via case statement
- `common.sh` contains: `afb_accounts_file()`, `afb_read_accounts()`, `afb_validate_accounts()`, `afb_slugify()`, `afb_detect_platform()`, `afb_preflight()` (checks accounts.json exists)
- Account validation and parsing reuse the python3 approach from current `install.sh`
- `SCRIPT_DIR` resolved via `dirname` of the `afb` binary (follows symlinks for when `afb` is symlinked into PATH)

**Traces to**: FR-11, NFR-1, NFR-3, NFR-5, NFR-6

---

### Unit 2: Install subcommand

**Delivers**: `afb install`, `afb uninstall`, `afb check` — drop-in replacement for `install.sh`.

**Files**: `lib/install.sh` (new)

**Tests first**:
- test_install_creates_symlinks — verify skills/, hooks, commands, CLAUDE.md, statusline-command.sh symlinked
- test_install_creates_settings_json — settings.json generated from template with correct hydration
- test_install_creates_aliases_sh — aliases.sh matches expected content
- test_install_creates_afb_symlink — `~/.local/bin/afb` points to repo `afb`
- test_install_copy_mode — all items are real files, not symlinks
- test_install_force_overwrites — real files replaced with symlinks
- test_check_synced_exits_0 — clean state exits 0
- test_check_diverged_exits_1 — modified controlled field exits 1
- test_uninstall_removes_all — symlinks gone, settings.json.original restored
- test_install_autocreates_accounts_json — when missing, creates default

**Implementation notes**:
- Direct port from current `install.sh` — functions renamed with `afb_` prefix, moved into `lib/install.sh`
- `afb install` also creates `~/.local/bin/afb` symlink (mkdir -p `~/.local/bin` if needed, warn if not in PATH)
- `afb uninstall` additionally calls `afb_daemon_remove()` (from Unit 5) if daemon is installed
- `accounts.json` auto-creation moves here (only for `afb install`)

**Traces to**: FR-1 through FR-11, AC-1, AC-2, AC-3, AC-16, AC-17

---

### Unit 3: Work subcommand (session management)

**Delivers**: `afb work` interactive menu and `afb work <name>` direct launch.

**Files**: `lib/work.sh` (new)

**Tests first**:
- test_work_menu_lists_sessions — existing tmux sessions appear in menu
- test_work_menu_has_cwd_option — "new in current dir" option present
- test_work_menu_has_wt_option — "new with worktree" option present
- test_work_with_name_creates_worktree — calls wt create, then tmux+claude
- test_work_slugifies_name — "My Feature" → tmux session "my-feature", branch "feat/my-feature"
- test_work_inside_tmux_switches — uses switch-client when $TMUX is set

**Implementation notes**:
- Port `c()` function logic into `afb_work()`
- Menu options: numbered list of existing sessions (attach), new-in-cwd, new-with-worktree
- `afb work <name>` skips menu → calls `afb_wt_create` (Unit 4), then `tmux new-session` + `send-keys "claude" Enter`
- Depends on `lib/wt.sh` for worktree creation

**Traces to**: FR-12 through FR-15, AC-4, AC-5

---

### Unit 4: Worktree subcommand

**Delivers**: `afb wt create|list|clean` — git worktree+branch lifecycle.

**Files**: `lib/wt.sh` (new)

**Tests first**:
- test_wt_create_makes_worktree — `.claude/worktrees/<slug>` exists, `feat/<slug>` branch exists
- test_wt_create_slugifies — "My Feature" → worktree `my-feature`, branch `feat/my-feature`
- test_wt_create_existing_exits_1 — duplicate name rejected
- test_wt_list_shows_worktrees — output includes path and branch
- test_wt_clean_removes_worktree — worktree and branch gone
- test_wt_clean_dirty_warns — uncommitted changes → exit 1 with message
- test_wt_clean_force_removes_dirty — `--force` overrides warning
- test_wt_not_in_git_repo_exits_1 — all wt commands fail outside git repo

**Implementation notes**:
- `afb_wt_create()`: `git worktree add .claude/worktrees/<slug> -b feat/<slug>`
- `afb_wt_list()`: `git worktree list` with formatting
- `afb_wt_clean()`: check `git status` in worktree for uncommitted changes, then `git worktree remove`, `git branch -d feat/<slug>`
- Dirty check: `git -C <worktree-path> status --porcelain` — non-empty = dirty

**Traces to**: FR-16 through FR-19, AC-6, AC-7, AC-8

---

### Unit 5: Rate monitoring — core + daemon

**Delivers**: `afb rate`, `afb rate --refresh`, `afb rate --daemon install|remove`. Platform-native scheduling. Per-account status files.

**Files**: `lib/rate.sh` (new), `lib/daemon.sh` (new)

**Tests first**:
- test_rate_displays_status_files — reads existing rate-status.json, formats output
- test_rate_no_status_file — shows "no data, run --refresh" per account
- test_rate_refresh_writes_status — after refresh, rate-status.json exists with valid schema
- test_rate_refresh_keychain_macos — on macOS, token extracted from Keychain
- test_rate_refresh_credentials_linux — on Linux, token read from .credentials.json
- test_rate_refresh_header_failure — missing headers → error in status file, exit 0
- test_rate_refresh_network_failure — connection error → error in status file, exit 0
- test_rate_interval_skips — account with recent last_check skipped when interval not elapsed
- test_daemon_install_macos_creates_plist — launchd plist at ~/Library/LaunchAgents/
- test_daemon_install_linux_creates_crontab — crontab entry present
- test_daemon_remove_macos — plist removed, agent unloaded
- test_daemon_remove_linux — crontab entry removed
- test_daemon_install_prompts_user — requires y/N confirmation

**Implementation notes**:

`lib/rate.sh`:
- `afb_rate_display()`: iterate accounts, read `${claude_home}/afb/rate-status.json`, format as compact table (account name, session %, weekly %, status, last_check). Utilisation shown as percentage (e.g. "42%"), not decimal.
- `afb_rate_refresh()`: iterate accounts, check `rate_interval` vs `last_check`, call `afb_rate_check_account()` for each due account
- `afb_rate_check_account()`:
  1. Get token: `afb_rate_get_token()` — platform switch
  2. `curl -s -D- -o /dev/null` to `api.anthropic.com/v1/messages` with minimal payload, `anthropic-beta` header
  3. Parse response headers with python3 (extract `anthropic-ratelimit-unified-*` headers)
  4. Write `rate-status.json` via python3 (atomic write to temp + mv)
- macOS token: `security find-generic-password -s "Claude Code-credentials" -w`
- Linux token: `python3 -c "import json; print(json.load(open('...'))['token'])"`

`lib/daemon.sh`:
- `afb_daemon_install()`:
  - macOS: generate plist XML → `~/Library/LaunchAgents/com.afb.rate-monitor.plist`, `launchctl bootstrap gui/$(id -u)` 
  - Linux: single crontab entry at GCD of all account intervals: `*/N * * * * /path/to/afb rate --refresh`
  - Both: show user what will be installed, prompt y/N
- `afb_daemon_remove()`:
  - macOS: `launchctl bootout`, rm plist
  - Linux: filter line from crontab
- `afb_daemon_status()`: check if daemon is active (used by `afb rate` display)

**Traces to**: FR-20 through FR-32, AC-9 through AC-15

---

### Unit 6: Docs + migration cleanup

**Delivers**: User-facing documentation. Remove `install.sh` and `c.sh` from repo root.

**Files**: `docs/install.md` (new), `docs/usage.md` (new), `docs/uninstall.md` (new), `README.md` (update), `install.sh` (delete), `c.sh` (delete)

**Tests first**:
- test_docs_install_exists — file present with required sections
- test_docs_usage_exists — file present with all subcommands documented
- test_docs_uninstall_exists — file present
- test_docs_rate_beta_warning — usage.md contains beta headers caveat
- test_readme_references_afb — README updated to reference `afb` not `install.sh`

**Implementation notes**:
- `docs/install.md`: clone repo, run `afb install`, source aliases, verify with `afb check`
- `docs/usage.md`: subcommand reference with examples. Includes rate monitoring section with prominent warning about beta/undocumented headers
- `docs/uninstall.md`: `afb uninstall`, manual cleanup steps
- Update `README.md`: replace `install.sh` / `c.sh` references with `afb` equivalents
- Delete `install.sh` and `c.sh` after all other units pass

**Traces to**: AC-17, AC-18, AC-19

## Dependency graph

```
Unit 1 (scaffold + common)
  ├→ Unit 2 (install)
  ├→ Unit 4 (wt)
  │    └→ Unit 3 (work) — depends on wt for worktree creation
  └→ Unit 5 (rate + daemon)
Unit 2 + Unit 3 + Unit 4 + Unit 5 → Unit 6 (docs + cleanup)
```

Units 2, 4, and 5 can be implemented in parallel after Unit 1.
Unit 3 depends on Unit 4.
Unit 6 is last.

## Risk register

| Risk                                                                      | Likelihood | Impact                        | Mitigation                                                                                                 |
| ------------------------------------------------------------------------- | ---------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Keychain access from launchd denied                                       | Medium     | Rate daemon broken on macOS   | Spike Keychain access in Unit 5 early. Fallback: cache token in `${claude_home}/afb/.token` with 600 perms |
| Undocumented rate headers removed by Anthropic                            | Medium     | Rate monitoring broken        | Error logged in status file, afb continues. Docs warn users. Easy to update header names when discovered   |
| Keychain access control list blocks afb                                   | Low        | Can't extract token           | Service name known (`Claude Code-credentials`). If ACL blocks, fallback: cache token in `${claude_home}/afb/.token` with 600 perms |
| `git worktree` path conflicts with Claude Code's own `.claude/worktrees/` | Low        | Confusion                     | This is the same convention Claude Code uses — compatible, not conflicting                                 |
| python3 not available                                                     | Low        | All JSON parsing broken       | Preflight check in common.sh, fail fast with message                                                       |
| `~/.local/bin` not in PATH                                                | Low        | `afb` not found after install | Detect and warn during `afb install`, print PATH instructions                                              |

## Verification

To verify the plan has been executed successfully:

1. **Functional parity**: run current `install.sh` and `afb install` side by side on a test account — diff the resulting symlinks and settings.json
2. **Subcommand smoke test**: exercise every subcommand listed in the CLI interface (SPEC §6) and verify exit codes
3. **Rate monitoring**: `afb rate --refresh` on a real Pro account produces valid status file; daemon installs and fires on schedule
4. **Keychain spike**: on macOS, confirm `security find-generic-password` can retrieve the Claude OAuth token (or document the fallback)
5. **Docs review**: each doc page covers its stated scope and the beta headers warning is prominent
6. **Clean removal**: `afb uninstall` leaves no symlinks, no daemon, no PATH entry

## Resolved questions

- **Keychain service name**: `security find-generic-password -s "Claude Code-credentials" -w`
- **afb symlink destination**: `~/.local/bin/afb` — confirmed
- **Rate display format**: compact table, account name + percentage (not decimal) + status + last_check. No utilisation bar.
- **Rate refresh scope**: always all accounts. No single-account refresh for now.
- **Linux cron strategy**: single crontab entry at GCD of all account intervals