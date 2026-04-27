# Architecture Review: Memory Ensemble

> Date: 2026-04-05
> Artefacts reviewed: architecture.md, research.md, idea.md
> Lenses: Ford-Parsons (evolvability), Kua (decision quality), Architecture (fitness)

---

## Ford-Parsons Lens — Evolvability & Implicit Bets

### Fitness Function Audit

| Characteristic                      | Status     | Issue                                                                                                                                                                             |
| ----------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Memory injection size (<500 tokens) | Vague      | No measurement mechanism. Who checks this? How? Not automated.                                                                                                                    |
| Session start latency (<3s)         | Vague      | No measurement pipeline. "Budget: <500ms for memory queries" contradicts the 3s verification criterion. Which is it?                                                              |
| RAM total (<2GB)                    | Measurable | Activity Monitor is named as mechanism — but manual, not a fitness function.                                                                                                      |
| Retrieval relevance                 | Unmeasured | "Score threshold" and "relevance cutoff" mentioned with no definition of what constitutes relevant. This is the *central* architectural characteristic and it has no measurement. |
| Cross-agent knowledge availability  | Unmeasured | Verification criterion #1 but no automated check proposed.                                                                                                                        |

**Verdict:** The architecture's most important properties (relevance, usefulness of injected memories) have no measurement mechanism at all. The quantitative thresholds that do exist (500 tokens, 3s, 2GB) are manual spot-checks, not automated fitness functions.

### Coupling Concerns

- **7 tools × N configuration surfaces**: Each tool has its own config format, storage location, query API, and versioning. The agent must know which tool to query for what. This is **semantic coupling** — the agent's CLAUDE.md instructions become the integration layer. If any tool changes its MCP tool names or query semantics, the agent breaks silently (wrong results, not errors).

- **CASS ↔ cass_memory_system**: L3b depends on L1. If CASS changes its session format or index structure, cass_memory_system breaks. Both are alpha, same author. Tight coupling to an unstable foundation.

- **Sleep-time reflection → L2, L3a, L3b**: The custom reflection process writes to three different stores. It becomes the coupling hub — understanding its behavior requires understanding all three stores' write semantics. A bug here corrupts multiple memory layers simultaneously.

- **hud prime → L2, L3, L4**: Prime queries 3+ systems in parallel. Prime's correctness now depends on the union of all their availability and response characteristics. Any one being slow or returning garbage degrades prime.

### Implicit Bets Extracted

| Bet                                        | Assumption                                                                                                         | Reversibility                                                                             | Risk       |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | ---------- |
| Ensemble of 7 tools                        | Composition of independent tools is manageable for a solo dev                                                      | Expensive — each tool accumulates data, config, learned behaviors                         | **High**   |
| Alpha/0.x tools as foundation              | CASS, cq, cass_memory_system will stabilize without breaking changes                                               | Expensive — data migration, config rewrite per breaking change                            | **High**   |
| "Run both" for L3a/L3b                     | Both cq and cass_memory_system will prove useful enough to justify operational overhead of two overlapping systems | Cheap per tool, but the *decision to defer* is expensive (you build integration for both) | **Medium** |
| SQLite everywhere                          | WAL mode handles all concurrency for 2-10 agents                                                                   | Cheap to verify, but the bet is implicit — no load testing proposed                       | **Low**    |
| MCP protocol stability                     | MCP tool interfaces won't break across tool versions                                                               | Expensive — every tool is an MCP server, protocol changes cascade                         | **Medium** |
| RepoMapper license is fine                 | "100% based on Aider" is legally safe for private use                                                              | Cheap if you cleanroom; expensive if you discover post-adoption                           | **Medium** |
| Sleep-time reflection is worth building    | Custom ~300 LOC glue will produce useful consolidation, not noise                                                  | Cheap to build, expensive to tune — calibration is open-ended                             | **Medium** |
| Single maintainer tools will be maintained | CASS, cass_memory_system, meta_skill, RepoMapper — all single-author                                               | Expensive if abandoned — you inherit maintenance or migrate                               | **High**   |

### Evolution Blockers

