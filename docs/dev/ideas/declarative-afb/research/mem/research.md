# Memory System Research

> Date: 2026-04-05
> Status: Research rev 2 — expanded tool survey, addressed review comments

---

## Problem Validation

### Confirmed Problems (from idea.md)

| # | Problem | Validated? | Notes |
|---|---------|-----------|-------|
| P1 | No semantic retrieval across sessions | Yes | Claude Code auto-memory is flat markdown, no embeddings, no ranked retrieval. MEMORY.md is an index — no semantic search. |
| P2 | Indiscriminate context loading | Yes | CLAUDE.md + MEMORY.md loaded every session regardless of task. No per-stage or per-bead filtering. |
| P3 | No structural code understanding / repo map | Yes | No persistent map of files, exports, symbol relationships. Agent re-explores structure each session. Aider has repo maps; Claude Code does not. |
| P4 | Weak mistake-avoidance loops | Yes | Auto-memory can store "feedback" but no structured track/surface/verify cycle. No confidence scoring or decay. |
| P5 | Instruction adherence degrades with length | Yes | ~150-200 instruction ceiling. CLAUDE.md, tool results, memory, conversation all compete for attention. |

### Additional Problems Identified

| # | Problem | Description | Hud relevance |
|---|---------|-------------|---------------|
| P6 | No cross-agent knowledge sharing | Parallel agents on same repo can't share discoveries. One agent finds a bug pattern; others repeat the search. | Direct — hud runs parallel beads. Already identified as R11 in risk register. |
| P7 | No structured session search | Past sessions are JSONL files. Debugging patterns, architectural decisions buried. No query interface. | Valuable for hud's retry/handoff — understanding what was tried before. |
| P8 | Context window waste on re-exploration | Even with read-once (intra-session), across sessions the agent re-reads same files, re-discovers same structure. | Every hud stage restart pays this cost. |
| P9 | No temporal knowledge management | Facts change. No concept of validity windows, staleness detection, or automatic invalidation. | Stage outputs evolve. Memory of "API X is at endpoint Y" may be stale after a refactor. |
| P10 | Collective intelligence gap | Multiple Claude Pro accounts can't share learned patterns. Each starts from zero. | If hud uses 2 Pro accounts in parallel, they can't learn from each other without explicit mechanism. |
| P11 | Memory injection timing mismatch | All context loaded at session start. On-demand retrieval during session not possible without MCP tools. | hud prime front-loads context. Mid-session memory queries need MCP server. |
| P12 | No memory provenance or confidence | No way to know if a fact is still valid, how confident it is, or where it came from. | Critical for parallel agents — confidence-weighted retrieval prevents acting on stale knowledge. |

---

## Tool Evaluations

### Tier 1: Recommended

#### CASS — Coding Agent Session Search
- **URL:** https://github.com/Dicklesworthstone/coding_agent_session_search
- **Stars:** 646 | **Language:** Rust | **Status:** Alpha
- **What:** Indexes session history across 11+ agent providers (Claude Code, Codex, Cursor, etc). TUI + CLI + MCP. Sub-60ms queries via Tantivy.
- **Search modes:** Lexical (BM25), Semantic (optional MiniLM), Hybrid (RRF)
- **Resources:** Minimal for lexical-only. ~90MB for MiniLM model if semantic enabled.
- **Integration:** CLI (`cass search`), Robot mode (`--robot --json`), MCP server
- **Solves:** P7 (session search), P8 (re-exploration), P4 (mistake patterns in history)
- **Verdict:** Foundation layer. Lightweight, fast, indexes what already exists. No new infrastructure.

#### cq — Mozilla Shared Agent Learning
- **URL:** https://github.com/mozilla-ai/cq
- **Stars:** 969 | **Language:** Python+Go | **Status:** Exploratory (0.x)
- **What:** Agents store/share/query collective knowledge units. Post-error auto-queries. SQLite local + optional remote API.
- **Architecture:** Agent → MCP server (local SQLite) → optional Docker container (shared API)
- **Resources:** Lightweight. SQLite + Python server.
- **Integration:** Claude Code plugin (`claude plugin install cq`), MCP server
- **Solves:** P4 (mistake avoidance), P6 (cross-agent sharing), P10 (collective intelligence), P12 (provenance via domains/tiers)
- **Verdict:** Already listed in hud README. Direct fit for cross-agent learning. Lightweight enough for M2 Air.

