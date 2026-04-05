#!/usr/bin/env bash
# lib/install.sh — install / uninstall / check subcommands

# AFB_INSTALL_BIN_DIR: override for ~/.local/bin (used in tests)
_afb_install_bin_dir() {
  echo "${AFB_INSTALL_BIN_DIR:-${HOME}/.local/bin}"
}

# --- Symlink helpers ---------------------------------------------------------

_afb_make_symlink() {
  local src="$1" dest="$2" label="$3" force="$4"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" == "$src" ]]; then
      return 0
    fi
    rm "$dest"
    ln -s "$src" "$dest"
    echo "  Updated symlink: ${label}"
  elif [[ -e "$dest" ]]; then
    if [[ "$force" -eq 1 ]]; then
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

_afb_check_symlink() {
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

# --- settings.json -----------------------------------------------------------

_afb_hydrate_template() {
  local claude_home="$1"
  sed "s|{{CLAUDE_HOME}}|${claude_home}|g" "${DOT_CLAUDE}/settings.json.template"
}

_afb_settings_diff_and_merge() {
  local claude_home="$1" skip_diff="$2" mode="$3"
  local settings_file="${claude_home}/settings.json"

  DOT_CLAUDE_PATH="$DOT_CLAUDE" _afb_timeout 2 python3 - "$settings_file" "$claude_home" "$skip_diff" "$mode" <<PYEOF
import json, sys, os

settings_path = sys.argv[1]
claude_home = sys.argv[2]
skip_diff = sys.argv[3] == "1"
mode = sys.argv[4]
DOT_CLAUDE = os.environ.get("DOT_CLAUDE_PATH", "")
template_path = os.path.join(DOT_CLAUDE, "settings.json.template")

with open(template_path) as f:
    template_raw = f.read()

hydrated_raw = template_raw.replace("{{CLAUDE_HOME}}", claude_home)
template_data = json.loads(hydrated_raw)
controlled_keys = list(template_data.keys())

with open(settings_path) as f:
    existing = json.load(f)

existing_normalised_raw = json.dumps(existing).replace(claude_home, "{{CLAUDE_HOME}}")
existing_normalised = json.loads(existing_normalised_raw)
template_normalised = json.loads(template_raw)

diffs = []
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
    sys.exit(1 if errors else 0)

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

# --- Per-account operations --------------------------------------------------

_afb_install_account() {
  local name="$1" claude_home="$2" force="$3" skip_diff="$4"
  echo ""
  echo "Account: ${name} (${claude_home})"

  mkdir -p "${claude_home}/skills"
  chmod u+w "${DOT_CLAUDE}/commands" 2>/dev/null || true

  # Migration: remove old per-skill symlinks pointing into repo root
  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill="$(basename "$skill_dir")"
    old_target="${AFB_ROOT}/${skill}"
    dest="${claude_home}/skills/${skill}"
    if [[ -L "$dest" ]]; then
      current="$(readlink "$dest")"
      if [[ "$current" == "$old_target" ]]; then
        rm "$dest"
        echo "  Migrating: removed old symlink skills/${skill}"
      fi
    fi
  done

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill="$(basename "$skill_dir")"
    _afb_make_symlink "${DOT_CLAUDE}/skills/${skill}" "${claude_home}/skills/${skill}" "skills/${skill}" "$force"
  done

  _afb_make_symlink "${DOT_CLAUDE}/hooks"                 "${claude_home}/hooks"                 "hooks/"       "$force"
  _afb_make_symlink "${DOT_CLAUDE}/commands"              "${claude_home}/commands"              "commands/"    "$force"
  _afb_make_symlink "${DOT_CLAUDE}/CLAUDE.md"             "${claude_home}/CLAUDE.md"             "CLAUDE.md"    "$force"
  _afb_make_symlink "${DOT_CLAUDE}/statusline-command.sh" "${claude_home}/statusline-command.sh" "statusline-command.sh" "$force"

  local settings_file="${claude_home}/settings.json"
  if [[ ! -f "$settings_file" && ! -f "${claude_home}/settings.json.original" ]]; then
    _afb_hydrate_template "$claude_home" > "$settings_file"
    cp "$settings_file" "${claude_home}/settings.json.original"
    echo "  Created: settings.json (original saved to settings.json.original)"
  else
    _afb_settings_diff_and_merge "$claude_home" "$skip_diff" "install"
  fi
}

_afb_copy_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Account: ${name} (${claude_home}) [copy mode]"

  mkdir -p "${claude_home}/skills"

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill="$(basename "$skill_dir")"
    dest="${claude_home}/skills/${skill}"
    rm -rf "$dest"
    cp -RL "${DOT_CLAUDE}/skills/${skill}" "$dest"
    echo "  Copied: skills/${skill}"
  done

  for item in hooks commands CLAUDE.md statusline-command.sh; do
    python3 -c "import os,sys,shutil; p=sys.argv[1]; (os.remove(p) if os.path.islink(p) or os.path.isfile(p) else shutil.rmtree(p)) if os.path.exists(p) else None" "${claude_home}/${item}" 2>/dev/null || true
  done
  cp -RL "${DOT_CLAUDE}/hooks"               "${claude_home}/hooks"
  cp -RL "${DOT_CLAUDE}/commands"            "${claude_home}/commands"
  cp     "${DOT_CLAUDE}/CLAUDE.md"           "${claude_home}/CLAUDE.md"
  cp     "${DOT_CLAUDE}/statusline-command.sh" "${claude_home}/statusline-command.sh"
  echo "  Copied: hooks/, commands/, CLAUDE.md, statusline-command.sh"

  _afb_hydrate_template "$claude_home" > "${claude_home}/settings.json"
  echo "  Generated: settings.json"
}

_afb_uninstall_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Uninstalling: ${name} (${claude_home})"

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
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

  if [[ -f "${claude_home}/settings.json.original" ]]; then
    cp "${claude_home}/settings.json.original" "${claude_home}/settings.json"
    rm -f "${claude_home}/settings.json.bak"
    echo "  Restored: settings.json from settings.json.original"
  fi
}

_afb_check_account() {
  local name="$1" claude_home="$2"
  echo ""
  echo "Checking: ${name} (${claude_home})"
  local errors=0

  for skill_dir in "${DOT_CLAUDE}/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    skill="$(basename "$skill_dir")"
    _afb_check_symlink "${DOT_CLAUDE}/skills/${skill}" "${claude_home}/skills/${skill}" "skills/${skill}" || errors=$((errors+1))
  done

  _afb_check_symlink "${DOT_CLAUDE}/hooks"                 "${claude_home}/hooks"                 "hooks/"       || errors=$((errors+1))
  _afb_check_symlink "${DOT_CLAUDE}/commands"              "${claude_home}/commands"              "commands/"    || errors=$((errors+1))
  _afb_check_symlink "${DOT_CLAUDE}/CLAUDE.md"             "${claude_home}/CLAUDE.md"             "CLAUDE.md"    || errors=$((errors+1))
  _afb_check_symlink "${DOT_CLAUDE}/statusline-command.sh" "${claude_home}/statusline-command.sh" "statusline-command.sh" || errors=$((errors+1))

  if [[ -f "${claude_home}/settings.json" ]]; then
    _afb_settings_diff_and_merge "$claude_home" "1" "check" || errors=$((errors+1))
  else
    echo "  Warning: settings.json not found"
  fi

  [[ "$errors" -eq 0 ]]
}

# --- PATH symlink for afb itself --------------------------------------------

_afb_install_bin_symlink() {
  local bin_dir
  bin_dir="$(_afb_install_bin_dir)"
  mkdir -p "$bin_dir"
  local dest="${bin_dir}/afb"
  local src="${AFB_ROOT}/afb"
  if [[ -L "$dest" ]]; then
    local current
    current="$(readlink "$dest")"
    if [[ "$current" != "$src" ]]; then
      rm "$dest"
      ln -s "$src" "$dest"
      echo "Updated afb symlink: ${dest}"
    fi
  else
    ln -s "$src" "$dest"
    echo "Installed afb → ${dest}"
  fi
  # Warn if bin_dir not in PATH
  case ":${PATH}:" in
    *":${bin_dir}:"*) ;;
    *)
      echo "Warning: ${bin_dir} is not in PATH." >&2
      echo "Add to ~/.zshrc or ~/.profile:" >&2
      echo "  export PATH=\"\${HOME}/.local/bin:\${PATH}\"" >&2
      ;;
  esac
}

