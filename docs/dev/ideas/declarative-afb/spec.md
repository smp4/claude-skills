# AFB Specification

> Status: Draft (rev 2)
> Date: 2026-04-25
> Companion: architecture.md
> Supersedes: synthesis.md (which remains as rationale/research record)

## Problem Statement

AFB is a CLI tool that manages the lifecycle of a multi-runtime AI coding harness. It composes config from layered sources, delegates format translation to LNAI, and manages external components (memory tools, orchestration, etc.) — all driven by a single declarative manifest (`afb.toml`).

Core problem: a solo dev using Claude Code, OpenCode, and potentially other runtimes needs config sync, memory, and orchestration tools deployed consistently across projects and machines, with the ability to add/remove any component without breakage or residue.

## Terminology

| Term | Definition |
|------|-----------|
| **Component** | External tool managed by afb (e.g., LNAI, CASS, mcp-memory-service) |
| **Layer** | A source of config files with a priority. Layers compose to produce final config |
| **Target** | A runtime receiving generated config (Claude Code, OpenCode, Codex) |
| **Manifest** | `afb.toml` — declarative description of desired harness state |
| **Lock** | `afb.lock` — records installed component versions and layer commits (see Challenge 2) |
| **Script** | User-defined shell script stored alongside the manifest |
| **Compose** | Merging layers into a single config directory |
| **Sync** | Translating composed config to runtime-native formats (delegated to LNAI) |

## Constraints

- Solo dev, 1-2 Pro subscriptions, no API keys (initially)
- MacBook Air M2 16GB + Linux 32GB available; Linux can serve as primary for heavier workloads
- FOSS only
- macOS + Linux
- Project-level config; user-level config is ephemeral/vanilla
- 2-10 concurrent agents maximum
- No database servers (SQLite/files only for all stateful components)
- Must be testable by LLM agents during development (lesson from ACFS)

## Functional Requirements

### FR1: Manifest-Driven Component Management

afb.toml declares components with lifecycle hooks:

| Hook | Purpose | Required? |
|------|---------|-----------|
| install | Install the component | Yes |
| update | Update to specified version | Yes |
| uninstall | Remove the component and clean up | Yes |
| backup | Back up component state | No |
| health | Check if component is running/available | No |

> CHALLENGE 1: update/uninstall as required forces boilerplate on trivial components. Napkin is a skill file — `uninstall = "echo 'nothing to uninstall'"` is pure ceremony. Components like shared prompt templates have no binary to update or remove. Only `install` should be required. The rest should be optional — `afb uninstall` skips components without an uninstall hook (logging a warning). Required hooks create friction for the simplest components and don't add safety — if the user forgets an uninstall hook for a real tool, they'll discover it when they try to uninstall. Consider: install=required, update/uninstall=required-if-applicable or just optional.

Hooks are shell commands or paths to scripts in the scripts directory. afb expands manifest variables before execution.

**Commands that execute hooks**:
- `afb install` — runs install hook for all enabled components, writes `afb.lock`
- `afb uninstall <name>` — runs uninstall hook. User then sets enabled=false in afb.toml manually
- `afb backup` — runs backup hook for each component that defines one
- `afb status` — runs health hook for enabled components, compares afb.lock vs afb.toml for version drift

**Install failure**: If a hook fails, afb logs the error (exit code + stderr), continues with remaining components, and records the failure in afb.lock. No auto-rollback — running uninstall after a partial install is fragile. User runs `afb uninstall <component>` manually to clean up.

### FR2: Layered Config Composition

- Layers declared in afb.toml with git URL (or local path), integer priority, and optional `ref` (branch/tag/commit)
- Higher priority wins on conflict
- Default merge strategies by file type:
  - Structured files (.yaml, .json, .toml): deep merge, last-in wins for leaf values
  - All other files (.md, .txt, etc.): overwrite