#### mcp-memory-service
- **URL:** https://github.com/doobidoo/mcp-memory-service
- **Stars:** 1.6k | **Language:** Python | **Status:** Active (v9.3)
- **What:** Persistent memory with local ONNX embeddings (MiniLM-L6-v2). SQLite-vec storage. Hybrid BM25 + vector search. Web dashboard.
- **Architecture:** MCP server, local embeddings, no external API calls.
- **Resources:** Moderate. ONNX runtime + MiniLM model (~90MB). SQLite for storage.
- **Integration:** MCP server (stdio), REST API (15 endpoints)
- **Solves:** P1 (semantic retrieval), P2 (on-demand retrieval via MCP), P11 (mid-session queries)
- **Verdict:** Best balance of capability vs. resource requirements for M2 Air. Local-only, no cloud dependency.

#### claude-handoff
- **URL:** https://github.com/REMvisual/claude-handoff
- **Stars:** 9 | **Language:** Shell | **Status:** v1.4.1
- **What:** Structured session handoff skills. Context-aware mining with tiered strategy (100K/500K/1M). Chain tracking across sessions. Integrates with beads.
- **Architecture:** Claude Code skills (`/handoff`, `/handoffplan`). Optional PreCompact hook.
- **Resources:** Zero — shell scripts only.
- **Integration:** Skills installed to `~/.claude/skills/`
- **Solves:** P1 (structured context preservation), P8 (re-exploration via handoff chain)
- **Low stars concern:** Small project but focused on exact problem. Shell-only means low risk. Beads integration is a bonus.
- **Verdict:** Consider cleanrooming. The shell scripts are simple (~200 LOC total) and the concept is more valuable than the implementation. A cleanroom version coupled with beads + agent_mail would enable **task-bound handovers** (tied to bead ID, agent identity, stage) rather than floating markdown in a repo. The handoff doc becomes a first-class artifact in the bead's lifecycle, routable via agent_mail to the next session/agent. Low effort to build, high control, and the coupling with hud's existing primitives would make it significantly better than the standalone version.

### Tier 2: Recommended if Capacity Allows

#### cass_memory_system
- **URL:** https://github.com/Dicklesworthstone/cass_memory_system
- **Stars:** 310 | **Language:** TypeScript/Bun | **Status:** Alpha
- **What:** Three-layer cognitive architecture over CASS: episodic (raw sessions) → working (structured diaries) → procedural (confidence-tracked rules with 90-day decay).
- **Architecture:** CLI (`cm` commands) + MCP server. Builds on CASS for session access.
- **Resources:** Bun runtime + TypeScript. Lightweight.
- **Integration:** CLI + MCP server
- **Solves:** P4 (mistake avoidance with confidence/decay), P12 (provenance + confidence tracking), anti-pattern learning
- **Revised verdict:** cass_memory_system is **more fundamentally sound** than cq for learned knowledge. Its three-layer cognitive model (episodic → working → procedural), 90-day confidence decay, 4x harmful multiplier, and maturity progression (candidate → established → proven → deprecated) represent a deeper solution. cq has no time-based decay — stale knowledge persists at full confidence indefinitely, which is a critical flaw for mistake-avoidance. However, cq wins on **integration** (Claude Code marketplace plugin, Mozilla backing, multi-language SDK). "Exploratory 0.x" is arguably *more* concerning than "alpha" because cq's core model may need fundamental redesign, while cass's model is architecturally sound and needs hardening. **Recommendation:** use both — cq for lightweight cross-agent knowledge sharing ("what did we learn"), cass for deep procedural memory with decay ("how should we behave"). They address overlapping but distinct concerns. cass has 764 commits vs cq's 115, suggesting more iteration on the core problem despite fewer stars.

