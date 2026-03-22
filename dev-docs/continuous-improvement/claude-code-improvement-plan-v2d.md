# Claude Code Continuous Improvement Plan v2.1

*Updated from v2 with session continuity system (ledgers, handoffs, context
tracking — cherry-picked from Continuous-Claude-v3 architecture) and keyword-
based skill activation hooks. Scoped to: git-based skill management, JSON
telemetry, Claude Code hooks, promptfoo community edition, human-in-the-loop.
No daemons, no databases, no external services.*

---

## Design principles (carried forward from v1, refined)

1. **Event-driven, not vigilance-driven.** Hooks and structural triggers, never
   "always watch for X."
2. **Telemetry over prose.** JSON is the source of truth. CLAUDE.md gets
   specific instructions, not reflections.
3. **Human as meta-learning layer is the design, not a limitation.** The system
   surfaces data and proposes changes; the human approves.
4. **Separate improvement from execution.** Never self-improve during active
   task work.
5. **Specialized over generic.** Each skill reduces the model's decision space
   for one capability.
6. **Generate skills after solving, never before.** (New — from Goedecke's
   finding that post-task skills outperform pre-task ones.)
7. **Tools earn their context budget or get pruned.** (New — every skill has a
   measurable cost and must justify it.)
8. **All skill changes go through git.** Branch, PR, review. Skills are code.
9. **Compound, don't compact.** (New — from CC-v3.) When context fills up,
   extract state to local files before compaction. Fresh sessions start with
   full knowledge of where things stand, not a lossy summary.

---

## Architecture overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          ACTIVE SESSION                                 │
│                                                                         │
│  /new-plan, /new-task, or ad-hoc Claude Code work                      │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │ HOOKS (fire automatically, no model involvement)                  │  │
│  │                                                                   │  │
│  │ SessionStart    →  load latest ledger + handoff into context      │  │
│  │                 →  rebuild continuity state                       │  │
│  │                                                                   │  │
│  │ UserPromptSubmit → scan message against skill-rules.json          │  │
│  │                  → inject matching skill names into context       │  │
│  │                                                                   │  │
│  │ PreToolUse      →  read tool-stats.json                           │  │
│  │                 →  inject warning if tool is degraded              │  │
│  │                 →  hard-block (exit 2) if tool is unreliable      │  │
│  │                                                                   │  │
│  │ PostToolUse     →  log tool outcome to session JSONL              │  │
│  │                 →  update tool-stats.json (rolling counts)        │  │
│  │                                                                   │  │
│  │ PreCompact      →  auto-generate handoff YAML before compaction   │  │
│  │                 →  save to thoughts/handoffs/                     │  │
│  │                                                                   │  │
│  │ Stop            →  update continuity ledger                       │  │
│  │                 →  remind user: /session-review                   │  │
│  │                                                                   │  │
│  │ StatusLine      →  show context % + git branch + current focus    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──────────────┬──────────────────────────────────────────────────────────┘
               │
               │  session JSONL written by hooks (not by the model)
               │  handoffs + ledgers written by hooks (not by the model)
               ▼
┌──────────────────────────────────────────────────────────────────────┐
│  LOCAL STATE (all files, no database, no daemon)                     │
│                                                                      │
│  .claude/telemetry/                                                  │
│  ├── session-2026-03-09.jsonl    (per-event, append-only)           │
│  ├── skill-activations.jsonl     (per-activation, append-only)      │
│  ├── aggregate.json              (cumulative stats)                  │
│  ├── tool-stats.json             (rolling tool reliability)          │
│  └── skill-health.json           (per-skill health metrics)         │
│                                                                      │
│  thoughts/                                                           │
│  ├── ledgers/                                                        │
│  │   └── CONTINUITY_CLAUDE-<session>.md   (current session state)   │
│  └── handoffs/                                                       │
│      └── <session>/                                                  │
│          └── handoff-<timestamp>.yaml     (compaction/session-end)   │
│                                                                      │
│  .claude/skill-rules.json        (keyword → skill activation map)   │
└──────────────┬───────────────────────────────────────────────────────┘
               │
       ┌───────┴───────────────────────────┐
       │                                   │
       ▼                                   ▼
┌──────────────────────┐    ┌─────────────────────────────────┐
│  /session-review     │    │  /retrospective                 │
│  (every session end) │    │  (after solving something new)  │
│                      │    │                                 │
│  Reads telemetry,    │    │  Extracts reusable knowledge    │
│  updates aggregate,  │    │  from current session into a    │
│  outputs 3-5 line    │    │  draft skill. Human reviews.    │
│  human summary.      │    │  Branch → commit → PR.          │
└──────────┬───────────┘    └──────────┬──────────────────────┘
           │                           │
           │  human decides            │  human reviews PR
           │  (weekly / as-needed)     │
           ▼                           │
┌──────────────────────────────┐       │
│  /improve                    │       │
│  (diagnose + hypothesize)    │       │
│                              │       │
│  1. Analyze telemetry FIRST  │       │
│  2. Generate fresh hypotheses│       │
│  3. THEN read improvements.md│       │
│  4. Reconcile + update file  │       │
│  5. Human approves updates   │       │
└──────────┬───────────────────┘       │
           │                           │
           │  writes improvements.md   │
           │  (git-tracked in skills   │
           │   repo, never loaded      │
           │   during active work)     │
           ▼                           │
┌──────────────────────────────┐       │
│  /build-improvement          │       │
│  (execute ONE approved       │       │
│   proposal per session)      │◀──────┘
│                              │
│  1. Read improvements.md     │
│  2. Pick one approved entry  │
│  3. Implement on branch      │
│  4. Run promptfoo tests      │
│  5. Update entry → built     │
│  6. Open PR                  │
└──────────────────────────────┘
               │
               │  skill changes merged via PR
               ▼
┌──────────────────────────────────────────┐
│  promptfoo CI (on PR / on schedule)      │
│                                          │
│  Runs regression tests for changed       │
│  skills. Fails PR if scores drop.        │
│  Tracks cost-per-skill over time.        │
└──────────────────────────────────────────┘
```

---

## Layer 0: Session continuity (ledgers, handoffs, context tracking)

This layer solves a problem the v2 plan completely ignored: what happens when
context compacts mid-session, or between sessions? Without continuity, every
compaction or new session starts from a lossy summary. The model forgets what
files it was editing, which decisions were made, and what's next. This is the
single highest-value addition from the CC-v3 architecture, and it requires
zero external infrastructure — just hooks and local markdown/YAML files.

### 0a. Continuity ledger

**File:** `thoughts/ledgers/CONTINUITY_CLAUDE-<session>.md`

A running record of the current session's state, updated by the model at
natural breakpoints (phase transitions in `/new-task`, after completing a
subtask, before a known-complex operation). Contains:

```markdown
# Session: <session-id>
## Goal
<what we're trying to accomplish>

## Constraints
<requirements, user preferences, things to avoid>

## Done
- <completed items with file:line references>

## Now
<what's currently in progress>

## Next
- <upcoming items in priority order>

## Key Decisions
- <architectural choices, trade-offs made, with reasoning>

## Working Files
- <files currently being modified, with their role>
```

**How it's maintained:** The model writes/updates this file during work. This
is one of the rare cases where asking the model to do something during active
work is justified — updating a ledger is a 10-second write that directly
serves the current task (by crystallizing intent), not a background
self-improvement activity that competes with the task.

**Where it lives:** `thoughts/` directory at project root, gitignored. These
are ephemeral working state, not permanent artifacts.

### 0b. Handoff YAML (automatic, hook-driven)

**File:** `thoughts/handoffs/<session>/handoff-<timestamp>.yaml`

Generated automatically by the PreCompact hook when context is about to
compact, and by the Stop hook when a session ends. The human never needs to
remember to create these.

```yaml
# Auto-generated by PreCompact/Stop hook
session_id: abc123
timestamp: "2026-03-09T18:45:00Z"
trigger: pre_compact  # or: session_end

goal: "Implement Stripe webhook handler with idempotency"

completed:
  - "Created src/webhooks/stripe.ts with event routing"
  - "Added tests for payment_intent.succeeded event"
  - "Configured webhook secret via env var"

in_progress:
  - "Implementing idempotency key deduplication (src/webhooks/idempotency.ts)"

next:
  - "Add retry logic for failed webhook processing"
  - "Integration test with Stripe CLI mock"

decisions:
  - "Using database-backed idempotency instead of Redis — simpler for current scale"
  - "Event routing via switch statement, not map — only 4 event types"

files_modified:
  - path: "src/webhooks/stripe.ts"
    status: "in progress"
    note: "Event routing complete, idempotency TODO"
  - path: "src/webhooks/__tests__/stripe.test.ts"
    status: "partial"
    note: "3/5 test cases written"

learnings:
  - "Stripe sends events with 5-second timeout — handler must respond fast"
  - "webhook signature verification requires raw body, not parsed JSON"
```

### 0c. PreCompact hook — automatic handoff before compaction

**File:** `.claude/hooks/pre-compact.sh`

Fires when Claude Code is about to compact context. This is the critical
safety net — it captures state *before* context is lost.

```bash
#!/usr/bin/env bash
# .claude/hooks/pre-compact.sh
#
# Fires before context compaction. Reads the current continuity ledger
# and generates a structured handoff YAML.

set -euo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%s)}"
HANDOFF_DIR="thoughts/handoffs/${SESSION_ID}"
mkdir -p "$HANDOFF_DIR"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HANDOFF_FILE="${HANDOFF_DIR}/handoff-${TIMESTAMP}.yaml"
LEDGER=$(find thoughts/ledgers/ -name "CONTINUITY_CLAUDE-*" -type f 2>/dev/null \
         | sort -r | head -1)

if [ -z "$LEDGER" ] || [ ! -f "$LEDGER" ]; then
  # No ledger exists — create minimal handoff from git state
  cat > "$HANDOFF_FILE" <<EOF
session_id: "${SESSION_ID}"
timestamp: "${TIMESTAMP}"
trigger: pre_compact
goal: "unknown — no continuity ledger found"
files_modified:
$(git diff --name-only HEAD 2>/dev/null | sed 's/^/  - path: "/' | sed 's/$/"/' || echo "  []")
note: "Auto-generated from git diff. No ledger was maintained this session."
EOF
  echo "⚠ No continuity ledger found. Minimal handoff saved to ${HANDOFF_FILE}" >&2
  exit 0
fi

# Convert markdown ledger to YAML handoff
# The model will have maintained the ledger; we just reformat it
cat > "$HANDOFF_FILE" <<EOF
session_id: "${SESSION_ID}"
timestamp: "${TIMESTAMP}"
trigger: pre_compact
source_ledger: "${LEDGER}"
EOF

# Append the ledger content as a YAML block scalar
echo "ledger_content: |" >> "$HANDOFF_FILE"
sed 's/^/  /' "$LEDGER" >> "$HANDOFF_FILE"

