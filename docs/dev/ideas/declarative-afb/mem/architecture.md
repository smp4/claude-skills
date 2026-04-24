# Memory Ensemble Architecture

> Date: 2026-04-05
> Status: Proposal rev 2 — expanded from review comments + additional research
> Depends on: [research.md](research.md) for tool evaluations

---

## Stock Claude Code Compatibility

This architecture **degrades gracefully without hud**. Assessment by layer:

| Layer                                  | Without hud   | Notes                                                               |
| -------------------------------------- | ------------- | ------------------------------------------------------------------- |
| L1 (CASS)                              | Full function | CLI + MCP, indexes all CC sessions regardless                       |
| L2 (Basic Memory / mcp-memory-service) | Full function | MCP server, agent queries directly                                  |
| L3 (cq)                                | Full function | CC marketplace plugin, no hud dependency                            |
| L3b (cass_memory_system)               | Full function | CLI + MCP, standalone                                               |
| L5 (RepoMapper)                        | Full function | MCP server, standalone                                              |
| L6 (Napkin)                            | Full function | CC skill, per-repo                                                  |
| L7 (Vestige)                           | Full function | MCP server, standalone                                              |
| Handoff (cleanroom)                    | Partial       | Without hud: manual skill invocation. With hud: automated via hooks |
| Sleep-time reflection                  | Partial       | Without hud: cron-based. With hud: hook-triggered with bead context |
| Memory-aware prime                     | None          | hud-specific orchestration                                          |
| Namespace scoping                      | None          | Flat memory. Still useful, just less organized                      |

**Bottom line:** 7 of 9 components work fully without hud. The architecture is a general-purpose CC memory ensemble; hud adds orchestration, scoping, and automation on top.

## Constraints Acknowledged

| Constraint                        | Impact on design                                                                                                                                             |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1-2 Claude Pro accounts, no API   | All memory tools must work with Claude Code CLI, not API. MCP servers communicate via stdio/HTTP, not Anthropic API.                                         |
| MacBook Air M2 16GB               | Rules out large local LLMs (Ollama 14B+). ONNX MiniLM (~90MB) is the ceiling for local embeddings. No Qdrant/Neo4j.                                          |
| Free open source only             | All recommended tools are FOSS. OpenViking's AGPLv3 is the only license concern (excluded).                                                                  |
| Glue code OK, not from scratch    | Integration layer between hud and memory tools = glue code. Memory tools themselves are off-the-shelf.                                                       |
| Drop-in solutions only            | Every recommended tool installs via pip/brew/curl and configures via JSON/env vars.                                                                          |
| Prefer well-accepted (many stars) | Prioritized: Basic Memory (2.8k), mcp-memory-service (1.6k), cq (969), CASS (646), Vestige (466), Napkin (468). Stars used as risk proxy, not quality proxy. |
| Solo dev, no distribution         | AGPLv3 is fine for local/private use — no distribution trigger. OpenViking reconsidered below.                                                               |
---

## Ensemble Design

### Layer Model

```
┌───────────────────────────────────────────────────────────────────┐
│                    hud orchestrator (or stock CC)                   │
│  SessionStart ─── prime injects relevant memories                  │
│  PostToolUse ──── checkpoint stores decisions                      │
│  PreCompact ───── handoff captures session summary                 │
│  Background ───── sleep-time reflection consolidates learnings     │
└──┬────────┬────────┬────────┬────────┬────────┬────────┬──────────┘
   │        │        │        │        │        │        │
┌──▼──┐ ┌──▼──┐ ┌──▼──┐ ┌──▼──┐ ┌──▼──┐ ┌──▼──┐ ┌──▼──────┐
│ L1  │ │ L2  │ │ L3a │ │ L3b │ │ L4  │ │ L5  │ │ L6      │
│Sess.│ │Sem. │ │Cross│ │Proc.│ │Repo │ │Mis- │ │Handoff  │
│Hist.│ │Mem. │ │Agent│ │Rules│ │Map  │ │take │ │(clean-  │
│     │ │     │ │Learn│ │     │ │     │ │Pad  │ │ room)   │
│CASS │ │Basic│ │ cq  │ │cass_│ │Repo │ │Nap- │ │hud-built│
│     │ │Mem. │ │     │ │mem. │ │Map- │ │kin  │ │+beads   │
│     │ │     │ │     │ │sys. │ │per  │ │     │ │+mail    │
└─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────┘ └─────────┘
 r/o     r/w     r/w     r/w     r/o     r/w     write→bead
 index   facts   shared  decay   struct  simple  task-bound
 past    +links  know.   rules   map     errors  handovers

              ┌──────────┐          ┌──────────┐
              │ Optional │          │ Optional │
              │ Vestige  │          │ meta_    │
              │ (FSRS-6  │          │ skill    │
              │  spaced   │          │ (skill   │
              │  repet.)  │          │  mgmt)   │
              └──────────┘          └──────────┘
```

### Coordination Layer (Orthogonal)

```
  ┌──────────────┐     ┌──────────────────┐
  │ mcp_agent_   │     │ sleep-time       │
  │ mail         │     │ reflection       │
  │              │     │                  │
  │ real-time    │     │ async background │
  │ inter-agent  │     │ memory consoli-  │
  │ messaging    │     │ dation (hook/    │
  │              │     │ cron triggered)  │
  └──────────────┘     └──────────────────┘
```

### What Each Layer Does
> COMMENT: not clear what the layers themselves are. is each layer a deeper abstration? is it solving a different memory gap? why use this mental model? explain it. use another if after explaining, you find it is lacking. or keep it. but justify it.

