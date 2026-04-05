#!/usr/bin/env bash
# Unit 1 tests: afb entrypoint + common.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AFB="${REPO}/afb"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Helper: run afb with a temp dir as accounts.json location
run_afb() {
  bash "$AFB" "$@"
}

# ---------------------------------------------------------------------------
# test_afb_no_args_prints_help
# ---------------------------------------------------------------------------
test_afb_no_args_prints_help() {
  out=$(run_afb 2>&1) && rc=$? || rc=$?
  if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "Usage"; then
    pass "test_afb_no_args_prints_help"
  else
    fail "test_afb_no_args_prints_help (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_afb_unknown_command_exits_1
# ---------------------------------------------------------------------------
test_afb_unknown_command_exits_1() {
  out=$(run_afb bogus 2>&1) || rc=$?
  rc=${rc:-0}
  # should exit 1
  run_afb bogus >/dev/null 2>&1 && rc=0 || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "test_afb_unknown_command_exits_1"
  else
    fail "test_afb_unknown_command_exits_1 (rc=$rc)"
  fi
}

# ---------------------------------------------------------------------------
# test_slugify
# ---------------------------------------------------------------------------
test_slugify() {
  # Source common.sh and test the function
  result=$(bash -c "
    source '${REPO}/lib/common.sh'
    afb_slugify 'My Feature Name'
  ")
  if [[ "$result" == "my-feature-name" ]]; then
    pass "test_slugify"
  else
    fail "test_slugify (got: $result)"
  fi
}

# ---------------------------------------------------------------------------
# test_platform_detect
# ---------------------------------------------------------------------------
test_platform_detect() {
  result=$(bash -c "
    source '${REPO}/lib/common.sh'
    afb_detect_platform
  ")
  if [[ "$result" == "macos" || "$result" == "linux" ]]; then
    pass "test_platform_detect (platform=$result)"
  else
    fail "test_platform_detect (got: $result)"
  fi
}

# ---------------------------------------------------------------------------
# test_preflight_no_accounts_json
# ---------------------------------------------------------------------------
test_preflight_no_accounts_json() {
  tmp=$(mktemp -d)
  # Run afb check with AFB_ACCOUNTS_FILE pointing to nonexistent file
  rc=0
  out=$(AFB_ACCOUNTS_FILE="${tmp}/accounts.json" bash "$AFB" check 2>&1) || rc=$?
  rm -rf "$tmp"
  if [[ "$rc" -eq 2 ]] && echo "$out" | grep -qi "setup\|install\|accounts"; then
    pass "test_preflight_no_accounts_json"
  else
    fail "test_preflight_no_accounts_json (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_accounts_parsing
# ---------------------------------------------------------------------------
test_accounts_parsing() {
  tmp=$(mktemp -d)
  cat > "${tmp}/accounts.json" <<'EOF'
{
  "accounts": [
    { "name": "alice", "claude_home": "~/.claude/.alice", "default": true },
    { "name": "bob",   "claude_home": "~/.claude/.bob" }
  ]
}
EOF
  result=$(bash -c "
    source '${REPO}/lib/common.sh'
    AFB_ACCOUNTS_FILE='${tmp}/accounts.json' afb_read_accounts
  ")
  rm -rf "$tmp"
  # Expect two lines: alice|...|1 and bob|...|0
  if echo "$result" | grep -q "^alice|" && echo "$result" | grep -q "^bob|"; then
    # Check default flag
    alice_line=$(echo "$result" | grep "^alice|")
    if [[ "$alice_line" == *"|1" ]]; then
      pass "test_accounts_parsing"
    else
      fail "test_accounts_parsing (default flag wrong: $alice_line)"
    fi
  else
    fail "test_accounts_parsing (got: $result)"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
test_afb_no_args_prints_help
test_afb_unknown_command_exits_1
test_slugify
test_platform_detect
test_preflight_no_accounts_json
test_accounts_parsing

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
