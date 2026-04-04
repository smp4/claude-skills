#!/usr/bin/env bash
# Multi-account Claude Code installer.
#
# Usage:
#   ./install.sh              # install/update all accounts
#   ./install.sh --check      # read-only sync check
#   ./install.sh --copy       # copy instead of symlink (standalone snapshot)
#   ./install.sh --uninstall  # remove managed items; restore settings.json.original
#   ./install.sh --force      # overwrite real files/dirs with symlinks
#   ./install.sh --skip-diff  # skip settings.json diff prompt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOT_CLAUDE="${SCRIPT_DIR}/dot_claude"

MODE="install"
FORCE=0
SKIP_DIFF=0

for arg in "$@"; do
  case "$arg" in
    --check)     MODE="check" ;;
    --copy)      MODE="copy" ;;
    --uninstall) MODE="uninstall" ;;
    --force)     FORCE=1 ;;
    --skip-diff) SKIP_DIFF=1 ;;
    *)
      echo "Usage: $0 [--check | --copy | --uninstall] [--force] [--skip-diff]"
      exit 1
      ;;
  esac
done

# --- Preflight --------------------------------------------------------------

if [[ ! -d "${DOT_CLAUDE}/skills" ]]; then
  echo "Error: dot_claude/skills/ not found. Complete Step 0 first." >&2
  exit 1
fi

# --- accounts.json ----------------------------------------------------------

ACCOUNTS_FILE="${SCRIPT_DIR}/accounts.json"

if [[ ! -f "$ACCOUNTS_FILE" ]]; then
  cat > "$ACCOUNTS_FILE" <<'EOF'
{ "accounts": [{ "name": "default", "claude_home": "~/.claude", "default": true }] }
EOF
  echo "Created accounts.json with single default account."
fi

# --- Validate accounts.json -------------------------------------------------

