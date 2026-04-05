#!/usr/bin/env bash
# lib/common.sh — shared utilities for afb

# AFB_SCRIPT_DIR is set by the afb entrypoint; fall back to dirname of this file
AFB_LIB_DIR="${AFB_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AFB_ROOT="${AFB_ROOT:-$(cd "${AFB_LIB_DIR}/.." && pwd)}"
DOT_CLAUDE="${DOT_CLAUDE:-${AFB_ROOT}/dot_claude}"

# Portable timeout: use system timeout if available, else perl fallback (macOS)
_afb_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    perl -e "alarm $secs; exec @ARGV" -- "$@"
  fi
}

# accounts.json location — override with AFB_ACCOUNTS_FILE for testing
afb_accounts_file() {
  echo "${AFB_ACCOUNTS_FILE:-${AFB_ROOT}/accounts.json}"
}

# Slugify: lowercase, spaces/underscores -> hyphens, strip non-alphanumeric-hyphens
afb_slugify() {
  local input="$1"
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[ _]/-/g' \
    | sed 's/[^a-z0-9-]//g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//'
}

# Detect platform: outputs "macos" or "linux"
afb_detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    *)      echo "linux" ;;
  esac
}

# Validate accounts.json — exits 1 on error
afb_validate_accounts() {
  local accounts_file
  accounts_file="$(afb_accounts_file)"
  _afb_timeout 2 python3 - "$accounts_file" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
try:
    data = json.load(open(path))
except json.JSONDecodeError as e:
    print(f"Error: accounts.json invalid JSON: {e}", file=sys.stderr)
    sys.exit(1)

accounts = data.get("accounts", [])
if not accounts:
    print("Error: accounts.json has no accounts", file=sys.stderr)
    sys.exit(1)

seen_homes = {}
defaults = 0
errors = 0

for i, acct in enumerate(accounts):
    if "name" not in acct:
        print(f"Error: account[{i}] missing 'name'", file=sys.stderr)
        errors += 1
    if "claude_home" not in acct:
        print(f"Error: account[{i}] missing 'claude_home'", file=sys.stderr)
        errors += 1
    else:
        expanded = os.path.expanduser(acct["claude_home"])
        if expanded in seen_homes:
            print(f"Warning: accounts '{seen_homes[expanded]}' and '{acct.get('name','?')}' share claude_home {expanded}", file=sys.stderr)
        seen_homes[expanded] = acct.get("name", str(i))
    if acct.get("default"):
        defaults += 1

if defaults > 1:
    print("Error: more than one account has \"default\": true", file=sys.stderr)
    sys.exit(1)
if defaults == 0:
    print("Warning: no account has \"default\": true — using first account as default", file=sys.stderr)

if errors:
    sys.exit(1)
PYEOF
}

# Read accounts — outputs name|home|is_default per line
afb_read_accounts() {
  local accounts_file
  accounts_file="$(afb_accounts_file)"
  _afb_timeout 2 python3 - "$accounts_file" <<'PYEOF'
import json, os, sys

data = json.load(open(sys.argv[1]))
accounts = data["accounts"]
default_idx = next((i for i, a in enumerate(accounts) if a.get("default")), 0)

for i, acct in enumerate(accounts):
    name = acct["name"]
    home = os.path.expanduser(acct["claude_home"])
    is_default = "1" if i == default_idx else "0"
    print(f"{name}|{home}|{is_default}")
PYEOF
}

# Preflight: ensure accounts.json exists; exits 2 if not
afb_preflight() {
  local accounts_file
  accounts_file="$(afb_accounts_file)"
  if [[ ! -f "$accounts_file" ]]; then
    echo "Setup required: accounts.json not found." >&2
    echo "" >&2
    echo "Run 'afb install' to create a default accounts.json and set up your account." >&2
    exit 2
  fi
}
