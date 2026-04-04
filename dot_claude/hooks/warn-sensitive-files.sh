#!/bin/bash

# Read the tool input from stdin (Claude Code passes it as JSON)
INPUT=$(cat)

# Extract the file path from the tool call
FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# tool params are nested under tool_input
params = data.get('tool_input', data)
print(params.get('file_path') or params.get('path') or '')
" 2>/dev/null)

# Normalize path - resolve ~ and relative paths
FILE_PATH=$(eval echo "$FILE_PATH")
FILE_PATH=$(realpath "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")

# Check if it matches sensitive files
CLAUDE_MD=$(realpath ~/.claude/claude.md 2>/dev/null)
SETTINGS=$(realpath ~/.claude/settings.json 2>/dev/null)

if [[ "$FILE_PATH" == "$CLAUDE_MD" ]] || [[ "$FILE_PATH" == "$SETTINGS" ]]; then
  echo "" >&2
  echo "╔══════════════════════════════════════════════════════════╗" >&2
  echo "║  ⚠️  WARNING: CLAUDE IS MODIFYING ITS OWN CONFIG  ⚠️       ║" >&2
  echo "╠══════════════════════════════════════════════════════════╣" >&2
  echo "║  File: $FILE_PATH" >&2
  echo "║                                                          ║" >&2
  echo "║  This could alter Claude's behavior, memory, or          ║" >&2
  echo "║  permissions. Review carefully before proceeding         ║" >&2
  echo "║  and make the changes manually.                          ║" >&2
  echo "╚══════════════════════════════════════════════════════════╝" >&2
  echo "" >&2
  exit 2
fi

exit 0