**L1: Session History (CASS)**
- Indexes all past Claude Code sessions automatically
- Agents query past sessions for: "has this been tried?", "what files were involved?", "what errors occurred?"
- Read-only — doesn't store new memories, just indexes existing session logs
- Foundation for L3b (cass_memory_system builds on CASS)

**L2: Semantic Memory (Basic Memory — preferred over mcp-memory-service)**
- Persistent fact store as markdown files with bidirectional links
- Knowledge graph built from markdown — natural fit for CC workflows
- Semantic + full-text search. SQLite storage. No ML model for core.
- 2.8k stars — strongest adoption of any dedicated memory tool
- MCP server → agents can query mid-session (solves P11)
- Alternative: mcp-memory-service (1.6k stars) if ONNX embeddings prove more effective than Basic Memory's search. Evaluate head-to-head.

> COMMENT: is vestige optional L2 or L3? it has a sleep-like function to review memories, looksl ike it has semantic retrieval. why are others better? give honest opinion

**L3a: Cross-Agent Learning (cq)**
- Post-error learning loop: agent hits error → cq auto-queries for relevant knowledge
- Agents store: "this approach failed because X", "Y is the correct pattern for Z"
- Cross-agent: knowledge stored by Agent A available to Agent B
- Domain-scoped: knowledge tagged by project/feature/bead
- Weakness: no time-based decay. Complements L3b.

**L3b: Procedural Rules (cass_memory_system)**
- Three-layer cognitive model: episodic → working → procedural
- 90-day confidence decay with 4x harmful multiplier
- Maturity progression: candidate → established → proven → deprecated
- Anti-patterns preserved as warnings rather than deleted
- Builds on CASS (L1) for session access. More fundamental decay model than cq.

**L4: Repo Map (RepoMapper)**
- Aider's repo map algorithm as standalone MCP server
- Tree-sitter + PageRank + token-budget binary search
- Agents get structural overview of files/symbols/relationships without re-exploring
- Solves P3 — the previously unsolved gap

**L5: Mistake Pad (Napkin)**
- Per-repo markdown scratchpad for mistake tracking
- Dead simple, zero infrastructure. CC skill.
- Floor-level P4 solution. Complements L3a/L3b for quick error notes.

**L6: Handoff Chain (cleanroom, hud-built)**
- Structured session handoff documents at session boundaries
- **Cleanroomed** rather than using claude-handoff — coupled with beads + agent_mail for task-bound handovers tied to bead ID, agent identity, stage
- Handoff doc is a first-class bead artifact, routable via agent_mail to next session/agent
- Not floating markdown in a repo — lifecycle-managed by hud

