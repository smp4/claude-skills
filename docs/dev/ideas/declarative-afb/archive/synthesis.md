# Synthesis: Declarative AFB Architecture

> Date: 2026-04-24
> Status: Proposal for review
> Companion: research-results.md (raw research), fusion_response.md (original analysis being critiqued)

---

## Problem Statement

Build a composable, declarative harness for multi-runtime AI-assisted coding that:

1. Syncs config/skills/hooks/MCP servers across Claude Code, OpenCode, and Codex
2. Enables easy model/provider switching (Pro subs today, API keys later, cheaper models via OpenCode Go/OpenRouter)
3. Keeps config at project level — user-level config is ephemeral/vanilla
4. Deploys declaratively — add/remove components by editing a manifest, re-running a command
5. Enforces workflows (ATDD, multi-review, structured pipelines) — not just "more agents"
6. Treats state as durable (simple backup), agents/sessions as ephemeral
7. Fits solo dev, 1-2 Pro accounts, macOS (32GB available), FOSS only

**Non-negotiable**: composability. Adding or removing a component must not break the system. Removing must leave no residue. The ACFS experience is the cautionary tale — monolithic bootstrap that can't be modified.

---

## Critique of fusion_response.md

### Fundamental problems

1. **Enterprise stack for a solo dev.** Temporal + Redis + ChromaDB + Mem0 + Nix flakes + Chezmoi + mcp-proxy = 7 infrastructure components before running a single agent. For 2-10 agents on one machine, this is 4x overprovisioned.

2. **Temporal requires a database server.** It needs PostgreSQL/MySQL/Cassandra plus its own server process plus worker processes. Designed for distributed microservice orchestration. Not lightweight, not local-first, not compatible with "no database maintenance."

3. **Redis adds zero value at this scale.** For inter-agent messaging between 2-10 agents on one machine, mcp_agent_mail (SQLite + Git) is sufficient. Redis adds operational complexity for no benefit.

4. **ChromaDB and Mem0 are redundant.** The detailed mem/ research (architecture.md, research.md) already identified better-fit tools: mcp-memory-service and Basic Memory handle embeddings locally in SQLite. ChromaDB adds another vector database. Mem0's self-hosted option is resource-heavy.

5. **Chezmoi is wrong for this problem.** See below.

6. **canonical.toml is a fragile SPOF.** A single file generating all runtime configs becomes enormously complex. Every runtime's idiosyncrasies get encoded in one file + templates. When a runtime changes its config format, you fix the canonical + the template + verify all other runtimes didn't break. LNAI's plugin architecture is a better model — each runtime has a dedicated translator.

7. **The context management solution (Section 6) is vague.** "Summarise recent turns using the active runtime" — how does a context-exhausted runtime summarise? "Conservative threshold for others" — what threshold? The mem/architecture.md cleanroom handoff + beads approach is far more concrete.

8. **MCP proxy is unnecessary.** MCP already defines a standard interface. Each runtime connects to MCP servers directly. A proxy adds latency, a SPOF, and operational complexity.

### Why Chezmoi is wrong

Chezmoi manages **personal dotfiles across machines** (your `.zshrc`, `.gitconfig`). The problem here is **project-level config translation across runtimes**. These are different problems:

- **Chezmoi copies files** with template substitution. It doesn't understand runtime config formats.
- **The real problem requires format-aware translation**: the same MCP server config must become `.mcp.json` for Claude Code and a different structure in `opencode.json` for OpenCode. The same permissions must map to Claude Code's `settings.json` format vs OpenCode's permission model.
- **Chezmoi's template language is Go templates**, not the Jinja2 the fusion response assumed.
- **Chezmoi doesn't support multi-source layering** (enterprise → team → personal config merge) natively. It supports per-machine overrides, which is different.
- **LNAI exists and solves this correctly** with per-runtime plugins that understand native formats.

### What fusion_response.md gets right

- Project-level config as non-negotiable
- Ephemeral agents/sessions philosophy
- Beads for tasking
- Capability-based task routing (good concept, needs concretisation)
- Portability as primary concern

---

## Proposed Architecture

Three independent concerns, solved independently:

