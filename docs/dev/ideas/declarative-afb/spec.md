# AFB Specification

> Status: Draft
> Date: 2026-04-25
> Companion: architecture.md
> Supersedes: synthesis.md (which remains as rationale/research record)

## Problem Statement

AFB is a CLI tool that manages the lifecycle of a multi-runtime AI coding harness. It composes config from layered sources, delegates format translation to LNAI, and manages external components (memory tools, orchestration, etc.) — all driven by a single declarative manifest (`afb.toml`).

Core problem: a solo dev using Claude Code, OpenCode, and potentially other runtimes needs config sync, memory, and orchestration tools deployed consistently across projects and machines, with the ability to add/remove any component without breakage or residue.

## Terminology

| Term          | Definition                                                                       |
| ------------- | -------------------------------------------------------------------------------- |
| **Component** | External tool managed by afb (e.g., LNAI, CASS, mcp-memory-service)              |
| **Layer**     | A source of config files with a priority. Layers compose to produce final config |
| **Target**    | A runtime receiving generated config (Claude Code, OpenCode, Codex)              |
| **Manifest**  | `afb.toml` — declarative description of desired harness state                    |
| **Script**    | User-defined shell script stored alongside the manifest                          |
| **Compose**   | Merging layers into a single config directory                                    |
| **Sync**      | Translating composed config to runtime-native formats (delegated to LNAI)        |

## Constraints

- Solo dev, 1-2 Pro subscriptions, no API keys (initially)
- MacBook Air M2 16GB (primary dev), Linux 32GB (secondary/test)
- FOSS only
- macOS + Linux
- Project-level config; user-level config is ephemeral/vanilla
- 2-10 concurrent agents maximum
- No database servers (SQLite/files only for all stateful components)
- Must be testable by LLM agents during development (lesson from ACFS)
>  COMMENT: linux 32gb can be primary. 
## Functional Requirements

### FR1: Manifest-Driven Component Management

afb.toml declares components with lifecycle hooks:

| Hook      | Purpose                                 | Required? |
| --------- | --------------------------------------- | --------- |
| install   | Install the component                   | Yes       |
| update    | Update to specified version             | No        |
| uninstall | Remove the component and clean up       | No        |
| backup    | Back up component state                 | No        |
| health    | Check if component is running/available | No        |
> COMMENT: update and uninstall required.
Hooks are shell commands or paths to scripts in the scripts directory. afb expands manifest variables before execution.

### FR2: Layered Config Composition

- Layers declared in afb.toml with git URL (or local path) and integer priority
- Higher priority wins on conflict
- Default merge strategies by file type:
  - Structured files (.yaml, .json, .toml): deep merge, last-in wins for leaf values
  - All other files (.md, .txt, etc.): overwrite
- Per-layer strategy override available (merge or overwrite for all files in that layer)
- Project-specific config (`.afb/config/`) is the implicit highest-priority layer
- `afb sync` composes layers into `.ai/`, then runs the configured sync command (default: `lnai sync`)
> COMMENT: probably need an `afb validate` or `afb check` - can we leverage something from lnai? or see what lnai uses, and copy it? 
### FR3: Drift Detection

`afb diff` generates what `afb sync` would produce, diffs against current `.ai/` and runtime config dirs. Reports divergence per file.

### FR4: Upstream Push

`afb push [layer]` pushes local changes in a layer dir back to its upstream git repo.
> COMMENT: `afb push` checks all layers an dpushes back for all layers.
### FR5: Script Runner

`afb run <name>` executes a script from the configured scripts directory. Convenience only — no pre/post hooks, no lifecycle.

### FR6: Test Isolation

Deploy and test a harness without affecting any production harness on the same machine. Runtimes auto-discover config in well-known locations (`$HOME`, project dirs), so isolation requires environment-level separation (HOME/XDG overrides, Devbox, or containers).

Must be possible for an LLM agent (Claude) to deploy and verify afb during development without manual intervention.

### FR7: Observability

Structured logs to stderr. Log level via `AFB_LOG_LEVEL` env var. 12-factor: logs are event streams, not files.

### FR8: Backup

`afb backup` runs the backup hook for every component that defines one. Manifest variables (e.g., `${backup_dir}`) are expanded.

## Non-Functional Requirements

| ID   | Requirement                                                                                                         |
| ---- | ------------------------------------------------------------------------------------------------------------------- |
| NFR1 | **Composability** — enabling/disabling a component + `afb sync` must not break the system and must leave no residue |
| NFR2 | **Declarative** — afb.toml describes desired state; afb converges reality to match                                  |
| NFR3 | **Lightweight** — single Go binary, no runtime dependencies beyond git                                              |
| NFR4 | **Fast** — CLI operations complete in seconds                                                                       |
| NFR5 | **Testable** — formalized Go test suite, CI-compatible                                                              |
| NFR6 | **Portable** — macOS + Linux from the same codebase                                                                 |

## Non-Goals

- AFB is not an orchestration engine (Gas City / beads / hooks handle that)
- AFB is not a config translator (LNAI handles format translation)
- AFB is not a memory system (memory MCP servers handle memory)
- AFB does not manage agent sessions, runtime state, or agent lifecycle
- AFB does not manage API keys or billing
- AFB does not provide a GUI
- AFB does not replace LNAI — it wraps and extends it with layering