validate_accounts() {
  python3 - "$ACCOUNTS_FILE" <<'PYEOF'
import json, sys

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

import os
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

validate_accounts

# --- Parse accounts ---------------------------------------------------------

read_accounts() {
  python3 - "$ACCOUNTS_FILE" <<'PYEOF'
import json, os, sys

data = json.load(open(sys.argv[1]))
accounts = data["accounts"]
default_idx = next((i for i, a in enumerate(accounts) if a.get("default")), 0)

for i, acct in enumerate(accounts):
    name = acct["name"]
    home = os.path.expanduser(acct["claude_home"])
    is_default = "1" if i == default_idx else "0"
    # output: name|home|is_default
    print(f"{name}|{home}|{is_default}")
PYEOF
}

# --- Symlink helpers --------------------------------------------------------

make_symlink() {
  local src="$1" dest="$2" label="$3"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      return 0  # already correct
    fi
    rm "$dest"
    ln -s "$src" "$dest"
    echo "  Updated symlink: ${label}"
  elif [[ -e "$dest" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      rm -rf "$dest"
      ln -s "$src" "$dest"
      echo "  Forced symlink: ${label}"
    else
      echo "  Warning: ${label} exists as real file/dir — skipping (use --force to overwrite)"
    fi
  else
    ln -s "$src" "$dest"
    echo "  Linked: ${label}"
  fi
}

check_symlink() {
  local src="$1" dest="$2" label="$3"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" != "$src" ]]; then
      echo "  Error: ${label} → wrong target (${current})" >&2
      return 1
    fi
  else
    echo "  Error: ${label} not a symlink" >&2
    return 1
  fi
  return 0
}

# --- settings.json management -----------------------------------------------

hydrate_template() {
  local claude_home="$1"
  sed "s|{{CLAUDE_HOME}}|${claude_home}|g" "${DOT_CLAUDE}/settings.json.template"
}

# Get controlled field keys from template (top-level keys present in template)
template_controlled_keys() {
  python3 - "${DOT_CLAUDE}/settings.json.template" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
for k in data.keys():
    print(k)
PYEOF
}

settings_diff_and_merge() {
  local claude_home="$1"
  local settings_file="${claude_home}/settings.json"

  python3 - "$settings_file" "$claude_home" "$SKIP_DIFF" "$MODE" <<PYEOF
import json, sys, os, re

settings_path = sys.argv[1]
claude_home = sys.argv[2]
skip_diff = sys.argv[3] == "1"
mode = sys.argv[4]
template_path = os.path.join(os.path.dirname(os.path.dirname(settings_path)),
    "dot_claude", "settings.json.template")

# Resolve SCRIPT_DIR from settings_path: settings_path = <claude_home>/settings.json
# template is at <repo>/dot_claude/settings.json.template
# But we pass claude_home and need to find repo root.
# Actually the script sets DOT_CLAUDE which we don't have here — use env var passed via heredoc.
DOT_CLAUDE = os.environ.get("DOT_CLAUDE_PATH", "")
template_path = os.path.join(DOT_CLAUDE, "settings.json.template")

with open(template_path) as f:
    template_raw = f.read()

hydrated_raw = template_raw.replace("{{CLAUDE_HOME}}", claude_home)
template_data = json.loads(hydrated_raw)
controlled_keys = list(template_data.keys())

with open(settings_path) as f:
    existing = json.load(f)

# Normalise existing by replacing actual claude_home with placeholder
existing_normalised_raw = json.dumps(existing).replace(claude_home, "{{CLAUDE_HOME}}")
existing_normalised = json.loads(existing_normalised_raw)

# Compare controlled fields
diffs = []
template_normalised = json.loads(template_raw)
for k in controlled_keys:
    tv = template_normalised.get(k)
    ev = existing_normalised.get(k)
    if tv != ev:
        diffs.append((k, ev, tv))

if diffs and not skip_diff and mode != "check":
    print(f"\\nSettings diff for {settings_path}:")
    for k, ev, tv in diffs:
        print(f"  {k}:")
        print(f"    existing: {json.dumps(ev, indent=2)}")
        print(f"    template: {json.dumps(tv, indent=2)}")
    resp = input("\\nApply template values for controlled fields? [y/N] ").strip().lower()
    if resp != "y":
        print("Aborted.")
        sys.exit(1)

if mode == "check":
    errors = 0
    warnings = 0
    for k in controlled_keys:
        tv = template_normalised.get(k)
        ev = existing_normalised.get(k)
        if tv != ev:
            print(f"  Error: settings.json controlled field '{k}' diverged from template", file=sys.stderr)
            errors += 1
    for k in existing_normalised:
        if k not in controlled_keys:
            tv = template_normalised.get(k)
            ev = existing_normalised.get(k)
            if tv != ev:
                print(f"  Warning: settings.json field '{k}' differs from template")
                warnings += 1
    sys.exit(1 if errors else 0)

# Merge: template values for controlled keys, existing values for rest
merged = dict(existing)
for k in controlled_keys:
    merged[k] = template_data[k]

with open(settings_path + ".bak", "w") as f:
    json.dump(existing, f, indent=2)
    f.write("\\n")

with open(settings_path, "w") as f:
    json.dump(merged, f, indent=2)
    f.write("\\n")

print(f"  Updated: settings.json (backup → settings.json.bak)")
PYEOF
}

# --- Per-account install ----------------------------------------------------

install_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Account: ${name} (${claude_home})"

  mkdir -p "${claude_home}/skills"
  chmod u+w "${SCRIPT_DIR}/dot_claude/commands"

  # Migration: remove old per-skill symlinks pointing into repo root
  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    skill="$(basename "$skill_dir")"
    old_target="${SCRIPT_DIR}/${skill}"
    dest="${claude_home}/skills/${skill}"
    if [[ -L "$dest" ]]; then
      current="$(readlink "$dest")"
      if [[ "$current" == "$old_target" ]]; then
        rm "$dest"
        echo "  Migrating: removed old symlink skills/${skill}"
      fi
    fi
  done

  # Per-skill symlinks
  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    skill="$(basename "$skill_dir")"
    make_symlink "${DOT_CLAUDE}/skills/${skill}" "${claude_home}/skills/${skill}" "skills/${skill}"
  done

  # hooks, commands, CLAUDE.md, statusline-command.sh
  make_symlink "${DOT_CLAUDE}/hooks"                  "${claude_home}/hooks"                  "hooks/"
  make_symlink "${DOT_CLAUDE}/commands"               "${claude_home}/commands"               "commands/"
  make_symlink "${DOT_CLAUDE}/CLAUDE.md"              "${claude_home}/CLAUDE.md"              "CLAUDE.md"
  make_symlink "${DOT_CLAUDE}/statusline-command.sh"  "${claude_home}/statusline-command.sh"  "statusline-command.sh"

  # settings.json
  local settings_file="${claude_home}/settings.json"
  if [[ ! -f "$settings_file" && ! -f "${claude_home}/settings.json.original" ]]; then
    # First install
    hydrate_template "$claude_home" > "$settings_file"
    cp "$settings_file" "${claude_home}/settings.json.original"
    echo "  Created: settings.json (original saved to settings.json.original)"
  else
    DOT_CLAUDE_PATH="$DOT_CLAUDE" settings_diff_and_merge "$claude_home"
  fi
}

copy_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Account: ${name} (${claude_home}) [copy mode]"

  mkdir -p "${claude_home}/skills"

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    skill="$(basename "$skill_dir")"
    dest="${claude_home}/skills/${skill}"
    rm -rf "$dest"
    cp -RL "${DOT_CLAUDE}/skills/${skill}" "$dest"
    echo "  Copied: skills/${skill}"
  done

  for item in hooks commands CLAUDE.md statusline-command.sh; do
    python3 -c "import os,sys; p=sys.argv[1]; os.remove(p) if os.path.islink(p) or os.path.isfile(p) else (os.path.isdir(p) and __import__('shutil').rmtree(p))" "${claude_home}/${item}" 2>/dev/null || true
  done
  cp -RL "${DOT_CLAUDE}/hooks"               "${claude_home}/hooks"
  cp -RL "${DOT_CLAUDE}/commands"            "${claude_home}/commands"
  cp     "${DOT_CLAUDE}/CLAUDE.md"           "${claude_home}/CLAUDE.md"
  cp     "${DOT_CLAUDE}/statusline-command.sh" "${claude_home}/statusline-command.sh"
  echo "  Copied: hooks/, commands/, CLAUDE.md, statusline-command.sh"

  hydrate_template "$claude_home" > "${claude_home}/settings.json"
  echo "  Generated: settings.json"
}

uninstall_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Uninstalling: ${name} (${claude_home})"

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    skill="$(basename "$skill_dir")"
    dest="${claude_home}/skills/${skill}"
    if [[ -L "$dest" ]]; then
      rm "$dest"
      echo "  Removed symlink: skills/${skill}"
    fi
  done

  for item in hooks commands CLAUDE.md statusline-command.sh; do
    dest="${claude_home}/${item}"
    if [[ -L "$dest" ]]; then
      rm "$dest"
      echo "  Removed symlink: ${item}"
    fi
  done

  # Restore settings.json from original
  if [[ -f "${claude_home}/settings.json.original" ]]; then
    cp "${claude_home}/settings.json.original" "${claude_home}/settings.json"
    rm -f "${claude_home}/settings.json.bak"
    echo "  Restored: settings.json from settings.json.original"
  fi
}