### Concern 1: Config Sync (CC ↔ OpenCode ↔ Codex)

**Solution: LNAI + git subtrees + thin CLI wrapper**

```
┌─────────────────────────────────────────────────┐
│                  Project repo                    │
│                                                  │
│  .ai/                    ← single source of truth│
│  ├── AGENTS.md           ← shared instructions   │
│  ├── rules/              ← shared rules          │
│  ├── skills/             ← shared skills         │
│  ├── settings.yaml       ← MCP servers, perms    │
│  ├── .claude/            ← CC-specific overrides │
│  ├── .opencode/          ← OC-specific overrides │
│  └── config.yaml         ← which tools enabled   │
│                                                  │
│  .ai/shared/             ← git subtree from      │
│  └── (base rules,          shared config repo    │
│       shared skills,                              │
│       shared MCP config)                          │
│                                                  │
│  lnai sync →                                     │
│  ├── .claude/            ← generated             │
│  ├── .opencode/          ← generated             │
│  ├── .codex/             ← generated             │
│  └── .mcp.json           ← generated             │
└─────────────────────────────────────────────────┘
```

**Layering via git subtrees**: A shared config repo contains base rules, skills, MCP server definitions. It's pulled into each project as a git subtree at `.ai/shared/`. Project-specific config in `.ai/` takes precedence. A small merge script composes the final `.ai/` state before `lnai sync`.

> COMMENT: clarification: "A small merge script composes the final .ai/ state from the share layers at ./ai/shared/<01_base>, ./ai/shared/<02_team>, ...". the user can bring in multiple shared repos into the shared directory as separate config layers. layers are applied alphanumerically (01 first, 99 last eg). last in wins. in another LLM chat we sketched a solution that used rsync and yq/jq for deep merging files. this doesnt have to be our solution. challenge this, or agree.

**Drift detection**: A wrapper script (`afb diff`) runs `lnai sync --dry-run` (or generates to a temp dir and diffs against actual). Reports divergence. User decides what to pull back into `.ai/`.

**Glue code estimate**: ~100 LOC shell/TypeScript.
- `afb sync` — compose layers + run `lnai sync`
- `afb diff` — detect drift between generated and actual
- `afb layer add <repo> <name>` — add a git subtree layer
- `afb layer remove <name>` — remove a subtree layer

> COMMENT: an `afb push` command also helpful - after the user runs afb diff to detect drift, then cherry picks updates into a `./ai/shared` layer dir, we can run afb push to push the changes to the relevant upstream repo.
> COMMENT: probably need an afb.toml config file to set the shared config repo url's and map them to the desired shared layer dir name. declarative. i prefer that to the user manually adding git subtrees.
> COMMENT: in addition to `afb diff` is something like `skillshare extras collect rules` that collects local/ loaclly changed files back to source useful? see https://github.com/runkids/skillshare. is skillshare a useful alternative to lnai?

### Concern 2: Memory

**Solution: The mem/ research ensemble, refined**

The mem/architecture.md and mem/research.md work is substantially more rigorous than the fusion response's memory proposal. Use that research directly. Key decisions to make:

| Choice              | Options                            | Recommendation                                                                                                                                           |
| ------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Semantic store (L2) | mcp-memory-service vs Basic Memory | mcp-memory-service — SQLite-vec with ONNX embeddings, efficient retrieval (not markdown re-parsing), built-in backup dir, 1.6k stars                     |
| Learning store (L3) | cq vs cass_memory_system vs both   | Pick one first. cq for cross-agent sharing if running parallel agents. cass_memory_system for deeper procedural memory with decay if running sequential. |
| Session search (L1) | CASS                               | Adopt — foundation layer, lightweight, index is derived/rebuildable                                                                                      |
| Mistake tracking    | Napkin                             | Adopt immediately — zero cost, zero risk                                                                                                                 |
| Repo map (L4)       | RepoMapper                         | Adopt — solves the structural understanding gap                                                                                                          |

> COMMENT: you have different levels L1 to L4 here. explain that categorisation. is this a hierarchy with lower/ higher levels of abstraction? do they communicate?