#### meta_skill
- **URL:** https://github.com/Dicklesworthstone/meta_skill
- **Stars:** 147 | **Language:** Python | **Status:** Active
- **What:** Skill management platform. Hash embeddings (no external model), dual persistence (SQLite + Git), bandit optimization for search ranking.
- **Architecture:** MCP server with 6 tools. Integrates with CASS and beads_viewer.
- **Resources:** Lightweight — hash embeddings, no ML model needed.
- **Integration:** MCP server
- **Solves:** Skill organization, provenance tracking, effectiveness loops.
- **Verdict:** Potentially useful for managing hud's growing skill library (Phase 7+). Not core memory.

### Tier 3: Evaluated, Not Recommended

#### OpenMemory (CaviraOSS)
- **Stars:** 3.9k | Undergoing **major rewrite** — breaking changes expected.
- **Why not:** Unstable API. More complex than needed. Better to revisit post-v1.0.

#### OpenViking (volcengine)
- **Stars:** 21.1k | Tiered context loading is interesting concept.
- **Why not:** Requires VLM model + embedding model. Go + C++ build dependencies. AGPLv3 license. Resource-heavy for M2 Air.

#### mem0-mcp-selfhosted
- **Stars:** 60 | Requires Qdrant (~2GB) + Ollama (~4GB) + optional Neo4j (~2GB).
- **Why not:** Infrastructure burden too heavy for 16GB M2 Air. Low community adoption.

