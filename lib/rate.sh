#!/usr/bin/env bash
# lib/rate.sh — rate monitoring, API check, status file I/O, daemon management

# Platform: use override env var for testing, else detect
_afb_platform() {
  echo "${AFB_PLATFORM_OVERRIDE:-$(afb_detect_platform)}"
}

# LaunchAgents dir: override for testing
_afb_launchagents_dir() {
  echo "${AFB_LAUNCHAGENTS_DIR:-${HOME}/Library/LaunchAgents}"
}

# Cron file: override for testing (empty = use real crontab)
_afb_cron_file() {
  echo "${AFB_CRON_FILE:-}"
}

# --- Token retrieval ---------------------------------------------------------

_afb_rate_read_creds() {
  local platform="$1" claude_home="$2"
  case "$platform" in
    macos)
      security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null
      ;;
    linux)
      local creds="${claude_home}/.credentials.json"
      if [[ ! -f "$creds" ]]; then
        echo "Error: .credentials.json not found at ${creds}" >&2
        return 1
      fi
      cat "$creds"
      ;;
    *)
      echo "Error: unknown platform '${platform}'" >&2
      return 1
      ;;
  esac
}

_afb_rate_write_creds() {
  local platform="$1" claude_home="$2" new_json="$3"
  case "$platform" in
    macos)
      security delete-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 || true
      security add-generic-password -s "Claude Code-credentials" -a "Claude Code" -w "$new_json"
      ;;
    linux)
      local creds="${claude_home}/.credentials.json"
      printf '%s\n' "$new_json" > "$creds"
      chmod 600 "$creds"
      ;;
  esac
}

_afb_rate_refresh_token() {
  local refresh_token="$1"
  local client_id="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  local token_url="https://platform.claude.com/v1/oauth/token"

  curl -sf --max-time 10 -X POST "$token_url" \
    -H "Content-Type: application/json" \
    -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"${refresh_token}\",\"client_id\":\"${client_id}\"}"
}

afb_rate_get_token() {
  # Test fixture: bypass real token retrieval
  if [[ -n "${AFB_RATE_FIXTURE_TOKEN:-}" ]]; then
    echo "$AFB_RATE_FIXTURE_TOKEN"
    return 0
  fi

  local claude_home="$1"
  local platform
  platform="$(_afb_platform)"

  local raw
  raw="$(_afb_rate_read_creds "$platform" "$claude_home")" || return 1

  # Extract token; check expiry
  local output
  output="$(_afb_timeout 2 python3 -c "
import json, sys, time
d = json.loads(sys.argv[1])
oauth = d.get('claudeAiOauth', {})
token = oauth.get('accessToken') or d.get('token')
expires_at = oauth.get('expiresAt', 0)

if not token:
    print('Error: no token in credentials', file=sys.stderr)
    sys.exit(1)

# Expired or within 5 min of expiry?
now_ms = int(time.time() * 1000)
if expires_at and now_ms >= (expires_at - 300000):
    rt = oauth.get('refreshToken')
    if not rt:
        print('Error: token expired, no refresh token', file=sys.stderr)
        sys.exit(1)
    print('REFRESH:' + rt)
else:
    print(token)
" "$raw" 2>/tmp/afb_token_err)" || return 1

  if [[ "$output" != REFRESH:* ]]; then
    echo "$output"
    return 0
  fi

  # Token expired — refresh it
  local refresh_token="${output#REFRESH:}"
  local refreshed
  refreshed="$(_afb_rate_refresh_token "$refresh_token")"
  if [[ $? -ne 0 || -z "$refreshed" ]]; then
    echo "Error: token refresh failed" >&2
    return 1
  fi

  # Update stored credentials with new token
  local new_json
  new_json="$(_afb_timeout 2 python3 -c "
import json, sys, time
d = json.loads(sys.argv[1])
r = json.loads(sys.argv[2])
oauth = d.get('claudeAiOauth', {})
oauth['accessToken'] = r['access_token']
if 'refresh_token' in r:
    oauth['refreshToken'] = r['refresh_token']
oauth['expiresAt'] = int(time.time() * 1000) + r.get('expires_in', 3600) * 1000
d['claudeAiOauth'] = oauth
print(json.dumps(d))
" "$raw" "$refreshed")" || return 1

  _afb_rate_write_creds "$platform" "$claude_home" "$new_json"

  # Return new access token
  _afb_timeout 2 python3 -c "
import json, sys
print(json.loads(sys.argv[1])['access_token'])
" "$refreshed"
}

