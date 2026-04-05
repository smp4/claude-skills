#!/usr/bin/env bash
# Unit 2 tests: afb install / uninstall / check

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AFB="${REPO}/afb"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Create a minimal test environment
# Returns: sets $TMP, $FAKE_HOME, $ACCOUNTS_FILE
setup_env() {
  TMP="$(mktemp -d)"
  FAKE_HOME="${TMP}/claude_home"
  mkdir -p "$FAKE_HOME"
  ACCOUNTS_FILE="${TMP}/accounts.json"
  cat > "$ACCOUNTS_FILE" <<EOF
{
  "accounts": [
    { "name": "test", "claude_home": "${FAKE_HOME}", "default": true }
  ]
}
EOF
}

run_afb() {
  AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash "$AFB" "$@"
}

# ---------------------------------------------------------------------------
# test_install_then_check_exits_0
# ---------------------------------------------------------------------------
test_install_then_check_exits_0() {
  setup_env
  run_afb install --skip-diff >/dev/null 2>&1
  rc=0
  run_afb check >/dev/null 2>&1 || rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]]; then
    pass "test_install_then_check_exits_0"
  else
    fail "test_install_then_check_exits_0 (afb check exited $rc)"
  fi
}

# ---------------------------------------------------------------------------
# test_install_copy_mode — --copy produces real files not symlinks
# ---------------------------------------------------------------------------
test_install_copy_mode() {
  setup_env
  run_afb install --copy >/dev/null 2>&1
  # CLAUDE.md should be a regular file, not a symlink
  if [[ -f "${FAKE_HOME}/CLAUDE.md" ]] && [[ ! -L "${FAKE_HOME}/CLAUDE.md" ]]; then
    pass "test_install_copy_mode"
  else
    fail "test_install_copy_mode (CLAUDE.md not a regular file)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_uninstall_then_check_exits_1
# ---------------------------------------------------------------------------
test_uninstall_then_check_exits_1() {
  setup_env
  run_afb install --skip-diff >/dev/null 2>&1
  run_afb uninstall >/dev/null 2>&1 || true
  rc=0
  run_afb check >/dev/null 2>&1 || rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -ne 0 ]]; then
    pass "test_uninstall_then_check_exits_1"
  else
    fail "test_uninstall_then_check_exits_1 (check should fail after uninstall)"
  fi
}

# ---------------------------------------------------------------------------
# test_install_autocreates_accounts_json
# ---------------------------------------------------------------------------
test_install_autocreates_accounts_json() {
  TMP="$(mktemp -d)"
  ACCOUNTS_FILE="${TMP}/accounts.json"
  FAKE_HOME="${HOME}/.claude"  # default account uses ~/.claude
  # Run install without pre-existing accounts.json
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash "$AFB" install --skip-diff 2>&1) || true
  if [[ -f "$ACCOUNTS_FILE" ]]; then
    pass "test_install_autocreates_accounts_json"
  else
    fail "test_install_autocreates_accounts_json (accounts.json not created)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_install_creates_afb_symlink
# ---------------------------------------------------------------------------
test_install_creates_afb_symlink() {
  setup_env
  LOCAL_BIN="${TMP}/local_bin"
  AFB_INSTALL_BIN_DIR="$LOCAL_BIN" run_afb install --skip-diff >/dev/null 2>&1
  if [[ -L "${LOCAL_BIN}/afb" ]]; then
    pass "test_install_creates_afb_symlink"
  else
    fail "test_install_creates_afb_symlink (${LOCAL_BIN}/afb not a symlink)"
  fi
  rm -rf "$TMP"
}


# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
test_install_then_check_exits_0
test_install_copy_mode
test_uninstall_then_check_exits_1
test_install_autocreates_accounts_json
test_install_creates_afb_symlink

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
