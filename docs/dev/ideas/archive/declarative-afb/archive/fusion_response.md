## Architecture: Portable, Ephemeral, Tool-first Multi-runtime Agenting

> COMMENT: this analysis was created by a prompt very similar to @promp0.md.
> COMMENT: this analysis by open router fusion (https://openrouter.ai/labs/fusion) using free tier models (ling-2.6-1T free, Hy3 preview, Ling-2.6-flash). The results SHALL NOT Be considered particularly well thought out. but they give interesting ideas.
> COMMENT: when reviewing, criticsing, augmenting this analysis, DO NOT GET DISTRACTED by existing material in the present repo. Here, we are EXPLICITLY considering an entirely new generation of solution to claude-skills/ afb, with lessons learned from crafting and using these tools.

This design enforces portability, ephemeral sessions/agents, automated failover, and project-level configuration using existing, maintained tools. It avoids unmaintained single-author repos and custom libraries in favor of composable off-the-shelf systems.

---

## 1. Core Principles (Non-negotiable)
- **Portability first**: A single canonical config defines agents, skills, workflows, and model failover. Per-runtime configs are generated from it.
- **Ephemeral agents & sessions**: No runtime-local persistent state. Sessions are short-lived; outcomes are recorded externally and discarded.
- **Minimal coordination surface**: One durable task/queue primitive (Beads) plus standard pub/sub and storage. Avoid heavyweight agent frameworks.
- **Never depend on compaction**: Continuously externalize decisions, summaries, and next steps. On high context usage, trigger a handoff, not compaction.
- **Project-level config only**: All agent config/skills/workflows live in `./ai/` inside each project, not in user-wide runtime directories.

---

## 2. Source of Truth and Config Portability
- **Canonical store**: `./ai/canonical.toml` (project-local) defines:
  - Agent definitions and capability requirements
  - Model provider priorities and per-model rate-limit thresholds
  - MCP servers to load (search, LSP, AstGrep, Task, Redis, Mem0, etc.)
  - Workflow references and policy rules
- **Templates**: Lightweight Jinja2 (or similar) scripts convert `canonical.toml` → runtime-specific configs for Claude Code, OpenCode, Codex. No need for a heavy conversion tool; these templates are project-local and auditable.
> COMMENT: what engine executes the jinja script? chezmoi?
- **Syncing shared `./ai` across projects**: Use **Chezmoi** (a maintained dotfile manager). Chezmoi supports templates, project-specific overrides, and deterministic cross-project sync without the merge hazards of git subtrees. If subtree-like behavior is desired, a CI job can copy/validate the canonical config, but Chezmoi is preferred for its declarative, conflict-safe approach.
> COMMENT: can chezmoi support layering of config? eg sync from an enterprise "base" config plus a project config repo, plus a team config repo, plus a personal config repo?
> COMMENT: can chezmoi help with checking drift (agent runtimes edit their configs - chezmoi detects/ prompts user to cherry pick changes into canonical?)
> COMMENT: see @config_sync_problem_statement.md for comments i had written wrt solving this problem, before generating the current analysis. 
---

## 3. Runtimes and Model Provider Portability
- **Runtimes**: Claude Code, OpenCode (which handles Claude Native, Go/Zen, OpenRouter), and Codex.
- **Failover**: Stored in `canonical.toml`. A thin orchestration wrapper (or Temporal retry logic) watches for `rate_limit`/`unavailable` errors and updates the runtime hint in canonical config (or per-session overrides) so subsequent tasks automatically try the next provider. No custom in-agent magic; policy is data, not code.
> COMMENT: Temporal is mentioned. can it be used for free, locally, with no external server/ API dependence? if so, then it is a candidate. if not, disconsider it. 
- **Unified capability model**: Tasks declare required capabilities (`code_edit`, `shell`, `search`, `web`). The orchestrator picks any runtime that satisfies them, enabling seamless provider switches.

---

## 4. Coordination, Tasking, and Workflow Enforcement
- **Task queue**: **Beads** (lightweight, durable). It provides the minimal necessary primitive: enqueue tasks, claim/process, record results.
> COMMENT: agree, nothing replaces beads yet i think.
- **Coordination & messaging**: Redis pub/sub for ephemeral inter-agent messages; SQLite for shared task/session state (both mature, cross-platform).
> COMMENT: challenge this. my assumption was mcp-agent-mail is rather well supported and liked. it is possible even only beads is necessary? (https://steve-yegge.medium.com/welcome-to-gas-city-57f564bb3607). 
- **Orchestration**: **Temporal** (lightweight self-hosted instance) for workflow orchestration (retries, timeouts, branching). Workflows are declarative YAML specs stored in `./ai/workflows/`. Agents validate tasks against workflow rules before execution. This replaces custom workflow engines with battle-tested orchestration.
> COMMENT: investigate gascity as an alternative (https://github.com/gastownhall/gascity). also as an alternative rolled-in-one solution to all of this. is this compatible with solo dev costing - 1-2 claude pro subscriptions, plus opencode go subscription?
> COMMENT: why temporal? are there alternatives?
- **Workflow policing**: Workflow YAMLs declare steps, required capabilities, input/output artifacts, and token budgets. A lightweight validator runs on task enqueue to reject non-compliant requests. CI can lint workflow YAMLs.
---

## 5. Memory and Skill Management
- **Agent memory (cross-session)**: **Mem0** (maintained, MCP-compatible) for short/long-term memory; **ChromaDB** (local) for vector storage of docs/code snippets. Both are external to agents, keeping agents stateless.
- **Skill management**: 
  - Portable skills are defined as MCP server manifests in `./ai/skills/`.
  - Agents can self-document newly created prompts/rules into `SKILLS.md` and corresponding MCP server stubs. No custom “skill mining” service is required; use agent self-reflection prompts and periodic consolidation scripts.
- **Search & navigation**: Use maintained MCP servers — Exa (web), Context7 (docs), grep-app (repo search), plus LSP and AstGrep MCP servers for structural codebase navigation. All minimize token spend by returning only precise hits.

> COMMENT: see also existing research on memory systems and a POTENTIAL (not confirmed) memory system at @mem/ directory. use it to challenge these solutions. 
---

## 6. Context Window Management (No Compaction)
A small purpose-built solution fills the missing handoff capability:

1. **Continuous Recording** (lightweight MCP companion): On each agent session, capture task, decisions, failed attempts, and next steps. Append to `./ai/memory/<agent_id>/session.json`.
2. **Distillation hook**: When estimated context usage (via tiktoken for supported runtimes; conservative threshold for others) exceeds ~80% of window:
   - Summarize recent turns (using the active runtime) into a `summary_N`.
   - Retain only summaries + critical decisions in session.json; discard raw transcript.
3. **Bootstrap next session**: The orchestrator reads session.json, injects concise summaries and critical decisions into the new agent’s system prompt via Jinja2 template. New session starts clean.
4. **Ephemeral guarantee**: Raw session transcript is deleted after distillation; only distilled artifacts persist.

This avoids compaction entirely and ensures continuity across agent/runtime switches.

> COMMENT: strikes me as vague. lacks concreteness. coupled with mature beads (https://github.com/gastownhall/beads), a memory system, and hooks, we can do better than a pure roll-your-own here. 
---

## 7. Tooling Integration (MCP-first)
- All search, memory, task, and code-navigation capabilities are exposed as MCP servers. Runtimes connect to a local `mcp-proxy` that exposes:
  - Redis (pub/sub), SQLite (task state), ChromaDB (vector search), Mem0 (memory), Task Server, LSP, AstGrep, Exa, Context7, grep_app.
- This uniform interface makes runtime/model switches transparent: capabilities are routed through MCP regardless of the underlying LLM.
> COMMENT: dont understand the need for a proxy. extra complication? MCPs should already have standard interfaces that are portable, that's the point.
---

## 8. Deployment and Lifecycle Management
- **Infrastructure as code**: **Nix flakes** (not Ansible) declaratively install and configure all runtimes, MCP servers, Redis, ChromaDB, Mem0, Beads, and scripts. Nix provides:
  - Reproducible environments across Linux/macOS
  - Atomic upgrades/rollbacks
  - Native teardown via garbage collection
- **Workflow**:
  - `nix run .` activates the full stack locally.
  - Remote machines use `nixos` configurations or `nix run` over SSH for uniform deployment.
  - Updates via `nix flake update` and GC.
- **Why not Ansible**: Ansible is imperative and stateful; Nix is declarative and better suited for reproducible, cross-platform toolchains. If ad-hoc imperative steps are needed, they can be encapsulated in Nix-managed scripts.
> COMMENT: agree prefer declarative. why nix? are there alternatives? can nix flakes run on top of both macos and ubuntu?
---

## 9. Data Flow (Ephemeral Session Example)
1. User enters project; Chezmoi syncs `./ai/` from master config repo.
2. Nix environment activates with all tools and MCP servers.
3. Canonical.toml → templates → runtime configs.
4. NTM/Temporal reads workflow YAMLs; Beads enqueues tasks.
5. Ephemeral agent starts (Claude Code or OpenCode), receives task + injected context (session summaries, critical decisions) via Jinja2.
6. Agent runs, uses LSP/AstGrep/Exa/Context7 via MCP, writes outcomes to SQLite and session.json.
7. If approaching context limit, distillation hook runs, summary written, raw transcript deleted.
8. Task completes → agent exits; session artifacts remain; transcript erased.
9. If rate-limited, orchestrator updates canonical.toml provider priority and retries with next runtime.

---

## 10. Positions on Key Differences (Rationale)
- **Coordination primitive**: Keep Beads for tasking (simple, durable) + Redis pub/sub for messaging + Temporal for workflow orchestration. This is simpler and more maintainable than custom frameworks while avoiding unmaintained repos.
- **Memory & state**: Mem0/ChromaDB + SQLite + Redis (external) preferred over unmaintained single-author repos. Keeps agents stateless and portable.
- **Config sync**: Chezmoi over git subtrees for safety, template support, and deterministic cross-project sync.
- **Deployment**: Nix flakes over Ansible for strict declarative reproducibility and native cross-platform lifecycle management.

---

## 11. Open Considerations / Blind Spots
- **Remote Temporal/Redis**: For cross-machine agents, secure exposure of Redis/Temporal is needed (Tailscale or managed services recommended). Policies for data residency should be defined.
- **Token approximation on non-CLM runtimes**: tiktoken is precise for OpenAI/Anthropic; for other models, use conservative estimates and larger safety margins.
- **MCP server compatibility**: Test each MCP server with each runtime version to ensure stable JSON-RPC behavior across updates.
- **Workflow schema evolution**: Define a version and migration path for workflow YAMLs to avoid breakage across agent versions.

---

## 12. Minimal Action Plan
1. Create project-local `./ai/canonical.toml` and Jinja2 templates for runtime configs.
2. Stand up Nix flake declaring all runtimes and MCP servers.
3. Configure Chezmoi to manage `./ai/` sync with override support.
4. Install and configure Beads, Redis, SQLite, Temporal, Mem0, ChromaDB.
5. Implement the distillation handoff script (tiktoken + Jinja2 + runtime CLI hooks).
6. Define workflow YAML schema and add validator hooks in CI.
7. Write validation tests for failover behavior (mock rate-limit errors).

This architecture gives you portable, ephemeral, tool-first multi-runtime agent workflows without custom libraries, with deterministic deployment and no reliance on context-window compaction.

--- 

> COMMENT: all of the following text shall be considered as a single `> COMMENT:`
> i have started experimenting with the ACFS stack (https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup). it solves a lot of problems, but the documentation is poor, i notice i do not fully trust it (unable to audit it myself), and it is opinionated in ways i dont understand or agree with (i need opencode, and opencode isnt first class citizen). i notice i need a harness that is composable so i can add/ remove parts when i want to use, experiment, remove them (entirely, so that left over garbage doesnt pollute a system), automated deployable so i can use it locally as well as headless on a remote server, flexible, evolvable. 
> 