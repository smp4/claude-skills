# AFB Specification

> Status: Draft (rev 3)
> Date: 2026-04-26
> Companion: architecture.md, domain.md
> Supersedes: synthesis.md (which remains as rationale/research record)

## Problem Statement

AFB is a CLI tool that manages the lifecycle of a multi-runtime AI coding harness. It composes config from layered sources, delegates format translation to LNAI, manages external components (memory tools, orchestration, etc.), and generates container images — all driven by a single declarative manifest (`afb.toml`).

Core problem: a solo dev using Claude Code, OpenCode, and potentially other runtimes needs config sync, memory, and orchestration tools deployed consistently across projects and machines, with the ability to add/remove any component without breakage or residue.

## Terminology

| Term | Definition |
|------|-----------|
| **Manifest** | `afb.toml` — declarative description of desired harness state |
| **Local manifest** | `afb.local.toml` — user-specific overrides, deep-merged over manifest. Gitignored |
| **Lockfile** | `afb.lock` — records resolved state (versions, commit hashes, image digests) |
| **Component** | External tool managed by AFB via lifecycle hooks. Opaque — AFB runs hooks without understanding what the component does |
| **Layer** | A source of config files with an integer priority and merge strategy. Layers compose to produce `.ai/` |
| **Project config** | `.afb/project/` — implicit highest-priority layer. Committed to project repo |
| **Target** | A runtime receiving generated config (Claude Code, OpenCode, Codex) |
| **Template** | An `afb.template.toml` or git repo used to scaffold a new manifest via `afb init --template` |
| **Script** | User-defined shell script in `.afb/scripts/` |
| **Compose** | Merging layers by priority into a single config directory (`.ai/`) |
| **Sync** | Compose + validate + run sync command (`lnai sync`) to translate `.ai/` into target-native formats. Updates lockfile |
| **Harness** | Complete agent development environment: runtime(s), tools, composed config, container image |
| **Doctor** | Context-aware diagnostic check covering lockfile, drift, component health |
| **Compose project** | Named set of containers managed by a single compose.yaml. Default: `afb-{dirname}` |
| **Port** | Go interface defining how AFB interacts with an external dependency |
| **Adapter** | Concrete implementation of a port |

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

`afb.toml` declares components with lifecycle hooks and optional named commands:

| Field | Purpose | Required? |
|-------|---------|-----------|
| `install` | Install the component | Yes |
| `version` | Command whose stdout is captured as installed version for lockfile | No |
| `[commands]` | User-defined named commands (e.g., `doctor`, `backup`) | No |

Hooks are shell commands or paths to scripts. AFB expands manifest variables before execution.

**No `uninstall`**: containers are disposable. To remove a component: set `enabled = false` in `afb.toml` and run `afb rebuild`. The new image simply doesn't include it — no side-path that can drift from manifest.

**No fixed `backup` or `health` hooks**: components define arbitrary named commands in `[components.NAME.commands]`, invoked via `afb run <component>.<command>`. Scripts in `.afb/scripts/` orchestrate multiple component commands (e.g., a `backups.sh` that calls `afb run cass.backup` then `afb run mcp-memory-service.backup`).

**Commands that execute hooks**:
- `afb sync` — includes component install if versions have drifted (lockfile vs manifest). Writes lockfile
- `afb lock` — resolves all versions, commit hashes, image digests. Writes `afb.lock`
- `afb lock --check` — exits non-zero if lockfile is stale. For CI
- `afb doctor` — runs `doctor` command for each component that defines one, plus lockfile and drift checks
- `afb run <component>.<command>` — runs a named component command
- `afb rebuild` — build + down + up. Replaces old container with new image

**Install failure**: AFB logs the error (exit code + stderr), continues with remaining components, records `install_ok = false` in lockfile. No auto-rollback. In `--strict` mode: first failure aborts.

### FR2: Layered Config Composition

- Layers declared in `afb.toml` with git URL (or local path), integer priority, and optional `ref` (branch/tag/commit)
- Higher priority wins on conflict
- Default merge strategies by file type:
  - Structured files (`.yaml`, `.json`, `.toml`): deep merge, incoming wins at leaf. Arrays: replace (incoming replaces existing entirely)
  - All other files (`.md`, `.txt`, etc.): overwrite