# --- API call ----------------------------------------------------------------

_afb_rate_curl() {
  local token="$1" headers_file="$2"

  # Test fixture: if AFB_RATE_FIXTURE_CURL_RC is set, simulate curl error
  if [[ -n "${AFB_RATE_FIXTURE_CURL_RC:-}" ]]; then
    return "${AFB_RATE_FIXTURE_CURL_RC}"
  fi

  # Test fixture: if AFB_RATE_FIXTURE_HEADERS is set, copy it to headers_file
  if [[ -n "${AFB_RATE_FIXTURE_HEADERS:-}" ]]; then
    cp "$AFB_RATE_FIXTURE_HEADERS" "$headers_file"
    # Log call for interval-skip test
    if [[ -n "${AFB_RATE_CALL_LOG:-}" ]]; then
      echo "called" >> "$AFB_RATE_CALL_LOG"
    fi
    return 0
  fi

  # Real curl
  curl -s -D "$headers_file" -o /dev/null \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "Authorization: Bearer ${token}" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "Content-Type: application/json" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'

  if [[ -n "${AFB_RATE_CALL_LOG:-}" ]]; then
    echo "called" >> "$AFB_RATE_CALL_LOG"
  fi
}

# --- Parse headers and write status -----------------------------------------

_afb_write_status_file() {
  local status_file="$1" headers_file="$2"
  local afb_dir
  afb_dir="$(dirname "$status_file")"
  mkdir -p "$afb_dir"

  _afb_timeout 2 python3 - "$headers_file" "$status_file" <<'PYEOF'
import json, sys, re
from datetime import datetime, timezone

headers_path = sys.argv[1]
output_path = sys.argv[2]
tmp_path = output_path + ".tmp"

with open(headers_path) as f:
    raw = f.read()

def find_header(name):
    m = re.search(rf'^{re.escape(name)}:\s*(.+)$', raw, re.MULTILINE | re.IGNORECASE)
    return m.group(1).strip() if m else None

session_limit     = find_header("anthropic-ratelimit-unified-session-limit")
session_remaining = find_header("anthropic-ratelimit-unified-session-remaining")
session_reset     = find_header("anthropic-ratelimit-unified-session-reset")
weekly_limit      = find_header("anthropic-ratelimit-unified-weekly-limit")
weekly_remaining  = find_header("anthropic-ratelimit-unified-weekly-remaining")
weekly_reset      = find_header("anthropic-ratelimit-unified-weekly-reset")

now = datetime.now(timezone.utc).isoformat()

def utilization(limit, remaining):
    try:
        l, r = int(limit), int(remaining)
        return round((l - r) / l, 4) if l > 0 else 0.0
    except (TypeError, ValueError, ZeroDivisionError):
        return None

def status_label(u):
    if u is None:
        return "unknown"
    if u >= 0.9:
        return "rate_limited"
    if u >= 0.7:
        return "warning"
    return "active"

if not session_limit or not weekly_limit:
    result = {
        "last_check": now,
        "session": None,
        "weekly": None,
        "error": "rate headers not present — beta API may have changed"
    }
else:
    su = utilization(session_limit, session_remaining)
    wu = utilization(weekly_limit, weekly_remaining)
    result = {
        "last_check": now,
        "session": {
            "utilization": su,
            "status": status_label(su),
            "resets_at": session_reset
        },
        "weekly": {
            "utilization": wu,
            "status": status_label(wu),
            "resets_at": weekly_reset
        },
        "error": None
    }

with open(tmp_path, "w") as f:
    json.dump(result, f, indent=2)
    f.write("\n")

import os
os.rename(tmp_path, output_path)
PYEOF
}