- Per-layer strategy override available (merge or overwrite for all files in that layer)
- Project-specific config (`.afb/project/`) is the implicit highest-priority layer
- `afb sync` composes layers into `.ai/`, then runs the configured sync command (default: `lnai sync`)

### FR3: Drift Detection

`afb diff` detects divergence at two levels:

1. **Composition drift**: current `.ai/` vs what `afb sync` would produce
2. **Runtime drift**: current `.claude/`, `.opencode/`, `.mcp.json` vs what LNAI would generate from composed `.ai/` (uses `lnai sync --dry-run`)

> CHALLENGE 7: LNAI dry-run is unverified. The research doc (research-results.md) explicitly states drift detection is "Not implemented" in LNAI — `detect()` and `import()` return `false`/`null` for every plugin. `lnai validate` exists (syntax checking), but `lnai sync --dry-run` may not. If it doesn't, Stage 2 requires the temp-dir workaround (compose to temp, run `lnai sync` there with HOME override, diff output). This needs verification against actual LNAI before building on it.

Runtime drift catches changes made directly by runtimes (e.g., Claude Code adding an MCP server via UI). LNAI symlinks some files and copies others; only copied files can diverge from `.ai/`. Reports divergence per file.

### FR4: Upstream Push

`afb push` pushes local changes in all layer dirs back to their upstream git repos. `afb push <layer>` for a specific layer.

### FR5: Script Runner

`afb run <name>` executes a script from the configured scripts directory. Convenience only — no pre/post hooks, no lifecycle.

### FR6: Test Isolation

Deploy and test a harness without affecting any production harness on the same machine. Runtimes auto-discover config in well-known locations, so isolation requires environment-level separation.

Two-tier strategy:
1. **afb testing**: HOME/XDG override via `afb test <command>`
2. **Agent execution**: Container isolation for secure permissive-mode runs (future — evaluate when running 3+ agents)

Must be possible for an LLM agent (Claude) to deploy and verify afb during development without manual intervention.

### FR7: Observability

Structured logs to stderr. Log level via `AFB_LOG_LEVEL` env var. 12-factor: logs are event streams, not files.

### FR8: Backup

`afb backup` runs the backup hook for every component that defines one. Manifest variables (e.g., `${backup_dir}`) are expanded.

### FR9: Validation

`afb validate` checks:
1. afb.toml syntax and schema validity
2. Composed `.ai/` directory validity — delegates to `lnai validate`

Runs automatically as final step of `afb sync`. Can be invoked standalone.

> CHALLENGE 5: Validation running AFTER sync is wrong. By the time validation runs, LNAI has already written runtime configs. If validation fails, invalid generated config is sitting in `.claude/` and `.opencode/`. Validation should run AFTER compose but BEFORE the sync command — catch problems before they propagate to runtime dirs. Proposed order: compose → validate → sync (not compose → sync → validate).

### FR10: Dry-Run Testing

`afb test [command]` runs any afb command in an isolated environment (temporary HOME/XDG dirs). Validates that hooks, composition, and sync work correctly without affecting production config. Environment is torn down after the test.

> CHALLENGE 3: `afb test` is a thin wrapper over `HOME=/tmp/xxx afb <command>`. A shell alias or one-liner achieves the same. A dedicated command adds code, tests, and docs for what's essentially an env var override. For a single-user tool, discoverability isn't a strong argument. Consider deferring this from v1 — document the HOME override trick instead, promote to a command only if users (you) actually use it regularly.

### FR11: Remote & Session Compatibility

afb must work over SSH (including Tailscale SSH) and inside tmux sessions. As a CLI that reads files and runs shell commands, this is largely inherent — but the following must hold:

