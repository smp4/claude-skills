#!/usr/bin/env bash
# Install /new-plan, /new-task, and shared references as personal Claude Code skills.
#
# Usage:
#   ./install.sh              # symlink mode (default) — stays in sync with repo
#   ./install.sh --copy       # copy mode — standalone snapshot, no sync
#   ./install.sh --uninstall  # remove installed skills
#
# Symlink mode (recommended):
#   Creates symlinks from ~/.claude/skills/ → this repo. Any `git pull`
#   in this repo immediately updates your skills. Edits in ~/.claude/skills/
#   are edits to the repo — commit and push directly.
#
# Copy mode:
#   Copies files into ~/.claude/skills/. Use for one-off installs where you
#   don't want to keep the repo around, or when distributing to others.

set -euo pipefail

SKILLS_DIR="${HOME}/.claude/skills"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIRS=("new-plan" "new-task" "shared" "sysmlv2")

MODE="symlink"
if [[ "${1:-}" == "--copy" ]]; then
  MODE="copy"
elif [[ "${1:-}" == "--uninstall" ]]; then
  MODE="uninstall"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--copy | --uninstall]"
  echo ""
  echo "  (no flag)     Symlink mode — skills stay in sync with this repo"
  echo "  --copy        Copy mode — standalone snapshot, no sync"
  echo "  --uninstall   Remove installed skills"
  exit 1
fi

# --- Uninstall -----------------------------------------------------------

if [[ "$MODE" == "uninstall" ]]; then
  echo "Removing Claude Code skills from ${SKILLS_DIR}..."
  for skill in "${SKILL_DIRS[@]}"; do
    target="${SKILLS_DIR}/${skill}"
    if [ -L "$target" ]; then
      rm "$target"
      echo "  ✓ Removed symlink: ${skill}"
    elif [ -d "$target" ]; then
      rm -rf "$target"
      echo "  ✓ Removed directory: ${skill}"
    else
      echo "  · Not installed: ${skill}"
    fi
  done
  echo ""
  echo "Done. Restart Claude Code to apply changes."
  exit 0
fi

# --- Pre-flight checks ----------------------------------------------------

# Verify source files exist
for skill in "${SKILL_DIRS[@]}"; do
  if [ ! -d "${SCRIPT_DIR}/${skill}" ]; then
    echo "Error: Source directory '${skill}' not found in ${SCRIPT_DIR}"
    echo "Are you running this from the repo root?"
    exit 1
  fi
done

# Warn if overwriting existing skills
EXISTING=()
for skill in "${SKILL_DIRS[@]}"; do
  target="${SKILLS_DIR}/${skill}"
  if [ -e "$target" ] || [ -L "$target" ]; then
    EXISTING+=("$skill")
  fi
done

if [ ${#EXISTING[@]} -gt 0 ]; then
  echo "⚠ The following skills already exist and will be replaced:"
  for skill in "${EXISTING[@]}"; do
    target="${SKILLS_DIR}/${skill}"
    if [ -L "$target" ]; then
      echo "  ${skill} (symlink → $(readlink "$target"))"
    else
      echo "  ${skill} (directory)"
    fi
  done
  echo ""
  read -rp "Continue? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# --- Install --------------------------------------------------------------

mkdir -p "$SKILLS_DIR"

echo "Installing Claude Code skills (${MODE} mode)..."
echo ""

for skill in "${SKILL_DIRS[@]}"; do
  src="${SCRIPT_DIR}/${skill}"
  dest="${SKILLS_DIR}/${skill}"

  # Remove existing (symlink or directory)
  if [ -L "$dest" ]; then
    rm "$dest"
  elif [ -d "$dest" ]; then
    rm -rf "$dest"
  fi

  if [[ "$MODE" == "symlink" ]]; then
    ln -s "$src" "$dest"
    echo "  ✓ ${skill} → ${src}"
  else
    cp -r "$src" "$dest"
    echo "  ✓ ${skill} (copied)"
  fi
done

echo ""
echo "Installed skills:"
echo "  /new-plan   — Interview → Spec → Plan → Handoff"
echo "  /new-task   — Worktree → TDD → Verify → PR/Commit"
echo "  shared/     — TDD and verification guides (referenced by both)"
echo ""

if [[ "$MODE" == "symlink" ]]; then
  echo "Sync: Skills are symlinked to this repo."
  echo "  • git pull in this repo updates your skills immediately"
  echo "  • Edits in ~/.claude/skills/ are edits to the repo"
  echo "  • Restart Claude Code after pulling changes"
else
  echo "Note: Skills were copied — they will NOT auto-update."
  echo "  • Re-run ./install.sh --copy to update from the repo"
  echo "  • Or switch to symlink mode: ./install.sh"
fi
echo ""
echo "Restart Claude Code to pick up the new skills."
