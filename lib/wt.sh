#!/usr/bin/env bash
# lib/wt.sh — git worktree+branch lifecycle

_afb_require_git_repo() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: not inside a git repository. wt commands require a git repo." >&2
    exit 1
  fi
}

_afb_git_root() {
  git rev-parse --show-toplevel
}

afb_wt_create() {
  local name="$1"
  _afb_require_git_repo

  local slug
  slug="$(afb_slugify "$name")"
  local repo_root
  repo_root="$(_afb_git_root)"
  local wt_path="${repo_root}/.claude/worktrees/${slug}"
  local branch="feat/${slug}"

  if [[ -d "$wt_path" ]]; then
    echo "Error: worktree '${slug}' already exists at ${wt_path}" >&2
    exit 1
  fi

  # Check if git already knows about this worktree path
  if git worktree list --porcelain | grep -q "^worktree ${wt_path}$"; then
    echo "Error: git already has a worktree at ${wt_path}" >&2
    exit 1
  fi

  mkdir -p "${repo_root}/.claude/worktrees"
  git worktree add "$wt_path" -b "$branch"
  echo "Created worktree: ${wt_path} (branch: ${branch})"
}

afb_wt_list() {
  _afb_require_git_repo
  git worktree list
}

afb_wt_clean() {
  local name="$1" force=0
  shift
  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      *) echo "afb wt clean: unknown option '${arg}'" >&2; exit 1 ;;
    esac
  done

  _afb_require_git_repo

  local slug
  slug="$(afb_slugify "$name")"
  local repo_root
  repo_root="$(_afb_git_root)"
  local wt_path="${repo_root}/.claude/worktrees/${slug}"
  local branch="feat/${slug}"

  if [[ ! -d "$wt_path" ]]; then
    echo "Error: worktree '${slug}' not found at ${wt_path}" >&2
    exit 1
  fi

  # Check for uncommitted changes
  local dirty
  dirty=$(git -C "$wt_path" status --porcelain 2>/dev/null)
  if [[ -n "$dirty" ]] && [[ "$force" -eq 0 ]]; then
    echo "Error: worktree '${slug}' has uncommitted changes." >&2
    echo "Commit or stash changes first, or use --force to override." >&2
    exit 1
  fi

  git worktree remove "$wt_path" ${force:+--force} 2>/dev/null || \
    git worktree remove --force "$wt_path" 2>/dev/null || true
  git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null || true
  echo "Removed worktree: ${wt_path} (branch: ${branch})"
}

afb_wt_main() {
  local subcmd="${1:-}"
  shift || true

  case "$subcmd" in
    create)
      if [[ -z "${1:-}" ]]; then
        echo "Usage: afb wt create <name>" >&2
        exit 1
      fi
      afb_wt_create "$1"
      ;;
    list)
      afb_wt_list
      ;;
    clean)
      if [[ -z "${1:-}" ]]; then
        echo "Usage: afb wt clean <name> [--force]" >&2
        exit 1
      fi
      afb_wt_clean "$@"
      ;;
    ""|--help|-h)
      echo "Usage: afb wt <create|list|clean> [options]"
      exit 0
      ;;
    *)
      echo "afb wt: unknown subcommand '${subcmd}'" >&2
      exit 1
      ;;
  esac
}