#### letta-code
- **Stars:** 2.1k | Memory-first coding harness.
- **Why not:** It's a complete alternative to Claude Code, not a composable memory layer. Can't use alongside hud's Claude Code sessions.
- **claude-subconscious (letta-ai/claude-subconscious):** 2.6k stars, TypeScript, MIT. **Does exist** — uses Claude Code's hook system (SessionStart, UserPromptSubmit, PreToolUse, Stop) to send transcripts to a Letta agent (async background worker on Stop hook) and inject guidance before each prompt (stdout on UserPromptSubmit). Requires `LETTA_API_KEY` (Letta Cloud or self-hosted server). Explicitly marked **"demo, not production"** — Letta wants you on Letta Code instead.
- **Limitations:** Reactive only (processes transcripts after each response), not proactive (no periodic consolidation/reflection/pruning). Adds Letta Cloud dependency or self-hosted server overhead. Limited customization.
- **Value as reference implementation:** Validates the hook-based architecture we planned (same 4 hooks). The async Stop hook pattern (spawn detached worker, don't block Claude) is a good design to borrow. Per-project agents possible via `LETTA_AGENT_ID` + direnv.
- **Verdict:** Don't adopt — build our own using the same hook pattern. We get full control, no external dependency, and can add true sleep-time reflection (periodic consolidation, not just reactive transcript capture). claude-subconscious is a useful reference, not a solution.
#### Aider
- **Stars:** 42.8k | Repo map feature is excellent.
- **Why not as agent:** Alternative coding agent. Can't use alongside Claude Code.
- **Repo map is now extractable** — see RepoMapper below (Tier 1). Aider's `repomap.py` (~700 LOC) uses tree-sitter + PageRank + token-budget binary search. Algorithm is well-documented public knowledge. RepoMapper is a cleanroom reimplementation as standalone MCP server.

### Tier 1 Additions (from awesome lists and broader ecosystem research)

#### RepoMapper
- **URL:** https://github.com/pdavis68/RepoMapper
- **Stars:** 149 | **Language:** Python + tree-sitter | **Status:** Active
- **What:** Aider's repo map algorithm as standalone MCP server. Tree-sitter parsing, PageRank on definition/reference graph, binary search to fit token budget. Token budget support (`--map-tokens 2048`).
- **Resources:** Lightweight — tree-sitter, networkx, tiktoken, diskcache. M2 Air friendly.
- **Integration:** MCP server (stdio) + CLI
- **Solves:** P3 (structural code understanding / repo map) — **the primary unsolved problem**
- **Weakness:** 149 stars, single maintainer, "100% based on Aider" — license situation unclear
- **Verdict:** **Directly solves P3.** Evaluate via MCP in Claude Code. If license is problematic or we need more control, a cleanroom rewrite is ~700 LOC of well-understood algorithm — cheap insurance.

#### mcp-codebase-index
- **URL:** https://github.com/MikeRecognex/mcp-codebase-index
- **Stars:** 49 | **Language:** Python 3.11+ | **License:** AGPL-3.0
- **What:** Query-oriented codebase index. 18 MCP tools (find_symbol, get_dependencies, get_call_chain, etc.). Not a ranked overview; returns targeted answers.
- **Resources:** M2 Air friendly — CPython (1.1M lines) indexes in 56s, 197MB peak. Sub-ms queries.
- **Solves:** P3 partially — good for on-demand structural queries but no upfront map. Uses Python `ast` (limited multi-language support).
- **Verdict:** Complementary to RepoMapper. RepoMapper gives the overview; mcp-codebase-index gives deep drill-down. Consider as Tier 2 addition if RepoMapper alone proves insufficient.

#### Basic Memory
- **URL:** https://github.com/basicmachines-co/basic-memory
- **Stars:** 2,768 | **Language:** Python | **Status:** Active
- **What:** MCP server storing AI conversations as markdown files with bidirectional links. Knowledge graph from markdown. Semantic + full-text search. SQLite storage.
- **Resources:** Lightweight. Python + SQLite. No ML model required for core.
- **Integration:** MCP server
- **Solves:** P1 (semantic retrieval), P11 (mid-session queries). Markdown-native — plays well with CLAUDE.md patterns.
- **Verdict:** **Strongest dedicated memory tool by adoption.** Direct competitor to mcp-memory-service. Markdown-native approach is more natural for Claude Code workflows. Evaluate head-to-head with mcp-memory-service.

#### Vestige
- **URL:** https://github.com/samvallad33/vestige
- **Stars:** 466 | **Language:** Rust | **Status:** Active
- **What:** Cognitive memory with FSRS-6 spaced repetition, 29 brain modules, 3D dashboard. Single 22MB binary. MCP server.
- **Resources:** Minimal — single Rust binary, no runtime dependencies.
- **Integration:** MCP server
- **Solves:** P4 (mistake avoidance via spaced repetition), P9 (temporal knowledge via FSRS decay), P12 (confidence)
- **Verdict:** Most sophisticated decay model found (FSRS-6 > cass's linear 90-day). Novel approach. Worth evaluating as L3 alternative or complement. Concern: 29 "brain modules" may be over-engineered.

#### Napkin
- **URL:** https://github.com/blader/napkin
- **Stars:** 468 | **Language:** Shell | **Status:** Active
- **What:** Skill giving agent persistent memory of mistakes via per-repo markdown scratchpad. Dead simple.
- **Resources:** Zero — shell scripts only.
- **Integration:** Claude Code skill
- **Solves:** P4 (mistake avoidance — simplest possible implementation)
- **Verdict:** Worth adopting immediately as a Phase A freebie alongside CASS. Zero risk, instant value. Does not replace cq/cass_memory for cross-agent or confidence-tracked knowledge, but provides a floor.

#### Memorix
- **URL:** https://github.com/AVIDS2/memorix
- **Stars:** 351 | **Language:** TypeScript | **Status:** Active
- **What:** Cross-agent memory layer via MCP. Works with Claude Code, Cursor, Codex, Gemini CLI, etc.
- **Resources:** Lightweight. TypeScript + SQLite.
- **Integration:** MCP server
- **Solves:** P6 (cross-agent sharing), P10 (collective intelligence across different agent types)
- **Verdict:** Strongest cross-agent story. Evaluate if hud's parallel pipelines use heterogeneous agents (not just Claude Code). If all agents are Claude Code, cq may suffice.

### Other Notable Finds (Tier 2-3)

| Tool | Stars | What | Verdict |
|------|-------|------|---------|
| claude-code-tools | 1,683 | Session continuity + Tantivy search + cross-agent handoff | Overlaps CASS. Evaluate if CASS falls short. |
| Claude CodePro | 1,610 | Full dev env with cross-session memory | Too opinionated. Memory not extractable. |
| claude-cognitive | 447 | Working memory + multi-instance coordination | Overlaps mcp-memory-service + memorix. |
| Total Recall | 190 | Tiered memory with write gates, correction propagation | Closest to our ensemble architecture. Study for design patterns. |
| Cog | 331 | Episodic + metacognitive memory | Novel but low adoption. Watch. |

---

## Non-Memory Components (Overlap Assessment)

### mcp_agent_mail (1.9k stars)
- **Memory overlap:** None directly. Complementary — enables agents to announce discoveries that should be memorized.
- **Integration:** HTTP MCP server. Git + SQLite persistence.
- **Verdict:** Coordination layer, not memory. But serves P6 (cross-agent sharing) in real-time where cq serves it asynchronously.

### beads_viewer / bv
- **Memory overlap:** Graph analytics (PageRank, bottleneck detection) could inform memory priority. meta_skill integrates with bv for dependency analysis.
- **Verdict:** No overlap. Complementary analytics.

---

## Unsolved Problems

### Repo Map (P3) — SOLVED
**RepoMapper** (see Tier 1 above) directly solves this. Aider's repo map algorithm as standalone MCP server. Tree-sitter + PageRank + token-budget binary search. M2 Air friendly.

**Recommendation:** Adopt RepoMapper as Phase A/B item. If license concerns arise or we need deeper integration with hud's bead/stage model, cleanroom rewrite is ~700 LOC of well-documented algorithm. mcp-codebase-index as complementary drill-down tool.
### Instruction Adherence (P5)
No single tool directly solves this. Mitigations:
1. **Shorter, focused context** — memory retrieval replaces bulk loading (mcp-memory-service or Basic Memory).
2. **Tiered injection** — only inject memories scoring above threshold.
3. **Sleep-time reflection pattern** (from Letta research) — a background process that monitors session activity and proactively injects relevant memories/reminders. The main agent doesn't "remember to remember." **High value, solves a structural gap.** Implementable as a hud hook + lightweight background agent that reads session logs and writes context-relevant reminders. Not a gimmick — this is how Letta Code's memory actually works, and it's the key differentiator. Each parallel agent could have its own reflection process. ~100 LOC glue, no Letta dependency.
4. **read-once** — reduces context window waste, leaving more room for instructions.
5. **Stage-scoped memory** — hud prime queries for stage-relevant memories only.
6. **Vestige's FSRS-6** — spaced repetition naturally surfaces frequently-needed knowledge and lets rarely-used instructions fade. Novel approach to the adherence problem.

### Temporal Knowledge (P9)
Only OpenMemory has temporal reasoning (valid_from/valid_to). Given it's in rewrite:
1. **cq tier graduation** — knowledge units graduate/decay based on usage. Partial solution.
2. **cass_memory_system confidence decay** — 90-day half-life on rules. Better.
3. **Manual invalidation** — tag memories with context, rely on verification before use.

---

## Resource Budget (M2 Air 16GB)

| Component | RAM estimate | Disk |
|-----------|-------------|------|
| Claude Code (running) | ~500MB | — |
| CASS (Rust binary) | ~50MB | ~200MB index |
| cq (Python MCP server) | ~100MB | SQLite |
| mcp-memory-service (Python + ONNX) | ~300MB | ~90MB model + SQLite |
| mcp_agent_mail (Python HTTP) | ~100MB | SQLite + Git |
| claude-handoff (shell) | ~0 | markdown files |
| cass_memory_system (Bun) | ~150MB | — |
| meta_skill (Python) | ~100MB | SQLite + Git |
| RepoMapper (Python + tree-sitter) | ~150MB | ~50MB cache |
| Basic Memory (Python) | ~100MB | SQLite |
| Vestige (Rust binary) | ~30MB | ~22MB binary |
| Napkin (shell) | ~0 | markdown files |
| **Total (recommended set)** | **~1.4GB** | **~450MB** |
| **Total (all layers)** | **~1.7GB** | **~450MB** |

Well within 16GB budget. Leaves ~13GB for OS + Claude Code sessions + other tools.