**Backup**: All tools use SQLite or plain files. A cron script:
```bash
# All memory backup in one script
sqlite3 ~/.local/share/cq/local.db ".backup /backup/cq.db"
cp /path/to/sqlite_vec.db /backup/memory-service.db
tar czf /backup/cass-memory.tar.gz ~/.cass-memory/
# CASS Tantivy index: skip — rebuildable from session logs
```

> COMMENT: keeping with the potential nix-based approach, the user probably has to write such a script - afb can't a priori know anything about it. so afb should probably have a central store for related scripts that the user can maintain next to their preferred afb.toml config, and deploy to any project. then we have a mechanism like `afb run <user_script>` for chores like this backup. 
> COMMENT: this makes me realise that the user might want to also store state in their personal afb config repo (along with afb.toml and their scripts). for example, the memory database backups. some (most?) memory systems exist as a single entity on a machine, so the memories get shared across all projects on that machine, good. but the user works on multiple machines. how to share memories across multiple machines? we could have a memory server that different machines can connect to. but this is overhead. we could also have independent memory db instances on each machine, but treat their state as distributed async data, and the user periodically backs up or syncs the database to their afb config repo (or other), then "pulls" that repo with the memory state down to other machines, then sync, then work with the new memories. requires the memory servers to have a migrate/ dedup/ conflict mgmt mechanism. thoughts? challenge and critique this idea. is there any out of the box sqlite solutions for migrate/dedup/conflict mgmt? could/ should we serialise the databases first, then sync to repos and share?

**Memory is independent of config sync and orchestration.** Install memory tools via MCP server config in `.ai/settings.yaml`. LNAI propagates to all runtimes. Memory tools don't know or care about the orchestration layer.

### Concern 3: Orchestration & Workflow Enforcement

**Solution: Gas City (when ready) + workflow definitions**

Orchestration is not just "run more agents." It includes:
- Enforcing ATDD workflow (spec → plan → red → green → refactor → review)
- Multi-agent review of plans (adversarial review, persona-based critique)
- Structured pipelines with gates and checkpoints
- Health monitoring and automatic recovery

**Gas City** is the strongest candidate for the orchestration layer because:
- Declarative `city.toml` config
- Pack system for composable config bundles (add/remove orchestration recipes)
- Beads-backed work tracking (already validated)
- Controller/supervisor loop for state reconciliation
- Pro-subscription compatible (agents auth independently)
- File-based beads mode avoids Dolt dependency
- MIT license, Go binary, actively maintained

**BUT**: Gas City just hit v1.0.0 (Apr 21, 2026). It's 3 days old at this version. Adoption risk is real.

**Phased approach**:
1. **Now**: Run agents manually in tmux. Use beads + Agent Mail for coordination primitives.
2. **Next 2-4 weeks**: Evaluate Gas City. Define workflow in `city.toml`. Test with simple pipeline (plan → implement → review).
3. **If Gas City doesn't fit**: The coordination primitives (beads, Agent Mail, hooks) still work. You've lost nothing.

**Workflow enforcement without Gas City**: Workflow rules can be encoded as:
- CLAUDE.md / AGENTS.md instructions (soft enforcement)
- Hooks that validate state before allowing next step (hard enforcement)
- Beads that gate work items on prerequisite completion
> COMMENT: see also hud, a tool we are in the middle of building together. only just started. stopped, when realised it is a large project and maybe other tools solve this problem already: @~/Projects/hud.
Gas City adds: automatic agent lifecycle management, health monitoring, declarative pipeline definition, pack-based composability. Worth it when you're running 3+ agents regularly.

---

## Deployment Model

> COMMENT: i would argue that deployment is concern #4, rather than treating it only as "deployment model". This is a real feature of afb, trying to solve the problem of dealing with an extremely rapidly changing tooling and workflow landscape.

The ACFS experience teaches: **deployment must be stateless and composable.**

```
afb.toml                    ← component manifest
├── [components]
│   ├── lnai = { enabled = true, version = "0.6.91" }
│   ├── cass = { enabled = true, version = "latest" }
│   ├── cq = { enabled = true }
│   ├── mcp-memory-service = { enabled = true }
│   ├── agent-mail = { enabled = false }
│   ├── gascity = { enabled = false }
│   └── napkin = { enabled = true }
├── [layers]
│   ├── shared = { repo = "git@...:shared-ai-config.git" }
│   └── team = { repo = "git@...:team-config.git" }
└── [sync]
    └── tools = ["claudeCode", "opencode", "codex"]
```