_afb_remove_bin_symlink() {
  local bin_dir
  bin_dir="$(_afb_install_bin_dir)"
  local dest="${bin_dir}/afb"
  if [[ -L "$dest" ]]; then
    rm "$dest"
    echo "Removed afb symlink: ${dest}"
  fi
}

# --- auto-create accounts.json ----------------------------------------------

_afb_autocreate_accounts() {
  local accounts_file
  accounts_file="$(afb_accounts_file)"
  cat > "$accounts_file" <<'EOF'
{ "accounts": [{ "name": "default", "claude_home": "~/.claude", "default": true }] }
EOF
  echo "Created accounts.json with single default account."
}

# --- Main entrypoint --------------------------------------------------------

afb_install_main() {
  local subcommand="$1"; shift
  local force=0 skip_diff=0 copy_mode=0

  for arg in "$@"; do
    case "$arg" in
      --force)     force=1 ;;
      --skip-diff) skip_diff=1 ;;
      --copy)      copy_mode=1 ;;
      --help|-h)
        echo "Usage: afb ${subcommand} [--copy] [--force] [--skip-diff]"
        exit 0
        ;;
      *)
        echo "afb ${subcommand}: unknown option '${arg}'" >&2
        exit 1
        ;;
    esac
  done

  local accounts_file
  accounts_file="$(afb_accounts_file)"

  case "$subcommand" in
    install)
      if [[ ! -f "$accounts_file" ]]; then
        _afb_autocreate_accounts
      fi
      afb_validate_accounts
      local aliases="" default_name=""
      while IFS='|' read -r name claude_home is_default; do
        if [[ "$copy_mode" -eq 1 ]]; then
          _afb_copy_account "$name" "$claude_home"
        else
          _afb_install_account "$name" "$claude_home" "$force" "$skip_diff"
        fi
        local alias_cmd="alias ${name}='CLAUDE_CONFIG_DIR=${claude_home} claude'"
        aliases="${aliases}${alias_cmd}\n"
        if [[ "$is_default" == "1" ]]; then
          default_name="$name"
          aliases="${aliases}alias claude='CLAUDE_CONFIG_DIR=${claude_home} claude'\n"
        fi
      done < <(afb_read_accounts)

      # Generate aliases.sh
      local script_dir="$AFB_ROOT"
      printf "# Auto-generated by afb install — source from ~/.profile or ~/.zshrc\n" > "${script_dir}/aliases.sh"
      printf "# NOTE: these aliases override CLAUDE_CONFIG_DIR if set in interactive shells.\n" >> "${script_dir}/aliases.sh"
      printf "${aliases}" >> "${script_dir}/aliases.sh"
      echo ""
      echo "Generated aliases.sh. To activate:"
      echo ""
      echo "  # Add to ~/.zshrc or ~/.profile (run once):"
      echo "  echo 'source ${script_dir}/aliases.sh' >> ~/.zshrc"
      echo ""
      echo "  # Source in current terminal:"
      echo "  source ${script_dir}/aliases.sh"

      _afb_install_bin_symlink
      echo ""
      echo "Done."
      ;;

    uninstall)
      afb_validate_accounts
      while IFS='|' read -r name claude_home is_default; do
        _afb_uninstall_account "$name" "$claude_home"
      done < <(afb_read_accounts)
      # Remove daemon if installed
      if declare -f afb_daemon_remove >/dev/null 2>&1; then
        afb_daemon_remove 2>/dev/null || true
      fi
      _afb_remove_bin_symlink
      echo ""
      echo "Done."
      ;;

    check)
      afb_validate_accounts
      local check_errors=0
      while IFS='|' read -r name claude_home is_default; do
        _afb_check_account "$name" "$claude_home" || check_errors=$((check_errors+1))
      done < <(afb_read_accounts)
      echo ""
      if [[ "$check_errors" -gt 0 ]]; then
        echo "Check failed: ${check_errors} account(s) diverged." >&2
        exit 1
      fi
      echo "Done."
      ;;
  esac
}