**Sleep-time Reflection (background process)**
- Async background agent reads session logs, consolidates learnings into memory
- Main agent doesn't "remember to remember" — reflection process handles it
- Hook architecture validated by `letta-ai/claude-subconscious` (2.6k stars) — same 4 hooks (SessionStart, UserPromptSubmit, PreToolUse, Stop). We build our own for full control, no Letta dependency.
- Key design borrowed from claude-subconscious: async Stop hook spawns detached worker (doesn't block Claude)
- **Beyond claude-subconscious:** our version adds true periodic reflection (consolidation, pruning, contradiction detection), not just reactive transcript capture
- Each parallel agent can have its own reflection instance
- Writes to L2 (facts), L3a (cross-agent learnings), L3b (procedural rules)
- Also performs **memory curation** (MR6): surfaces contradictions, suggests removals/decay

---

## Integration with hud

### hud prime (SessionStart) — Memory-Aware Context Injection

Current hud prime injects: role, stage context, inputs, expected outputs, constraints, checkpoint chain.

**Enhancement:** Before injection, query memory layers for relevant context.

```
hud prime flow (enhanced):
  1. Read state.json → current bead, stage
  2. Query L2 (Basic Memory) for memories matching bead/stage keywords
  3. Query L3 (cq) for knowledge relevant to current domain/task
  4. Read L4 (handoff chain) for prior session summaries on this bead
  5. Score and rank results, apply token budget cap
  6. Inject: stage context + relevant memories + handoff chain
```
> COMMENT: no napkin in prime?
**Token budget:** Memory injection uses a **reference + on-demand** model, not full-text injection:
- Prime injects **memory references** (title, relevance score, 1-line summary) — ~50 tokens each
- Agent uses MCP tools to retrieve full text of relevant memories on-demand during session
- Reference budget: ~500 tokens (≈10 memory references). Enough to orient the agent without crowding stage instructions.
- Full retrieval happens mid-session via L2/L3 MCP calls, charged against conversation context, not prime injection.
- This keeps prime lean while giving the agent access to deep memory when needed. Configurable per stage type.

> COMMENT: the list above has been adapted based on one of my past review comments. but were you just agreeing with me? i STRONGLY prefer you independently critique my comments and PUSH BACK if you think it is a bad idea based on your knowledge and research. DO NOT BE SYCOPHANTIC. remember this always

### hud checkpoint (PostToolUse) — Decision Capture

Currently a no-op stub (Phase 10 fills in).

**Enhancement:** Decision storage depends on significance level:
- **ADR-worthy decisions** → `docs/dev/adr/` as today. No change.
- **Bead-scoped decisions** (approach chosen for this task, rejected alternatives) → **bead state** via beads. These are planning artifacts that belong to the work unit. Retrievable by any agent working on the same bead.
- **Cross-cutting learnings** ("library X doesn't support Y", "config pattern Z works") → **L3a (cq)** for cross-agent sharing, or **L2 (Basic Memory)** for persistent facts.
- **Real-time announcements** ("I just discovered X, other agents should know") → **agent_mail** for immediate broadcast.

The checkpoint hook detects significance heuristically and routes accordingly. Most decisions are bead-scoped.

```
hud checkpoint flow (enhanced):
  1. Original checkpoint logic (write to .hud/checkpoints/)
  2. If decision detected (heuristic: "decided", "chose", "rejected"):
     → store to L2 with bead/stage/feature tags
  3. If error encountered:
     → cq auto-learns from the error context
```

### hud handoff (PreCompact) — Session Boundary

Currently a no-op stub (Phase 10 fills in).

**Enhancement:** Trigger claude-handoff `/handoff` skill before session dies.

```
hud handoff flow (enhanced):
  1. Original handoff logic (checkpoint + kill + restart)
  2. Before kill: create structured handoff doc (cleanroom L6)
  3. Store handoff as bead artifact (primary) + announce via agent_mail
  4. Optionally index key facts from handoff into L2 for cross-agent retrieval
```

**Where handoffs live:** Primary storage is the **bead** — the handoff is a first-class artifact of the work unit, routed via agent_mail to the next session/agent. This is the right fit because handoffs are task-bound (same bead, next session) not global knowledge.

**L2 indexing is secondary and selective:** Only cross-cutting facts extracted from the handoff go to L2 (e.g., "discovered that API X requires auth header Y"). This serves retrospectives, doc writing, and review stages that need to query across bead boundaries. The sleep-time reflection process (not the main agent) handles this extraction — the main agent just writes the handoff doc.

### Memory Namespacing for Parallel Agents

hud runs parallel beads. Memory must be scoped:

```
Memory scopes:
  global/                    ← cross-project knowledge (language patterns, tool behaviors)
  repo/<name>/               ← project-level facts, all agents on this repo see
  repo/<name>/feature/<slug>/  ← feature-level, all beads in feature see
  repo/<name>/bead/<id>/       ← bead-specific, only this bead's agents see
```

**Non-hud usage:** Without hud, only `global/` and `repo/<name>/` scopes are meaningful. Tools tag memories with repo name (derived from git remote or directory). Feature/bead scoping is hud-specific enrichment.

**Multi-repo layout:** If user manages repos via hud at `~/hud/<repo>/`, the namespace naturally maps. Memory tools don't need to know about the directory layout — scoping is via tags/domains, not filesystem paths.


**Implementation:**
- L2 (Basic Memory): tag memories with scope prefix in markdown frontmatter/links
- L3a (cq): use domain field for scope
- L3b (cass_memory_system): workspace binding for scope
- L1 (CASS): sessions already associated with worktree/branch
- L4 (RepoMapper): per-repo index, no scoping needed
- L6 (Handoff): bead artifact, inherits bead scope

### Concurrency Model

| Scenario          | L1 (CASS)       | L2 (Basic Mem)      | L3a (cq)               | L3b (cass_mem)         | L4 (RepoMapper)  | L6 (Handoff)          |
| ----------------- | --------------- | ------------------- | ---------------------- | ---------------------- | ---------------- | --------------------- |
| Parallel reads    | Safe (Tantivy)  | Safe (SQLite WAL)   | Safe (SQLite)          | Safe (append-only)     | Safe (diskcache) | Safe (files)          |
| Parallel writes   | N/A (read-only) | Serialized (SQLite) | Serialized (SQLite)    | Append-only log        | N/A (read-only)  | Per-bead dirs         |
| Cross-agent query | Safe            | Safe                | Safe (designed for it) | Safe (shared playbook) | Safe             | N/A                   |
| Write contention  | None            | Low (WAL mode)      | Low (WAL mode)         | None (append)          | None             | None (separate files) |

SQLite WAL mode handles concurrent reads with serialized writes. Good enough for 2-10 parallel agents. Not a bottleneck until hundreds of agents.

---

## Adoption Strategy

### Phase A: Foundation (Immediate, no code changes)

1. Install CASS: `brew install dicklesworthstone/tap/cass`
2. Install cq: `claude plugin install cq`
3. Install Napkin skill to `~/.claude/skills/`
4. Install read-once (already planned)
5. Configure as launchd services (base infra, not hud-managed)

Zero hud code changes. Agents get session search, collective learning, mistake tracking, duplicate-read prevention immediately. Works with stock CC.

### Phase B: MCP Integration (No hud code changes)

1. Install Basic Memory MCP server (evaluate vs mcp-memory-service)
2. Install RepoMapper MCP server
3. Install cass_memory_system (optional, evaluate need)
4. Configure all as MCP servers in `.claude/settings.json`
5. Agents can now query/store memories + get repo maps mid-session

Still no hud code changes — MCP servers available to agents automatically.

### Phase C: hud prime Memory Injection (Medium code change)

1. Enhance `hud prime` to query L2 + L3 for memory references
2. Add reference-based injection (~500 tokens, summaries not full text)
3. Add memory scope tagging (global/repo/feature/bead)
4. Build telemetry hooks to measure injection size + retrieval latency

Requires hud code changes: `service/prime.py` and `hooks/prime.py`.

### Phase D: Handoff + Reflection (Medium code change)

1. Build cleanroom handoff (L6) coupled with beads + agent_mail
2. Implement sleep-time reflection as background hook (~100 LOC glue)
3. Wire cq post-error learning into hud's retry flow
4. Add memory curation sweep (periodic contradiction detection)

Can proceed independently of Phase 10 — handoff is now bead-native, not dependent on checkpoint stubs.

### Phase E: Calibration (After Phases C+D)

1. Tune token budgets based on telemetry data
2. Calibrate sleep-time reflection aggressiveness
3. Evaluate Vestige (FSRS-6) as L3 complement
4. Head-to-head Basic Memory vs mcp-memory-service
5. Consider OpenViking if resource headroom allows

---

## Deep Critique

### Advantages

1. **Incremental adoption** — Phase A requires zero code. Agents benefit immediately.
2. **Resource-light** — ~1.7GB RAM total (all layers). Fits M2 Air with room to spare.
3. **Layered resilience** — any single layer can fail without breaking others. CASS down? L2/L3 still work.
4. **Standards-based** — MCP protocol for L2/L3. Skills for L4. CLI for L1. No proprietary integration.
5. **Composable with hud** — hooks architecture gives natural injection points.
6. **Cross-agent by design** — cq and mcp_agent_mail specifically designed for multi-agent.

### Disadvantages

1. **No unified query interface** — querying "what do we know about X" hits 4+ different systems with different APIs. Agent must know which layer to query. CLAUDE.md instructions mitigate but don't eliminate.
> COMMENT: Do we need to add routing logic - for information storage, and information retrieval, across the different systems?
2. **Configuration sprawl** — each tool has its own config: CASS (`.config/cass/`), cq (`cq.toml`), Basic Memory (MCP config), RepoMapper (MCP config), Napkin (skill files). No single config file.
> COMMENT: can we use/ adapt AFB (~/projects/claude-skills) to help manage/solve universal install, manage,config,update, uninstall?
3. **Layer count** — 6 core layers + 2 optional + 2 coordination processes. Cognitive overhead for the operator. Mitigated by incremental adoption (Phase A → E).
4. **L3a/L3b overlap** — cq and cass_memory_system both handle learned knowledge. Roles are now defined (cq = cross-agent sharing, cass = procedural decay) but agents may still be confused. Requires clear CLAUDE.md instructions.
5. **MCP server startup cost** — 4-5 MCP servers add latency to session start. Each needs Python/Bun/Rust runtime initialization. Estimate: ~2-5s per server cold start. Mitigated by launchd (always-running).
6. **Alpha/exploratory status** — CASS (alpha), cq (0.x), cass_memory_system (alpha). Breaking changes likely. Pin versions.
7. **Two custom builds** — cleanroom handoff (L6) and sleep-time reflection require ~300 LOC glue code. Low effort but still custom code to maintain.

### Risks

| #    | Risk                                       | Likelihood | Severity | Mitigation                                                                                                                                                                                                                                                                                                                                                                              |
| ---- | ------------------------------------------ | ---------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| MR1  | Memory noise drowns useful context         | Medium     | High     | Token budget cap on memory injection. Score threshold. Only inject memories above relevance cutoff.                                                                                                                                                                                                                                                                                     |
| MR2  | Stale memories cause wrong decisions       | Medium     | High     | cq has tier graduation. cass_memory has confidence decay. For L2: agent instructions to verify before acting on recalled facts.                                                                                                                                                                                                                                                         |
| MR3  | Bad patterns enshrined via CASS            | Low        | Medium   | CASS indexes sessions including hallucinated ones. cq's scientific validation gate helps — rules need historical evidence.                                                                                                                                                                                                                                                              |
| MR4  | Resource contention on M2 Air              | Low        | Medium   | Total ~1.7GB RAM (all layers). Monitor with Activity Monitor. Kill optional layers (meta_skill, Vestige, cass_memory) if needed.                                                                                                                                                                                                                                                        |
| MR5  | Version churn breaks integration           | Medium     | Medium   | Pin versions. hud CI should test against pinned versions. Adapter pattern for each memory layer (like hud's existing adapter architecture).                                                                                                                                                                                                                                             |
| MR6  | Parallel agents store contradictory facts  | Low        | High     | Scope memories by bead. Cross-bead facts require human review or confidence weighting. **Memory curation process:** periodic (daily or every N sessions) background sweep scans all layers, surfaces contradictions, suggests removals/decay, presents to user. Natural extension of sleep-time reflection — a "memory hygiene" pass. Low effort, high value for long-running projects. |
| MR7  | Memory injection adds latency to prime     | Medium     | Low      | Query L2/L3/L4 in parallel. Cache results for session duration. Budget: <500ms total for memory queries.                                                                                                                                                                                                                                                                                |
| MR8  | Agent confusion from multiple memory tools | Medium     | Medium   | Consolidate MCP tool names. Add instructions to CLAUDE.md: "use Basic Memory for facts, cq for learned patterns, CASS for session history, RepoMapper for code structure."                                                                                                                                                                                                              |
| MR9  | hud prime becomes too complex              | Medium     | Medium   | Memory injection as optional, independently testable module. Feature flag to disable. Adapter pattern for each memory source.                                                                                                                                                                                                                                                           |
| MR10 | Sleep-time reflection writes noise         | Medium     | Medium   | Reflection agent has strict prompt: only extract cross-cutting facts, not task-specific trivia. Human review gate for first N sessions until calibrated.                                                                                                                                                                                                                                |

### Edge Cases

1. **Agent writes contradictory memory mid-session** — Agent A stores "use pattern X"; Agent B stores "pattern X causes Y bug" during overlapping sessions. Resolution: cq's confidence system will surface both with evidence. Agent must judge.

2. **Handoff chain grows unbounded** — Long-running features accumulate many handoff docs. Claude-handoff's chain tracking helps, but injection of full chain eventually exceeds token budget. Resolution: summarize old handoffs. Only inject latest N.

3. **CASS indexes private/sensitive sessions** — All Claude Code sessions indexed, including ones with credentials or secrets. Resolution: CASS respects `.gitignore`-style exclusions. Configure before first index.

4. **cq knowledge from branch-specific context** — Agent learns "config is at path X" in bead's worktree. Different bead has different structure. Resolution: **two-tier knowledge classification** at write time:
   - **Portable knowledge** (language patterns, API behaviors, tool quirks) → tagged `repo/<name>/` scope, visible to all features/beads. Example: "pytest-asyncio requires `@pytest.mark.asyncio` decorator" generalises across features.
   - **Context-bound knowledge** (file paths, config locations, branch-specific state) → tagged `repo/<name>/bead/<id>/` scope. Example: "config is at `src/config.py`" may not be true in another feature's worktree.
   - The **sleep-time reflection process** handles this classification — the main agent just stores knowledge; the reflection agent decides portability based on content analysis. cass_memory_system's maturity progression (candidate → established) also helps: knowledge confirmed across multiple beads graduates to repo scope naturally.
5. **Memory system bootstrapping** — Fresh install = empty memories. Cold start problem. Resolution: CASS immediately indexes existing session history (if any). cq's `/cq:reflect` mines current sessions for knowledge. mcp-memory-service starts empty but grows organically.

6. **Two agents query same memory simultaneously during write** — SQLite WAL mode: readers see consistent snapshot even during writes. Not a real issue.

---

## Comparison to Alternatives

### Why not a single comprehensive system?

**OpenMemory** (3.9k stars) aims to be comprehensive: episodic, semantic, procedural, emotional, reflective memory. Why not just use it?

1. **In major rewrite** — breaking changes expected. Can't build on shifting foundation.
2. **Heavier than ensemble** — requires more configuration for features we may not need.
3. **No agent-session integration** — doesn't index Claude Code sessions natively.
4. **Single point of failure** — if OpenMemory is down, all memory is gone. Ensemble degrades gracefully.

**Revisit when OpenMemory hits v1.0.** If it stabilizes and covers CASS + cq + mcp-memory-service functionality, consolidation makes sense.

### Why not just enhanced CLAUDE.md / auto-memory?

Claude Code's built-in auto-memory (the system we're using right now in this session) is:
- Flat file, no semantic search
- No cross-agent sharing
- No confidence/decay
- No on-demand mid-session retrieval
- No session history search

It's a good starting point but doesn't scale to hud's parallel agent model.

---

## Resolved Questions

1. **Repo map gap** — **Resolved.** RepoMapper (L4) solves P3. Standalone MCP, Aider algorithm. Cleanroom rewrite as fallback (~700 LOC).

2. **cq vs cass_memory_system overlap** — **Resolved: run both, different roles.**
   - cq (L3a): cross-agent knowledge sharing. Lightweight, CC marketplace plugin, fast to deploy. Owns "what did we learn?"
   - cass_memory_system (L3b): procedural rules with confidence decay. Owns "how should we behave?" More fundamental model (90-day decay, maturity progression, anti-pattern tracking).
   - Trade: cq is easier to deploy but has no decay (stale knowledge festers). cass has better architecture but solo-maintainer bus factor. Running both gives redundancy and complementary strengths. If forced to pick one: cass for solo work (deeper model), cq for teams (cross-agent first-class).

3. **MCP server lifecycle** — **Resolved: base infrastructure, not hud-managed.**
   - Memory servers are system services (launchd on macOS). Always running. hud discovers and uses them if present, degrades gracefully if absent.
   - Non-hud CC sessions benefit equally.
   - Install/config is a one-time setup step, not per-session.

4. **Memory migration** — **Accepted risk.** Pin versions. SQLite databases are portable. Export/import as last resort. Hope for upstream migration paths. Monitor changelogs.

5. **Token budget split** — **Empirical tuning needed.** 
   - Add a **hud telemetry/logging system** to record: memory injection size, retrieval latency, agent success rate, token usage per stage. Essential for self-monitoring and improvement beyond just memory tuning. This is a separate feature worth tracking as its own bead.

6. **claude-handoff low stars** — **Resolved: cleanroom instead.** Build task-bound handoff coupled with beads + agent_mail. More control, better integration, low effort (~200 LOC).

7. **Phase ordering** — **Resolved: ASAP.** Token/quota/quality savings compound. Memory integration before Phase 7 (skills) and Phase 8 (dogfood). Phase A (install tools) can happen immediately with zero code changes.

## Remaining Open Questions

1. **Basic Memory vs mcp-memory-service** — head-to-head evaluation needed. Basic Memory has more stars and markdown-native approach; mcp-memory-service has ONNX embeddings. Which produces better retrieval for code-related facts?
2. **Vestige adoption** — FSRS-6 spaced repetition is novel and promising. Worth adding to the ensemble or too many moving parts? Evaluate after L3a/L3b are stable.
> COMMENT: put vestige in the deployment plan. 
3. **OpenViking reconsideration** — AGPLv3 is fine for solo dev. Tiered context loading concept is interesting. Resource requirements (VLM + embeddings) may still be too heavy for M2 Air. Research lighter configuration.
4. **Sleep-time reflection calibration** — how aggressive should the background consolidation be? Too aggressive = noise. Too conservative = missed learnings. Needs empirical tuning.
5. **Telemetry system scope** — memory metrics, agent success rates, token usage, latency. Separate feature or part of memory ensemble?
> COMMENT: should be the first thing built? then we can measure effect of each new component added? not clear to me where the data is stored, what, when, how it is processed. highlights general problem of observability of the LLM for improvement, not just for memory, but also for improving skills etc. when we implement the telemetry system, can we build it generically enough we can use it for other observability and improvement? do you think this is a fit for AFB, or hud? (i think afb, since it is infra, independent of hud, which is a pipeline/workflow tool). challenge my ideas, give honest assessment.
---

## Verification

Architecture is successful when:

1. Agent in bead A can retrieve knowledge stored by agent in bead B (cross-agent, P6)
2. Session restart loads relevant memories without re-exploring codebase (P1, P8)
3. Post-error, agent receives relevant past failure knowledge before retrying (P4)
4. Memory references injected at prime stay under ~500 tokens; full retrieval is on-demand (P5 mitigation)
5. All memory servers run simultaneously within 2GB RAM total (constraint)
6. Session start latency increases by <3s from memory queries (MR7)
7. Agent can query memories mid-session via MCP (P11)
8. Repo structure available to agent without re-exploration (P3, via RepoMapper)
9. Sleep-time reflection produces useful cross-cutting facts, not noise (calibration metric)
10. Memory curation sweep surfaces contradictions before they cause wrong decisions (MR6)
11. Architecture works with stock Claude Code (no hud) for layers L1-L5 (degradation test)

---

## Addendum: Telemetry & Feedback System

> Date: 2026-04-05
> Status: Proposal — addendum to architecture rev 2
> Origin: Mostly original synthesis. Draws on cognitive science memory research (Ebbinghaus, Tulving), RAG evaluation frameworks (RAGAS precision/recall/faithfulness triad), information retrieval implicit feedback (click-through analogy), and caching theory (hit rate). I'm not aware of a published "agent memory telemetry framework" — the space is too new. The behavioral signal approach (observing agent actions as implicit feedback on memory quality) is my adaptation of IR implicit feedback to agent behavior. The re-work avoidance framing is my own — analogous to cache hit rates but applied to agent cognition rather than data retrieval.

### The Measurement Problem, From First Principles

#### What memory does

Memory stores and retrieves information to influence future behavior. A memory system is working when:

1. The right information comes back (**relevance**)
2. It comes back when needed, not before or after (**timing**)
3. What comes back is true and current (**accuracy**)
4. The retrieved memory actually changes behavior for the better (**impact**)
5. The cost of remembering < the cost of not remembering (**economy**)

The fundamental challenge: **you don't have ground truth.** You don't know which memories *should* have been retrieved. You can't observe the counterfactual — what the agent *would* have done without memory. This is a causal inference problem and it doesn't have a clean solution for a solo dev running production workloads.

#### How cognitive science measures memory

In cognitive science (Tulving's episodic/semantic distinction, Ebbinghaus's forgetting curves), memory effectiveness is assessed via:

| Cognitive measure                                   | Agent analogue                                                | Measurable?                                              |
| --------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------- |
| **Recall** — retrieve X when prompted               | Agent retrieves relevant memory when facing known problem     | Partially — can log retrievals but not missed retrievals |
| **Recognition** — identify X when shown             | Agent uses injected memory rather than re-discovering         | Yes — behavioral signal                                  |
| **Transfer** — knowing X helps with Y               | Memory from task A improves performance on task B             | Hard — requires controlled comparison                    |
| **Interference** — knowing X hurts Z                | Stale/wrong memory causes agent to make worse decisions       | Observable post-hoc only                                 |
| **Forgetting curve** — retrieval degrades over time | Decay/confidence systems appropriately reduce stale knowledge | Measurable in stores with decay (L3b)                    |

Key insight from cognitive science: **you can't measure recall completeness** (what was missed) without ground truth. You *can* measure recall precision (of what was retrieved, how much was useful) and behavioral change (did the agent act differently because of memory).

#### The counterfactual problem

The ideal test: run the same task with and without memory, compare outcomes. For a solo dev, this is impractical as a routine measure. But it *is* practical as an occasional calibration:

- **Calibration sessions**: Every N sessions (monthly?), run a known task with memory disabled. Compare: tool calls, file reads, errors, time to completion. This gives a ground-truth comparison point, but infrequently.
- **Shadow scoring**: Log what memory *would have* injected but don't inject it. Check post-hoc whether the agent needed it. Cheap but only tests recall, not impact.

### Proposed Metrics

Three tiers: **instrument everything cheap**, **compute derived signals**, **sample for ground truth**.

#### Tier 1: Raw Instrumentation (automatic, every session)

These are cheap to collect and provide the foundation for all derived metrics.

| Metric                       | Source              | What it captures                            |
| ---------------------------- | ------------------- | ------------------------------------------- |
| `mem.retrieved.count`        | MCP call logs       | Number of memories retrieved per session    |
| `mem.retrieved.tokens`       | MCP call logs       | Total tokens of retrieved memory content    |
| `mem.injected.count`         | hud prime logs      | Memory references injected at session start |
| `mem.injected.tokens`        | hud prime logs      | Token count of prime memory injection       |
| `mem.stored.count`           | MCP call logs       | New memories written per session            |
| `mem.query.latency_ms`       | MCP call logs       | Per-query retrieval latency                 |
| `mem.prime.latency_ms`       | hud prime logs      | Total memory query time during prime        |
| `session.file_reads`         | Tool call logs      | Files read per session (paths + count)      |
| `session.tool_calls`         | Tool call logs      | Total tool invocations per session          |
| `session.errors`             | Tool call logs      | Errors encountered per session              |
| `session.tokens_used`        | CC session metadata | Total tokens consumed                       |
| `session.duration_s`         | CC session metadata | Wall-clock session time                     |
| `mem.store.size`             | Periodic scan       | Row/file count per memory store             |
| `mem.store.age_distribution` | Periodic scan       | Age histogram of stored memories            |

**Implementation**: A lightweight logger (hud hook or standalone) that tails MCP call logs and CC session logs, extracts these metrics, writes to a local SQLite database. ~50-100 LOC. No ML, no external dependencies.

#### Tier 2: Derived Behavioral Signals (computed from Tier 1)

These are the actual indicators of whether memory is working. Each addresses a specific aspect of the memory problem.

**Signal 1: Re-exploration Rate (economy)**

```
re_exploration_rate = (file reads repeated from prior sessions) / (total file reads)
```

Source: Compare `session.file_reads` against CASS-indexed prior sessions on the same repo.

- **Decreasing over time** → memory is reducing redundant work (good)
- **Flat or increasing** → memory isn't preventing re-discovery (problem)
- **Caveat**: Some re-reads are legitimate (file changed since last session). Filter by comparing file mtime against last-read timestamp. Only count re-reads of unchanged files.

**Signal 2: Mistake Repetition Rate (accuracy + impact)**

```
mistake_repetition_rate = (errors matching stored learnings) / (total errors)
```

Source: Match `session.errors` against L3a/L3b stored knowledge. Fuzzy match on error message + context.

- **Low rate** → mistake-avoidance memory is working
- **High rate** → learnings aren't being retrieved or aren't effective
- **Caveat**: Matching is fuzzy — false positives (different error, similar message) and false negatives (same root cause, different surface error). Accept noise in this metric; look at trends, not absolutes.

**Signal 3: Memory Utilization Rate (relevance)**

```
utilization_rate = (memories retrieved and subsequently referenced in agent output) / (memories retrieved)
```

Source: Cross-reference retrieved memory content against agent's subsequent tool calls and output.

- **High utilization** → retrieved memories are relevant, agent acts on them
- **Low utilization** → retrieval is returning noise that gets ignored
- **Caveat**: This is the hardest signal to compute reliably. "Referenced" requires semantic matching between memory content and agent behavior — essentially a classifier. A crude proxy: did the agent call any tool related to the memory's topic within N turns of retrieval? Even this proxy has uncertainty — I'm not confident it's reliable enough to act on without human validation. **Uncertainty: may need to fall back to periodic human review.**

**Signal 4: Memory-Assisted Orientation Speed (timing)**

```
orientation_speed = (tool calls before first productive action) / (baseline without memory)
```

Source: Count tool calls at session start before the agent begins "real work" (first write, first test run, first commit). Compare against sessions without memory or early sessions before memory was populated.

- **Fewer orientation calls** → memory is helping the agent ramp up faster
- **No change** → memory isn't reducing startup cost
- **Caveat**: "Productive action" is hard to define automatically. Heuristic: first Edit/Write tool call, or first test execution. This will misclassify read-heavy review sessions. **Uncertainty: this heuristic needs empirical validation.**

**Signal 5: Memory Freshness Health (accuracy)**

```
stale_memory_rate = (memories >90 days with zero retrievals) / (total memories)
contradiction_rate = (detected contradictions across stores) / (total assertions)
```

Source: Periodic scan of all memory stores.

- **Rising stale rate** → memory is accumulating dead weight
- **Rising contradiction rate** → stores are drifting apart (the ensemble coordination problem)
- **Caveat**: Zero-retrieval memories aren't necessarily stale — they may be rare-but-valuable. A memory about an uncommon error pattern might sit unused for months until that error recurs. Don't auto-delete; surface for human review.

#### Tier 3: Ground Truth Sampling (periodic human review)

Automated metrics tell you *what's happening*. Only human review tells you *whether it's good*. This tier is expensive but essential for calibrating Tier 2 signals.

**Review 1: Retrieval Quality Audit (monthly)**

Sample 10 memory retrievals from the past month. For each:
- Was the retrieved memory relevant to the task? (precision)
- Was there a memory that should have been retrieved but wasn't? (recall — requires checking stores manually)
- Was the memory accurate/current? (freshness)
- Did the agent act on it? (impact)

Score each 0/1. Track precision and recall over time. This is the **only reliable relevance metric** — everything in Tier 2 is a proxy.

**Review 2: Memory Quality Audit (monthly)**

Sample 10 recently stored memories. For each:
- Is this worth remembering? (signal vs. noise)
- Is it correctly scoped? (global vs. repo vs. bead)
- Is it accurate? (check against current code/state)
- Is it duplicated in another store? (ensemble overlap)

This catches the sleep-time reflection noise problem (MR10) and the cross-store drift problem.

**Review 3: Calibration Session (quarterly)**

Run a known task (e.g., fix a seeded bug in a test repo) with memory enabled and disabled. Compare:
- Total tool calls
- Total tokens consumed
- Time to completion
- Error count
- Final outcome quality

This is the closest thing to a controlled experiment. Quarterly is enough to detect systemic drift; more often is impractical.

### Feedback Loops

Metrics without feedback loops are dashboards — interesting but not actionable. Each signal needs a response.

| Signal                                | Threshold                      | Response                                                                                                                                                        |
| ------------------------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Re-exploration rate >50%              | After 5+ sessions on same repo | Review: are memories being stored for re-explored content? If stored but not retrieved, retrieval is broken. If not stored, storage trigger is missing.         |
| Mistake repetition rate >20%          | After 10+ stored learnings     | Review: are learnings being retrieved? If yes but ignored, the learning is too vague or the agent doesn't trust it. If not retrieved, query/matching is broken. |
| Memory utilization rate <30%          | After 20+ retrievals           | Tighten retrieval threshold. Too many low-relevance memories being returned.                                                                                    |
| Stale memory rate >40%                | After 90 days of operation     | Run curation sweep. Surface candidates for removal.                                                                                                             |
| Contradiction rate >5%                | Any time                       | Immediate review. Contradictions actively degrade trust.                                                                                                        |
| Prime latency >3s                     | Any session                    | Investigate slowest query. Consider caching or reducing query count.                                                                                            |
| Memory store growth >50 memories/week | Sustained                      | Review storage triggers. Likely storing trivia.                                                                                                                 |

### What This System Does NOT Measure

Being honest about blind spots:

1. **Negative impact of wrong memories.** If a stale memory causes the agent to make a wrong decision, this shows up as a task failure — but the failure isn't attributed to the memory system. You'd need to trace the causal chain: memory retrieved → agent relied on it → decision was wrong → because memory was stale. This requires post-hoc analysis, not automated metrics.

2. **Opportunity cost.** The tokens spent on memory retrieval could have been spent on more context, more tool calls, or a longer conversation. There's no way to measure whether the memory system is a better use of those tokens than the alternative.

3. **Agent trust calibration.** The agent should trust fresh, high-confidence memories and verify stale ones. Whether the agent is correctly calibrating its trust in memories is not measurable from outside — it requires inspecting the agent's reasoning, which is opaque.

4. **Cross-agent transfer quality.** When Agent B uses knowledge from Agent A, did it help? The behavioral signals above measure individual session quality but don't isolate cross-agent transfer specifically.

### Implementation

**Phase 1 (with Phase A of main architecture):** Raw instrumentation only. Hook into CC session logs and MCP call logs. Write to SQLite. ~100 LOC.

**Phase 2 (with Phase C):** Derived signals. Compute re-exploration rate and mistake repetition rate. These require CASS integration (compare current session against history). ~200 LOC.

**Phase 3 (with Phase D):** Full feedback loops. Automated threshold alerts. Monthly review prompts. Calibration session tooling. ~100 LOC + human process.

**Total:** ~400 LOC glue code + a SQLite database + a monthly 30-minute human review.

### Risks & Downsides

| #   | Risk                                       | Severity | Detail                                                                                                                                                                                                                               |
| --- | ------------------------------------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| T1  | **Goodhart's Law**                         | High     | If you optimize for "fewer re-reads," agents might skip reading files they *should* re-read because the file changed. The metric incentivizes less reading, not better reading. Mitigation: filter re-reads of unchanged files only. |
| T2  | **Measurement overhead**                   | Low      | Logging adds I/O per session. SQLite writes are fast. Estimate: <50ms per session. Negligible.                                                                                                                                       |
| T3  | **Metric gaming by sleep-time reflection** | Medium   | If the reflection process is tuned to improve metrics (e.g., "store fewer memories to reduce stale rate"), it may under-store useful knowledge. Keep reflection and telemetry independent — reflection should not read telemetry.    |
| T4  | **Human review fatigue**                   | Medium   | Monthly reviews require discipline. If skipped, Tier 2 signals drift uncalibrated. Mitigation: automate the sampling and presentation. Human just rates 0/1.                                                                         |
| T5  | **False confidence from proxy metrics**    | High     | Tier 2 signals are proxies. A system that looks good on re-exploration rate but delivers irrelevant memories will show "improving" metrics while actually degrading agent performance. Only Tier 3 catches this. Don't skip Tier 3.  |
| T6  | **Bootstrap problem**                      | Low      | No metrics until memories exist. First ~10 sessions have no baseline. Accept this; don't try to measure from day 1.                                                                                                                  |

### Uncertainties I Want to Flag

1. **Memory utilization rate (Signal 3) may not be computable.** Matching "agent used this memory" from behavioral signals requires semantic analysis that may be too noisy to be useful. I proposed it because it's the most direct relevance measure, but I have low confidence it will work in practice. May need to fall back entirely to Tier 3 human review for relevance measurement.

2. **Re-exploration rate filtering is fragile.** Distinguishing "re-read unchanged file" from "re-read changed file" requires tracking file mtimes across sessions. If files change frequently (active development), the filter excludes most re-reads and the signal becomes too sparse. This metric may only be useful for slow-moving codebases or across long time windows.

3. **Monthly review sample size (10) may be too small.** With potentially hundreds of retrievals per month, 10 is a 5-10% sample. Statistical significance requires larger samples or longer observation periods. But larger samples increase review burden. I don't have a good answer here — it's a tradeoff between measurement quality and human effort.

4. **I don't know how to measure cross-agent transfer specifically.** The behavioral signals measure individual session quality. If Agent B benefits from Agent A's stored knowledge, it shows up as "Agent B had fewer re-reads" — but I can't attribute that to the cross-agent memory vs. Agent B being better at the task. For the parallel-agent use case (hud's core scenario), this is a significant blind spot.

5. **Calibration sessions (Tier 3, Review 3) require a reproducible task.** Real tasks vary too much for controlled comparison. A synthetic test repo with seeded bugs is reproducible but may not represent real workloads. I'm not confident the calibration sessions will produce actionable signal vs. noise from task variation.

## USER QUESTIONS

> COMMENT: there shall be a very simple, direct way to turn all memory off, or memory on/ off by system. config flags, slash command, a menu, ...
> COMMENT: give your assessment on whether this memory system should live at the infra level (at claude-code or afb level) or hud level? where should memory be managed? my feeling is that this is enough customisation, and there is enough coupling risk, that it should be managed by AFB (useful to hud, but also to other services), rather than as part of hud. hud can make use of the infra if installed with its own dedicated add-ons (context handoff etc). for context, see afb we are developing at ~/projects/claude-skills.
> COMMENT: User needs a simple mechanism to pin versions and update, for externally developed systems