_afb_write_error_status() {
  local status_file="$1" error_msg="$2"
  local afb_dir
  afb_dir="$(dirname "$status_file")"
  mkdir -p "$afb_dir"
  local tmp="${status_file}.tmp"
  _afb_timeout 2 python3 -c "
import json, sys
from datetime import datetime, timezone
now = datetime.now(timezone.utc).isoformat()
d = {'last_check': now, 'session': None, 'weekly': None, 'error': sys.argv[1]}
tmp = sys.argv[2]
out = sys.argv[3]
with open(tmp, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
import os; os.rename(tmp, out)
" "$error_msg" "$tmp" "$status_file"
}

# --- Check interval ---------------------------------------------------------

_afb_check_interval_elapsed() {
  local status_file="$1" interval_minutes="$2"
  [[ ! -f "$status_file" ]] && return 0  # no file = always check
  _afb_timeout 2 python3 - "$status_file" "$interval_minutes" <<'PYEOF'
import json, sys
from datetime import datetime, timezone, timedelta

d = json.load(open(sys.argv[1]))
interval = int(sys.argv[2])
last = d.get("last_check")
if not last:
    sys.exit(0)  # no last_check = check now

try:
    # Parse ISO-8601 with timezone
    last_dt = datetime.fromisoformat(last.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    if now - last_dt >= timedelta(minutes=interval):
        sys.exit(0)  # elapsed
    else:
        sys.exit(1)  # not yet
except Exception:
    sys.exit(0)  # parse error = check now
PYEOF
}

# --- Per-account refresh ----------------------------------------------------

afb_rate_check_account() {
  local name="$1" claude_home="$2" interval_minutes="${3:-10}"
  local status_file="${claude_home}/afb/rate-status.json"

  # Check if interval elapsed
  if ! _afb_check_interval_elapsed "$status_file" "$interval_minutes"; then
    echo "  ${name}: skipping (checked within last ${interval_minutes} min)"
    return 0
  fi

  # Get token
  local token
  if ! token=$(afb_rate_get_token "$claude_home" 2>/tmp/afb_token_err); then
    local err_msg
    err_msg="$(cat /tmp/afb_token_err 2>/dev/null || echo "token retrieval failed")"
    _afb_write_error_status "$status_file" "token error: ${err_msg}"
    echo "  ${name}: token error — ${err_msg}" >&2
    return 0
  fi

  # Make API call
  local headers_file
  headers_file="$(mktemp)"
  if ! _afb_rate_curl "$token" "$headers_file"; then
    local curl_rc=$?
    _afb_write_error_status "$status_file" "network error: curl exited ${curl_rc}"
    echo "  ${name}: network error (curl rc=${curl_rc})" >&2
    rm -f "$headers_file"
    return 0
  fi

  # Parse headers and write status
  _afb_write_status_file "$status_file" "$headers_file"
  rm -f "$headers_file"
  echo "  ${name}: updated ${status_file}"
}

# --- Display ----------------------------------------------------------------

afb_rate_display() {
  local has_any=0
  printf "%-15s %-10s %-10s %-12s %s\n" "Account" "Session" "Weekly" "Status" "Last check"
  printf "%-15s %-10s %-10s %-12s %s\n" "-------" "-------" "------" "------" "----------"

  while IFS='|' read -r name claude_home is_default; do
    local status_file="${claude_home}/afb/rate-status.json"
    if [[ ! -f "$status_file" ]]; then
      printf "%-15s %-10s %-10s %-12s %s\n" "$name" "no data" "no data" "-" "run --refresh"
      has_any=1
      continue
    fi
    has_any=1
    _afb_timeout 2 python3 - "$status_file" "$name" <<'PYEOF'
import json, sys

d = json.load(open(sys.argv[1]))
name = sys.argv[2]
err = d.get("error")
last = d.get("last_check", "?")[:19].replace("T", " ")

if err:
    print(f"{name:<15} {'error':<10} {'error':<10} {'error':<12} {last}")
else:
    def pct(u):
        if u is None: return "?"
        return f"{int(round(u*100))}%"
    s = d.get("session") or {}
    w = d.get("weekly") or {}
    su = pct(s.get("utilization"))
    wu = pct(w.get("utilization"))
    status = s.get("status", "?")
    print(f"{name:<15} {su:<10} {wu:<10} {status:<12} {last}")
PYEOF
  done < <(afb_read_accounts)

  if [[ "$has_any" -eq 0 ]]; then
    echo "No accounts configured."
  fi
}

# --- Self-test ---------------------------------------------------------------

afb_rate_self_test() {
  local all_ok=1
  while IFS='|' read -r name claude_home is_default; do
    local status_file="${claude_home}/afb/rate-status.json"
    if [[ ! -f "$status_file" ]]; then
      echo "WARN [${name}]: no status file — run 'afb rate --refresh'" >&2
      all_ok=0
      continue
    fi
    local has_error
    has_error=$(_afb_timeout 2 python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
err = d.get('error')
print('error' if err else 'ok')
" "$status_file" 2>/dev/null)
    if [[ "$has_error" == "error" ]]; then
      echo "WARN [${name}]: last refresh had an error — API headers may have changed" >&2
      all_ok=0
    else
      echo "OK   [${name}]: last refresh OK"
    fi
  done < <(afb_read_accounts)
  [[ "$all_ok" -eq 1 ]]
}

# --- Refresh -----------------------------------------------------------------

afb_rate_refresh() {
  while IFS='|' read -r name claude_home is_default; do
    local interval=10
    # Read per-account rate_interval if set
    local accounts_file
    accounts_file="$(afb_accounts_file)"
    local acct_interval
    acct_interval=$(_afb_timeout 2 python3 - "$accounts_file" "$name" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
name = sys.argv[2]
for a in data["accounts"]:
    if a["name"] == name:
        print(a.get("rate_interval", 10))
        break
PYEOF
)
    interval="${acct_interval:-10}"
    afb_rate_check_account "$name" "$claude_home" "$interval"
  done < <(afb_read_accounts)
}

# --- Daemon: macOS (launchd) -------------------------------------------------

_afb_daemon_label() {
  echo "com.afb.rate-monitor"
}

_afb_launchd_plist_path() {
  local launchagents_dir
  launchagents_dir="$(_afb_launchagents_dir)"
  echo "${launchagents_dir}/$(_afb_daemon_label).plist"
}

_afb_daemon_install_macos() {
  local afb_path="${AFB_ROOT}/afb"
  local plist_path
  plist_path="$(_afb_launchd_plist_path)"
  local launchagents_dir
  launchagents_dir="$(_afb_launchagents_dir)"
  # Use first account's rate_interval for plist interval (seconds)
  local interval_min=10
  local accounts_file
  accounts_file="$(afb_accounts_file)"
  local first_interval
  first_interval=$(_afb_timeout 2 python3 -c "
import json; d=json.load(open('${accounts_file}')); a=d['accounts'][0]; print(a.get('rate_interval',10))
" 2>/dev/null)
  interval_min="${first_interval:-10}"
  local interval_sec=$((interval_min * 60))

  local label
  label="$(_afb_daemon_label)"

  cat <<EOF
Will install launchd plist at:
  ${plist_path}

Interval: every ${interval_min} minutes
Command: ${afb_path} rate --refresh
EOF
  printf "Proceed? [y/N] "
  local ans
  read -r ans
  if [[ "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
    echo "Aborted."
    exit 0
  fi

  mkdir -p "$launchagents_dir"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${afb_path}</string>
    <string>rate</string>
    <string>--refresh</string>
  </array>
  <key>StartInterval</key>
  <integer>${interval_sec}</integer>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
PLIST

  launchctl bootstrap "gui/$(id -u)" "$plist_path" 2>/dev/null || \
    launchctl load "$plist_path" 2>/dev/null || true
  echo "Daemon installed: ${plist_path}"
}

_afb_daemon_remove_macos() {
  local plist_path
  plist_path="$(_afb_launchd_plist_path)"
  local label
  label="$(_afb_daemon_label)"
  if [[ -f "$plist_path" ]]; then
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || \
      launchctl unload "$plist_path" 2>/dev/null || true
    rm -f "$plist_path"
    echo "Daemon removed."
  else
    echo "Daemon not installed."
  fi
}

# --- Daemon: Linux (cron) ----------------------------------------------------

_afb_cron_read() {
  local cron_file
  cron_file="$(_afb_cron_file)"
  if [[ -n "$cron_file" ]]; then
    cat "$cron_file" 2>/dev/null || true
  else
    crontab -l 2>/dev/null || true
  fi
}

_afb_cron_write() {
  local cron_file
  cron_file="$(_afb_cron_file)"
  if [[ -n "$cron_file" ]]; then
    cat > "$cron_file"
  else
    crontab -
  fi
}

_afb_daemon_install_linux() {
  local afb_path="${AFB_ROOT}/afb"
  local accounts_file
  accounts_file="$(afb_accounts_file)"

  # Build cron lines per account
  local new_entries=""
  while IFS='|' read -r name claude_home is_default; do
    local interval=10
    local acct_interval
    acct_interval=$(_afb_timeout 2 python3 - "$accounts_file" "$name" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
name = sys.argv[2]
for a in data["accounts"]:
    if a["name"] == name:
        print(a.get("rate_interval", 10))
        break
PYEOF
)
    interval="${acct_interval:-10}"
    new_entries="${new_entries}*/${interval} * * * * ${afb_path} rate --refresh  # afb-managed\n"
  done < <(afb_read_accounts)

  cat <<EOF
Will add to crontab:
$(printf "$new_entries")
EOF
  printf "Proceed? [y/N] "
  local ans
  read -r ans
  if [[ "$(echo "$ans" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
    echo "Aborted."
    exit 0
  fi

  # Remove existing afb entries, then append new ones
  local current
  current="$(_afb_cron_read | grep -v '# afb-managed' || true)"
  printf "%s\n%b" "$current" "$new_entries" | _afb_cron_write
  echo "Daemon installed (crontab updated)."
}

_afb_daemon_remove_linux() {
  local current
  current="$(_afb_cron_read | grep -v '# afb-managed' || true)"
  printf "%s\n" "$current" | _afb_cron_write
  echo "Daemon removed (crontab updated)."
}

# --- Daemon dispatch ---------------------------------------------------------

afb_daemon_install() {
  local platform
  platform="$(_afb_platform)"
  case "$platform" in
    macos) _afb_daemon_install_macos ;;
    linux) _afb_daemon_install_linux ;;
    *)     echo "Error: unsupported platform '${platform}'" >&2; exit 1 ;;
  esac
}

afb_daemon_remove() {
  local platform
  platform="$(_afb_platform)"
  case "$platform" in
    macos) _afb_daemon_remove_macos ;;
    linux) _afb_daemon_remove_linux ;;
    *)     echo "Error: unsupported platform '${platform}'" >&2; exit 1 ;;
  esac
}

# --- Main entrypoint ---------------------------------------------------------

afb_rate_main() {
  local refresh=0 self_test=0 daemon_cmd=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --refresh)   refresh=1 ;;
      --self-test) self_test=1 ;;
      --daemon)
        shift
        daemon_cmd="${1:-}"
        ;;
      --help|-h)
        echo "Usage: afb rate [--refresh] [--self-test] [--daemon install|remove]"
        exit 0
        ;;
      *)
        echo "afb rate: unknown option '${1}'" >&2
        exit 1
        ;;
    esac
    shift
  done

  if [[ -n "$daemon_cmd" ]]; then
    case "$daemon_cmd" in
      install) afb_daemon_install ;;
      remove)  afb_daemon_remove ;;
      *)
        echo "afb rate --daemon: unknown command '${daemon_cmd}'" >&2
        exit 1
        ;;
    esac
  elif [[ "$self_test" -eq 1 ]]; then
    afb_rate_self_test
  elif [[ "$refresh" -eq 1 ]]; then
    afb_rate_refresh
  else
    afb_rate_display
  fi
}
