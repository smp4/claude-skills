#!/bin/bash

# Read JSON input
input=$(cat)

# Extract values
model=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Get git info (skip optional locks for performance)
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    repo=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    git_info="$repo:$branch"
else
    git_info="no-repo"
fi

# Create progress bar for context usage
if [ -n "$used_pct" ]; then
    used_int=$(printf "%.0f" "$used_pct")
    bar_width=20
    filled=$((used_int * bar_width / 100))
    empty=$((bar_width - filled))
    bar="["
    for ((i=0; i<filled; i++)); do bar+="="; done
    for ((i=0; i<empty; i++)); do bar+=" "; done
    bar+="]"
    context_info="$bar ${used_int}%"
else
    context_info="[====================] 0%"
fi

echo "$model | $git_info | $context_info"