- No interactive prompts or GUI dependencies (all input via flags, env vars, or manifest)
- No localhost-only assumptions (e.g., hardcoded 127.0.0.1 for any service)
- Log output usable in headless/detached sessions (structured stderr, no ANSI unless TTY detected)
- Component hooks must also be non-interactive (user's responsibility, but afb should document this constraint)

Remote harness management (running afb on a remote machine via SSH to manage containers or agents there) is a natural workflow. afb does not need a remote execution mode — the user SSHes in and runs afb locally on the remote machine. The project repo and afb.toml are on the remote machine (cloned via git).

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR1 | **Composability** — enabling/disabling a component + `afb sync` must not break the system and must leave no residue |
| NFR2 | **Declarative** — afb.toml describes desired state; afb converges reality to match |
| NFR3 | **Lightweight** — single Go binary, no runtime dependencies beyond git |
| NFR4 | **Fast** — CLI operations complete in seconds |
| NFR5 | **Testable** — formalized Go test suite, CI-compatible |
| NFR6 | **Portable** — macOS + Linux from the same codebase |

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

Cross-machine memory sync: automated nightly backup of SQLite files to shared git repo. Restore on other machines. Philosophy: **eventual consistency is acceptable** — memory data is append-mostly, conflicts are rare for a solo dev.

> CHALLENGE 9: "Append-mostly" doesn't prevent duplicates — it guarantees them. If you work on the same task from both machines in one day, both machines add memories about the same topic. Nightly sync merges both sets, producing duplicate or near-duplicate entries. For a solo dev this may be tolerable (memory tools should handle redundant context gracefully), but it's a real gap. Consider: is deduplication the memory tool's responsibility, afb's, or the user's? If the memory tool doesn't dedup, you'll accumulate noise over time.

### Concern 3: Orchestration (deferred)

Gas City is the primary candidate. AFB installs and configures it as a component. Workflow enforcement (ATDD stages, review gates) is Gas City's responsibility. Evaluate at Phase 3.

Until then: manual tmux, beads + Agent Mail for coordination.

HUD (workflow state machine with human-gated transitions, `~/Projects/hud`) may be subsumed by Gas City. Evaluate alongside.

### Concern 4: Deployment & Lifecycle

AFB itself. The manifest + CLI. Gets built and dogfooded first.

## Verification Criteria

Architecture is successful when:

1. Adding a runtime to a project = edit `.afb/project/config.yaml` + `afb sync`
2. Removing a component = `afb uninstall <name>` + set enabled=false in afb.toml + `afb sync` → no residue in runtime configs
3. Shared config change propagates via `afb layer pull` + `afb sync`
4. Config drift detectable via `afb diff` (both composition and runtime levels)
5. Fresh machine setup = clone project + `afb install` + `afb sync`
6. All stateful components backup with `afb backup`
7. Test harness deployable in isolation via `afb test sync` without clobbering production
8. `afb.lock` records installed state; `afb status` reports drift between declared and actual

## Phased Adoption

### Phase 1: Deployment Infra + Config Sync

Build afb CLI (init, install, sync, diff, validate, test). Implement layer composition. Integrate LNAI. Dogfood with Claude Code + OpenCode on one project. Validate composability guarantee.

### Phase 2: Memory Foundation

Add memory tools as components (CASS, Napkin, one semantic store). Validate install/update/uninstall/backup hooks. Test cross-runtime memory access via MCP.

### Phase 3: Orchestration Evaluation

Install Gas City as component. Test workflow enforcement. Evaluate pack system overlap with afb layers. Evaluate whether Gas City subsumes HUD. Fallback: beads + hooks.

### Phase 4: Polish

`afb push`, `afb status`, cross-machine sync via shared git repo, CI integration, container isolation template, metrics.

## Unresolved Questions

1. Array merge semantics — replace whole array (current default) or append items?
2. `afb adopt <file> <layer>` — command for cherry-picking drift back to a layer?
3. Per-file merge strategy overrides — needed, or per-layer sufficient?
4. User-level afb.toml — for machine-wide tools (MCP servers). How does project inherit?
5. Per-harness vs per-machine backups — some components are machine-wide, not project-scoped
6. Container isolation details — Dockerfile template, which runtimes work well in containers?
7. Statistical process control metrics — what to track, how to couple with logging?