## The Four Concerns

### Concern 1: Config Sync

Synchronise unified config across Claude Code, OpenCode, and other runtimes. LNAI does format-aware translation. AFB adds layered composition (personal → team → project) on top.

### Concern 2: Memory (component details deferred)

Memory tools (CASS, mcp-memory-service, cq, Napkin, etc.) are managed as afb components. AFB installs, updates, backs them up. Memory architecture (L1 session search → L2 semantic store → L3 learning store → L4 repo map) is documented separately in `mem/architecture.md`. AFB treats memory tools as opaque components.

Cross-machine memory sync: automated nightly backup of SQLite files to shared storage (rsync, git, or similar). Restore on other machines. Append-mostly data minimises conflicts. Mechanism TBD (see unresolved questions).
> COMMENT: key here is that the philosophy is eventual consistency is acceptable.
### Concern 3: Orchestration (deferred)

Gas City is the primary candidate. AFB installs and configures it as a component. Workflow enforcement (ATDD stages, review gates) is Gas City's responsibility. Evaluate at Phase 3.

Until then: manual tmux, beads + Agent Mail for coordination.

HUD (workflow state machine with human-gated transitions, `~/Projects/hud`) may be subsumed by Gas City. Evaluate alongside.

### Concern 4: Deployment & Lifecycle

AFB itself. The manifest + CLI. Gets built and dogfooded first.

## Verification Criteria

Architecture is successful when:

1. Adding a runtime to a project = edit config + `afb sync`
2. Removing a component = edit afb.toml + `afb sync` → no residue in runtime configs
3. Shared config change propagates via `git pull` in layer repo + `afb sync`
4. Config drift detectable via `afb diff`
5. Fresh machine setup = clone project + `afb install` + `afb sync`
6. All stateful components backup with `afb backup`
7. Test harness deployable in isolation without clobbering production
> COMMENT: first time `afb install` is mentioned. what does it do?
## Phased Adoption

### Phase 1: Deployment Infra + Config Sync

Build afb CLI (init, install, sync, diff). Implement layer composition. Integrate LNAI. Dogfood with Claude Code + OpenCode on one project. Validate composability guarantee.
> COMMENT: dogfood on afb itself
### Phase 2: Memory Foundation

Add memory tools as components (CASS, Napkin, one semantic store). Validate install/backup hooks. Test cross-runtime memory access via MCP.

### Phase 3: Orchestration Evaluation

Install Gas City as component. Test workflow enforcement. Evaluate pack system overlap with afb layers. Fallback: beads + hooks.

### Phase 4: Polish

`afb push`, `afb status`, cross-machine sync, CI integration.

## Unresolved Questions

1. Array merge semantics — replace whole array (current default) or append items?
> COMMENT: i assume you mean in the config layer composition. append. what would be the downside?
2. `afb adopt <file> <layer>` — command for cherry-picking drift back to a layer?
> COMMENT: could be useful yes, for whole of file adoption, and if the user only wants to take individual lines out of a file, they can do that manually.
1. Per-file merge strategy overrides — needed, or per-layer sufficient?
> COMMENT: start with per layer. put per-file in list of future work
2. afb.toml inheritance — project extends user-level afb.toml for cross-project defaults?
> COMMENT: this is what i was trying to avoid. but if we have machine/ user-level common components (MCP servers), then we probably need a user level manifest, yes. afb needs a way to bring those configs (eg mcp url addresses) down to the projects. and project afb.toml can override if neceessary. since different users on different machines collaborating on the same repom may need to add their own memory servers (so these urls should not appear in the files committed to the project). the project afb.toml does get committed to the project, so if a project uses a company wide mcp server with common address, then it can be configured in project afb.toml. hmm. in this case, this should all just be in a user-specific layer. not in afb.toml. what would go in a user level afb.toml? i guess configuration for the user-specific harness. so this begs the question - shall harnesses be user or project specific? a user may want to work with their own personal harness on personal projects, and a work harness on work projects, on the same machine. this is where the nix/devbox/ containers come in. but then afb.toml is project-specific, and team members use it to install and enter the same harness as team mates. and we're back to wondering what goes in the user level afb.toml? this feels like duplicating workflows from dev container based setups. what can we learn from that in terms of best practices?
3. Test isolation mechanism — Devbox + HOME override vs containers? Both?
> COMMENT: how do we handle components that dont have native nix packages? user must roll the package themself? how to maintain currency with latest versions? is a better way to do this declaratively rather via containeers?
4. Cross-machine memory sync — dump/import vs Litestream vs cr-sqlite?
5. Layer git strategy — clone to cache dir (proposed) vs git subtree vs git submodule?
6. LNAI dry-run — does it exist? If not, how does `afb diff` work for runtime configs?
> COMMENT: yes, it has dry-run

> COMMENT: new requirement. afb install, sync, shall be idempotent. it will require some sort of afb lock file, or record of what was installed? a hash of the config to check if anything changed since last run? does not get committed to project dir.
> COMMENT: new requirement for nix/ container approach: shall be able to roll back to earlier versions of the harness if an experiment/ upgrade doesnt work