- **Config sprawl as a change barrier**: Adding, removing, or replacing a tool requires changes in: MCP config, CLAUDE.md instructions, hud prime queries, sleep-time reflection writes, namespace scoping logic. No single place to make the change. This will actively resist swapping tools as the ecosystem matures.
> COMMENT: agree. can AFB help by composing claude.md based on inclusion of memory components or not? afb.conf sets memory components to install, there is a usr components dir where the user puts install, uninstall, update scripts per the component docs, and a claude.md snippet to be included in claude.md if the component is active, then afb installs it to all accounts?
- **Agent instruction coupling**: The CLAUDE.md instructions ("use Basic Memory for facts, cq for patterns, CASS for history") are a **distributed routing table maintained in prose**. When you add/remove/change a tool, you must update instructions across all agents and hope they comply. This is the kind of coupling that looks free but costs continuously.
> COMMENT: agree. is afb the right place to solve this, also scalably/ solves the general problem to distribute changes to multiple claude accounts?
### Summary Verdict (Ford-Parsons)

The architecture optimizes for coverage (every problem gets a tool) at the expense of evolvability. Adding tools is easy; removing or replacing them is hard because each one accumulates integration points. The ensemble approach makes an implicit bet that **7 alpha/early tools will all stabilize in roughly the same timeframe** — historically unlikely. The architecture would be more evolvable with fewer tools and explicit "replace with X when Y happens" triggers.

---

## Kua Lens — Decision Quality & Reversibility

### Decision Inventory

| Decision                                    | Explicit?                         | Reversibility                                         | ADR? |
| ------------------------------------------- | --------------------------------- | ----------------------------------------------------- | ---- |
| Use ensemble of 7 tools instead of 1-2      | Explicit                          | Expensive (integration sprawl)                        | No   |
| Run both cq AND cass_memory_system          | Explicit but framed as "resolved" | Cheap per tool, but defers real decision              | No   |
| Cleanroom handoff instead of claude-handoff | Explicit                          | Cheap                                                 | No   |
| Basic Memory vs mcp-memory-service          | Deferred                          | Cheap (both are MCP, similar API)                     | No   |
| Build sleep-time reflection custom          | Explicit                          | Cheap to build, unknown to tune                       | No   |
| launchd for MCP lifecycle                   | Explicit                          | Cheap                                                 | No   |
| RepoMapper for P3                           | Explicit                          | Cheap (can cleanroom)                                 | No   |
| Memory namespacing scheme                   | Explicit                          | Expensive (data tagged with scheme is hard to re-tag) | No   |
| Token budget: reference + on-demand model   | Explicit                          | Cheap                                                 | No   |

**Zero ADRs for an architecture with 9+ significant decisions.** The architecture doc itself partially serves this role, but no individual decision has recorded alternatives-considered or cost-to-reverse in structured form.

### Reversibility Flags

- **Ensemble of 7 tools**: Classified implicitly as "incremental, adopt at will." Actually **expensive to reverse** once data accumulates across stores. Removing a tool means migrating or abandoning its data. The more sessions that run, the harder removal becomes.

- **Memory namespace scheme** (global/repo/feature/bead): This is an **effectively irreversible** decision once memories are tagged. Changing the scheme requires re-tagging all existing memories or accepting a break in retrieval. Not acknowledged as such.
> COMMENT: OK, but what is the alternative(s)?
- **cass_memory_system dependency on CASS**: Choosing L3b implicitly commits you to L1's stability. This is an **expensive coupling** disguised as a tool choice.

### Deferral Attractors

| Deferred Decision                  | Trigger Specified?                                 | Risk                                                                                    |
| ---------------------------------- | -------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Basic Memory vs mcp-memory-service | "Head-to-head evaluation needed" — no trigger      | **High** — you may end up running both indefinitely because there's no forcing function |
| Vestige adoption                   | "Evaluate after L3a/L3b stable" — vague trigger    | **Medium** — "stable" is undefined for alpha tools                                      |
| OpenViking reconsideration         | "Research lighter configuration" — no trigger      | **Low** — likely never revisited                                                        |
| Sleep-time reflection calibration  | "Needs empirical tuning" — no trigger              | **High** — "too aggressive vs too conservative" with no metric = indefinite tuning      |
| Telemetry system scope             | "Separate feature or part of memory?" — no trigger | **Medium** — telemetry is prerequisite for calibrating the system you're building       |

**Pattern:** 5 of 5 open questions have no concrete trigger. These will drift. The most dangerous is **telemetry** — you need it to evaluate whether the ensemble is working, but it's deferred as an open question.

### Technology Radar Positions

