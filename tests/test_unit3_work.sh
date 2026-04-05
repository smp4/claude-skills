#!/usr/bin/env bash
# Unit 3 tests: afb work

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AFB="${REPO}/afb"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Setup: git repo + tmux mock
setup_env() {
  TMP="$(mktemp -d)"
  GIT_REPO="${TMP}/repo"
  mkdir -p "$GIT_REPO"
  git -C "$GIT_REPO" init -b main >/dev/null 2>&1
  git -C "$GIT_REPO" config user.email "test@test.com"
  git -C "$GIT_REPO" config user.name "Test"
  echo "init" > "${GIT_REPO}/init.txt"
  git -C "$GIT_REPO" add init.txt
  git -C "$GIT_REPO" commit -m "init" >/dev/null 2>&1

  ACCOUNTS_FILE="${TMP}/accounts.json"
  cat > "$ACCOUNTS_FILE" <<EOF
{"accounts":[{"name":"test","claude_home":"${TMP}/home","default":true}]}
EOF
  mkdir -p "${TMP}/home"

  # Mock tmux: logs calls, always succeeds
  MOCK_BIN="${TMP}/mockbin"
  mkdir -p "$MOCK_BIN"
  TMUX_LOG="${TMP}/tmux.log"
  cat > "${MOCK_BIN}/tmux" <<SCRIPT
#!/usr/bin/env bash
echo "tmux \$*" >> "${TMUX_LOG}"
exit 0
SCRIPT
  chmod 755 "${MOCK_BIN}/tmux"

  # Mock claude: just succeeds
  cat > "${MOCK_BIN}/claude" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  chmod 755 "${MOCK_BIN}/claude"
}

run_afb() {
  (cd "$GIT_REPO" && PATH="${MOCK_BIN}:${PATH}" AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash "$AFB" "$@")
}

# ---------------------------------------------------------------------------
# test_work_with_name_creates_session
# ---------------------------------------------------------------------------
test_work_with_name_creates_session() {
  setup_env
  rc=0
  run_afb work testname 2>&1 >/dev/null || rc=$?
  # Check tmux was called with new-session containing the name
  wt_exists=0
  [[ -d "${GIT_REPO}/.claude/worktrees/testname" ]] && wt_exists=1
  tmux_called=0
  grep -q "new-session" "$TMUX_LOG" 2>/dev/null && tmux_called=1
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && [[ "$wt_exists" -eq 1 ]] && [[ "$tmux_called" -eq 1 ]]; then
    pass "test_work_with_name_creates_session"
  else
    fail "test_work_with_name_creates_session (rc=$rc, wt=$wt_exists, tmux=$tmux_called)"
  fi
}

# ---------------------------------------------------------------------------
# test_work_slugifies_name
# ---------------------------------------------------------------------------
test_work_slugifies_name() {
  setup_env
  rc=0
  run_afb work "My Feature" 2>&1 >/dev/null || rc=$?
  wt_exists=0
  [[ -d "${GIT_REPO}/.claude/worktrees/my-feature" ]] && wt_exists=1
  # tmux session should be my-feature
  tmux_session=0
  grep -q "my-feature" "$TMUX_LOG" 2>/dev/null && tmux_session=1
  rm -rf "$TMP"
  if [[ "$wt_exists" -eq 1 ]] && [[ "$tmux_session" -eq 1 ]]; then
    pass "test_work_slugifies_name"
  else
    fail "test_work_slugifies_name (wt=$wt_exists, tmux_session=$tmux_session)"
  fi
}

# ---------------------------------------------------------------------------
# test_work_menu_lists_sessions
# Menu output should show existing tmux sessions
# ---------------------------------------------------------------------------
test_work_menu_lists_sessions() {
  setup_env
  # Mock tmux list-sessions to return a session
  cat > "${MOCK_BIN}/tmux" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$1" == "list-sessions" ]]; then
  echo "mysession"
  exit 0
fi
echo "tmux \$*" >> "${TMUX_LOG}"
exit 0
SCRIPT
  chmod 755 "${MOCK_BIN}/tmux"

  # Feed "q" or invalid input to exit the menu without choosing
  out=$(cd "$GIT_REPO" && PATH="${MOCK_BIN}:${PATH}" AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash -c "echo q | bash '$AFB' work" 2>&1) || true
  rm -rf "$TMP"
  if echo "$out" | grep -q "mysession"; then
    pass "test_work_menu_lists_sessions"
  else
    fail "test_work_menu_lists_sessions (mysession not in menu output: $out)"
  fi
}

# ---------------------------------------------------------------------------
# test_work_inside_tmux_switches
# When $TMUX is set, use switch-client instead of attach-session
# ---------------------------------------------------------------------------
test_work_inside_tmux_switches() {
  setup_env
  rc=0
  TMUX="/tmp/tmux-socket" run_afb work testname 2>&1 >/dev/null || rc=$?
  switch_called=0
  grep -q "switch-client" "$TMUX_LOG" 2>/dev/null && switch_called=1
  rm -rf "$TMP"
  if [[ "$switch_called" -eq 1 ]]; then
    pass "test_work_inside_tmux_switches"
  else
    fail "test_work_inside_tmux_switches (switch-client not called)"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
test_work_with_name_creates_session
test_work_slugifies_name
test_work_menu_lists_sessions
test_work_inside_tmux_switches

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
