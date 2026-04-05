# Verification Report — afb (Agentic Flight Bag)

**Tests**: 36 passing, 0 failing
**Branch**: worktree-ic
**Date**: 2026-04-05

## Acceptance criteria traceability

| AC | Description | Covering test(s) | Status |
|---|---|---|---|
| AC-1 | `afb install` produces symlinks and settings.json | test_install_then_check_exits_0, test_parity_with_install_sh (removed when install.sh deleted) | ✅ |
| AC-2 | `afb uninstall` removes all managed items | test_uninstall_then_check_exits_1 | ✅ |
| AC-3 | `afb check` exits 0/1 correctly | test_install_then_check_exits_0, test_uninstall_then_check_exits_1 | ✅ |
| AC-4 | `afb work` menu lists sessions | test_work_menu_lists_sessions | ✅ |
| AC-5 | `afb work foo` creates worktree+session | test_work_with_name_creates_session | ✅ |
| AC-6 | `afb wt create foo` creates worktree | test_wt_create_and_list | ✅ |
| AC-7 | `afb wt list` shows worktrees | test_wt_create_and_list | ✅ |
| AC-8 | `afb wt clean foo` refuses dirty, accepts `--force` | test_wt_clean_dirty_warns, test_wt_clean_force_removes_dirty | ✅ |
| AC-9 | `afb rate` reads status files | test_rate_displays_status, test_rate_no_status_file | ✅ |
| AC-10 | `afb rate --refresh` hits API, writes status | test_rate_refresh_parses_headers | ✅ |
| AC-11 | macOS Keychain / Linux .credentials.json | test_rate_refresh_token_macos, test_rate_refresh_token_linux | ✅ |
| AC-12 | `afb rate --daemon install` creates scheduler | test_daemon_install_macos, test_daemon_install_linux | ✅ |
| AC-13 | `afb rate --daemon remove` cleans up | test_daemon_remove_macos, test_daemon_remove_linux | ✅ |
| AC-14 | Header failure logged, no crash | test_rate_refresh_header_failure, test_rate_refresh_network_failure | ✅ |
| AC-15 | Per-account rate_interval respected | test_rate_interval_skips | ✅ |
| AC-16 | Non-install commands exit 2 without accounts.json | test_preflight_no_accounts_json | ✅ |
| AC-17 | install.sh and c.sh deleted | Confirmed — deleted in Unit 6 commit | ✅ |
| AC-18 | docs/install.md, docs/usage.md, docs/uninstall.md exist | Confirmed — created in Unit 6 | ✅ |
| AC-19 | Docs warn about beta headers | docs/usage.md "Warning" section | ✅ |

## Test summary

| Unit | Tests | Result |
|---|---|---|
| Unit 1: scaffold + common.sh | 6 | ✅ all pass |
| Unit 2: install subcommand | 5 | ✅ all pass |
| Unit 3: work subcommand | 4 | ✅ all pass |
| Unit 4: wt subcommand | 7 | ✅ all pass |
| Unit 5: rate + daemon | 14 | ✅ all pass |
| **Total** | **36** | **✅ 36/36** |

## Open items

- **Real API smoke test**: `afb rate --refresh` against a live Pro account is a manual test — automated tests use fixture headers.
- **Keychain spike**: on macOS, `security find-generic-password -s "Claude Code-credentials"` access from launchd context should be verified by the user (may require ACL entry). Fallback documented in risk register.
- **FR-33** (`afb rate --self-test`): implemented and tested (test_rate_self_test).