| Technology                     | Suggested Position | Rationale                                                                             |
| ------------------------------ | ------------------ | ------------------------------------------------------------------------------------- |
| CASS                           | **Trial**          | Alpha, single author, 646 stars. Promising but unproven at scale.                     |
| cq                             | **Trial**          | 0.x, Mozilla "exploratory." May be abandoned or fundamentally redesigned.             |
| cass_memory_system             | **Assess**         | Alpha, single author, depends on another alpha tool. Too early to trial.              |
| Basic Memory                   | **Trial**          | 2.8k stars, active, but untested in your workflow.                                    |
| mcp-memory-service             | **Trial**          | 1.6k stars, active, more mature than most.                                            |
| RepoMapper                     | **Assess**         | 149 stars, single author, license unclear.                                            |
| Vestige                        | **Assess**         | Novel (FSRS-6) but 466 stars, unproven concept.                                       |
| Napkin                         | **Adopt**          | Zero risk, zero infra, immediate value.                                               |
| Sleep-time reflection (custom) | **Assess**         | Unbuilt. Concept validated by claude-subconscious but your version is more ambitious. |

**4 tools at Assess, 4 at Trial, 1 at Adopt.** The architecture proposes to *build on* tools that haven't even reached Trial. This is unusual risk concentration for a solo dev with no fallback team.

### Summary Verdict (Kua)

The document is thorough in listing what it wants to do, but weak in decision discipline. Many "resolved" questions are actually deferrals. The namespace scheme and ensemble commitment are expensive/irreversible decisions treated casually. No ADRs exist. The technology radar profile (mostly Trial/Assess) suggests this is a research spike, not a production architecture — but the phased adoption plan treats it as production-ready.

---

## Architecture Lens — Fitness Functions & Drift

### Missing Fitness Functions

| Property                       | Why It Matters                                                                        | How to Measure                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **Memory retrieval relevance** | The entire value proposition. Irrelevant memories are worse than no memories (noise). | Periodic sample: inject memories, have agent rate usefulness. Track over time. |
| **Memory freshness**           | Stale memories cause wrong decisions (MR2).                                           | Automated scan: flag memories >90 days with no access or confirmation.         |
| **Cross-agent consistency**    | Contradictory facts across stores (MR6).                                              | Scheduled job: extract assertions from L2/L3a/L3b, diff for contradictions.    |
| **Tool availability**          | 7 MCP servers must all be running.                                                    | Health check: launchd + periodic MCP ping.                                     |
| **Instruction compliance**     | Agent must use correct tool for each query type.                                      | Log MCP calls per session, verify routing matches intent.                      |

### Reversibility Assessment

| Decision                                    | Reversibility                        | Notes                                                                             |
| ------------------------------------------- | ------------------------------------ | --------------------------------------------------------------------------------- |
| Adopt 7-tool ensemble                       | Expensive                            | Data in 7 stores, config in 7 places, instructions referencing 7 APIs             |
| Memory namespace (global/repo/feature/bead) | Effectively irreversible             | All tagged data must be re-tagged on change                                       |
| Build custom sleep-time reflection          | Cheap to start, expensive to abandon | Once agents depend on consolidated memories, removing reflection degrades quality |
| launchd for MCP servers                     | Cheap                                | Standard macOS, easy to change                                                    |
| SQLite as storage across tools              | Cheap per tool                       | But migrating away from SQLite means migrating 5+ databases                       |

### Architectural Drift Risk

The ensemble architecture has **no single owner of truth**. When the agent asks "what do I know about X?", the answer is spread across 4+ stores, each with different relevance scoring, confidence models, and freshness semantics. Over time, the stores will **drift apart** — L2 says one thing, L3a says another, L3b has a decayed version of something L2 still considers fresh. There is no reconciliation mechanism beyond the proposed "memory curation sweep," which is itself custom code that hasn't been built or tested.

---

## Direct Answers to Your Questions

### Is it all needed?

**No.** The architecture is over-specified for a solo dev on 1-2 Claude Pro accounts. Specific concerns:

1. **L3a + L3b (cq + cass_memory_system) overlap is real.** "Run both" is not a decision — it's deferring the decision while paying double integration cost. Pick one. If forced: cq for simplicity, cass_memory_system for depth. Running both means two systems that answer "what did we learn?" with potentially conflicting answers.

2. **Three mistake-tracking tools (Napkin + cq + cass_memory_system)** is two too many. Napkin is free, keep it. Pick one of L3a/L3b. Three tools for one problem is not an ensemble — it's indecision.