**`afb` CLI**:
- `afb install` — install/update enabled components at pinned versions
- `afb uninstall <component>` — remove component, clean up config references
- `afb sync` — compose config layers + run lnai sync
- `afb diff` — detect drift
- `afb backup` — run backup script for all stateful components
- `afb status` — health check all running components

> COMMENT: presumably the user must also define how afb shall install each of the components right? components come from many different installation methods and package managers. afb doesnt know about any of this. 

**Composability guarantee**: disabling a component in `afb.toml` and running `afb sync` removes its config from all runtimes. No residue. State in the component's own store is untouched (can re-enable later).

**What `afb` is NOT**: It's not an orchestration engine. It's a package manager for your AI coding harness. Gas City (or beads+hooks) handles orchestration. LNAI handles config translation. `afb` manages the manifest of what's installed.
> COMMENT: agree. 
---

## What This Architecture Does NOT Include

| Excluded                     | Why                                                              |
| ---------------------------- | ---------------------------------------------------------------- |
| Temporal                     | Requires database server, overkill for scale                     |
| Redis                        | Unnecessary at 2-10 agent scale                                  |
| ChromaDB                     | Redundant with mcp-memory-service                                |
| Mem0                         | Resource-heavy, cloud dependency                                 |
| MCP proxy                    | Unnecessary indirection                                          |
| Chezmoi                      | Wrong abstraction (dotfile manager, not config translator)       |
| Nix flakes                   | Learning curve too high for marginal benefit over Devbox/mise    |
| canonical.toml + Jinja2      | Fragile SPOF, replaced by LNAI's plugin architecture             |
| Custom sleep-time reflection | Premature — build memory stores first, evaluate need empirically |
| ACFS                         | Not composable, Ubuntu-only, not Pro-compatible                  |

> COMMENT: im going to challenge dropping nix/ nix flakes. is the learning curve really too high if claude/ other llm is taking care of the config, orchestration, etc? nix gives very nice composability, it allows us to deploy full harnesses in indepdent test environments locally for development, allows the user to have multiple harnesses with different configs locally and on remote machines, and potentially even on k8s clusters. potential nix downside is that we need all components to be available as nix packages (confirm this is correct, else correct me). is it possible to have nix/ nix flakes install components that are not nix packages? it also allows the user to experiment with new harnesses without sacrificing an old/ known good harness, working in different nix shells.
> COMMENT: are their alternatives to nix, like open OpenTofu? or even deploying the harness on local k8s with ked/ k3s/ similar? see 


> COMMENT: i want to see more concrete detail on the afb architecture. what are the components of afb (the tool) itself? what is its architecture? layered? ports/ adapters? other? in what language? where does data, state, user preferences and config live? what is the lifecycle of that data? what are the afb primitives? think hard about this and design an architecture. keep it as simple and lightweight as possible. justify it. only once we understand the architecture, should we plan the dev. 
---

## Phased Adoption

### Phase 1: Config Sync (this week)

> COMMENT: i think phase 1 should be the deployment infra, so that we can cleanly deploy, test, iterate, then add components. agree first copmonent is the config sync. we should dogfood the deployment infra from the start

1. `npm install -g lnai`
2. Create `.ai/` in a project, move existing config
3. `lnai sync` — verify CC and OpenCode pick up generated config
4. Create shared config repo, add as git subtree to `.ai/shared/`
5. Write `afb sync` wrapper (~50 LOC)

**Validates**: LNAI works, OpenCode reads generated config, layering via subtrees works.

### Phase 2: Memory Foundation (next week)

1. Install CASS (`brew install dicklesworthstone/tap/cass`)
2. Install Napkin skill
3. Install one semantic store (evaluate mcp-memory-service first)
4. Add MCP server configs to `.ai/settings.yaml`
5. `afb sync` propagates to all runtimes
6. Write backup script (~10 LOC)

