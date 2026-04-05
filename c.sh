c() {
  # Gather existing tmux sessions
  sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)

  echo ""
  echo "  ── tmux / claude sessions ──────────────────────"

  i=1
  if [ -n "$sessions" ]; then
    while IFS= read -r s; do
      printf "  %2d) [attach] %s\n" "$i" "$s"
      i=$((i + 1))
    done <<EOF
$sessions
EOF
  fi

  new_cwd_idx=$i
  printf "  %2d) [new]    <n> in %s\n" "$i" "$(pwd)"
  i=$((i + 1))

  new_wt_idx=$i
  printf "  %2d) [new]    <n> as claude worktree (claude -w <n>)\n" "$i"
  total=$i

  echo "  ────────────────────────────────────────────────"
  echo ""
  printf "  pick a number: " && read -r choice

  case "$choice" in
    ''|*[!0-9]*)
      echo "  invalid choice, bye."
      return 1
      ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "$total" ]; then
    echo "  invalid choice, bye."
    return 1
  fi

  # Attach to existing session
  if [ "$choice" -lt "$new_cwd_idx" ]; then
    sname=$(echo "$sessions" | sed -n "${choice}p")
    if [ -n "$TMUX" ]; then
      tmux switch-client -t "$sname"
    else
      tmux attach-session -t "$sname"
    fi
    return
  fi

  # New session — ask for a name
  printf "  session name: " && read -r sname
  if [ -z "$sname" ]; then
    echo "  no name given, bye."
    return 1
  fi

  sname=$(echo "$sname" | tr ' ' '-')

  if [ "$choice" -eq "$new_cwd_idx" ]; then
    if [ -n "$TMUX" ]; then
      tmux new-session -d -s "$sname" -c "$(pwd)" \; \
           send-keys -t "$sname" "claude" Enter \; \
           switch-client -t "$sname"
    else
      tmux new-session -s "$sname" -c "$(pwd)" \; \
           send-keys -t "$sname" "claude" Enter
    fi

  elif [ "$choice" -eq "$new_wt_idx" ]; then
    if [ -n "$TMUX" ]; then
      tmux new-session -d -s "$sname" -c "$(pwd)" \; \
           send-keys -t "$sname" "claude -w \"$sname\"" Enter \; \
           switch-client -t "$sname"
    else
      tmux new-session -s "$sname" -c "$(pwd)" \; \
           send-keys -t "$sname" "claude -w \"$sname\"" Enter
    fi
  fi
}
