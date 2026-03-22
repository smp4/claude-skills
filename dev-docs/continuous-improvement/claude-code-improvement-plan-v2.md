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
│  ├── aggregate.json              (cumulative stats)                  │
│  └── tool-stats.json             (rolling tool reliability)          │
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
│  (dedicated session)         │       │
│                              │       │
│  1. Load aggregate telemetry │       │
│  2. Load tool-stats.json     │       │
│  3. Top 3 failure patterns   │       │
│     + top 3 cost/value       │       │
│     concerns                 │       │
│  4. Propose actions          │◀──────┘
│  5. Human approves           │
│  6. Execute on branch → PR   │
│  7. Update promptfoo tests   │
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
    "keywords": ["improve", "what should we fix", "improvement session", "optimize skills"],
    "description": "Data-driven improvement proposals from aggregate telemetry"
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

Fires after every tool call. Captures outcome to two destinations:

```bash
#!/usr/bin/env bash
# .claude/hooks/post-tool-use.sh
#
# Receives JSON on stdin with: tool_name, input, output, exit_code, duration_ms
# Writes to two files:
#   1. Session JSONL  — per-event log for /session-review
#   2. tool-stats.json — rolling reliability stats for PreToolUse gating

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

# Classify outcome
if [ "$EXIT_CODE" -eq 0 ]; then
  OUTCOME="pass"
else
  OUTCOME="fail"
fi

# 1. Append to session JSONL
jq -nc \
  --arg ts "$TS" \
  --arg tool "$TOOL" \
  --arg outcome "$OUTCOME" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson duration "$DURATION" \
  '{ts: $ts, tool: $tool, outcome: $outcome, exit_code: $exit_code, duration_ms: $duration}' \
  >> "$SESSION_FILE"

# 2. Update rolling tool stats
# Uses jq to atomically update counts; creates file if missing
if [ ! -f "$STATS_FILE" ]; then
  echo '{}' > "$STATS_FILE"
fi

jq --arg tool "$TOOL" \
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
```

**Notes:**
- The 5-call minimum before tiering prevents premature classification.
- Tiers: `new` (<5 calls), `healthy` (≥80%), `degraded` (50–80%),
  `unreliable` (20–50%), `deprecated` (<20%).
- All data stays local in `.claude/telemetry/`. Nothing leaves your machine.
- Session JSONLs are append-only and cheap to grep.

### 1b. PreToolUse hook — reliability gating

**File:** `.claude/hooks/pre-tool-use.sh`

Fires before each tool call. Reads tool-stats.json and acts:

```bash
#!/usr/bin/env bash
# .claude/hooks/pre-tool-use.sh

set -euo pipefail

STATS_FILE=".claude/telemetry/tool-stats.json"
[ ! -f "$STATS_FILE" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')

TIER=$(jq -r --arg t "$TOOL" '.[$t].tier // "new"' "$STATS_FILE")
RATE=$(jq -r --arg t "$TOOL" '.[$t].success_rate // 1' "$STATS_FILE")

case "$TIER" in
  degraded)
    echo "⚠ WARNING: $TOOL has ${RATE}% success rate (degraded). Consider alternatives." >&2
    exit 0  # allow but warn
    ;;
  unreliable)
    echo "⛔ BLOCKED: $TOOL has ${RATE}% success rate (unreliable). Check tool-stats.json for details." >&2
    exit 2  # block the call
    ;;
  deprecated)
    echo "⛔ BLOCKED: $TOOL has ${RATE}% success rate (deprecated). This tool should be removed." >&2
    exit 2
    ;;
  *)
    exit 0
    ;;
esac
```

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

### 2c. `/improve` — Dedicated improvement sessions (updated from v1)

**Retained from v1:**
- Dedicated session, never background
- Loads aggregate telemetry
- Proposes actions, human approves
- No backlog file

**New in v2 — tool reliability analysis:**

In addition to failure pattern analysis, `/improve` now also:
- Reads tool-stats.json
- Identifies tools in `degraded` or `unreliable` tiers
- For each, proposes one of:
  a. Write a specialized skill to replace the unreliable generic approach
  b. Add failure mode documentation to existing skill
  c. Add a workaround/alternative to CLAUDE.md
  d. Reset the stats (if the failures were situational, not systemic)

**New in v2 — skill cost/value assessment:**