check_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Checking: ${name} (${claude_home})"
  local errors=0

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    skill="$(basename "$skill_dir")"
    check_symlink "${DOT_CLAUDE}/skills/${skill}" "${claude_home}/skills/${skill}" "skills/${skill}" || errors=$((errors+1))
  done

  check_symlink "${DOT_CLAUDE}/hooks"                 "${claude_home}/hooks"                 "hooks/" || errors=$((errors+1))
  check_symlink "${DOT_CLAUDE}/commands"              "${claude_home}/commands"              "commands/" || errors=$((errors+1))
  check_symlink "${DOT_CLAUDE}/CLAUDE.md"             "${claude_home}/CLAUDE.md"             "CLAUDE.md" || errors=$((errors+1))
  check_symlink "${DOT_CLAUDE}/statusline-command.sh" "${claude_home}/statusline-command.sh" "statusline-command.sh" || errors=$((errors+1))

  if [[ -f "${claude_home}/settings.json" ]]; then
    DOT_CLAUDE_PATH="$DOT_CLAUDE" settings_diff_and_merge "$claude_home" || errors=$((errors+1))
  else
    echo "  Warning: settings.json not found"
  fi

  [[ "$errors" -eq 0 ]]
}

# --- Main loop --------------------------------------------------------------

ALIASES=""
DEFAULT_NAME=""
CHECK_ERRORS=0

while IFS='|' read -r name claude_home is_default; do
  case "$MODE" in
    install) install_account "$name" "$claude_home" ;;
    copy)    copy_account    "$name" "$claude_home" ;;
    uninstall) uninstall_account "$name" "$claude_home" ;;
    check)   check_account "$name" "$claude_home" || CHECK_ERRORS=$((CHECK_ERRORS+1)) ;;
  esac

  alias_cmd="alias ${name}='CLAUDE_CONFIG_DIR=${claude_home} claude'"
  ALIASES="${ALIASES}${alias_cmd}\n"
  if [[ "$is_default" == "1" ]]; then
    DEFAULT_NAME="$name"
    ALIASES="${ALIASES}alias claude='CLAUDE_CONFIG_DIR=${claude_home} claude'\n"
  fi
done < <(read_accounts)

# --- Generate aliases.sh ----------------------------------------------------

if [[ "$MODE" != "check" && "$MODE" != "uninstall" ]]; then
  printf "# Auto-generated by install.sh — source from ~/.profile or ~/.zshrc\n" > "${SCRIPT_DIR}/aliases.sh"
  printf "# NOTE: these aliases override CLAUDE_CONFIG_DIR if set in interactive shells.\n" >> "${SCRIPT_DIR}/aliases.sh"
  printf "${ALIASES}" >> "${SCRIPT_DIR}/aliases.sh"
  echo ""
  echo "Generated aliases.sh"
  echo "Add to ~/.profile or ~/.zshrc:"
  echo "  source ${SCRIPT_DIR}/aliases.sh"
fi

echo ""
echo "Done."

if [[ "$MODE" == "check" && "$CHECK_ERRORS" -gt 0 ]]; then
  exit 1
fi