- Per-layer strategy override available (`merge` or `overwrite` for all files in that layer)
- `.afb/project/` is the implicit highest-priority layer
- `afb.local.toml` deep-merges over `afb.toml` using same rules. Processed after manifest, before layer composition. Gitignored
- `afb sync` composes layers into `.ai/`, validates, then runs the configured sync command (default: `lnai sync`)

### FR3: Drift Detection

`afb diff` detects divergence at two levels, running **inside the container** from within the project directory:

1. **Composition drift**: current `.ai/` vs what compose would produce
2. **Runtime drift**: current `.claude/`, `.opencode/`, `.mcp.json` vs what the sync command would generate from composed `.ai/`

Stage 2 does NOT assume `lnai sync --dry-run` exists. Instead: compose to temp dir, run `lnai sync` in a temp HOME override, diff output against actual runtime dirs.

Runtime drift catches changes made directly by runtimes (e.g., Claude Code adding an MCP server via UI). Reports divergence per file.

`afb doctor` is the entry point for drift checks — it calls the diff logic as part of its diagnostics.

### FR4: Upstream Push

`afb push` pushes local changes in all layer dirs back to their upstream git repos. `afb push <layer>` for a specific layer.

### FR5: Script Runner

`afb run <name>` executes a script from the configured scripts directory. `afb run <component>.<command>` runs a named component command. Convenience only — no pre/post hooks, no lifecycle.

### FR6: Container Isolation

Every project harness runs inside a container. This is the single isolation mechanism — HOME/XDG overrides are not used.

The container is self-contained: harness tools, project code, and composed config all live inside the image. Shared services (MCP servers, databases) run in adjacent containers, connected via compose networking.

**Container-first benefits**:
- Eliminates fragile HOME/XDG override hacks
- Enables safe permissive-mode agent runs
- Makes harness versioning trivial (new image = new version)
- Blue-green deployment: run test harness alongside production via `afb up --project <name>`

**LLM agents can deploy and verify AFB during development** without manual intervention — the container is the test environment.

**Three-tier test strategy** (from architecture.md):
1. **Unit**: core domain (manifest parsing, compose, merge, generation). No external deps — uses in-memory FS adapter
2. **Integration**: adapter packages + cross-package workflows. Requires git
3. **E2E**: full harness lifecycle. Requires container runtime. Tests build → up → verify inside container → down

### FR7: Observability

Structured logs to stderr via zerolog. Log level via `AFB_LOG_LEVEL` env var. 12-factor: logs are event streams, not files.

### FR8: Component Commands (replaces top-level backup)

Components define arbitrary named commands in `[components.NAME.commands]`. User writes scripts in `.afb/scripts/` to orchestrate them. No top-level `afb backup` command — backup is a user-defined command convention (`doctor`, `backup`, etc.) invoked via `afb run`.

### FR9: Validation

`afb validate` checks:
1. `afb.toml` syntax and schema validity
2. Composed `.ai/` directory validity — delegates to `lnai validate`

Validation runs AFTER compose but BEFORE the sync command. If validation fails, sync never runs, runtime configs are untouched.

Can be invoked standalone. Also runs automatically inside `afb sync`.

### FR10: Container Build and Lifecycle

AFB generates Containerfiles and Compose files from `afb.toml`, then delegates lifecycle to `podman-compose` / `docker-compose`.

- `afb build` — generate `.afb/generated/Containerfile` + `compose.yaml`, run `{runtime}-compose build`. `--strict` fails on error
- `afb up [--project <name>]` — `{runtime}-compose up -d`. `--project` for parallel test instances
- `afb down [--project <name>]` — `{runtime}-compose down`
- `afb rebuild` — build + down + up (convenience)

Testing a new harness version alongside production:
```
afb build
afb up --project afb-myproject-test
# verify
afb down --project afb-myproject-test
# if good: afb rebuild
```

### FR11: Remote & Session Compatibility

AFB must work over SSH (including Tailscale SSH) and inside tmux sessions:

