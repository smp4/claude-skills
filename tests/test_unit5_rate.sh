#!/usr/bin/env bash
# Unit 5 tests: afb rate

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
AFB="${REPO}/afb"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

setup_env() {
  TMP="$(mktemp -d)"
  FAKE_HOME="${TMP}/claude_home"
  mkdir -p "${FAKE_HOME}/afb"
  ACCOUNTS_FILE="${TMP}/accounts.json"
  cat > "$ACCOUNTS_FILE" <<EOF
{
  "accounts": [
    { "name": "testacct", "claude_home": "${FAKE_HOME}", "default": true }
  ]
}
EOF
}

run_afb() {
  AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" bash "$AFB" "$@"
}

# ---------------------------------------------------------------------------
# test_rate_displays_status
# ---------------------------------------------------------------------------
test_rate_displays_status() {
  setup_env
  # Write fixture status file
  cat > "${FAKE_HOME}/afb/rate-status.json" <<'EOF'
{
  "last_check": "2026-04-05T10:00:00Z",
  "session": { "utilization": 0.42, "status": "active", "resets_at": "2026-04-05T18:00:00Z" },
  "weekly":  { "utilization": 0.15, "status": "active", "resets_at": "2026-04-12T00:00:00Z" },
  "error": null
}
EOF
  out=$(run_afb rate 2>&1)
  rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && echo "$out" | grep -q "testacct" && echo "$out" | grep -q "42%"; then
    pass "test_rate_displays_status"
  else
    fail "test_rate_displays_status (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_rate_no_status_file
# ---------------------------------------------------------------------------
test_rate_no_status_file() {
  setup_env
  out=$(run_afb rate 2>&1)
  rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && echo "$out" | grep -qi "no data\|refresh\|--refresh"; then
    pass "test_rate_no_status_file"
  else
    fail "test_rate_no_status_file (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_rate_refresh_parses_headers
# Fixture: canned curl headers -> valid rate-status.json
# ---------------------------------------------------------------------------
test_rate_refresh_parses_headers() {
  setup_env
  # Create fixture headers file
  FIXTURE="${TMP}/headers.txt"
  cat > "$FIXTURE" <<'EOF'
HTTP/2 200
anthropic-ratelimit-unified-session-limit: 80000
anthropic-ratelimit-unified-session-remaining: 46400
anthropic-ratelimit-unified-session-reset: 2026-04-05T18:00:00Z
anthropic-ratelimit-unified-weekly-limit: 200000
anthropic-ratelimit-unified-weekly-remaining: 170000
anthropic-ratelimit-unified-weekly-reset: 2026-04-12T00:00:00Z
content-type: application/json
EOF
  # AFB_RATE_FIXTURE_HEADERS tells rate.sh to use the fixture instead of real curl
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" AFB_RATE_FIXTURE_HEADERS="$FIXTURE" AFB_RATE_FIXTURE_TOKEN="mock-token" bash "$AFB" rate --refresh 2>&1)
  rc=$?
  status_file="${FAKE_HOME}/afb/rate-status.json"
  if [[ "$rc" -eq 0 ]] && [[ -f "$status_file" ]]; then
    # Validate schema
    valid=$(python3 -c "
import json
d = json.load(open('${status_file}'))
assert 'last_check' in d
assert 'session' in d and 'utilization' in d['session']
assert 'weekly' in d and 'utilization' in d['weekly']
assert d['session']['utilization'] >= 0
print('ok')
" 2>&1)
    if [[ "$valid" == "ok" ]]; then
      pass "test_rate_refresh_parses_headers"
    else
      fail "test_rate_refresh_parses_headers (invalid schema: $valid)"
    fi
  else
    fail "test_rate_refresh_parses_headers (rc=$rc, status_file exists=$(test -f "$status_file" && echo yes || echo no), out=$out)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_rate_refresh_header_failure
# Fixture: response with no rate headers -> error in status file, exit 0
# ---------------------------------------------------------------------------
test_rate_refresh_header_failure() {
  setup_env
  FIXTURE="${TMP}/headers.txt"
  cat > "$FIXTURE" <<'EOF'
HTTP/2 200
content-type: application/json
x-request-id: abc123
EOF
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" AFB_RATE_FIXTURE_HEADERS="$FIXTURE" AFB_RATE_FIXTURE_TOKEN="mock-token" bash "$AFB" rate --refresh 2>&1)
  rc=$?
  status_file="${FAKE_HOME}/afb/rate-status.json"
  if [[ "$rc" -eq 0 ]] && [[ -f "$status_file" ]]; then
    error_msg=$(python3 -c "import json; d=json.load(open('${status_file}')); print(d.get('error',''))" 2>&1)
    if [[ -n "$error_msg" ]] && [[ "$error_msg" != "None" ]] && [[ "$error_msg" != "null" ]]; then
      pass "test_rate_refresh_header_failure"
    else
      fail "test_rate_refresh_header_failure (error not set in status file: $error_msg)"
    fi
  else
    fail "test_rate_refresh_header_failure (rc=$rc, status_file=$(test -f "$status_file" && echo exists || echo missing))"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_rate_refresh_network_failure
# Fixture: curl returns error -> error in status file, exit 0
# ---------------------------------------------------------------------------
test_rate_refresh_network_failure() {
  setup_env
  # AFB_RATE_FIXTURE_CURL_RC=6 simulates curl network error
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" AFB_RATE_FIXTURE_CURL_RC=6 AFB_RATE_FIXTURE_TOKEN="mock-token" bash "$AFB" rate --refresh 2>&1)
  rc=$?
  status_file="${FAKE_HOME}/afb/rate-status.json"
  if [[ "$rc" -eq 0 ]] && [[ -f "$status_file" ]]; then
    error_msg=$(python3 -c "import json; d=json.load(open('${status_file}')); print(d.get('error',''))" 2>&1)
    if [[ -n "$error_msg" ]] && [[ "$error_msg" != "None" ]] && [[ "$error_msg" != "null" ]]; then
      pass "test_rate_refresh_network_failure"
    else
      fail "test_rate_refresh_network_failure (error not set: $error_msg)"
    fi
  else
    fail "test_rate_refresh_network_failure (rc=$rc, out=$out)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_rate_refresh_token_macos — mock security command returns token
# ---------------------------------------------------------------------------
test_rate_refresh_token_macos() {
  setup_env
  FIXTURE="${TMP}/headers.txt"
  cat > "$FIXTURE" <<'EOF'
HTTP/2 200
anthropic-ratelimit-unified-session-limit: 80000
anthropic-ratelimit-unified-session-remaining: 40000
anthropic-ratelimit-unified-session-reset: 2026-04-05T18:00:00Z
anthropic-ratelimit-unified-weekly-limit: 200000
anthropic-ratelimit-unified-weekly-remaining: 100000
anthropic-ratelimit-unified-weekly-reset: 2026-04-12T00:00:00Z
EOF
  # Mock security command: create a fake one that returns a token
  MOCK_BIN="${TMP}/mockbin"
  mkdir -p "$MOCK_BIN"
  cat > "${MOCK_BIN}/security" <<'EOF'
#!/usr/bin/env bash
echo '{"claudeAiOauth":{"accessToken":"mock-oauth-token-12345","expiresAt":9999999999999}}'
EOF
  chmod 755 "${MOCK_BIN}/security"

  out=$(PATH="${MOCK_BIN}:${PATH}" AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" AFB_RATE_FIXTURE_HEADERS="$FIXTURE" AFB_PLATFORM_OVERRIDE=macos bash "$AFB" rate --refresh 2>&1)
  rc=$?
  status_file="${FAKE_HOME}/afb/rate-status.json"
  file_exists=0
  [[ -f "$status_file" ]] && file_exists=1
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && [[ "$file_exists" -eq 1 ]]; then
    pass "test_rate_refresh_token_macos"
  else
    fail "test_rate_refresh_token_macos (rc=$rc, file_exists=$file_exists, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_rate_refresh_token_linux — mock .credentials.json returns token
# ---------------------------------------------------------------------------
test_rate_refresh_token_linux() {
  setup_env
  FIXTURE="${TMP}/headers.txt"
  cat > "$FIXTURE" <<'EOF'
HTTP/2 200
anthropic-ratelimit-unified-session-limit: 80000
anthropic-ratelimit-unified-session-remaining: 40000
anthropic-ratelimit-unified-session-reset: 2026-04-05T18:00:00Z
anthropic-ratelimit-unified-weekly-limit: 200000
anthropic-ratelimit-unified-weekly-remaining: 100000
anthropic-ratelimit-unified-weekly-reset: 2026-04-12T00:00:00Z
EOF
  # Write .credentials.json to fake claude_home
  cat > "${FAKE_HOME}/.credentials.json" <<'EOF'
{"claudeAiOauth": {"accessToken": "mock-linux-token-99999", "expiresAt": 9999999999999}}
EOF
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" AFB_RATE_FIXTURE_HEADERS="$FIXTURE" AFB_PLATFORM_OVERRIDE=linux bash "$AFB" rate --refresh 2>&1)
  rc=$?
  status_file="${FAKE_HOME}/afb/rate-status.json"
  file_exists=0
  [[ -f "$status_file" ]] && file_exists=1
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && [[ "$file_exists" -eq 1 ]]; then
    pass "test_rate_refresh_token_linux"
  else
    fail "test_rate_refresh_token_linux (rc=$rc, file_exists=$file_exists, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_rate_interval_skips
# Account with recent last_check is skipped when interval not elapsed
# ---------------------------------------------------------------------------
test_rate_interval_skips() {
  TMP="$(mktemp -d)"
  FAKE_HOME="${TMP}/claude_home"
  mkdir -p "${FAKE_HOME}/afb"
  ACCOUNTS_FILE="${TMP}/accounts.json"
  # rate_interval = 60 min; last_check = now
  NOW=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).isoformat())")
  cat > "$ACCOUNTS_FILE" <<EOF
{
  "accounts": [
    { "name": "testacct", "claude_home": "${FAKE_HOME}", "default": true, "rate_interval": 60 }
  ]
}
EOF
  cat > "${FAKE_HOME}/afb/rate-status.json" <<EOF
{
  "last_check": "${NOW}",
  "session": { "utilization": 0.5, "status": "active", "resets_at": "2026-04-05T18:00:00Z" },
  "weekly":  { "utilization": 0.2, "status": "active", "resets_at": "2026-04-12T00:00:00Z" },
  "error": null
}
EOF
  FIXTURE="${TMP}/headers.txt"
  cat > "$FIXTURE" <<'EOF'
HTTP/2 200
anthropic-ratelimit-unified-session-limit: 80000
anthropic-ratelimit-unified-session-remaining: 40000
anthropic-ratelimit-unified-session-reset: 2026-04-05T18:00:00Z
anthropic-ratelimit-unified-weekly-limit: 200000
anthropic-ratelimit-unified-weekly-remaining: 100000
anthropic-ratelimit-unified-weekly-reset: 2026-04-12T00:00:00Z
EOF
  CALL_LOG="${TMP}/called"
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" AFB_RATE_FIXTURE_HEADERS="$FIXTURE" AFB_RATE_FIXTURE_TOKEN="mock-token" AFB_RATE_CALL_LOG="$CALL_LOG" bash "$AFB" rate --refresh 2>&1)
  # If interval hasn't elapsed, the API should NOT have been called
  if [[ ! -f "$CALL_LOG" ]]; then
    pass "test_rate_interval_skips"
  else
    fail "test_rate_interval_skips (API was called despite interval not elapsed)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_rate_self_test
# ---------------------------------------------------------------------------
test_rate_self_test() {
  setup_env
  # Write a recent status file with no errors
  cat > "${FAKE_HOME}/afb/rate-status.json" <<'EOF'
{
  "last_check": "2026-04-05T10:00:00Z",
  "session": { "utilization": 0.42, "status": "active", "resets_at": "2026-04-05T18:00:00Z" },
  "weekly":  { "utilization": 0.15, "status": "active", "resets_at": "2026-04-12T00:00:00Z" },
  "error": null
}
EOF
  out=$(run_afb rate --self-test 2>&1)
  rc=$?
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]]; then
    pass "test_rate_self_test"
  else
    fail "test_rate_self_test (rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_daemon_install_macos
# ---------------------------------------------------------------------------
test_daemon_install_macos() {
  setup_env
  MOCK_BIN="${TMP}/mockbin"
  mkdir -p "$MOCK_BIN"
  # Mock launchctl
  cat > "${MOCK_BIN}/launchctl" <<'SCRIPT'
#!/usr/bin/env bash
echo "launchctl $*" >> "${MOCK_LAUNCHCTL_LOG:-/dev/null}"
exit 0
SCRIPT
  chmod 755 "${MOCK_BIN}/launchctl"
  PLIST_DIR="${TMP}/LaunchAgents"
  mkdir -p "$PLIST_DIR"

  out=$(PATH="${MOCK_BIN}:${PATH}" \
    AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" \
    AFB_PLATFORM_OVERRIDE=macos \
    AFB_LAUNCHAGENTS_DIR="$PLIST_DIR" \
    MOCK_LAUNCHCTL_LOG="${TMP}/launchctl.log" \
    bash -c "echo y | bash '$AFB' rate --daemon install" 2>&1)
  rc=$?
  # Check that plist was created
  plist_count=$(find "$PLIST_DIR" -name "*.plist" | wc -l | tr -d ' ')
  rm -rf "$TMP"
  if [[ "$plist_count" -gt 0 ]]; then
    pass "test_daemon_install_macos"
  else
    fail "test_daemon_install_macos (no plist created, rc=$rc, out=$out)"
  fi
}

# ---------------------------------------------------------------------------
# test_daemon_install_linux
# ---------------------------------------------------------------------------
test_daemon_install_linux() {
  setup_env
  CRON_FILE="${TMP}/crontab"
  touch "$CRON_FILE"

  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" \
    AFB_PLATFORM_OVERRIDE=linux \
    AFB_CRON_FILE="$CRON_FILE" \
    bash -c "echo y | bash '$AFB' rate --daemon install" 2>&1)
  rc=$?
  # Check crontab entry was added
  if grep -q "afb rate --refresh" "$CRON_FILE"; then
    pass "test_daemon_install_linux"
  else
    fail "test_daemon_install_linux (no crontab entry, rc=$rc, out=$out)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_daemon_remove_macos
# ---------------------------------------------------------------------------
test_daemon_remove_macos() {
  setup_env
  MOCK_BIN="${TMP}/mockbin"
  mkdir -p "$MOCK_BIN"
  cat > "${MOCK_BIN}/launchctl" <<'SCRIPT'
#!/usr/bin/env bash
echo "launchctl $*" >> "${MOCK_LAUNCHCTL_LOG:-/dev/null}"
exit 0
SCRIPT
  chmod 755 "${MOCK_BIN}/launchctl"
  PLIST_DIR="${TMP}/LaunchAgents"
  mkdir -p "$PLIST_DIR"
  # Pre-create plist
  touch "${PLIST_DIR}/com.afb.rate-monitor.plist"

  out=$(PATH="${MOCK_BIN}:${PATH}" \
    AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" \
    AFB_PLATFORM_OVERRIDE=macos \
    AFB_LAUNCHAGENTS_DIR="$PLIST_DIR" \
    MOCK_LAUNCHCTL_LOG="${TMP}/launchctl.log" \
    bash "$AFB" rate --daemon remove 2>&1)
  rc=$?
  plist_count=$(find "$PLIST_DIR" -name "*.plist" | wc -l | tr -d ' ')
  rm -rf "$TMP"
  if [[ "$rc" -eq 0 ]] && [[ "$plist_count" -eq 0 ]]; then
    pass "test_daemon_remove_macos"
  else
    fail "test_daemon_remove_macos (rc=$rc, plists_remaining=$plist_count)"
  fi
}

# ---------------------------------------------------------------------------
# test_daemon_remove_linux
# ---------------------------------------------------------------------------
test_daemon_remove_linux() {
  setup_env
  CRON_FILE="${TMP}/crontab"
  cat > "$CRON_FILE" <<'EOF'
# existing cron jobs
0 9 * * * echo hello
*/10 * * * * /path/to/afb rate --refresh  # afb-managed
EOF

  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" \
    AFB_PLATFORM_OVERRIDE=linux \
    AFB_CRON_FILE="$CRON_FILE" \
    bash "$AFB" rate --daemon remove 2>&1)
  rc=$?
  if [[ "$rc" -eq 0 ]] && ! grep -q "afb rate --refresh" "$CRON_FILE"; then
    pass "test_daemon_remove_linux"
  else
    fail "test_daemon_remove_linux (rc=$rc, cron still has afb entry)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# test_daemon_install_prompts_user
# ---------------------------------------------------------------------------
test_daemon_install_prompts_user() {
  setup_env
  CRON_FILE="${TMP}/crontab"
  touch "$CRON_FILE"
  # Respond "n" — should abort
  out=$(AFB_ACCOUNTS_FILE="$ACCOUNTS_FILE" \
    AFB_PLATFORM_OVERRIDE=linux \
    AFB_CRON_FILE="$CRON_FILE" \
    bash -c "echo n | bash '$AFB' rate --daemon install" 2>&1)
  rc=$?
  # Should NOT have added crontab entry
  if ! grep -q "afb rate --refresh" "$CRON_FILE"; then
    pass "test_daemon_install_prompts_user"
  else
    fail "test_daemon_install_prompts_user (installed without y confirmation)"
  fi
  rm -rf "$TMP"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
test_rate_displays_status
test_rate_no_status_file
test_rate_refresh_parses_headers
test_rate_refresh_header_failure
test_rate_refresh_network_failure
test_rate_refresh_token_macos
test_rate_refresh_token_linux
test_rate_interval_skips
test_rate_self_test
test_daemon_install_macos
test_daemon_install_linux
test_daemon_remove_macos
test_daemon_remove_linux
test_daemon_install_prompts_user

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