# Append git state for cross-reference
echo "git_state:" >> "$HANDOFF_FILE"
echo "  branch: $(git branch --show-current 2>/dev/null || echo 'unknown')" >> "$HANDOFF_FILE"
echo "  uncommitted_files:" >> "$HANDOFF_FILE"
git diff --name-only HEAD 2>/dev/null | sed 's/^/    - /' >> "$HANDOFF_FILE" || true

echo "✓ Handoff saved: ${HANDOFF_FILE}" >&2
exit 0
```

**Why YAML not markdown:** Handoffs are structured data that the SessionStart
hook needs to parse and inject. YAML is more reliably parseable than markdown
while still being human-readable.

### 0d. SessionStart hook — restore continuity after compaction or new session

**File:** `.claude/hooks/session-start.sh`

Fires on session start, after `/clear`, and after compaction. Finds the latest
handoff and ledger and injects them into context.

```bash
#!/usr/bin/env bash
# .claude/hooks/session-start.sh
#
# Restores continuity state by injecting the latest handoff + ledger
# into the conversation context.

set -euo pipefail

# Find latest handoff across all sessions
LATEST_HANDOFF=$(find thoughts/handoffs/ -name "handoff-*.yaml" -type f 2>/dev/null \
                 | sort -r | head -1)

# Find latest ledger
LATEST_LEDGER=$(find thoughts/ledgers/ -name "CONTINUITY_CLAUDE-*" -type f 2>/dev/null \
                | sort -r | head -1)

OUTPUT=""

if [ -n "$LATEST_HANDOFF" ] && [ -f "$LATEST_HANDOFF" ]; then
  OUTPUT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 CONTINUITY: Last handoff
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(cat "$LATEST_HANDOFF")
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"
fi

if [ -n "$LATEST_LEDGER" ] && [ -f "$LATEST_LEDGER" ]; then
  OUTPUT+="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 CONTINUITY: Current ledger
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$(cat "$LATEST_LEDGER")
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"
fi

if [ -n "$OUTPUT" ]; then
  echo "$OUTPUT"
fi

exit 0
```

### 0e. Stop hook — create handoff + remind for /session-review

**File:** `.claude/hooks/stop.sh`

Fires when a session ends. Creates a final handoff (same logic as PreCompact)
and reminds the user about `/session-review`.

```bash
#!/usr/bin/env bash
# .claude/hooks/stop.sh

set -euo pipefail

# Reuse pre-compact logic to create final handoff
# (set trigger to session_end instead of pre_compact)
SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%s)}"
HANDOFF_DIR="thoughts/handoffs/${SESSION_ID}"
mkdir -p "$HANDOFF_DIR"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
HANDOFF_FILE="${HANDOFF_DIR}/handoff-${TIMESTAMP}.yaml"
LEDGER=$(find thoughts/ledgers/ -name "CONTINUITY_CLAUDE-*" -type f 2>/dev/null \
         | sort -r | head -1)

if [ -n "$LEDGER" ] && [ -f "$LEDGER" ]; then
  cat > "$HANDOFF_FILE" <<EOF
session_id: "${SESSION_ID}"
timestamp: "${TIMESTAMP}"
trigger: session_end
source_ledger: "${LEDGER}"
EOF
  echo "ledger_content: |" >> "$HANDOFF_FILE"
  sed 's/^/  /' "$LEDGER" >> "$HANDOFF_FILE"
  echo "git_state:" >> "$HANDOFF_FILE"
  echo "  branch: $(git branch --show-current 2>/dev/null || echo 'unknown')" >> "$HANDOFF_FILE"
  echo "  uncommitted_files:" >> "$HANDOFF_FILE"
  git diff --name-only HEAD 2>/dev/null | sed 's/^/    - /' >> "$HANDOFF_FILE" || true
fi

echo "" >&2
echo "✓ Session handoff saved." >&2
echo "💡 Run /session-review to log telemetry and check for extractable skills." >&2
exit 0
```

### 0f. StatusLine hook — context usage visibility

**File:** `.claude/hooks/status-line.sh`

Shows context usage, git branch, and current focus at a glance. Color-coded
to warn when compaction is approaching.

```bash
#!/usr/bin/env bash
# .claude/hooks/status-line.sh
#
# Outputs a single-line status for Claude Code's status bar.
# Format: <context%> | <branch> <git-status> | <current-focus>

set -euo pipefail

# Git info
BRANCH=$(git branch --show-current 2>/dev/null || echo "?")
UNSTAGED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
STAGED=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
GIT_STATUS=""
[ "$STAGED" -gt 0 ] && GIT_STATUS+="S:${STAGED} "
[ "$UNSTAGED" -gt 0 ] && GIT_STATUS+="U:${UNSTAGED}"

# Current focus from ledger (extract "## Now" section)
LEDGER=$(find thoughts/ledgers/ -name "CONTINUITY_CLAUDE-*" -type f 2>/dev/null \
         | sort -r | head -1)
FOCUS=""
if [ -n "$LEDGER" ] && [ -f "$LEDGER" ]; then
  FOCUS=$(awk '/^## Now/{getline; if (/^[^#]/) print; exit}' "$LEDGER" 2>/dev/null \
          | head -c 60 | tr -d '\n')
fi

echo "${BRANCH} ${GIT_STATUS}| ${FOCUS:-no ledger}"
```

### 0g. UserPromptSubmit hook — skill activation by keyword

**File:** `.claude/hooks/user-prompt-submit.sh`

Fires on every user message. Scans the message against a keyword map
(`skill-rules.json`) and injects matching skill names into context so the
model knows which skills are relevant before it starts responding.

```bash
#!/usr/bin/env bash
# .claude/hooks/user-prompt-submit.sh
#
# Keyword-based skill activation. Reads the user's message (from stdin),
# matches against skill-rules.json, and outputs activation hints.

set -euo pipefail

RULES_FILE=".claude/skill-rules.json"
[ ! -f "$RULES_FILE" ] && exit 0

# Read the user message from hook stdin
INPUT=$(cat)
MESSAGE=$(echo "$INPUT" | jq -r '.message // ""' | tr '[:upper:]' '[:lower:]')

[ -z "$MESSAGE" ] && exit 0