**Validates**: Memory tools work across both runtimes, retrieval quality is acceptable.

### Phase 3: Orchestration Evaluation (week 3-4)

1. Install Gas City (`go install`)
2. Define minimal `city.toml` with 2 agents (CC + OpenCode)
3. Test simple workflow: plan → implement → review
4. Evaluate: does Gas City's pack system handle adding/removing workflow recipes?
5. If Gas City doesn't fit: fall back to beads + hooks + Agent Mail

**Validates**: Gas City's orchestration model works at your scale, workflow enforcement is achievable.

### Phase 4: AFB CLI (week 4-5)

1. Build `afb.toml` manifest format
2. Implement `afb install/uninstall/sync/diff/backup/status`
3. Test composability: enable/disable components, verify no residue
4. Add drift detection

**Validates**: Composability guarantee holds, daily workflow is low-friction.

---

## Verification

Architecture is successful when:

1. Adding OpenCode to a project = edit `.ai/config.yaml` + `afb sync`
2. Removing a memory tool = edit `afb.toml` + `afb sync` — no residue in runtime configs
3. Shared config change propagates to all projects via `git subtree pull` + `afb sync`
4. Runtime config drift is detectable and reportable
5. Workflow enforcement gates are respected (can't skip review step)
6. All stateful components backup with `afb backup` (one command)
7. Fresh machine setup = clone project + `afb install` + `afb sync`

---

## Unresolved Questions

1. **LNAI layer merging** — LNAI doesn't natively merge multiple `.ai/` sources. The subtree compose step happens before `lnai sync`. What's the merge strategy for conflicts? Last-layer-wins? Per-file? Per-key in settings?
> COMMENT: see above, layers are composed alpha-numerically. (challenge: perhaps in afb.toml we should have a mandatory priority field for each layer, an integer, highest number wins, then we dont depend on dir names). perhaps the user defines the strategy, and afb offers strategy primitives (overwrite, append, merge)? with sane defaults. skill files probably should overwrite (and if the user doesnt want this, they should rename the skills). yaml, toml, json should deep merge, with last-in as winner. how does chezmoi https://github.com/twpayne/chezmoi handle this? can we learn anything? challenge my ideas here.
2. **Gas City workflow enforcement** — can Gas City's packs encode ATDD stages as gates, or is workflow enforcement still custom logic on top?
> COMMENT: dont know, i think we can defer this until we come to adding a workflow/ orchestrator component. 
3. **Memory store selection** — mcp-memory-service vs cass_memory_system vs cq: the mem/ research recommends evaluating head-to-head. When and how? Suggestion: install one (mcp-memory-service), use it for 2 weeks, measure retrieval quality, then decide if a second store adds value.
> COMMENT: we can defer this until we come to adding the first memory component. 
4. **afb CLI language** — shell script for simplicity, or TypeScript/Go for type safety? Shell is faster to prototype; TypeScript aligns with LNAI's ecosystem.
> COMMENT: not shell, i think we need to have a formalised tests system/ infra for afb. i know python best, but typescript/ go seem to be more common in the agentic development space. 
5. **Gas City + LNAI overlap** — Gas City's pack system manages agent config (prompts, fragments, overlays). LNAI manages runtime config (rules, skills, MCP, permissions). Do they conflict when both try to write to `.claude/` or `.opencode/`?
> COMMENT: unknown. worry about it when we get to gas city deployment. if they do conflict, we can spike it, and potentially afb shall have "the last word" at deploy time with a final cleanup operation. 


---

> COMMENT: it shall be possible for you (claude) to deploy afb in a test environment for verification and validation during development. we shall not rely on the user deploying the developed result and reporting back for bugs. this is a requirement. lesson learnt from acfs, and trying to modify the acfs deploy script. 
> COMMENT: related to the above comment, afb shall have an observability system built in during all operations, to help us debug. a simple logging system suffices? use 12 factor app principles here. 

> COMMENT: components to be added / future work: handoff system (high priority), continuous improvement/ metrics/ feedback system. https://github.com/pdavis68/RepoMapper, https://github.com/MikeRecognex/mcp-codebase-index; https://github.com/REMvisual/claude-handoff