- No interactive prompts or GUI dependencies (all input via flags, env vars, or manifest)
- No localhost-only assumptions
- Log output usable in headless/detached sessions (structured stderr, no ANSI unless TTY detected)
- Component hooks must be non-interactive (user's responsibility; AFB documents this constraint)

Remote harness management: user SSHes in, runs AFB locally on the remote machine. No remote execution mode needed.

## Non-Functional Requirements

| ID | Requirement |
|----|-------------|
| NFR1 | **Composability** — enabling/disabling a component + `afb sync` must not break the system and must leave no residue |
| NFR2 | **Declarative** — `afb.toml` describes desired state; AFB converges reality to match |
| NFR3 | **Lightweight** — single Go binary, no runtime dependencies beyond `git` and a container runtime (podman or docker) |
| NFR4 | **Fast** — CLI operations complete in seconds |
| NFR5 | **Testable** — formalized Go test suite, CI-compatible, three-tier strategy |
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

Memory tools (CASS, mcp-memory-service, cq, Napkin, etc.) are managed as AFB components. AFB installs, updates, and runs backup commands on them. Memory architecture (L1 session search → L2 semantic store → L3 learning store → L4 repo map) is documented separately. AFB treats memory tools as opaque components.

Cross-machine memory sync: automated nightly backup of SQLite files to shared git repo. Restore on other machines. Philosophy: eventual consistency is acceptable — memory data is append-mostly, conflicts are rare for a solo dev.

> Note (Challenge 9 — not resolved): "Append-mostly" doesn't prevent duplicates — it guarantees them. If the same task is worked on from both machines in one day, both machines add memories about the same topic. Nightly sync merges both sets, producing duplicate or near-duplicate entries. Deduplication is the memory tool's responsibility, not AFB's. If the memory tool doesn't dedup, noise accumulates over time. Acceptable for now; reassess when actually running cross-machine.

### Concern 3: Orchestration (deferred)

Gas City is the primary candidate. AFB installs and configures it as a component inside the project container. Workflow enforcement (ATDD stages, review gates) is Gas City's responsibility. Evaluate at Phase 3.

Until then: manual tmux, beads + Agent Mail for coordination.

HUD may be subsumed by Gas City. Evaluate alongside.

### Concern 4: Deployment & Lifecycle

AFB itself. The manifest + CLI. Gets built and dogfooded first.

## Verification Criteria

Architecture is successful when:

1. Adding a runtime to a project = edit `.afb/project/config.yaml` + `afb sync`
2. Removing a component = set `enabled = false` in `afb.toml` + `afb rebuild` → no residue in new container
3. Shared config change propagates via `afb layer pull` + `afb sync`
4. Config drift detectable via `afb diff` (both composition and runtime levels)
5. Fresh machine setup = clone project + `afb build` + `afb up` + restore named volumes from backup
6. All stateful components have backup via `afb run <component>.backup`
7. Test harness deployable in isolation via `afb up --project <test-name>` without clobbering production
8. `afb.lock` records installed state; `afb doctor` reports drift between declared and actual
9. `afb lock --check` exits non-zero when lockfile is stale
10. `afb doctor` provides context-aware diagnostics (project context vs host context)

## Phased Adoption

### Phase 1: Deployment Infra + Config Sync

Build AFB CLI (`init`, `sync`, `diff`, `validate`, `lock`, `doctor`). Implement layer composition. Integrate LNAI. Implement container generation (`build`, `up`, `down`, `rebuild`). Dogfood with Claude Code + OpenCode on one project. Validate composability guarantee.

### Phase 2: Memory Foundation

Add memory tools as components (CASS, Napkin, one semantic store). Validate install + version + backup commands. Test cross-runtime memory access via MCP. Container registry for cross-machine image sharing.

### Phase 3: Orchestration Evaluation

Install Gas City as component inside project container. Test workflow enforcement. Evaluate pack system overlap with AFB layers. Evaluate whether Gas City subsumes HUD. Fallback: beads + hooks.

### Phase 4: Polish

`afb push`, cross-machine sync via shared git repo, CI integration, continuous improvement metrics. Host harness management (`afb` on host lists running harness containers).

## Unresolved Questions

1. **Shared services management**: should `~/afb-shared/` be a standard convention documented by AFB, or should AFB provide a built-in `afb shared init/up/down` command? Leaning convention — it's just another AFB project
2. **Per-file merge strategy overrides**: needed, or per-layer sufficient?
3. **Statistical process control metrics**: what to track, how to couple with logging?
4. **AgentGateway config generation**: how much of gateway config should AFB generate from `[mcp]` declarations? Investigate AgentGateway's config format
5. **afb.local.toml merge edge cases**: what if local manifest adds a layer or changes priority? Need clear semantics for what local overrides can and cannot do