# Match keywords and collect skill names
MATCHED_SKILLS=$(jq -r --arg msg "$MESSAGE" '
  to_entries[]
  | select(
      .value.keywords
      | any(. as $kw | $msg | test($kw; "i"))
    )
  | .key
' "$RULES_FILE" 2>/dev/null)

if [ -n "$MATCHED_SKILLS" ]; then
  # Log activation for skill health tracking
  TELEMETRY_DIR=".claude/telemetry"
  mkdir -p "$TELEMETRY_DIR"
  ACTIVATION_FILE="$TELEMETRY_DIR/skill-activations.jsonl"
  SKILLS_JSON=$(echo "$MATCHED_SKILLS" | jq -R -s 'split("\n") | map(select(. != ""))')
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson skills "$SKILLS_JSON" \
    '{ts: $ts, skills_suggested: $skills}' \
    >> "$ACTIVATION_FILE"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🎯 SKILL ACTIVATION"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$MATCHED_SKILLS" | while read -r skill; do
    DESC=$(jq -r --arg s "$skill" '.[$s].description // ""' "$RULES_FILE")
    echo "  → $skill: $DESC"
  done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit 0
```

**skill-rules.json format:**

```jsonc
// .claude/skill-rules.json
{
  "new-plan": {
    "keywords": ["new plan", "plan a feature", "design something", "start a new project", "let's design"],
    "description": "Interview → Spec → Plan → Handoff"
  },
  "new-task": {
    "keywords": ["new task", "pick up the plan", "implement unit", "start work on", "execute the plan"],
    "description": "Worktree → TDD → Verify → PR/Commit"
  },
  "session-review": {
    "keywords": ["session review", "end of session", "wrap up", "what happened this session"],
    "description": "Aggregate telemetry, summarise session"
  },
  "retrospective": {
    "keywords": ["retrospective", "extract skill", "save what we learned", "capture this pattern"],
    "description": "Extract reusable skill from current session"
  },
  "improve": {
    "keywords": ["improve", "what should we fix", "improvement session", "analyze telemetry", "diagnose"],
    "description": "Diagnose patterns in telemetry, update improvements.md"
  },
  "build-improvement": {
    "keywords": ["build improvement", "implement improvement", "pick up improvement", "IMP-"],
    "description": "Execute one approved improvement from improvements.md"
  }
}
```

**Why keyword matching instead of relying on the model:**

The CC-v3 community found that keyword-based activation gets ~84% activation
rate for relevant skills vs ~20% when relying purely on the model reading
skill descriptions from CLAUDE.md. The hook fires before the model responds,
injecting context that makes the model far more likely to load the right skill.
It's not perfect — keyword matching is crude — but it's a massive improvement
over hoping the model reads skill descriptions in a long CLAUDE.md.

**Maintenance:** When `/retrospective` creates a new skill, it also adds an
entry to `skill-rules.json` as part of the PR. When `/improve` prunes a skill,
it removes the corresponding entry. The rules file stays in sync with the
skill library through the same git workflow.

### 0h. What this layer replaces

The v2 plan had a `Notification` hook that reminded the user to run
`/session-review` at session end. That's now handled by the `Stop` hook,
which also creates a handoff. The v2 plan had no continuity story at all —
sessions were treated as independent units where only telemetry carried
forward. This was a significant gap: the model would lose all context about
what it was doing after a compaction, forcing the human to re-explain.

The v2 plan's decision log listed "Skill activation hooks" as rejected because
"the model's judgment about when to load a skill is usually fine." Based on
the CC-v3 community data showing 84% vs 20% activation rates, this was wrong.
Keyword matching is crude but the improvement is too large to ignore.

---

## Layer 1: Hook-based telemetry and tool gating

This is the foundation everything else depends on. Hooks run outside the model's
context — they fire automatically on tool events, so there's no "model forgot
to log" failure mode.

### 1a. PostToolUse hook — event logging

**File:** `.claude/hooks/post-tool-use.sh`

Fires after every tool call. Captures outcome at two granularity levels:
the Claude Code tool type (`Bash`, `Read`, `Write`, `Edit`, `Grep`, etc.)
and, for Bash calls, the specific CLI tool invoked (`npm`, `git`, `docker`,
`curl`, etc.). Both levels are logged and tracked.

**Scope — what counts as a "tool" in this system:**

| Category | Examples | How it's captured |
|---|---|---|
| Claude Code built-in tools | `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `WebFetch` | Directly from hook `tool_name` field |
| CLI tools invoked via Bash | `npm`, `git`, `docker`, `curl`, `make`, `python` | Extracted from Bash command input → logged as `bash:<cmd>` |
| MCP server tools | Any tools from connected MCP servers | Via hook `tool_name` (typically `mcp_<server>_<tool>`) |
| Subagent tool calls | Tools used by spawned subagents | NOT captured by parent hooks — each subagent has its own context. Future: SubagentStop hook could aggregate. |
| Skill activation | Which skills are suggested/loaded | Separate stream: `skill-activations.jsonl` (Layer 0g), NOT tool-stats |

```bash
#!/usr/bin/env bash
# .claude/hooks/post-tool-use.sh
#
# Receives JSON on stdin with: tool_name, input, output, exit_code, duration_ms
# Writes to two files:
#   1. Session JSONL  — per-event log for /session-review
#   2. tool-stats.json — rolling reliability stats for PreToolUse gating
#
# For Bash tool calls, extracts the specific CLI command to enable
# per-command reliability tracking (e.g. bash:npm, bash:git, bash:docker).

set -euo pipefail

TELEMETRY_DIR=".claude/telemetry"
mkdir -p "$TELEMETRY_DIR"

SESSION_FILE="$TELEMETRY_DIR/session-$(date +%Y-%m-%d).jsonl"
STATS_FILE="$TELEMETRY_DIR/tool-stats.json"

# Read hook input
INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
EXIT_CODE=$(echo "$INPUT" | jq -r '.exit_code // 0')
DURATION=$(echo "$INPUT" | jq -r '.duration_ms // 0')
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- CLI tool extraction for Bash calls ---
# "Bash" is an envelope, not a tool. Extract the actual command.
CLI_TOOL=""
if [ "$TOOL" = "Bash" ]; then
  # Extract command from hook input. Handle pipes, env vars, cd prefixes.
  RAW_CMD=$(echo "$INPUT" | jq -r '.input.command // ""')
  # Strip leading env vars (FOO=bar cmd ...), cd prefixes, sudo, etc.
  # Then take the first real command word and basename it.
  CLI_TOOL=$(echo "$RAW_CMD" \
    | sed 's/^[[:space:]]*//' \
    | sed 's/^cd [^;&|]*//' \
    | sed 's/^sudo[[:space:]]*//' \
    | sed 's/^[A-Z_]*=[^ ]* *//' \
    | awk '{print $1}' \
    | xargs basename 2>/dev/null || true)
fi

# Build the tool key for stats tracking.
# Log both the envelope (Bash) and the specific CLI tool (bash:npm).
TOOL_KEY="$TOOL"
if [ -n "$CLI_TOOL" ]; then
  TOOL_KEY="bash:${CLI_TOOL}"
fi

# Classify outcome
if [ "$EXIT_CODE" -eq 0 ]; then
  OUTCOME="pass"
else
  OUTCOME="fail"
fi

# 1. Append to session JSONL — includes both envelope and CLI tool
jq -nc \
  --arg ts "$TS" \
  --arg tool "$TOOL" \
  --arg tool_key "$TOOL_KEY" \
  --arg outcome "$OUTCOME" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson duration "$DURATION" \
  '{ts: $ts, tool: $tool, tool_key: $tool_key, outcome: $outcome, exit_code: $exit_code, duration_ms: $duration}' \
  >> "$SESSION_FILE"

# 2. Update rolling tool stats for BOTH the envelope and the CLI tool.
#    This means tool-stats.json tracks "Bash" (aggregate) AND "bash:npm"
#    (specific). PreToolUse can warn on either level.
if [ ! -f "$STATS_FILE" ]; then
  echo '{}' > "$STATS_FILE"
fi

update_stats() {
  local key="$1"
  jq --arg tool "$key" \
     --arg outcome "$OUTCOME" \
     --argjson duration "$DURATION" \
     '
     .[$tool] //= {total: 0, pass: 0, fail: 0, total_ms: 0, last_used: "", tier: "healthy"} |
     .[$tool].total += 1 |
     .[$tool][$outcome] += 1 |
     .[$tool].total_ms += $duration |
     .[$tool].last_used = (now | todate) |
     .[$tool].success_rate = (.[$tool].pass / .[$tool].total) |
     .[$tool].tier = (
       if .[$tool].total < 5 then "new"
       elif .[$tool].success_rate >= 0.80 then "healthy"
       elif .[$tool].success_rate >= 0.50 then "degraded"
       elif .[$tool].success_rate >= 0.20 then "unreliable"
       else "deprecated"
       end
     )
     ' "$STATS_FILE" > "${STATS_FILE}.tmp" && mv "${STATS_FILE}.tmp" "$STATS_FILE"
}

# Always update the envelope tool (Bash, Read, Write, etc.)
update_stats "$TOOL"

# If we extracted a CLI tool, also track it specifically
if [ -n "$CLI_TOOL" ] && [ "$TOOL_KEY" != "$TOOL" ]; then
  update_stats "$TOOL_KEY"
fi
```

**What this produces in tool-stats.json:**

```jsonc
{
  "Bash": {
    "total": 142, "pass": 119, "fail": 23,
    "success_rate": 0.838, "tier": "healthy"
  },
  "bash:npm": {
    "total": 34, "pass": 24, "fail": 10,
    "success_rate": 0.706, "tier": "degraded"
  },
  "bash:git": {
    "total": 28, "pass": 27, "fail": 1,
    "success_rate": 0.964, "tier": "healthy"
  },
  "bash:docker": {
    "total": 12, "pass": 5, "fail": 7,
    "success_rate": 0.417, "tier": "unreliable"
  },
  "Read": {
    "total": 89, "pass": 88, "fail": 1,
    "success_rate": 0.989, "tier": "healthy"
  }
}
```

Now `/improve` can say "your `docker` commands fail 58% of the time — mostly
`docker compose up` timeouts" instead of "Bash has 84% success rate."

**Notes:**
- Dual-level tracking: both the envelope (`Bash`) and the specific CLI tool
  (`bash:npm`) are tracked. The aggregate `Bash` entry shows overall command
  reliability; the specific entries show where the problems are.
- The 5-call minimum before tiering prevents premature classification.
- Tiers: `new` (<5 calls), `healthy` (≥80%), `degraded` (50–80%),
  `unreliable` (20–50%), `deprecated` (<20%).
- CLI extraction handles common prefixes: env vars (`FOO=bar npm test`),
  `sudo`, `cd` prefixes, and takes the basename to normalize paths.
- MCP tools surface with their own `tool_name` (e.g. `mcp_github_create_pr`)
  and are tracked like any other tool — no special handling needed.
- All data stays local in `.claude/telemetry/`. Nothing leaves your machine.
- Session JSONLs are append-only and cheap to grep.

### 1b. PreToolUse hook — reliability gating

**File:** `.claude/hooks/pre-tool-use.sh`

Fires before each tool call. Reads tool-stats.json and checks both the
envelope tool (e.g. `Bash`) and, for Bash calls, the specific CLI tool
(e.g. `bash:docker`). The most specific match takes precedence — if `Bash`
is healthy but `bash:docker` is unreliable, the docker call gets blocked.

```bash
#!/usr/bin/env bash
# .claude/hooks/pre-tool-use.sh
#
# Checks tool reliability at two levels:
#   1. Specific CLI tool (bash:<cmd>) — takes precedence
#   2. Envelope tool (Bash, Read, Write, etc.) — fallback

set -euo pipefail

STATS_FILE=".claude/telemetry/tool-stats.json"
[ ! -f "$STATS_FILE" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')

# For Bash calls, extract the CLI tool to check specific stats
CLI_KEY=""
if [ "$TOOL" = "Bash" ]; then
  RAW_CMD=$(echo "$INPUT" | jq -r '.input.command // ""')
  CLI_TOOL=$(echo "$RAW_CMD" \
    | sed 's/^[[:space:]]*//' \
    | sed 's/^cd [^;&|]*//' \
    | sed 's/^sudo[[:space:]]*//' \
    | sed 's/^[A-Z_]*=[^ ]* *//' \
    | awk '{print $1}' \
    | xargs basename 2>/dev/null || true)
  [ -n "$CLI_TOOL" ] && CLI_KEY="bash:${CLI_TOOL}"
fi

# Check the most specific key first, fall back to envelope
check_tier() {
  local key="$1"
  local tier=$(jq -r --arg t "$key" '.[$t].tier // "new"' "$STATS_FILE")
  local rate=$(jq -r --arg t "$key" '.[$t].success_rate // 1' "$STATS_FILE")

  case "$tier" in
    degraded)
      echo "⚠ WARNING: ${key} has ${rate} success rate (degraded). Consider alternatives." >&2
      return 1  # signal: warned
      ;;
    unreliable)
      echo "⛔ BLOCKED: ${key} has ${rate} success rate (unreliable). Check tool-stats.json." >&2
      return 2  # signal: block
      ;;
    deprecated)
      echo "⛔ BLOCKED: ${key} has ${rate} success rate (deprecated). This tool should be removed." >&2
      return 2
      ;;
    *)
      return 0  # healthy or new
      ;;
  esac
}

# Check CLI-specific stats first (most actionable)
if [ -n "$CLI_KEY" ]; then
  check_tier "$CLI_KEY"
  result=$?
  [ "$result" -eq 2 ] && exit 2  # hard block
  [ "$result" -eq 1 ] && exit 0  # warned, allow to proceed
fi

# Fall back to envelope check
check_tier "$TOOL"
result=$?
[ "$result" -eq 2 ] && exit 2

exit 0
```

**What this enables:**

The model gets messages like:
- `⚠ WARNING: bash:npm has 0.71 success rate (degraded). Consider alternatives.`
- `⛔ BLOCKED: bash:docker has 0.42 success rate (unreliable). Check tool-stats.json.`

These are far more actionable than "Bash is degraded." The model can reason
about specific CLI tools and choose alternatives (e.g. `npx vitest` instead
of `npm test`, or `docker compose` instead of `docker-compose`).

**Why exit 2:** Claude Code treats exit code 2 from a PreToolUse hook as a hard
block — the tool call is cancelled and the model receives the stderr message as
feedback. This is the mechanism for teaching the agent to distrust unreliable
tools without requiring vigilance.

### 1c. What this replaces from v1

The v1 plan had "Option A: Explicit logging in skill instructions" as the
starting recommendation, with hooks as a future migration. Based on the research
finding that hook-forced activation has ~84% vs ~20% reliability compared to
in-skill instructions, **hooks are the starting point, not the future state.**
The model never needs to remember to log anything — the hooks do it
unconditionally.

### 1d. Privacy note (CC-v3: cherry-picked, not wholesale)

This plan cherry-picks CC-v3's continuity system (Layer 0: ledgers, handoffs,
SessionStart/PreCompact/Stop hooks, status line) and its skill activation hook
pattern (UserPromptSubmit + skill-rules.json). These components are purely
local — they read/write markdown, YAML, and JSON files on disk, never access
conversation content beyond the structured hook input, and make zero network
calls.

What we deliberately exclude from CC-v3:

- **Memory daemon** (PostgreSQL + pgvector): Spawns headless Sonnet API calls
  to analyze thinking blocks at session end. Even with a local database, the
  extraction process makes API calls carrying conversation-derived content.
  Our `/session-review` skill achieves similar outcomes (structured learnings
  from sessions) without a daemon or database — the human runs it explicitly,
  and it reads telemetry, not thinking blocks.