3. **Sleep-time reflection is ambitious custom code** for a system that doesn't exist yet. You're building a consolidation layer for stores that haven't proven their individual value. Build the stores first. See if you actually need automated consolidation or if manual curation suffices. The ~300 LOC estimate is optimistic — calibration is open-ended.

4. **Basic Memory vs mcp-memory-service** — evaluate and pick one before building the architecture around "whichever." The architecture should commit to a semantic store, not hedge.

5. **meta_skill and Vestige are correctly flagged as optional** but their presence in the architecture doc adds cognitive load. Remove them from the architecture; revisit when the core is stable.

**Minimum viable ensemble:** CASS (L1, session search) + one semantic store (L2, pick one) + cq OR cass_memory_system (L3, pick one) + RepoMapper (L4) + Napkin (L5, free) + cleanroom handoff (L6). That's 5 tools, not 7+. Add the rest only when you have evidence the core isn't enough.

### Are all proposed tools safe to use?

**Mostly, with caveats:**

| Tool                               | Safe?       | Justification                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **CASS**                           | **Caution** | Indexes ALL Claude Code sessions, including those containing credentials, API keys, secrets. The mitigation ("configure exclusions before first index") is one missed step away from indexing sensitive data. CASS also makes session content queryable by any MCP client — expanding the attack surface for sessions containing secrets. Safe if configured correctly; dangerous if misconfigured. |
| **cq**                             | **Yes**     | SQLite local storage, no external calls, no credential handling. Mozilla-backed. Exploratory status means API churn, not safety risk.                                                                                                                                                                                                                                                               |
| **Basic Memory**                   | **Yes**     | Local SQLite + markdown. No external network calls. No credential handling.                                                                                                                                                                                                                                                                                                                         |
| **mcp-memory-service**             | **Yes**     | Local ONNX + SQLite. No external API calls despite having REST endpoints (localhost only).                                                                                                                                                                                                                                                                                                          |
| **cass_memory_system**             | **Caution** | Builds on CASS, inherits its session-indexing risks. Also: Bun runtime is less audited than CPython/Rust for security. Alpha status means less security review. Single author.                                                                                                                                                                                                                      |
| **RepoMapper**                     | **Caution** | License unclear — "100% based on Aider" (Apache 2.0) but unclear if it's a fork or cleanroom. Using it privately is fine; distributing or contributing back could be problematic. The tool itself is safe (tree-sitter parsing, no network calls), but the legal risk is unresolved.                                                                                                                |
| **Napkin**                         | **Yes**     | Shell scripts writing markdown. Zero attack surface.                                                                                                                                                                                                                                                                                                                                                |
| **mcp_agent_mail**                 | **Caution** | HTTP MCP server — listens on a port. On a shared network, this is an attack surface. Messages are unencrypted, unauthenticated. Safe on a private machine; risky on shared/public networks.                                                                                                                                                                                                         |
| **Vestige**                        | **Yes**     | Single Rust binary, local storage, no network.                                                                                                                                                                                                                                                                                                                                                      |
| **Sleep-time reflection (custom)** | **Unknown** | Doesn't exist yet. Safety depends entirely on implementation. The concept of a background process that writes to multiple memory stores unsupervised has inherent risk — a bug or prompt injection in session logs could propagate malicious content into trusted memory stores. Needs careful input validation.                                                                                    |

**Key safety gap:** No tool in the ensemble encrypts data at rest. All use SQLite or markdown files. If the machine is compromised, all memory content (including anything from indexed sessions) is plaintext. For a solo dev on a personal machine this is acceptable risk, but it should be acknowledged.

---

## Summary

The research is thorough and the problem analysis is solid. The architecture suffers from a common pattern: **solving every identified problem with a dedicated tool, rather than solving the most important problems well.** The result is an ensemble that covers all bases but creates its own complexity problem — which is ironic for a system meant to reduce context overhead.

**Highest-priority concerns:**
1. No automated fitness functions for the system's core value proposition (retrieval relevance)
2. Running overlapping tools (L3a+L3b) as a deferred decision, not a resolved one
3. CASS session indexing as a credential exposure vector
4. Namespace scheme is effectively irreversible but not treated as such

**Recommendation:** Cut to a 5-tool core. Ship Phase A with CASS + Napkin only. Evaluate one semantic store and one learning store before committing to the full ensemble. Build telemetry *first* (not Phase E) — you can't calibrate what you can't measure.