For each existing skill, `/improve` calculates (from aggregate telemetry):
- **Invocation rate:** % of sessions where the skill was loaded
- **Token cost:** Approximate tokens in the skill file
- **Value signal:** Success rate of work done while skill was active vs
  baseline (requires enough sessions to be meaningful)

Proposes pruning for skills that are:
- Loaded <10% of sessions AND have no regression test justification
- Larger than 3,000 tokens without proportional value signal
- Superseded by a newer, more specific skill

**New in v2 — contrastive analysis (lightweight version):**

When the aggregate shows repeated failures in a specific task type, `/improve`
can do a simplified contrastive analysis:
- Pull the session JSONL from a successful instance of that task type
- Pull the session JSONL from a failed instance
- Ask: "Compare these event sequences. What did the successful session do
  differently? Extract one specific, actionable rule."
- Proposed rule becomes a candidate CLAUDE.md addition or skill refinement.

This is not the full MACLA pipeline — it's a human-triggered, lightweight
version that uses telemetry sequences rather than full conversation traces.
The human decides when it's worth running and approves the output.

**New in v2 — all changes go through git:**

Every change `/improve` proposes gets executed on a branch:

```bash
git checkout -b improve/2026-03-09
# makes approved changes to skill files, CLAUDE.md, etc.
git add .
git commit -m "improve: async test checklist, prune unused csv-import skill

From /improve session analyzing 14 sessions.
Changes:
- shared/reference/tdd-guide.md: added async test checklist (7 failures)
- removed skills/csv-import/ (0 invocations in 14 sessions)
- CLAUDE.md: added worktree path validation reminder (4 failures)"
# opens PR
```

### 2d. Skill file standards (NEW)

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
into context) stays under 2,000 tokens. `/improve` monitors this.

---

## Layer 3: What NOT to build (updated)

Carried forward from v1, with additions and adjustments:

1. **No OPPORTUNITIES.md or backlog file.** Deferral attractor.
2. **No "continuous learning capture" skill.** Vigilance doesn't work.
3. **No "build it now" interrupt.** The model won't context-switch.
4. **No reflective prose files.** JSON telemetry is the source of truth.
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

### Phase 5 — Improve skill v2 (week 3–4)

Goal: Data-driven improvement proposals including tool reliability and skill
cost/value analysis.

- [ ] Update `/improve` SKILL.md with tool reliability analysis
- [ ] Add skill cost/value assessment (invocation rate, token cost, value signal)
- [ ] Add lightweight contrastive analysis capability
- [ ] Add git workflow (all changes on branch → PR)
- [ ] Add skill-rules.json maintenance (prune entries for removed skills)
- [ ] Test: run with real aggregate telemetry from Phases 0–4
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

### Phase 7 — First /improve cycle (week 5+)

Goal: Close the loop. Use the system to improve itself.

- [ ] Accumulate 10+ sessions of telemetry
- [ ] Run `/improve` for real
- [ ] Evaluate: did the proposals make sense? Were they actionable?
- [ ] Evaluate: did the tool reliability tiers correctly identify problems?
- [ ] Evaluate: is the telemetry schema capturing the right events, or is it
      too noisy / too sparse?
- [ ] Evaluate: is the continuity system actually reducing wasted tokens
      after compaction? (Compare pre-continuity vs post-continuity sessions)
- [ ] Evaluate: are skill activation hints firing correctly, or producing
      too many false positives?
- [ ] Adjust hook scripts, schemas, and skill templates based on findings
- [ ] Run `/improve` on the improvement system itself (meta-improvement)

---

## Decision log: what was considered and decided

| Considered | Decision | Rationale |
|---|---|---|
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
  "tool": "Bash",              // tool name from hook (not skill name)
  "exit_code": 1,              // raw exit code
  "outcome": "fail",           // pass | fail (derived from exit_code)
  "duration_ms": 3400,         // wall clock from hook
  "session_id": "abc123"       // optional: group events within a session
}
```

**Simplified from v1:** The hook only sees tool name and exit code — it doesn't
know which skill is active, which phase we're in, or what the semantic error
class is. Those richer annotations come from the model during `/session-review`,
not from the hook. This keeps the hook simple, fast, and privacy-preserving
(it never reads conversation content).

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
  "Read": {
    "total": 89, "pass": 88, "fail": 1,
    "success_rate": 0.989,
    "tier": "healthy"
  }
}
```

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