- **TLDR code analysis daemon**: Useful for large codebases but adds a
  background process and FAISS index. Tangential to self-improvement.
  Reconsider if codebase exceeds ~100k LOC and token costs for file reads
  become a bottleneck.
- **109 skills + 32 agents library**: Would conflict with custom skills
  (`/new-plan`, `/new-task`). The activation pattern is adopted; the content
  is not.
- **Braintrust integration**: Cloud-based tracing. Privacy-incompatible.

---

## Layer 2: Skills (the things that improve)

### 2a. `/session-review` — Structured post-session summary

**Trigger:** Human runs `/session-review` at session end (or a
`Notification` hook reminds them).

**Retained from v1:**
- Reads session JSONL + aggregate.json
- Updates aggregate.json with cumulative stats
- Outputs 3–5 line human summary (not reflective prose)

**New in v2 — tool reliability summary:**
- Also reads tool-stats.json
- Flags any tools that changed tier since last session
- Flags any tool with >3 failures this session

**New in v2 — skill extraction prompt:**

At the end of the review, one question:

> "Did this session involve discovering an API, workflow, or niche tool
> interface that wasn't already captured in a skill? [yes/no]"

If yes → tell the user to run `/retrospective` (don't auto-run it; keep
improvement separate from review).

### 2b. `/retrospective` — Post-session skill extraction (NEW)

This is the highest-leverage new addition. Based on the Goedecke finding that
skills generated *after* solving a problem outperform pre-task skills, and
Sionic AI's production-validated workflow.

**Trigger:** Human runs `/retrospective` after a session where something novel
was learned (API discovered, niche workflow figured out, repeated manual
process identified).

**What it does:**

1. **Reads the current session** (conversation history in context).
2. **Identifies extractable knowledge.** Asks: "What did this session discover
   that would be useful if encountered again?" Categories:
   - API interface patterns (auth, pagination, error codes, gotchas)
   - Tool usage patterns (flags, common pitfalls, working invocations)
   - Workflow sequences (multi-step processes that worked)
   - Domain knowledge (project-specific conventions, architecture decisions)
3. **Drafts a skill file** in standard format:
   - YAML frontmatter (name, description, trigger conditions)
   - "When to use" section (positive triggers)
   - "When NOT to use" section (negative triggers — from the Gorilla finding
     that irrelevance detection is critical)
   - "Known failure modes" section (from the Tools Fail paper — document
     failures alongside usage)
   - Procedure / reference content
   - Max 3,000 tokens (enforce the context budget rule)
4. **Presents the draft to the human** for review and editing.
5. **On approval:** Creates a git branch, commits the skill file, opens a PR.
   Also creates a skeleton promptfoo test file alongside the skill (see Layer 4).

**What it does NOT do:**
- Run automatically (human decides when extraction is worthwhile)
- Extract during active work (this is a post-session activity)
- Create skills speculatively ("might be useful someday" = no)
- Generate more than one skill per retrospective (reduce scope creep)

**Git workflow:**

```bash
# /retrospective creates:
git checkout -b skill/stripe-pagination
# writes ~/.claude/skills/stripe-pagination/SKILL.md
# writes ~/.claude/skills/stripe-pagination/tests/eval.yaml (promptfoo skeleton)
git add .
git commit -m "skill(stripe-pagination): extract from session 2026-03-09

Source: manual retrospective after Stripe integration work.
Covers: cursor-based pagination, error handling for rate limits,
idempotency key patterns.
Token budget: ~1,800 tokens."
# opens PR (or prompts user to push and open PR)
```

### 2c. `/improve` — Diagnose and hypothesize (analysis only)

This skill answers: "What should we improve?" It does NOT implement anything.

**Trigger:** Human runs `/improve` (weekly, or when session reviews flag
something interesting).

**Order of operations (anti-anchoring):**

This sequence matters. The model analyzes telemetry *first* to generate fresh
hypotheses, then cross-references `improvements.md` to reconcile — never the
reverse. This prevents the file from anchoring the model to past proposals at
the expense of noticing new patterns.

1. **Load and analyze aggregate telemetry + tool-stats.json.**
   Generate fresh hypotheses from the data. Do not read `improvements.md` yet.
   - Identify top failure patterns by frequency × impact
   - Identify tools in `degraded` or `unreliable` tiers

2. **Run skill health assessment.**
   Read `skill-activations.jsonl` and current `skill-health.json`. For each
   skill: calculate token cost, activation rate, failure delta, section-level
   breakdown. Classify health (healthy / underperforming / bloated / thin /
   unused). Write updated `skill-health.json`. Generate skill health
   proposals (compact, expand, prune). Still do not read `improvements.md`.

3. **Perform contrastive analysis where applicable.**
   When the aggregate shows repeated failures in a specific task type:
   - Pull session JSONL from a successful instance of that task type
   - Pull session JSONL from a failed instance
   - Compare: "What did the successful session do differently?"
   - Extract one specific, actionable rule per comparison

4. **NOW read `improvements.md`.**
   Reconcile fresh hypotheses (from steps 1–3) against existing entries:
   - New hypothesis matches an existing `proposed` entry → update evidence
     count, add new telemetry references, note if pattern is worsening
   - New hypothesis has no existing entry → add as new `proposed` entry
   - Existing entry is no longer supported by telemetry → mark `stale`
   - Existing `stale` entry unsupported for 2+ consecutive `/improve`
     cycles → mark `retired` (human can delete or keep for reference)

5. **Present the updated `improvements.md` diff to the human.**
   For each new or updated proposal, show:
   - The evidence (telemetry data, not vibes)
   - The proposed action category (one of the types below)
   - Estimated effort (quick: <30 min, medium: 1-2 hours, involved: half day+)
   Human approves the updated file. Committed to git on a branch.

**Proposal action categories:**

Each entry in `improvements.md` proposes exactly ONE of:
- `new-skill` — Write a new specialized skill or reference file
- `modify-skill` — Change an existing skill's procedure or failure modes
- `compact-skill` — Remove low-value sections from a skill (with evidence)
- `expand-skill` — Add content to a skill that's too thin (with evidence)
- `split-skill` — Break a skill into focused parts when sections serve
  different triggers
- `prune-skill` — Remove an entire skill that isn't earning its context budget
- `modify-claude-md` — Add/update a specific instruction in CLAUDE.md
- `reset-tool-stats` — Clear stats for a tool whose failures were situational
- `not-actionable` — Pattern is real but no clear fix exists (with reasoning)

**Skill health analysis (from `skill-health.json` — see Layer 2g):**

After analyzing telemetry and before reading `improvements.md`, `/improve`
also reads `skill-health.json` and runs the skill health assessment:

- For each skill, compare token cost against value signals
- Identify skills or skill sections that are candidates for compaction,
  expansion, or pruning
- Generate skill health proposals as `improvements.md` entries alongside
  telemetry-derived hypotheses

See **Layer 2g** for the full skill health subsystem: what gets measured,
how section-level assessment works, and the expansion detection logic.

**What `/improve` does NOT do:**
- Implement any changes (that's `/build-improvement`'s job)
- Run during active work (dedicated session)
- Generate reflective prose about what it learned
- Read `improvements.md` before analyzing telemetry (anti-anchoring rule)

**Example output:**

```
## /improve — 14 sessions analyzed

### Fresh from telemetry (analyzed before reading improvements.md):

1. NEW: ASYNC TEST FAILURES (7 occurrences across 3 sessions)
   Evidence: session-2026-03-02.jsonl lines 14-18, session-2026-03-07.jsonl lines 8-12
   Pattern: Tests on async code fail on first run, pass on retry.
   Root cause hypothesis: Missing `await` or insufficient timeout in test setup.
   Proposed action: modify-skill (add async test checklist to tdd-guide.md)
   Effort: quick

2. NEW: WORKTREE PATH CONFUSION (4 occurrences)
   Evidence: session-2026-03-05.jsonl lines 22-25
   Pattern: File edit succeeds but subsequent read fails (path mismatch).
   Root cause hypothesis: Editing in worktree but reading from main tree.
   Proposed action: modify-skill (add path validation to /new-task Phase 2)
   Effort: quick

3. UPDATED: SLOW INTERVIEW PHASE (previously proposed, still present)
   Evidence: avg 12 min across 6 sessions (was 4 sessions last cycle)
   Pattern: /new-plan interview phase asks too many questions.
   Status: proposed → proposed (evidence strengthened)
   Proposed action: modify-skill (reduce interview rounds)
   Effort: medium

4. STALE: CSV ENCODING ERRORS (proposed 3 cycles ago, no recent occurrences)
   Last seen: session-2026-02-15
   Status: proposed → stale (no telemetry support in 14 sessions)

### Skill health (from skill-health.json):

5. NEW: COMPACT new-plan "Known failure modes" section
   Health: bloated (2,800 tokens, activation 62%)
   Section: "Known failure modes" — 340 tokens, no promptfoo coverage,
   no telemetry correlation with reduced failures
   Proposed action: compact-skill (save ~340 tokens, 12% of skill)
   Effort: quick

6. NEW: PRUNE stripe-pagination
   Health: unused (activated 7% of sessions, no failure delta)
   Active for 3 cycles with no meaningful use
   Proposed action: prune-skill (or demote to reference/)
   Effort: quick

7. NEW: EXPAND docker-debugging networking section
   Health: thin (activated 45%, failure_delta +0.08 — MORE failures when active)
   Failures cluster in docker network errors, which the skill doesn't cover
   Proposed action: expand-skill (add networking failure modes + workarounds)
   Effort: medium
```

### 2d. `improvements.md` — Persistent hypothesis tracker

**File:** `~/.claude/skills/improvements.md` (in the skills git repo,
git-tracked, versioned alongside skills)

This file persists improvement hypotheses across `/improve` sessions. It is
NOT an opportunity backlog or a todo list — it's a structured record of
data-driven hypotheses with lifecycle tracking.

