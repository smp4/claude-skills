#!/usr/bin/env bash
# lib/work.sh — tmux session menu and direct launch

_afb_require_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "Error: tmux is not installed." >&2
    echo "Install with: brew install tmux (macOS) or apt install tmux (Linux)" >&2
    exit 1
  fi
}

# Show interactive menu of existing sessions + create options
afb_work_menu() {
  _afb_require_tmux
  local sessions
  sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null || true)

  echo ""
  echo "  ── tmux / claude sessions ──────────────────────"

  local i=1
  if [[ -n "$sessions" ]]; then
    while IFS= read -r s; do
      printf "  %2d) [attach] %s\n" "$i" "$s"
      i=$((i + 1))
    done <<EOF
$sessions
EOF
  fi

  local new_cwd_idx=$i
  printf "  %2d) [new]    <n> in %s\n" "$i" "$(pwd)"
  i=$((i + 1))

  local new_wt_idx=$i
  printf "  %2d) [new]    <n> as worktree (afb work <n>)\n" "$i"
  local total=$i

  echo "  ────────────────────────────────────────────────"
  echo ""
  printf "  pick a number: "
  local choice
  read -r choice

  case "$choice" in
    ''|*[!0-9]*)
      echo "  invalid choice, bye."
      return 1
      ;;
  esac
  if [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$total" ]]; then
    echo "  invalid choice, bye."
    return 1
  fi

  # Attach to existing session
  if [[ "$choice" -lt "$new_cwd_idx" ]]; then
    local sname
    sname=$(echo "$sessions" | sed -n "${choice}p")
    if [[ -n "${TMUX:-}" ]]; then
      tmux switch-client -t "$sname"
    else
      tmux attach-session -t "$sname"
    fi
    return 0
  fi

  # New session — ask for a name
  printf "  session name: "
  local sname
  read -r sname
  if [[ -z "$sname" ]]; then
    echo "  no name given, bye."
    return 1
  fi

  if [[ "$choice" -eq "$new_cwd_idx" ]]; then
    local slug
    slug="$(afb_slugify "$sname")"
    if [[ -n "${TMUX:-}" ]]; then
      tmux new-session -d -s "$slug" -c "$(pwd)"
      tmux send-keys -t "$slug" "claude" Enter
      tmux switch-client -t "$slug"
    else
      tmux new-session -s "$slug" -c "$(pwd)"
      tmux send-keys -t "$slug" "claude" Enter
    fi
  elif [[ "$choice" -eq "$new_wt_idx" ]]; then
    afb_work_with_name "$sname"
  fi
}

# Direct launch: create worktree+branch, tmux session, launch claude
afb_work_with_name() {
  local name="$1"
  _afb_require_tmux

  local slug
  slug="$(afb_slugify "$name")"

  # Create worktree (via wt.sh)
  source "${AFB_LIB_DIR}/wt.sh"
  afb_wt_create "$name" 2>/dev/null || true  # may already exist

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)")"
  local wt_path="${repo_root}/.claude/worktrees/${slug}"

  if [[ -n "${TMUX:-}" ]]; then
    tmux new-session -d -s "$slug" -c "$wt_path"
    tmux send-keys -t "$slug" "claude" Enter
    tmux switch-client -t "$slug"
  else
    tmux new-session -d -s "$slug" -c "$wt_path"
    tmux send-keys -t "$slug" "claude" Enter
    tmux attach-session -t "$slug"
  fi
}

afb_work_main() {
  if [[ $# -gt 0 ]]; then
    afb_work_with_name "$1"
  else
    afb_work_menu
  fi
}