**Why this file exists (and why it's not a deferral attractor):**

In the BMO architecture, OPPORTUNITIES.md was a deferral attractor because
the model was supposed to self-improve during active work. The file gave the
model an easy escape from the harder action. In our architecture, the model
is never asked to self-improve during active work. `/improve` is a dedicated
session the human runs. `/build-improvement` is another dedicated session the
human runs. Deferral between sessions is the human's prioritization decision,
not a failure mode.

The file is only loaded by two skills: `/improve` (which reads it AFTER
analyzing telemetry to avoid anchoring) and `/build-improvement` (which reads
it to pick up approved work). It is never loaded during active work sessions
(`/new-plan`, `/new-task`, ad-hoc coding). It lives in the skills git repo,
not in the active project, so it's invisible to normal Claude Code context.

**Format:**

```markdown
# Improvements

Last updated: 2026-03-09 (from /improve session analyzing 14 sessions)

## Proposed

### IMP-001: Async test checklist for TDD guide
- **Status:** proposed
- **First identified:** 2026-03-09
- **Last evidence:** 2026-03-09
- **Evidence count:** 7 occurrences across 3 sessions
- **Telemetry refs:** session-2026-03-02 L14-18, session-2026-03-07 L8-12
- **Action:** modify-skill → shared/reference/tdd-guide.md
- **Effort:** quick
- **Description:** Tests on async code fail on first run, pass on retry.
  Add a checklist: ensure `await`, set adequate timeouts, use `waitFor`
  patterns in testing-library.

### IMP-002: Worktree path validation in /new-task
- **Status:** proposed
- **First identified:** 2026-03-09
- **Last evidence:** 2026-03-09
- **Evidence count:** 4 occurrences across 2 sessions
- **Action:** modify-skill → new-task/SKILL.md Phase 2
- **Effort:** quick
- **Description:** File edits succeed but reads fail due to
  worktree/main-tree path confusion. Add explicit path validation step.

## Approved

### IMP-003: Reduce /new-plan interview rounds
- **Status:** approved (2026-03-09)
- **First identified:** 2026-02-28
- **Last evidence:** 2026-03-09
- **Evidence count:** 12 min avg across 6 sessions
- **Action:** modify-skill → new-plan/reference/interview-guide.md
- **Effort:** medium
- **Description:** Interview phase takes 3x longer than other phases.
  Reduce from 5 rounds to 3, with optional deep-dive only if user requests.

## Built

### IMP-004: Safe file read wrapper
- **Status:** built (2026-02-25, PR #12)
- **Action:** new-skill → skills/safe-read/
- **Outcome:** Reduced file read failures from 12% to 2%

## Stale

### IMP-005: CSV encoding errors
- **Status:** stale (no telemetry support for 3 cycles)
- **First identified:** 2026-02-15
- **Note:** Likely resolved by switching to UTF-8 default. Will retire
  next cycle if still unsupported.

## Retired

(Entries moved here when stale for 2+ consecutive cycles, or explicitly
retired by human. Kept for historical reference but ignored by /improve.)
```

**Lifecycle:** `proposed` → `approved` (human approves during `/improve`) →
`built` (human runs `/build-improvement`) → done. Or: `proposed` → `stale`
(no telemetry support) → `retired`. Human can also reject (`proposed` →
`retired` with reason).

**Staleness rules:**
- If telemetry no longer supports a `proposed` entry after 2 consecutive
  `/improve` cycles, mark `stale`.
- If `stale` for 2 more cycles, mark `retired`.
- Human can override: keep a `stale` entry as `proposed` if they believe
  the pattern will recur.

### 2e. `/build-improvement` — Execute one approved improvement (NEW)

This skill answers: "How do we implement this specific improvement?" It picks
up exactly one `approved` entry from `improvements.md` and builds it.

**Trigger:** Human runs `/build-improvement` when ready to implement an
approved proposal. Equivalent to running `/new-task` but for the improvement
system itself.

**What it does:**

1. **Reads `improvements.md`.** Shows all `approved` entries. Human picks one
   (or `/build-improvement IMP-003` to specify directly).

2. **Scopes the work.** Based on the proposal's action category:
   - `new-skill` → Draft SKILL.md, write promptfoo skeleton, add
     skill-rules.json entry
   - `modify-skill` → Read the target skill, apply the change, update
     promptfoo tests to cover the new behavior
   - `modify-claude-md` → Read CLAUDE.md, add the specific instruction
   - `prune-skill` → Remove the skill directory, remove skill-rules.json
     entry, remove promptfoo config reference
   - `reset-tool-stats` → Zero out the relevant entry in tool-stats.json

3. **Implements on a branch.**

```bash
git checkout -b improve/IMP-003-reduce-interview-rounds
# makes the changes
git add .
git commit -m "improve(IMP-003): reduce /new-plan interview rounds

From improvements.md entry IMP-003 (approved 2026-03-09).
Evidence: 12 min avg across 6 sessions, 3x longer than other phases.
Changes:
- new-plan/reference/interview-guide.md: 5 rounds → 3, optional deep-dive
- new-plan/tests/eval.yaml: added test for 3-round default"
```

4. **Updates `improvements.md`.** Moves the entry from `approved` to `built`
   with PR reference and date.

5. **Runs promptfoo locally.** Verifies the changed skill still passes
   existing tests plus any new tests added for the improvement.

**What `/build-improvement` does NOT do:**
- Analyze telemetry or propose new improvements (that's `/improve`)
- Implement more than one proposal per session (focus)
- Skip the promptfoo verification step
- Merge the PR (human reviews and merges)

### 2f. Skill file standards

Every skill in the git repo must follow this structure:

```
project-root/
├── .claude/
│   ├── hooks/                     # All hooks (Layer 0 + Layer 1)
│   │   ├── session-start.sh
│   │   ├── user-prompt-submit.sh
│   │   ├── pre-tool-use.sh
│   │   ├── post-tool-use.sh
│   │   ├── pre-compact.sh
│   │   ├── stop.sh
│   │   └── status-line.sh
│   ├── telemetry/                 # Auto-populated by hooks
│   │   ├── session-*.jsonl
│   │   ├── aggregate.json
│   │   └── tool-stats.json
│   ├── skill-rules.json           # Keyword → skill activation map
│   └── settings.json              # Hook registration
├── thoughts/                      # Ephemeral session state (gitignored)
│   ├── ledgers/
│   │   └── CONTINUITY_CLAUDE-*.md
│   └── handoffs/
│       └── <session>/
│           └── handoff-*.yaml
└── ~/.claude/skills/              # Persistent skills (git-tracked)
    ├── improvements.md            # Hypothesis tracker (Layer 2d)
    ├── new-plan/
    │   ├── SKILL.md
    │   └── tests/
    │       └── eval.yaml
    ├── new-task/
    │   ├── SKILL.md
    │   └── tests/
    │       └── eval.yaml
    ├── shared/reference/
    │   ├── tdd-guide.md
    │   └── verification-guide.md
    └── promptfoo.yaml             # Root config for all skill tests
```

**Individual skill structure:**

```
~/.claude/skills/<skill-name>/
├── SKILL.md              # Main skill file (≤3,000 tokens)
└── tests/
    └── eval.yaml         # promptfoo regression tests
```

**SKILL.md required sections:**

```markdown
---
name: <skill-name>
description: <one-line for skill index — must be ≤200 tokens>
keywords: [<activation keywords for skill-rules.json>]
version: <semver>
created: <date>
last-validated: <date of last passing promptfoo run>
---

# <Skill Name>

## When to use
<positive trigger conditions>

## When NOT to use
<negative triggers — explicit exclusions to prevent misapplication>

## Known failure modes
<documented failure patterns and workarounds>

## Procedure / Reference
<the actual content>
```

**Why the "When NOT to use" and "Known failure modes" sections:**

The Gorilla research showed irrelevance detection is one of the hardest
capabilities for LLMs. Without explicit negative triggers, the model will reach
for familiar-but-wrong skills. The Tools Fail paper showed that per-tool failure
checklists outperform raw confidence scores. These sections are cheap to write
and high-leverage.

**Token budget rule:** No single SKILL.md exceeds 3,000 tokens of active
content. The total skill description index (all `description` fields loaded
into context) stays under 2,000 tokens. `/improve` monitors this via
`skill-health.json`.

### 2g. Skill health subsystem (NEW)

This is the missing instrumentation that makes skill lifecycle management
data-driven rather than guesswork. It answers three questions per skill:
is this skill earning its token cost? Which parts of it are dead weight?
Is it too thin for the problems it's meant to solve?

#### Instrumentation: what gets measured

**1. Activation logging (from UserPromptSubmit hook)**

The skill activation hook (Layer 0g) already scans messages and suggests
skills. Add a logging line to the hook that records every activation to
`.claude/telemetry/skill-activations.jsonl`:

```jsonc
{
  "ts": "2026-03-09T14:22:01Z",
  "skills_suggested": ["new-task", "tdd-guide"],
  "message_keywords_matched": ["implement", "tdd"],
  "session_id": "abc123"
}
```

This gives us the raw activation rate per skill — how often the hook
suggests it. It doesn't tell us whether the model actually *loaded* the
skill, but activation rate is the most reliable proxy we can measure
without invasive context inspection.

**2. Token cost (static, from skill files)**

`/improve` counts tokens per skill file using a simple heuristic (words × 1.3).
This is static — it only changes when skills are edited. Tracked in
`skill-health.json` alongside dynamic metrics.

**3. Failure rate while skill is active (from aggregate telemetry)**

When `/session-review` annotates which skills were active during a session
(the `skills_active` field in `aggregate.json`), we can calculate:
- Failure rate in sessions where skill X was active
- Failure rate in sessions where skill X was NOT active
- The delta is a rough value signal (positive = skill helps, negative =
  skill might be causing problems, near zero = skill has no measurable
  effect)

This is noisy — many confounds — but over 10+ sessions the trends are
meaningful enough for `/improve` to flag.

**4. Promptfoo test results (from CI)**

Each promptfoo run produces per-test pass/fail with cost data. Over time,
this shows whether a skill's regression tests are stable, flaky, or
degrading. Stored as a summary in `skill-health.json`.

#### skill-health.json

**File:** `.claude/telemetry/skill-health.json`

Updated by `/improve` each time it runs. This is structured data that
persists across sessions — like `tool-stats.json` but for skills.

```jsonc
{
  "updated": "2026-03-09T...",
  "skills": {
    "new-task": {
      "token_count": 2400,
      "token_budget_pct": 4.8,          // % of total skill budget consumed
      "activation_count": 23,            // total activations across all sessions
      "activation_rate": 0.74,           // % of sessions where activated
      "sessions_active": 11,             // sessions where /session-review tagged it
      "sessions_total": 15,              // total /session-review'd sessions
      "failure_rate_when_active": 0.12,  // tool failure rate in sessions using this skill
      "failure_rate_baseline": 0.18,     // tool failure rate in sessions without this skill
      "failure_delta": -0.06,            // negative = skill helps (fewer failures)
      "promptfoo_pass_rate": 1.0,        // latest promptfoo run
      "promptfoo_avg_cost": 0.018,       // avg cost per test case
      "last_modified": "2026-03-02",
      "last_promptfoo_run": "2026-03-08",
      "health": "healthy",              // healthy | underperforming | bloated | thin | unused
      "sections": {                      // section-level assessment (see below)
        "When to use": { "tokens": 180, "referenced_in_tests": true },
        "When NOT to use": { "tokens": 120, "referenced_in_tests": true },
        "Known failure modes": { "tokens": 340, "referenced_in_tests": false },
        "Procedure / Reference": { "tokens": 1760, "referenced_in_tests": true }
      }
    },
    "stripe-pagination": {
      "token_count": 1800,
      "activation_rate": 0.07,
      "failure_delta": 0.01,             // near zero — no measurable effect
      "health": "unused",
      "sections": { ... }
    }
  },
  "totals": {
    "total_skill_tokens": 8400,
    "skill_count": 5,
    "budget_used_pct": 42.0,             // of 2,000 token description index budget
    "description_index_tokens": 840
  }
}
```

#### Health classifications

Each skill gets one of five health states, determined by `/improve`:

| Health | Criteria | Action |
|---|---|---|
| **healthy** | Activated >20% of sessions, failure_delta ≤ 0 (helps or neutral), token_count ≤ 3,000, promptfoo passing | No action needed |
| **underperforming** | Activated >20% but failure_delta > 0 (skill correlates with MORE failures), or promptfoo flaky | Investigate — may need `modify-skill` or `expand-skill` |
| **bloated** | Token count > 2,000 AND (activation_rate < 0.3 OR failure_delta ≈ 0) | Candidate for `compact-skill` — remove low-value sections |
| **thin** | Activated >20% AND failure_delta > 0 AND failures cluster in the skill's domain | Candidate for `expand-skill` — skill covers the area but lacks depth |
| **unused** | Activated <10% of sessions for 3+ consecutive `/improve` cycles | Candidate for `prune-skill` |

These are heuristics, not hard rules. `/improve` presents the classification
and evidence to the human, who decides what to do.

#### Section-level assessment

This is where compaction gets precise. Rather than asking "is the whole skill
worth it?", we ask "which sections of this skill justify their token cost?"

**How it works during `/improve`:**

For each skill classified as `bloated` or `underperforming`, `/improve`
does a section-by-section assessment:

1. **Read the SKILL.md and identify sections** by markdown headers.
2. **For each section, assess:**
   - Token count (measured)
   - Is it referenced by any promptfoo test? (checked against eval.yaml)
   - Does it address a pattern present in the telemetry? (cross-reference
     against aggregate.json failure patterns)
   - Is it referenced in `improvements.md` as having been added to fix
     a specific problem? (check commit history / improvement entries)
3. **Flag sections that are candidates for removal:**
   - Not referenced by any test AND not correlated with any telemetry pattern
   - Token count > 500 AND no evidence of value
   - Duplicate of content in another skill or CLAUDE.md
4. **Flag sections that are candidates for expansion:**
   - Referenced by tests but tests are failing (content insufficient)
   - Covers an area where telemetry shows repeated failures but the
     section is < 200 tokens (too thin for the problem)

**Output format (in `/improve` session):**

```
SKILL HEALTH: new-task (2,400 tokens, healthy)
  ✓ When to use:           180 tok — tested, active
  ✓ When NOT to use:       120 tok — tested, active
  ? Known failure modes:   340 tok — NOT tested, no telemetry correlation
    → Proposal: compact (remove or merge into Procedure section)
    → Saves: ~340 tokens (14% of skill)
  ✓ Procedure / Reference: 1,760 tok — tested, active

SKILL HEALTH: stripe-pagination (1,800 tokens, unused)
  Activated in 1/15 sessions (7%)
  No measurable failure delta
  → Proposal: prune (or demote to reference/ subfolder, not loaded by default)

SKILL HEALTH: new-plan (2,800 tokens, bloated)
  ✓ When to use:           200 tok — tested
  ✓ When NOT to use:       150 tok — tested
  ✓ Known failure modes:   280 tok — correlates with reduced interview overruns
  ? Procedure / Reference: 2,170 tok
    Section breakdown:
      ✓ Interview protocol:  800 tok — tested, essential
      ? Spec template:       600 tok — tested but never modified by users
      ? Approval checklist:  400 tok — NOT tested, no telemetry signal
      ✓ Handoff format:      370 tok — tested, essential
    → Proposal: compact approval checklist (400 tok, no evidence of value)
    → Proposal: evaluate spec template usage in next 5 sessions before deciding
```

Each flagged section becomes an `improvements.md` entry with action type
`compact-skill` or `expand-skill`, evidence, and estimated token savings
or additions.

#### Expansion detection

A skill is "too thin" when:
- It's activated frequently (the model reaches for it)
- But the failure rate in its domain is high (it doesn't help enough)
- And the failures are in the skill's claimed area of coverage

Example: a `docker-debugging` skill that covers container startup but not
networking failures. Telemetry shows repeated `docker network` errors in
sessions where the skill was active. The skill is activated (the keyword
matches) but doesn't have content for this failure class.

`/improve` detects this by:
1. Finding skills with `failure_delta > 0` (more failures when active)
2. Cross-referencing the failure patterns against the skill's "When to use"
   section — do the failures fall within the skill's claimed scope?
3. If yes → `expand-skill` proposal with the specific failure pattern to add
4. If no → the skill isn't the problem; the failures are outside its scope

#### What `/build-improvement` does with skill health proposals

When executing a `compact-skill` entry:
1. Read the skill, remove the flagged sections
2. Update promptfoo tests to reflect the removed content
3. Run promptfoo — if existing tests fail, the section was load-bearing
   despite appearing valueless, and should be kept (abort the compaction)
4. If tests pass, commit on branch, open PR

When executing an `expand-skill` entry:
1. Read the skill and the failure pattern from the improvement entry
2. Draft new content for the specific gap (failure mode documentation,
   procedure extension, or worked example)
3. Stay within the 3,000 token budget — if expansion would exceed it,
   first check if other sections can be compacted to make room
4. Write promptfoo test covering the new content
5. Commit on branch, open PR

---

## Layer 3: What NOT to build (updated)

Carried forward from v1, with additions and adjustments:

1. ~~**No OPPORTUNITIES.md or backlog file.**~~ **Revised in v2.1:**
   `improvements.md` now exists as a persistent hypothesis tracker. The BMO
   argument against this (deferral attractor) was specific to an architecture
   where the model was asked to self-improve during active work. In our
   architecture, the file is only loaded by `/improve` and
   `/build-improvement` — never during active sessions. Human deferral
   between improvement sessions is prioritization, not a failure mode. See
   Layer 2d for the anti-anchoring protocol and staleness rules that prevent
   the file from accumulating stale proposals.
2. **No "continuous learning capture" skill.** Vigilance doesn't work.
3. **No "build it now" interrupt.** The model won't context-switch.
4. **No reflective prose files.** JSON telemetry is the source of truth.
   `improvements.md` contains structured entries with evidence references,
   not narrative reflections.
5. **No autonomous skill creation.** `/retrospective` is human-triggered.
6. **No CC-v3 memory daemon or database.** The daemon reads thinking blocks
   and spawns API calls — privacy-incompatible. CC-v3's continuity system
   (ledgers, handoffs, hooks) is adopted in Layer 0; its memory and TLDR
   systems are not.
7. **No vector database.** Overkill for the skill library size we're targeting.
   If skill retrieval becomes a problem at 50+ skills, revisit with Memorix
   (local BM25, no API keys).
8. **No cross-agent memory.** (Memorix, Vibe Brain, etc.) These solve the
   "re-explain your project" problem, which CLAUDE.md already handles.
   Reassess if you start using multiple agents (Cursor, Copilot) alongside
   Claude Code.
9. **No CC-v3 skill/agent library.** 109 skills and 32 agents is bloat that
   would conflict with custom skills and consume context budget. The skill
   activation *pattern* (keyword hooks) is adopted; the actual content is not.

---

## Layer 4: Regression testing with promptfoo

### Why this matters

Without regression tests, skill improvements are faith-based. You change
tdd-guide.md, and you *hope* it still works. With promptfoo, you run 5 test
cases and *know* it still works — or catch the regression before it ships.

### Setup (community edition, CLI-only)

```bash
npm install -g promptfoo
```

Promptfoo config lives alongside each skill:

```
~/.claude/skills/
├── new-task/
│   ├── SKILL.md
│   └── tests/
│       └── eval.yaml
├── new-plan/
│   ├── SKILL.md
│   └── tests/
│       └── eval.yaml
└── promptfoo.yaml          # root config referencing all skill tests
```

### Test structure per skill

Each `eval.yaml` defines:
- **The prompt:** The skill content + a representative user message
- **Test cases:** 3–5 scenarios covering the skill's core functionality
- **Assertions:** LLM-graded rubrics (does the output follow the procedure?
  does it avoid known failure modes?) + cost assertions (token budget)

Example for a hypothetical `stripe-pagination` skill:

```yaml
# ~/.claude/skills/stripe-pagination/tests/eval.yaml
description: "Regression tests for stripe-pagination skill"

prompts:
  - file://../SKILL.md

providers:
  - id: anthropic:messages:claude-sonnet-4-20250514
    config:
      max_tokens: 2000

tests:
  - description: "Uses cursor-based pagination, not offset"
    vars:
      task: "Fetch all customers from Stripe API"
    assert:
      - type: llm-rubric
        value: "Response uses starting_after parameter with last object ID, not offset-based pagination"
      - type: not-contains
        value: "offset"

  - description: "Handles rate limit errors"
    vars:
      task: "Fetch all invoices, handling potential rate limits"
    assert:
      - type: llm-rubric
        value: "Response includes retry logic with exponential backoff for 429 responses"

  - description: "Token budget compliance"
    assert:
      - type: cost
        threshold: 0.02  # skill shouldn't cost more than ~$0.02 per invocation

  - description: "Negative trigger: doesn't activate for non-Stripe APIs"
    vars:
      task: "Paginate through GitHub API results"
    assert:
      - type: llm-rubric
        value: "Response does NOT apply Stripe-specific patterns to GitHub API"
```

### Running tests

```bash
# Test a single skill
cd ~/.claude/skills/stripe-pagination
promptfoo eval -c tests/eval.yaml

# Test all skills (root config)
cd ~/.claude/skills
promptfoo eval

# View results
promptfoo view
```

### CI integration

When a skill PR is opened, the CI workflow runs:

```yaml
# .github/workflows/skill-regression.yml
name: Skill Regression Tests
on:
  pull_request:
    paths:
      - '.claude/skills/**'

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: npm install -g promptfoo
      - run: |
          cd .claude/skills
          promptfoo eval --output results.json
      - run: |
          # Fail if any test regressed
          jq -e '.results.stats.failures == 0' results.json
```

**Cost control:** promptfoo community edition runs locally. Each test case
costs one API call (~$0.01–0.03 for Sonnet). A full suite of 5 skills × 5
tests = 25 calls ≈ $0.50 per run. Run on PR only, not on every commit.

### What promptfoo catches that telemetry doesn't

Telemetry tells you "this skill's success rate dropped from 90% to 70%."
Promptfoo tells you *why* — which specific capability regressed, and whether
it's a skill change, a model update, or a codebase change that caused it.
They're complementary: telemetry is the smoke detector, promptfoo is the
fire investigation.

---

## Implementation roadmap (updated)

### Phase 0 — Session continuity (week 1, do first)

Goal: Context survives compactions and session boundaries. This is the
foundation for everything else — without continuity, long sessions lose
state and the model wastes tokens rediscovering where it was.

- [ ] Create `thoughts/ledgers/` and `thoughts/handoffs/` directories
- [ ] Add `thoughts/` to `.gitignore` (ephemeral working state)
- [ ] Write `pre-compact.sh` hook (auto-generate handoff YAML)
- [ ] Write `session-start.sh` hook (inject latest handoff + ledger)
- [ ] Write `stop.sh` hook (final handoff + /session-review reminder)
- [ ] Write `status-line.sh` hook (context %, branch, current focus)
- [ ] Register all hooks in `.claude/settings.json`
- [ ] Test: start a session, create a ledger manually, `/clear`, verify
      ledger is re-injected
- [ ] Test: work until compaction triggers, verify handoff YAML is created
      and context is restored
- [ ] Add ledger maintenance instructions to `/new-task` SKILL.md (update
      ledger at phase transitions)
- [ ] Commit hooks to skills git repo

### Phase 0b — Skill activation hook (week 1, alongside Phase 0)

Goal: Skills activate reliably based on keyword matching.

- [ ] Write `user-prompt-submit.sh` hook (keyword scan + activation hint)
- [ ] Write `skill-rules.json` with entries for: new-plan, new-task,
      session-review, retrospective, improve
- [ ] Register hook in `.claude/settings.json`
- [ ] Test: type "let's plan a feature" → verify /new-plan activation hint
- [ ] Test: type "what's the weather" → verify no activation (no false
      positives)
- [ ] Commit to skills git repo

### Phase 1 — Hooks and telemetry (week 1–2)

Goal: Every tool call gets logged automatically. Tool reliability starts
accumulating.

- [ ] Write `post-tool-use.sh` hook (session JSONL + tool-stats.json)
- [ ] Write `pre-tool-use.sh` hook (read tool-stats.json, warn/block)
- [ ] Register hooks in `.claude/settings.json`
- [ ] Create `.claude/telemetry/` directory
- [ ] Test: run a normal Claude Code session, verify JSONL and stats populate
- [ ] Test: artificially set a tool to `unreliable` in stats, verify it blocks
- [ ] Commit hooks to skills git repo

### Phase 2 — Session review skill (week 2)

Goal: End-of-session summaries that surface actionable data.

- [ ] Write `/session-review` SKILL.md
- [ ] Include: telemetry aggregation, tool tier changes, skill extraction prompt
- [ ] Add entry to `skill-rules.json`
- [ ] Test: run after a real session, verify aggregate.json updates correctly
- [ ] Test: verify the human summary is ≤5 lines and data-driven
- [ ] Commit to skills git repo

### Phase 3 — Skill file standards + existing skill migration (week 2–3)

Goal: All existing skills follow the standard format with test skeletons.

- [ ] Define SKILL.md template (frontmatter, required sections)
- [ ] Migrate `/new-plan` to new format (add "When NOT to use", "Known failure
      modes" sections)
- [ ] Migrate `/new-task` to new format (add ledger maintenance instructions)
- [ ] Migrate `shared/reference/` files
- [ ] Write skeleton promptfoo eval.yaml for each migrated skill
- [ ] Verify total skill description index is <2,000 tokens
- [ ] Commit all migrations as a single PR

### Phase 4 — Retrospective skill (week 3)

Goal: Human-triggered skill extraction with git workflow.

- [ ] Write `/retrospective` SKILL.md
- [ ] Include: extraction categories, draft template, git workflow, promptfoo
      skeleton generation, **skill-rules.json update**
- [ ] Add entry to `skill-rules.json`
- [ ] Test: run after a session where you manually discovered an API, verify
      skill draft is reasonable
- [ ] Test: verify git branch/commit/PR workflow works
- [ ] Test: verify new skill-rules.json entry is included in PR
- [ ] Commit to skills git repo

### Phase 5a — Improve skill (diagnose + hypothesize) (week 3–4)

Goal: Data-driven analysis that produces persistent, structured improvement
hypotheses — including skill health assessments.

- [ ] Write `/improve` SKILL.md with anti-anchoring protocol (telemetry
      first, then skill-health.json, then improvements.md)
- [ ] Create initial `improvements.md` in skills git repo (empty template
      with section headers)
- [ ] Implement skill health assessment logic:
  - [ ] Token counting per skill (words × 1.3 heuristic)
  - [ ] Activation rate calculation from skill-activations.jsonl
  - [ ] Failure delta calculation (failure rate with skill vs without)
  - [ ] Section-level breakdown by markdown headers
  - [ ] Health classification (healthy / underperforming / bloated / thin / unused)
- [ ] Write `skill-health.json` update logic (create or update per cycle)
- [ ] Add section-level assessment for bloated/underperforming skills
  - [ ] Cross-reference sections against promptfoo test coverage
  - [ ] Cross-reference sections against telemetry failure patterns
- [ ] Add expansion detection (high activation + positive failure delta +
      failures in skill's domain)
- [ ] Add lightweight contrastive analysis capability
- [ ] Add staleness sweep logic (mark stale after 2 cycles without evidence,
      retire after 2 more)
- [ ] Add entry to `skill-rules.json`
- [ ] Test: run with real aggregate telemetry from Phases 0–4
- [ ] Test: verify fresh hypotheses are generated BEFORE reading improvements.md
- [ ] Test: verify skill health classifications are reasonable
- [ ] Test: verify section-level assessment identifies low-value sections
- [ ] Commit to skills git repo

### Phase 5b — Build-improvement skill (execute) (week 4)

Goal: Focused implementation of one approved improvement per session,
including skill compaction, expansion, and pruning.

- [ ] Write `/build-improvement` SKILL.md
- [ ] Include: pick one approved entry, implement on branch, run promptfoo,
      update improvements.md status, open PR
- [ ] Include compact-skill workflow: remove flagged sections, run promptfoo
      to verify no regressions, abort if tests fail (section was load-bearing)
- [ ] Include expand-skill workflow: draft new content for gap, stay within
      3,000 token budget (compact elsewhere if needed), write new tests
- [ ] Include prune-skill workflow: remove skill directory, skill-rules.json
      entry, promptfoo config reference
- [ ] Add entry to `skill-rules.json`
- [ ] Test: approve an entry in improvements.md, run `/build-improvement`,
      verify branch/PR/status-update workflow
- [ ] Test: run a compact-skill action, verify promptfoo catches regressions
- [ ] Commit to skills git repo

### Phase 6 — Promptfoo CI (week 4)

Goal: Skill changes are regression-tested before merging.

- [ ] Install promptfoo, create root `promptfoo.yaml`
- [ ] Write full eval.yaml for `/new-plan` (3–5 test cases)
- [ ] Write full eval.yaml for `/new-task` (3–5 test cases)
- [ ] Run locally, verify all pass, establish baseline scores
- [ ] Write GitHub Actions workflow for skill PRs
- [ ] Test: open a PR with a deliberately breaking skill change, verify CI fails
- [ ] Document the "add tests when adding skills" convention

### Phase 7 — First full improvement cycle (week 5+)

Goal: Close the loop. Use the system to improve itself.

- [ ] Accumulate 10+ sessions of telemetry
- [ ] Run `/improve` for real — generate hypotheses, assess skill health,
      update improvements.md
- [ ] Evaluate: did the hypotheses make sense? Were they data-driven?
- [ ] Evaluate: did the anti-anchoring protocol work? (Did `/improve`
      generate fresh ideas, or just confirm existing entries?)
- [ ] Evaluate: are skill health classifications reasonable?
  - [ ] Do activation rates match your intuition of how often you use each skill?
  - [ ] Do failure deltas directionally make sense? (Does a skill you trust
        show a negative delta, and one you distrust show positive?)
  - [ ] Are section-level assessments identifying genuinely low-value content,
        or flagging essential sections that just lack test coverage?
- [ ] Approve 1–2 proposals in improvements.md (mix of telemetry-derived
      and skill-health-derived if possible)
- [ ] Run `/build-improvement` for real — implement one approved proposal
- [ ] If a compact-skill action: verify promptfoo catches load-bearing
      sections before they're removed
- [ ] If an expand-skill action: verify new content stays within token budget
- [ ] Evaluate: was the implementation focused and clean?
- [ ] Evaluate: did promptfoo tests pass after the change?
- [ ] After 5+ more sessions, check: did the telemetry improve for the
      pattern the improvement was meant to fix?
- [ ] After 5+ more sessions, check: did the compacted skill maintain its
      effectiveness? (Same or better failure delta with fewer tokens?)
- [ ] Run `/improve` again — verify stale entries are detected, new
      patterns are surfaced, skill health reflects recent changes
- [ ] Evaluate: is `improvements.md` accumulating useful history, or
      growing stale entries faster than they're resolved?
- [ ] Run `/improve` on the improvement system itself (meta-improvement)

---

## Decision log: what was considered and decided

| Considered | Decision | Rationale |
|---|---|---|
| Persistent improvements.md | **Adopted (Layer 2d)** | Originally rejected (BMO's OPPORTUNITIES.md was a deferral attractor). Revisited: in our architecture, the model never self-improves during active work. The file is only loaded by `/improve` and `/build-improvement`. Human deferral is prioritization, not a failure mode. Anti-anchoring protocol (telemetry first, then file) prevents the file from limiting fresh hypotheses. Staleness rules prevent unbounded accumulation. |
| Split /improve into diagnose + build | **Adopted (2c + 2e)** | Mirrors the `/new-plan` → `/new-task` separation. Diagnosis benefits from breadth (scanning all telemetry). Implementation benefits from depth (focused execution of one change). Mixing them in a single session causes context-switching between analysis and coding. |
| CC-v3 continuity (ledgers, handoffs, hooks) | **Adopted (Layer 0)** | Solves context loss across compactions/sessions. Pure local files, no daemon, no database. The highest-value piece of CC-v3. |
| CC-v3 skill activation hook (keyword matching) | **Adopted (Layer 0g)** | 84% vs 20% activation rate. Crude but effective. Maintained via same git workflow as skills. |
| CC-v3 memory daemon (PostgreSQL + pgvector) | **Rejected** | Daemon reads thinking blocks, spawns API calls. Privacy-incompatible. `/session-review` + `/improve` achieve similar outcomes without a daemon. Revisit if semantic search over past sessions becomes a clear bottleneck. |
| CC-v3 TLDR code analysis | **Rejected** | Background daemon, tangential to self-improvement. Revisit if codebase exceeds ~100k LOC and token costs for file reads become a bottleneck. |
| CC-v3 skill/agent library (109 + 32) | **Rejected** | Conflicts with custom skills, context budget bloat. The pattern is adopted; the content is not. |
| Memorix (cross-agent memory) | **Rejected** | CLAUDE.md handles project context for single-agent setup. Revisit if using multiple AI coding agents. |
| Vector database for skill retrieval | **Rejected** | Overkill at <50 skills. Revisit if skill library exceeds 50 and retrieval accuracy drops. |
| Autonomous skill extraction | **Rejected** | Quality and privacy concerns outweigh convenience. `/retrospective` is human-triggered. |
| PromptOps (git-native prompt versioning) | **Rejected** | Too new, git + commit messages suffice. Revisit if it matures. |
| Contrastive in-context learning in skill files | **Selectively adopted** | Full positive+negative examples double token cost. Used selectively in "Known failure modes" sections only. |
| AGENTS.md cross-tool standard | **Rejected** | Only useful with multiple AI tools. Revisit if adopting multiple coding agents. |

---

## Telemetry and state file schemas (final)

### Session events (`.claude/telemetry/session-<date>.jsonl`)

```jsonc
{
  "ts": "2026-03-09T14:22:01Z",
  "tool": "Bash",              // envelope tool name from hook
  "tool_key": "bash:npm",      // specific tool (CLI extracted, or same as tool)
  "exit_code": 1,              // raw exit code
  "outcome": "fail",           // pass | fail (derived from exit_code)
  "duration_ms": 3400,         // wall clock from hook
  "session_id": "abc123"       // optional: group events within a session
}
```

**Dual-level tracking:** Every event records both the envelope (`tool`) and the
specific tool (`tool_key`). For non-Bash tools these are the same. For Bash
calls, `tool_key` is `bash:<command>` — enabling per-CLI-tool analysis.
The hook extracts the command automatically; it doesn't know which skill is
active, which phase we're in, or what the semantic error class is. Those richer
annotations come from the model during `/session-review`.

### Tool reliability stats (`.claude/telemetry/tool-stats.json`)

```jsonc
{
  "Bash": {
    "total": 142, "pass": 119, "fail": 23,
    "total_ms": 253437,
    "success_rate": 0.838,
    "last_used": "2026-03-09T21:38:48Z",
    "tier": "healthy"
  },
  "bash:npm": {
    "total": 34, "pass": 24, "fail": 10,
    "success_rate": 0.706, "tier": "degraded"
  },
  "bash:git": {
    "total": 28, "pass": 27, "fail": 1,
    "success_rate": 0.964, "tier": "healthy"
  },
  "bash:docker": {
    "total": 12, "pass": 5, "fail": 7,
    "success_rate": 0.417, "tier": "unreliable"
  },
  "Read": {
    "total": 89, "pass": 88, "fail": 1,
    "success_rate": 0.989,
    "tier": "healthy"
  }
}
```

**Dual-level entries:** Both the envelope (`Bash` — aggregate of all CLI
commands) and specific CLI tools (`bash:npm`, `bash:docker`, etc.) are tracked.
PreToolUse checks the specific key first (more actionable warnings), falling
back to the envelope.

### Aggregate stats (`.claude/telemetry/aggregate.json`)

```jsonc
{
  "updated": "2026-03-09T...",
  "sessions_reviewed": 14,       // only counts /session-review'd sessions
  "by_session": [
    {
      "date": "2026-03-09",
      "events": 47,
      "pass": 38,
      "fail": 9,
      "duration_total_ms": 124000,
      "skills_active": ["new-task"],   // annotated by /session-review
      "notes": "stripe integration, discovered pagination pattern"
    }
  ],
  "top_failure_patterns": [
    // populated by /session-review from semantic analysis of session
    { "pattern": "async test timeout", "count": 7, "first_seen": "2026-03-02" },
    { "pattern": "worktree path confusion", "count": 4, "first_seen": "2026-03-05" }
  ]
}
```

**Split responsibilities:** Hooks write the raw data (session JSONL,
tool-stats). `/session-review` adds the semantic annotations (which skills
were active, what the failure patterns mean, the human-readable notes).
`/improve` reads the aggregate and proposes changes. Clean separation.

### Continuity ledger (`thoughts/ledgers/CONTINUITY_CLAUDE-<session>.md`)

Maintained by the model during active work. See Layer 0a for full format.
Key constraint: the model updates this at structural moments (phase
transitions, subtask completion), not on every turn. If the model doesn't
maintain it, the PreCompact hook falls back to git diff.

### Handoff YAML (`thoughts/handoffs/<session>/handoff-<timestamp>.yaml`)

Auto-generated by PreCompact and Stop hooks. See Layer 0b for full format.
Read by SessionStart hook to restore context. Only the latest handoff is
used; older handoffs are retained for debugging but not injected.

### Skill activation rules (`.claude/skill-rules.json`)

Maintained alongside skills — `/retrospective` adds entries, `/improve`
prunes entries. See Layer 0g for full format. The UserPromptSubmit hook
reads this on every user message; keep it small and fast to parse.

### Skill activations (`.claude/telemetry/skill-activations.jsonl`)

Append-only log written by the UserPromptSubmit hook every time it
suggests one or more skills. Used by `/improve` to calculate activation
rates for `skill-health.json`.

```jsonc
{
  "ts": "2026-03-09T14:22:01Z",
  "skills_suggested": ["new-task", "tdd-guide"]
}
```

### Skill health metrics (`.claude/telemetry/skill-health.json`)

Updated by `/improve` each cycle. Contains per-skill token costs,
activation rates, failure deltas, section-level breakdowns, and health
classifications. See Layer 2g for full schema and the five health states
(healthy, underperforming, bloated, thin, unused).

### Improvement hypotheses (`~/.claude/skills/improvements.md`)

Maintained by `/improve` (analysis) and `/build-improvement` (status
updates). See Layer 2d for full format and lifecycle rules. Key properties:
- Only loaded during `/improve` and `/build-improvement` sessions
- Never loaded during active work (invisible to normal Claude Code context)
- Git-tracked in the skills repo (versioned, reviewable, diffable)
- Entries have a lifecycle: proposed → approved → built (or → stale → retired)
- Anti-anchoring: `/improve` reads this AFTER generating fresh hypotheses

---

## Open questions (to resolve through usage)

1. **Hook granularity:** The PostToolUse hook fires on every tool call. Is
   this too noisy for tools like `Read` that fire hundreds of times? May need
   to filter to only `Bash`, `Write`, `Edit` in the hook script, or add a
   sampling rate.

2. **Tool-stats decay:** Should old failures decay over time? A tool that
   failed 10/20 times two weeks ago but has been 50/50 since might deserve a
   fresh start. Consider a rolling window (last N calls) instead of all-time.

3. **Promptfoo cost at scale:** 25 test cases at $0.50/run is fine for weekly
   CI. If the skill library grows to 20+ skills with 5 tests each, costs
   reach ~$2/run. Still cheap, but worth monitoring. Use Haiku for
   non-critical assertions to cut costs.

4. **Contrastive analysis quality:** The lightweight version (comparing JSONL
   sequences) may not have enough semantic information to produce useful
   comparisons. If it consistently produces unhelpful output, drop it from
   `/improve` rather than trying to fix it.

5. **Skill activation monitoring:** The UserPromptSubmit hook now surfaces
   activation hints, but we don't yet measure: how often each skill is
   activated, how often activations are false positives (skill was suggested
   but not used), or how often a skill was needed but NOT activated (missed
   keywords). Consider adding activation logging to the hook and reviewing
   it during `/improve`.

6. **Ledger maintenance discipline:** The model is asked to update the
   continuity ledger during active work — one of the few things we ask it to
   do mid-task. Will it actually do this reliably? If not, the PreCompact
   handoff falls back to git diff (minimal but usable). Monitor whether
   ledgers are maintained consistently and adjust: either make ledger updates
   a structural trigger (e.g. after every phase transition in `/new-task`)
   or accept that handoffs will often be git-diff-only.

7. **Handoff file accumulation:** Handoff YAMLs are append-only in
   `thoughts/handoffs/`. Over weeks of use, these will accumulate. Need a
   retention policy — keep last N sessions? Keep last 7 days? The
   SessionStart hook only reads the latest, so old handoffs are unused. Add
   a cleanup step to the Stop hook or to `/session-review`.

8. **Skill-rules.json keyword quality:** Keyword matching is crude. If false
   positives become annoying (every message triggers some activation), the
   keywords need tightening. If false negatives are common (skills not
   activating when they should), keywords need broadening. Track this
   qualitatively in early sessions and adjust.

9. **Hook execution overhead:** With 7 hooks firing on various events, there's
   a latency cost per interaction. The hooks are lightweight (shell scripts
   reading small JSON files), but if cumulative overhead exceeds ~200ms per
   turn, it'll be noticeable. Profile early and optimise hot paths (especially
   PostToolUse and UserPromptSubmit which fire most frequently).

10. **Improvements.md anchoring in practice:** The anti-anchoring protocol
    (telemetry first, then file) is the theory. In practice, we need to
    monitor whether `/improve` sessions generate genuinely novel hypotheses
    or just confirm existing entries. A simple check: after 5 `/improve`
    cycles, count how many proposals were net-new vs confirmations. If the
    ratio drops below 50% new, the file may be anchoring despite the
    protocol — consider having `/improve` skip reading the file entirely
    every other cycle.

11. **Improvements.md size:** With structured entries averaging ~200 words
    each, the file stays manageable at 10-20 active proposals. If it grows
    beyond 30 entries, it becomes a context burden even for `/improve`
    sessions. The staleness rules should prevent this, but monitor the
    retired section — if it's growing faster than entries are deleted,
    add a periodic purge of old retired entries.

12. **Activation rate as proxy for actual use:** The UserPromptSubmit hook
    logs which skills are *suggested*, not which are *loaded and followed*.
    A skill might be suggested every session but the model ignores the hint
    and doesn't load it. This makes activation rate an upper bound on
    actual use, not a precise measure. If skill health classifications
    seem wrong (a skill marked "healthy" because it's always suggested but
    you notice the model never actually follows it), consider adding a
    manual "was this skill useful?" field to `/session-review`.

13. **Section-level assessment granularity:** The plan assesses sections by
    markdown headers, which means skills with few headers get coarse-grained
    assessment. If a skill has only two sections ("When to use" and a
    single large "Procedure" section), the section-level assessment can't
    distinguish valuable from dead-weight content within Procedure. For
    skills with large monolithic sections, consider whether the section
    should be split into subsections *before* assessing — which is itself
    a `/improve` proposal.

14. **Failure delta confounds:** The failure delta (failure rate with skill
    active minus without) is a crude signal with many confounds. A skill
    might activate only on hard tasks, which have higher failure rates
    regardless of the skill's quality. Over 10+ sessions the noise averages
    out somewhat, but treat the delta as directional evidence, not proof.
    If the delta consistently doesn't match your intuition, downweight it
    in skill health classifications.

15. **Token counting accuracy:** The words × 1.3 heuristic for token
    counting is rough. Different content (code blocks, YAML, prose) has
    different token densities. If precise token budgets matter, use
    `tiktoken` or the Anthropic tokenizer for exact counts. For now the
    heuristic is good enough for relative comparisons between skills.
