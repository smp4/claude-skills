# AFB Architecture

> Status: Draft (rev 4)
> Date: 2026-04-26
> Companion: spec.md, domain.md

## Overview

AFB is a Go CLI that reads a TOML manifest (`afb.toml`) and orchestrates config composition, container image builds, and component lifecycle. It is a thin coordinator — format translation is LNAI's job, orchestration is Gas City's job, memory is MCP servers' job. AFB's own logic: parse manifest, compose layers, generate Containerfiles and Compose files, shell out to tools, report results.

**Container-first design**: every project harness runs inside a container. The container is self-contained — harness tools, project code, and composed config all live inside the image. Shared services (MCP servers, databases) run in adjacent containers or on the host, connected via network. This eliminates isolation hacks (HOME/XDG overrides), enables safe permissive-mode agent runs, and makes harness versioning trivial (new image = new version).

AFB contains a thin translation layer: it maps its own manifest structure and composed config into the `.ai/` directory format that LNAI expects. This translation is deliberately minimal (directory copy + merge) so that swapping LNAI for a future alternative requires changing only the sync command and possibly the `.ai/` output format.

**LNAI replaceability**: LNAI has few maintainers and 239 stars. Something better will likely emerge. AFB's coupling to LNAI is a single configurable shell command (`[sync].command`). The user can switch sync tools by changing one line in afb.toml without modifying afb itself.

**Significant weakness**: AFB is a wrapper around wrappers. LNAI wraps runtime configs. AFB wraps LNAI. Each abstraction layer adds failure modes and debugging depth. This is inherent to the coordinator role — the alternatives (building a custom format translator, using a general-purpose config manager like Ansible, manual shell scripts) are all worse. Managed by keeping AFB's scope minimal and each layer independently removable.

**Scope boundary**: AFB generates Containerfiles and Compose files. It does NOT become a container orchestrator — it delegates lifecycle to `podman-compose` / `docker-compose`. AFB's container role is declarative generation, not runtime management.

## Primitives

| Primitive         | Description                                    | Durable?                                                 | Owned by         |
| ----------------- | ---------------------------------------------- | -------------------------------------------------------- | ---------------- |
| **Manifest**      | `afb.toml` — desired state declaration         | Yes (git)                                                | User             |
| **Local manifest**| `afb.local.toml` — user overrides              | No (gitignored)                                          | User             |
| **Lockfile**      | `afb.lock` — records resolved state            | Yes (git)                                                | AFB (generated)  |
| **Component**     | External tool with lifecycle hooks + commands  | Declaration in manifest; state owned by component        | User + component |
| **Layer**         | Config source with priority + merge strategy   | Content is external (git repos); declaration in manifest | User             |
| **Script**        | User shell script in `.afb/scripts/`           | Yes (git)                                                | User             |
| **Containerfile** | Generated image definition for project harness | Generated (`.afb/generated/`)                            | AFB              |
| **Compose file**  | Generated multi-container orchestration        | Generated (`.afb/generated/`)                            | AFB              |

AFB does not introduce new concepts for targets — target configuration lives in the composed `.ai/config.yaml` and is read by LNAI directly.

## Directory Layout

```
project-root/
├── afb.toml                    # manifest (committed)
├── afb.local.toml              # user overrides (gitignored)
├── afb.lock                    # resolved state (committed, generated)
├── .afb/
│   ├── project/                # project-specific config (committed)
│   │   ├── AGENTS.md           #   highest-priority layer
│   │   ├── rules/
│   │   ├── skills/
│   │   ├── settings.yaml       #   MCP servers, permissions
│   │   └── config.yaml         #   which targets enabled
│   ├── layers/                 # external layers (gitignored)
│   │   ├── base/               #   cloned from git
│   │   └── team/               #   cloned from git
│   ├── generated/              # generated container files (gitignored)
│   │   ├── Containerfile       #   project harness image
│   │   ├── compose.yaml        #   multi-container orchestration
│   │   └── .env                #   runtime env vars for compose
│   └── scripts/                # user scripts (committed)
│       └── install-custom.sh
├── .ai/                        # composed output (gitignored, also exists inside container)
│   ├── AGENTS.md
│   ├── rules/
│   ├── skills/
│   ├── settings.yaml
│   └── config.yaml
├── .claude/                    # generated by LNAI (gitignored, lives inside container)
├── .opencode/                  # generated by LNAI (gitignored, lives inside container)
└── .mcp.json                   # generated by LNAI (gitignored, lives inside container)
```

**What's committed**: `afb.toml`, `afb.lock`, `.afb/project/`, `.afb/scripts/`
**What's gitignored**: `.ai/`, `.claude/`, `.opencode/`, `.mcp.json`, `.afb/layers/`, `.afb/generated/`, `afb.local.toml`
**What's external**: layer git repos, component state (SQLite DBs, etc.), backups
**What's inside the container**: project code (cloned), `.ai/`, `.claude/`, `.opencode/`, `.mcp.json`, all component binaries

**afb.local.toml**: user-specific overrides that deep-merge over `afb.toml` using the same merge rules as layers. Gitignored. Use case: personal tool preferences, local paths, dev-mode overrides (e.g., `mount_workspace = true` for bind-mount debugging). Processed after `afb.toml`, before layer composition.

`.afb/project/` is functionally a layer — the highest-priority one. Named "project" because it contains the same type of content as `.afb/layers/*` dirs (rules, skills, settings), just committed to the project repo instead of pulled from an external source.

## Application Architecture

### Architecture Selection

Three candidates evaluated for a Go CLI of this scope:

| Architecture | Fit | Verdict |
|-------------|-----|---------|
| **Ports & Adapters (Hexagonal)** | Core domain defines interfaces (ports). External tools implement them (adapters). Commands wire core + adapters | **Selected** |
| **Simple Package-per-Feature** | Direct function calls, no abstraction layers. Go-idiomatic, less code | Rejected: can't unit-test composition without real git repos and container runtimes. Every test becomes integration |
| **Pipeline / Dataflow** | Each command is a linear pipeline of stages | Rejected: forces linearity. `afb doctor` doesn't fit a pipeline. Awkward for commands with branching logic |

**Not considered**: Clean Architecture (4+ layers for a CLI is absurd), CQRS (no read/write split), event-driven (no events).

### Why Ports & Adapters

AFB has 4-5 external tools that are explicitly designed to be swappable:
- **Sync command**: LNAI today, something else tomorrow (`[sync].command`)
- **Container runtime**: podman or docker (`[container].runtime`)
- **Compose tool**: podman-compose or docker-compose
- **Git**: shell out to `git` CLI (could become go-git later)
- **Filesystem**: OS filesystem (test with in-memory FS)

The architecture should make swappability structural, not accidental. Go's implicit interfaces keep this lightweight — define the interface where it's consumed, not in a separate package.

**Weakness**: interface proliferation risk. Mitigation: only define ports for genuinely external/swappable dependencies. Internal packages call each other directly. No port for "manifest parsing" — that's core domain.

### Port Definitions

```go
// Git operations — consumed by layer package
type Git interface {
    Clone(url, dest string, ref string) error
    Pull(dir string) error
    Push(dir string) error
    ResolveRef(dir string) (string, error)  // returns commit hash
}

// Container runtime — consumed by container package
type ContainerRuntime interface {
    Build(contextDir, containerfile string, tag string, args map[string]string) error
    ComposeUp(composeFile string, project string, detach bool) error
    ComposeDown(composeFile string, project string) error
    ImageID(tag string) (string, error)
}

// Sync command — consumed by sync package
type SyncCommand interface {
    Run(projectDir string) error
    Validate(projectDir string) error
}

// Filesystem — consumed by layer, diff packages
type FS interface {
    ReadFile(path string) ([]byte, error)
    WriteFile(path string, data []byte, perm os.FileMode) error
    Walk(root string, fn filepath.WalkFunc) error
    MkdirAll(path string, perm os.FileMode) error
    RemoveAll(path string) error
    // ... standard fs operations
}
```

### Adapter Implementations

| Port | Adapter | Implementation |
|------|---------|---------------|
| `Git` | `GitCLI` | Shells out to `git` binary |
| `ContainerRuntime` | `PodmanRuntime` | Shells out to `podman` + `podman-compose` |
| `ContainerRuntime` | `DockerRuntime` | Shells out to `docker` + `docker-compose` |
| `SyncCommand` | `LNAISync` | Shells out to `lnai sync` / `lnai validate` |
| `FS` | `OSFS` | Standard `os` package |
| `FS` | `MemFS` | In-memory filesystem for unit tests |

### Dependency Wiring

Cobra commands wire ports to adapters in `cmd/afb/`. No DI framework — constructor injection:

```go
func newSyncCmd() *cobra.Command {
    return &cobra.Command{
        Use: "sync",
        RunE: func(cmd *cobra.Command, args []string) error {
            manifest := manifest.MustLoad("afb.toml")
            git := gitcli.New()
            fs := osfs.New()
            syncCmd := lnaisync.New(manifest.Sync.Command)
            return sync.Run(manifest, git, fs, syncCmd)
        },
    }
}
```

## Go Project Structure

```
afb/
├── cmd/afb/
│   └── main.go                 # cobra root + subcommands, dependency wiring
├── internal/
│   ├── domain/                 # core domain — pure logic, no external deps
│   │   ├── manifest/           # afb.toml parsing, validation, variable expansion
│   │   │   ├── manifest.go
│   │   │   ├── local.go        # afb.local.toml merge
│   │   │   └── manifest_test.go
│   │   ├── lock/               # afb.lock read/write/check
│   │   │   ├── lock.go
│   │   │   └── lock_test.go
│   │   ├── compose/            # layer composition algorithm, deep merge
│   │   │   ├── compose.go
│   │   │   ├── merge.go        # deep merge orchestration (delegates to mergo)
│   │   │   └── *_test.go
│   │   └── generate/           # Containerfile + compose.yaml generation
│   │       ├── containerfile.go
│   │       ├── composefile.go
│   │       └── *_test.go
│   ├── ports/                  # interface definitions (small file per port)
│   │   ├── git.go
│   │   ├── runtime.go
│   │   ├── sync.go
│   │   └── fs.go
│   ├── adapters/               # external tool implementations
│   │   ├── gitcli/
│   │   │   └── git.go          # Git port via git CLI
│   │   ├── podman/
│   │   │   └── runtime.go      # ContainerRuntime port via podman
│   │   ├── docker/
│   │   │   └── runtime.go      # ContainerRuntime port via docker
│   │   ├── lnaisync/
│   │   │   └── sync.go         # SyncCommand port via lnai
│   │   └── osfs/
│   │       └── fs.go           # FS port via os package
│   ├── doctor/                 # afb doctor logic (traversal, checks)
│   │   └── doctor.go
│   ├── diff/                   # drift detection (both stages)
│   │   └── diff.go
│   └── runner/                 # script + component command execution
│       └── runner.go
├── testdata/                   # test fixtures (sample manifests, layer dirs)
├── go.mod
└── go.sum
```

Core domain packages (`internal/domain/*`) have zero external tool dependencies — they depend only on port interfaces and stdlib. This makes them unit-testable without git, containers, or filesystem.

Adapter packages (`internal/adapters/*`) implement ports by shelling out to external tools. Integration-tested.

## Container Architecture

### Design Principles

1. **Self-contained**: each project container includes the harness (AFB, LNAI, runtimes), project code (cloned from git), and composed config. No host mounts for project files.
2. **Shared services via network**: MCP servers and databases run in their own containers (or on host), accessed over the network. Agent containers connect to them via Compose networking.
3. **Podman preferred**: rootless, daemonless, no sudo. Docker compatible — Compose files work with both `podman-compose` and `docker-compose`.
4. **Declarative**: AFB generates Containerfiles and Compose files from `afb.toml`. User runs `podman-compose up` (or AFB wraps this).
5. **Disposable**: containers are ephemeral. State lives in named volumes or external services. Rebuild image = fresh harness.

### Container Topology

Two tiers of compose projects:

**Tier 1 — Shared services** (`afb-shared`): machine-wide MCP servers, databases. Managed by a dedicated manifest. Creates an external network that project containers join.

**Tier 2 — Per-project** (`afb-{dirname}`): project container with harness + code. Joins the shared services network.

```
┌─────────────────────────────────────────────────────┐
│                    Host machine                      │
│                                                      │
│  Compose project: afb-shared                         │
│  ┌──────────────────────────────────────┐            │
│  │  agentgateway     cass       memory  │            │
│  │  (Streamable HTTP) (SSE)     (stdio  │            │
│  │                              via gw) │            │
│  │  ┌────────────────────────────────┐  │            │
│  │  │     shared network             │  │            │
│  │  └────────────┬───────────────────┘  │            │
│  └───────────────┼──────────────────────┘            │
│                  │ external network                   │
│         ┌────────┴─────────┐                         │
│         │                  │                         │
│  ┌──────┴───────┐  ┌──────┴───────┐                 │
│  │ afb-project-a│  │ afb-project-b│                 │
│  │              │  │              │                 │
│  │ claude-code  │  │ opencode     │                 │
│  │ afb + lnai   │  │ afb + lnai   │                 │
│  │ project repo │  │ project repo │                 │
│  │ .ai/ .claude/│  │ .ai/.opencode│                 │
│  └──────────────┘  └──────────────┘                 │
│                                                      │
│  Named volumes: cass-data, memory-data, claude-auth  │
└─────────────────────────────────────────────────────┘
```

### Shared Services Architecture

Shared services (CASS, memory, MCP gateway) are machine-wide — one instance per machine, shared by all project harnesses. They are managed by a separate `afb.toml` in a dedicated directory (e.g., `~/afb-shared/`).

Per-project `afb.toml` references shared services as external — it doesn't define them, just connects to them:

```toml
[mcp.cass]
external = true
address = "cass:9100"
network = "afb-shared_harness"    # external compose network to join
```

The shared services compose project creates a named network. Per-project compose files join that network via `external: true` in the networks section.

This separation means:
- Shared services start once, serve all projects
- Per-project rebuild doesn't restart shared services
- Named volumes for shared data (cass-data, memory-data) belong to the shared compose project
- Per-project volumes (claude-auth) belong to the project compose project

### MCP Server Sharing

MCP uses two transport modes. SSE is deprecated — Streamable HTTP is the recommended transport for new integrations.

| Transport                 | How to share          | Approach                                                                                                              |
| ------------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **Streamable HTTP**       | Native network access | Run in own container, expose port. Agent containers connect via `http://service-name:port` on compose network         |
| **stdio**                 | Requires gateway      | Run behind an MCP gateway that wraps stdio in Streamable HTTP. Gateway container exposes unified endpoint             |

**MCP gateway**: AgentGateway (agentgateway/agentgateway) — 2.3k stars, Rust, Linux Foundation, v1.0. Supports tool federation, all transports (stdio/HTTP/SSE/Streamable HTTP), OAuth. Runtime-agnostic — works with both Podman and Docker. AFB declares which MCP servers need gateway wrapping in `afb.toml`; the generated Compose file configures the gateway container accordingly.

Stdio servers that only one agent uses can run inside that agent's container directly (no gateway needed). The gateway is for shared access across containers.

### Generated Containerfile

AFB generates `.afb/generated/Containerfile` from `afb.toml`:

```dockerfile
# Generated by afb — do not edit
FROM node:20-bookworm-slim AS base

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git openssh-client ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# Extra packages (from [container].extra_packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    iptables ipset \
    && rm -rf /var/lib/apt/lists/*

# Install AFB
COPY --from=golang:1.23-bookworm /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"
RUN go install github.com/user/afb@v0.1.0

# Install components (from afb.toml [components])
RUN npm install -g lnai@0.6.91
RUN npm install -g @anthropic-ai/claude-code@latest
# ... other components from manifest

# Extra commands (from [container].extra_run)
# RUN <user-defined commands here>

# Clone project
ARG PROJECT_REPO
ARG PROJECT_REF=main
RUN git clone ${PROJECT_REPO} /workspace && \
    cd /workspace && git checkout ${PROJECT_REF}

# Copy manifest and project config
WORKDIR /workspace
# afb.toml and .afb/project/ are part of the cloned repo

# Compose layers and sync
RUN afb sync

# Runtime
ENV AFB_LOG_LEVEL=info
ENTRYPOINT ["claude"]
```

The Containerfile is generated line by line from parsed manifest data, not templated. This avoids template-language complexity and makes the output inspectable.

**ENTRYPOINT** configurable via `[container].entrypoint` in afb.toml. Defaults to the first enabled runtime. Eventually the workflow orchestrator (Gas City) when integrated.

**Containerfile customization**: follows the Aptfile/Devbox pattern — `extra_packages` is a list of apt packages installed in a dedicated layer, `extra_run` is a list of arbitrary shell commands run after package install. This covers common needs without a feature/plugin system. Users needing full control can fork the generated Containerfile. Cache-busting: extra_packages and extra_run are ordered after component installs — changes to them don't invalidate the component install cache.

### Generated Compose File

AFB generates `.afb/generated/compose.yaml`. For a per-project container:

```yaml
# Generated by afb — do not edit
services:
  project-a:
    build:
      context: ../..
      dockerfile: .afb/generated/Containerfile
      args:
        PROJECT_REPO: git@github.com:user/project-a.git
        PROJECT_REF: main
    stdin_open: true
    tty: true
    networks:
      - harness
      - afb-shared_harness    # join shared services network
    environment:
      - CLAUDE_CONFIG_DIR=/home/node/.claude
    volumes:
      - claude-auth:/home/node/.claude
    # no depends_on — shared services managed separately

networks:
  harness:
    driver: bridge
  afb-shared_harness:
    external: true              # created by shared services compose

volumes:
  claude-auth:
```

For the shared services compose (`~/afb-shared/`):

```yaml
# Generated by afb — do not edit
services:
  agentgateway:
    image: ghcr.io/agentgateway/agentgateway:v1.0
    networks:
      - harness
    ports:
      - "8080:8080"

  cass:
    image: cass:latest
    networks:
      - harness
    volumes:
      - cass-data:/data
    ports:
      - "9100:9100"

networks:
  harness:
    driver: bridge

volumes:
  cass-data:
  memory-data:
```

### Compose Project Naming

Default: `afb-{dirname}` where dirname is the project directory name. Predictable, unique enough for single-machine use, visible in `podman-compose ps`.

| Scenario | Project name |
|----------|-------------|
| Normal project | `afb-myproject` (auto from dirname) |
| Test alongside prod | `afb-myproject-test` (via `afb up --project afb-myproject-test`) |
| Shared services | `afb-shared` (convention) |
| Custom | `[container].project_name` overrides in afb.toml |

### Authentication

| Method              | When                | How                                                                                                                    |
| ------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **OAuth (Pro sub)** | Interactive use     | `claude auth login` inside container. Token stored in named volume (`claude-auth`). Persists across container rebuilds |
| **API key**         | Headless / CI       | `ANTHROPIC_API_KEY` env var in compose `.env` file (gitignored) or injected via secrets                                |
| **apiKeyHelper**    | Enterprise rotation | Script in container that outputs short-lived key                                                                       |

For Pro subscription: authenticate once per container. Named volume preserves the token. No host `~/.claude/` mount needed.

### Image Lifecycle

```
afb.toml changed
    │
    ├─ afb build          → regenerate Containerfile + compose.yaml
    │                       → podman-compose build (or docker-compose build)
    │
    ├─ afb up             → podman-compose up -d
    │                       (starts project container, joins shared network)
    │
    ├─ afb down           → podman-compose down
    │
    └─ afb rebuild        → build + down + up (convenience)
```

**Updating an existing harness**: edit `afb.toml` → `afb rebuild`. Old container is replaced. Named volumes (auth tokens) persist. Project code is re-cloned at the specified ref.

**Template-driven updates**: if the manifest was scaffolded from a template (`afb init --template`), the template source and ref are recorded in `[template]`. `afb doctor` checks if the upstream template has changed and recommends a merge. The user decides whether to incorporate upstream changes — no auto-update.

### Development Workflow Inside Containers

The container clones the project repo at build time. For active development:

**Golden path — Develop inside container**: use VS Code Dev Containers or similar to open a shell inside the running container. Edit code there directly. Changes are in the container's filesystem — commit and push from inside, or lose on rebuild. This follows the well-known Dev Containers workflow.

**Escape hatch — Bind mount workspace**: for situations where Dev Container integration isn't available or performance matters. Add to afb.toml or afb.local.toml:

```toml
[container]
mount_workspace = true   # bind-mount project dir instead of cloning
```

This generates a volume mount in compose.yaml instead of the `git clone` step in Containerfile. macOS bind mount performance is acceptable at single-dev scale. Best put in `afb.local.toml` since it's a local development preference.

**Harness config changes**: edit `afb.toml` → `afb rebuild`. This is for changing components, layers, container config — not for editing project code.

## Data Model: afb.toml

```toml
[settings]
scripts_dir = ".afb/scripts"

[sync]
command = "lnai sync"

# --- Template (recorded by afb init --template) ---

[template]
source = "git@github.com:team/templates.git//harness/standard"
ref = "v1.0"
ref_resolved = "abc123def456"    # commit hash at init time

# --- Container ---

[container]
runtime = "podman"          # podman | docker
entrypoint = "claude"       # default command when container starts
base_image = "node:20-bookworm-slim"
mount_workspace = false     # true = bind-mount host project dir
project_name = ""           # override compose project name (default: afb-{dirname})
strict = false              # true = fail build on any error (--strict flag overrides)
build_args = { PROJECT_REPO = "git@github.com:user/project.git", PROJECT_REF = "main" }
extra_packages = ["iptables", "ipset"]              # additional apt packages
extra_run = ["curl -fsSL https://example.com/setup.sh | sh"]  # arbitrary build commands

# --- Layers ---
# Composed in priority order (ascending). .afb/project/ is implicit highest
# priority. Higher priority wins on merge conflict.

[layers.base]
source = "git@github.com:user/ai-base-config.git"
priority = 10
ref = "main"                    # branch, tag, or commit hash (default: default branch)
# strategy: merge (default) | overwrite

[layers.team]
source = "git@github.com:team/ai-config.git"
priority = 20
ref = "v1.2.0"                 # pin to specific tag

# --- Components ---
# install is required. version, doctor, and user-defined commands are optional.

[components.lnai]
enabled = true
version_spec = "0.6.91"
install = "npm install -g lnai@${version_spec}"
version = "lnai --version"           # outputs installed version for lockfile

[components.lnai.commands]
doctor = "lnai --version"

[components.claude-code]
enabled = true
install = "npm install -g @anthropic-ai/claude-code@latest"
version = "claude --version"

[components.claude-code.commands]
doctor = "claude --version"

[components.cass]
enabled = true
install = "apt-get install -y cass"
version = "cass --version"

[components.cass.commands]
doctor = "which cass"
backup = "cp ~/.config/cass/*.db ${backup_dir}/"

[components.mcp-memory-service]
enabled = false
install = ".afb/scripts/install-mcp-memory.sh"

[components.mcp-memory-service.commands]
backup = "cp data/sqlite_vec.db ${backup_dir}/mcp-memory.db"

[components.napkin]
enabled = true
install = "echo 'skill file, no binary to install'"

[components.gascity]
enabled = false
install = "go install github.com/gastownhall/gascity@latest"
version = "gascity version"

[components.gascity.commands]
doctor = "gascity version"

# --- MCP Services ---
# Services defined here are project-local (run in project's compose).
# For shared services, use external = true.

[mcp.cass]
external = true
address = "cass:9100"
network = "afb-shared_harness"

[mcp.memory]
external = true
address = "agentgateway:8080"     # accessed via gateway
network = "afb-shared_harness"

# Example of a project-local MCP server (not shared):
# [mcp.project-tools]
# image = "project-tools:latest"
# transport = "streamable-http"
# port = 9200
# volumes = ["tools-data:/data"]
```

### Component Model

Components are opaque — AFB runs hook commands without understanding what the component does. The hooks and commands:

| Field | Purpose | Required? |
|-------|---------|-----------|
| `install` | Install the component | Yes |
| `version_spec` | Desired version (used in install command variable expansion) | No |
| `version` | Command that outputs installed version (captured for lockfile) | No |
| `[commands]` | Named user-defined commands (doctor, backup, etc.) | No |

**No `uninstall` command**: containers are disposable. To remove a component, set `enabled = false` in `afb.toml` and `afb rebuild`. The new image simply doesn't include it. No side-path that can drift from manifest.

**Composable commands**: instead of fixed hooks (`backup`, `health`), components define arbitrary named commands in `[components.NAME.commands]`. Invoked via `afb run <component>.<command>`. Scripts in `.afb/scripts/` can orchestrate multiple component commands (e.g., a `backups.sh` that calls `afb run cass.backup` then `afb run mcp-memory-service.backup`).

### afb.local.toml

User-specific overrides. Deep-merged over `afb.toml` using the same merge rules as layers. Gitignored.

Common uses:
- `mount_workspace = true` for local bind-mount development
- Local tool paths
- Dev-mode settings
- Override `strict = true` for local builds

### Variable Expansion

Variables available in all hook commands and component commands:

| Variable          | Source                                               |
| ----------------- | ---------------------------------------------------- |
| `${version_spec}` | Component's own `version_spec` field                 |
| `${scripts_dir}`  | `[settings].scripts_dir`                             |
| `${project_root}` | Absolute path to project root (where afb.toml lives) |

Simple string substitution. No template language, no conditionals. `${backup_dir}` removed as a built-in — define it in a script or component command as a local variable.

## Lockfile

### Purpose

`afb.lock` records the exact resolved state of the harness. Committed to git. Enables reproducibility across machines and users. Modeled on uv's lock/sync workflow.

### Contents

```toml
# afb.lock — generated by afb, do not edit
# Resolved at: 2026-04-26T07:00:00Z

[components.lnai]
installed_version = "0.6.91"     # output of version hook
installed_at = "2026-04-26T07:00:00Z"
install_ok = true

[components.claude-code]
installed_version = "1.0.31"
installed_at = "2026-04-26T07:00:00Z"
install_ok = true

[components.cass]
installed_version = "2.1.0"
installed_at = "2026-04-26T07:01:00Z"
install_ok = true

[components.napkin]
# no version hook — only tracks install status
installed_at = "2026-04-26T07:01:00Z"
install_ok = true

[layers.base]
ref_requested = "main"
ref_resolved = "abc123def456"    # actual commit hash
pulled_at = "2026-04-26T07:00:00Z"

[layers.team]
ref_requested = "v1.2.0"
ref_resolved = "def789abc012"
pulled_at = "2026-04-26T07:00:00Z"

[container]
image_id = "sha256:abc123..."
built_at = "2026-04-26T07:02:00Z"

[template]
ref_resolved = "abc123def456"    # template commit hash at init time
checked_at = "2026-04-26T07:00:00Z"
```

### Version Hook

The `version` field in a component is a shell command whose stdout is captured and stored in the lockfile as `installed_version`. It is **optional**. Components without it (e.g., skill files, prompt templates) get `install_ok = true` + timestamp, no version tracking.

This handles the heterogeneity problem — npm packages have versions, brew packages have versions, but skill files and scripts don't. The lockfile records what it can. Imperfect but useful, same as how `uv.lock` can't lock system packages.

### CLI Integration

| Command | What it does |
|---------|-------------|
| `afb lock` | Resolve all versions, commit hashes, image digests. Write `afb.lock` |
| `afb lock --check` | Exit non-zero if lockfile is stale (for CI) |
| `afb sync` | Compose + validate + sync + updates lockfile as side effect |

## Layer Composition Algorithm

```
COMPOSE(manifest):
    layers ← manifest.layers sorted by priority ASC
    target ← new empty temp directory

    FOR each layer in layers:
        dir ← .afb/layers/{layer.name}/
        IF dir not cloned:
            git clone layer.source → dir
            IF layer.ref specified:
                git -C dir checkout layer.ref
        FOR each file in dir (recursive, excluding .git/):
            dest ← target / relative_path(file)
            IF dest does not exist:
                copy file → dest
            ELSE:
                MERGE(dest, file, layer.strategy)

    # Project config is implicit highest priority
    FOR each file in .afb/project/ (recursive):
        dest ← target / relative_path(file)
        IF dest does not exist:
            copy file → dest
        ELSE:
            MERGE(dest, file, "merge")

    # Atomic replace
    remove .ai/ entirely
    move target → .ai/

MERGE(existing, incoming, strategy):
    IF strategy == "overwrite":
        replace existing with incoming
        RETURN
    # strategy == "merge" (default)
    ext ← file extension
    IF ext in {.yaml, .yml, .json, .toml}:
        deep_merge(existing, incoming)    # incoming wins at leaf (via mergo)
    ELSE:
        replace existing with incoming    # unstructured → overwrite
```

Cloning external git repos into `.afb/layers/` (which is gitignored) does not cause nested-repo errors — the outer git completely ignores gitignored directories. The inner repos have their own `.git/` dirs and work independently.

### Deep Merge Semantics

| Structure                                   | Behavior                                                      |
| ------------------------------------------- | ------------------------------------------------------------- |
| Object/map keys                             | Merge recursively. Incoming wins at leaf                      |
| Arrays                                      | **Replace** — incoming array replaces existing array entirely |
| Scalars                                     | Incoming wins                                                 |
| Key present in existing, absent in incoming | Preserved (no implicit deletion)                              |

Array replace is the safe default — predictable, avoids duplication. Uses `mergo.WithOverride` and `mergo.WithOverwriteWithEmptyValue` flags. Edge cases to test: nil vs empty maps, typed vs untyped interfaces, TOML's array/table-array types.

## Drift Detection

Drift detection runs **inside the container**, from within a project directory. AFB does not discover or manage containers from the host — that is deferred to future work.

Detection trigger: `afb doctor` traverses upward from cwd to git repo root, looking for the topmost `afb.toml`. If found, it runs drift checks as part of its diagnostics.

```
DIFF(manifest):
    # Stage 1: composition drift (.ai/ vs what compose would produce)
    expected_ai ← COMPOSE(manifest) to temp dir
    actual_ai ← current .ai/
    diff expected_ai vs actual_ai → report composition drift

    # Stage 2: runtime config drift (generated configs vs actual)
    temp_home ← create temp directory
    copy expected_ai → temp_home/project/.ai/
    run sync command in temp_home with HOME override
    expected_runtime ← temp_home/project/.claude/, .opencode/, .mcp.json
    actual_runtime ← current .claude/, .opencode/, .mcp.json
    diff expected_runtime vs actual_runtime → report runtime drift
```

Stage 2 does NOT assume `lnai sync --dry-run` exists. Instead: compose to temp dir, run `lnai sync` in a temp HOME, diff output against actual runtime dirs.

Stage 2 catches changes made directly by runtimes — e.g., Claude Code adding an MCP server via its UI.

## CLI Commands

| Command                 | What it does                                                                                                    |
| ----------------------- | --------------------------------------------------------------------------------------------------------------- |
| `afb init`              | Create `afb.toml` scaffold + `.afb/project/`. Add gitignore entries. Optional: `--template <source>[@ref]`     |
| `afb sync`              | Pull layers → compose → `.ai/` → validate → run sync command → update lockfile                                 |
| `afb sync --config`     | Config composition only (layers → compose → validate → sync command)                                           |
| `afb sync --components` | Component install/update only                                                                                   |
| `afb lock`              | Resolve all versions and commit hashes. Write `afb.lock`                                                       |
| `afb lock --check`      | Exit non-zero if lockfile stale. For CI                                                                        |
| `afb build`             | Generate Containerfile + compose.yaml from manifest. Run `{runtime}-compose build`. `--strict` fails on error  |
| `afb up`                | `{runtime}-compose up -d`. Optional `--project <name>` for parallel test instances                             |
| `afb down`              | `{runtime}-compose down`. Optional `--project <name>`                                                          |
| `afb rebuild`           | build + down + up                                                                                              |
| `afb doctor`            | Context-aware diagnostics (see below)                                                                          |
| `afb diff`              | Compose to temp, diff against current `.ai/` + runtime configs (both stages)                                   |
| `afb validate`          | Validate manifest schema + composed `.ai/` via `lnai validate`                                                 |
| `afb push [layer]`      | Push changes in layer dir(s) to upstream                                                                       |
| `afb run <target>`      | Execute `<target>`: either a script from scripts_dir, or `<component>.<command>` for component commands        |
| `afb layer pull [name]` | Git pull in specified (or all) layer dirs. Respects `ref` pin                                                  |
| `afb shell [service]`   | Open interactive shell in running container (default: project container)                                       |

### Command: `afb doctor`

Context-aware diagnostic command. Behavior depends on where it's called from.

**Detection**: traverses upward from cwd to git repo root, searching for `afb.toml`. The topmost `afb.toml` found is taken as the master manifest for the harness.

**Inside a project dir (harness context)**:
1. Check lockfile vs manifest sync (`afb lock --check` logic)
2. Check composition drift (`.ai/` vs expected)
3. Check runtime config drift (`.claude/`, `.opencode/`, `.mcp.json` vs expected)
4. Check template drift (if `[template]` exists, compare against upstream)
5. Run `doctor` command for each component that defines one
6. Report findings, recommend actions

**Outside a project dir (host context)**:
1. Check AFB prerequisites: podman/docker installed and version, compose tool installed, git installed
2. Report versions and availability
3. Recommend install actions if missing

### Command: `afb sync` (detailed)

```
1. Parse afb.toml (merge with afb.local.toml if present)
2. If --components or no flag:
   a. Run install hook for components with version drift (lockfile vs manifest)
   b. Run version hook, capture output
3. If --config or no flag:
   a. For each layer (by priority):
      i. If .afb/layers/{name}/ missing → git clone + checkout ref
      ii. Optionally git pull (if --pull flag)
   b. Run COMPOSE algorithm → writes .ai/
   c. Run validation (lnai validate)
   d. Shell out: sync command (default "lnai sync")
4. Update afb.lock with versions, layer commit hashes
5. Log summary: layers composed, files written, components synced
```

Validation (step 3c) runs BEFORE sync (step 3d). If validation fails, sync never runs, runtime configs are untouched.

Exit codes: 0 = success, 1 = composition error, 2 = validation error, 3 = sync command error, 4 = component install error.

### Command: `afb build` (detailed)

```
1. Parse afb.toml (merge with afb.local.toml if present)
2. Generate .afb/generated/Containerfile from [container] + [components]
3. Generate .afb/generated/compose.yaml from [container] + [mcp]
4. Generate .afb/generated/.env (non-secret runtime vars)
5. Detect runtime: podman or docker (from [container].runtime or auto-detect)
6. Shell out: {runtime}-compose build
7. If --strict and any step failed: exit non-zero
8. Update afb.lock with image ID
9. Log summary
```

**`--strict` flag**: in strict mode, any failure during Containerfile generation, compose build, component install, or post-setup scripts causes the entire build to fail. Default: best-effort (log errors, continue). Configurable in manifest: `[container].strict = true`. The `--strict` CLI flag overrides the manifest value.

### Command: `afb init` (detailed)

```
afb init                                        # minimal scaffold
afb init --template git@github.com:team/templates.git//path@ref
afb init --template /local/path/to/template.toml
```

When using `--template`:
1. Clone/fetch the template source
2. Copy template content to `afb.toml`
3. Record template source, ref, and resolved commit hash in `[template]` section
4. Mutable refs (`latest`, `main`) are resolved to a commit hash at init time — both the ref and resolved hash are recorded

`afb doctor` later checks if the upstream template has moved ahead of the recorded hash and warns the user.

### Install Failure Behavior

If a component's install hook fails: AFB logs the error (exit code + stderr), continues with remaining components, and records `install_ok = false` in lockfile. No auto-rollback.

In `--strict` mode: first install failure causes the entire build to fail.

## Technology Choices

| Choice                              | Rationale                                                                               |
| ----------------------------------- | --------------------------------------------------------------------------------------- |
| **Go**                              | Single binary, no runtime deps, fast startup, strong test stdlib. Aligns with Gas City  |
| **cobra**                           | Standard Go CLI framework for subcommands                                               |
| **BurntSushi/toml**                 | Mature, well-tested TOML parser                                                         |
| **dario.cat/mergo**                 | Proven deep merge library (9k+ stars). Handles recursive map merge with override        |
| **zerolog**                         | Structured JSON logging, zero-allocation, 12-factor compatible                          |
| **gopkg.in/yaml.v3**               | YAML parsing (mergo handles the merge logic)                                            |
| **encoding/json**                   | stdlib JSON parsing                                                                     |
| **git CLI**                         | Shell out for clone/pull/push. Respects user's git config, SSH keys                     |
| **podman / docker**                 | Container runtime. Shell out for build/up/down. Podman preferred (rootless, daemonless) |
| **podman-compose / docker-compose** | Multi-container orchestration. AFB generates compose.yaml, delegates lifecycle          |
| **AgentGateway**                    | MCP gateway for shared stdio servers. Linux Foundation, Rust, v1.0, runtime-agnostic   |

External runtime dependencies: `git`, `podman` or `docker`, `podman-compose` or `docker-compose`, configured sync command (default: `lnai` — installed inside container).

**Not using**: k3s/minikube/kind (overkill for 2-10 containers on 1-2 machines), Docker MCP Gateway (requires Docker Desktop — incompatible with Podman), yq/jq (mergo handles merge in-process), go-git (shell git is simpler), template engines (line-by-line generation suffices for Containerfiles).

## Test Strategy

### Three Tiers

| Tier | Tag | Dependencies | What's tested | Speed |
|------|-----|-------------|---------------|-------|
| **Unit** | (none) | None | Manifest parsing, composition algorithm, merge logic, Containerfile generation, lockfile read/write | Fast |
| **Integration** | `//go:build integration` | git | Real layer cloning, composition with real git repos, merge with real files | Medium |
| **E2E** | `//go:build e2e` | podman or docker | Build real images, start containers, verify harness inside, check logs, tear down | Slow |

### Unit Tests

Core domain packages (`internal/domain/*`) are pure logic. Test with in-memory FS adapter. No git, no containers, no filesystem.

- Parse sample manifests from `testdata/`
- Compose layers from in-memory file trees
- Assert merge results (especially edge cases: nil vs empty, array replace, typed interfaces)
- Generate Containerfile strings, assert content
- Generate compose.yaml strings, assert content
- Lockfile round-trip: write → read → compare

### Integration Tests

Adapter packages + cross-package workflows. Require git installed.

- Clone a test layer repo to temp dir, checkout ref, verify files
- Compose real layers from temp dirs, compare output
- Full sync workflow: parse → clone → compose → validate (mock sync command)

### E2E Tests

Full harness lifecycle. Require container runtime.

```
1. Parse test manifest from testdata/
2. afb build → generates Containerfile + compose.yaml, builds image
3. afb up → starts container
4. Exec inside container: verify .ai/ exists, runtime configs exist, components installed
5. Exec inside container: afb doctor → verify clean report
6. Exec inside container: afb diff → verify no drift
7. afb down → tear down
8. Verify: named volumes created, container removed
```

### CI: GitHub Actions

```yaml
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - run: go test ./...

  integration:
    runs-on: ubuntu-latest
    steps:
      - run: go test -tags integration ./...

  e2e:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        runtime: [podman, docker]
    steps:
      # podman is pre-installed on ubuntu runners
      - run: go test -tags e2e -runtime ${{ matrix.runtime }} ./...
```

Matrix tests both runtimes. E2e tests are tagged and slow — run on merge to main, not on every push.

### Limitations

- OAuth tokens in named volumes are per-container-runtime, not shared across podman/docker
- Full e2e tests require container runtime installed
- E2e test duration scales with number of components installed in test image

## Data Lifecycle

```
afb.toml (authored, committed)
    │
    ├─── afb.local.toml (user overrides, gitignored)
    │         │
    │         ▼ deep merge
    │    effective manifest
    │         │
    ├─── [layers] → git clone/pull → .afb/layers/*/
    │                                     │
    │                                     ▼
    │                              COMPOSE (merge by priority)
    │                                     │
    ├─── .afb/project/ ─────────────────►│ (highest priority)
    │                                     │
    │                                     ▼
    │                                .ai/ (composed, gitignored)
    │                                     │
    │                     ┌───────────────┤
    │                     ▼               ▼
    │              afb build         afb sync
    │                 │                   │
    │                 ▼                   ▼  sync command (lnai sync)
    │          .afb/generated/            │
    │          Containerfile         ┌────┼────┐
    │          compose.yaml          ▼    ▼    ▼
    │                 │          .claude/ .opencode/ .mcp.json
    │                 ▼          (generated, gitignored)
    │          podman-compose
    │          build / up
    │                 │
    │          ┌──────┴──────┐
    │          ▼             ▼
    │    project         shared services
    │    container       (separate compose project)
    │    (harness +
    │     project +
    │     runtime configs)
    │
    ├─── [components] → install hooks (run inside container at build time)
    │
    ├─── afb.lock (generated, committed — records resolved state)
    │
    └─── [scripts] → .afb/scripts/ (authored, committed)
```

**Derived/regenerable**: `.ai/`, `.claude/`, `.opencode/`, `.mcp.json`, `.afb/generated/`, container images
**Durable user data**: `afb.toml`, `.afb/project/`, `.afb/scripts/` — committed to project git
**Durable generated data**: `afb.lock` — committed, records resolved state
**Durable component data**: named volumes (SQLite DBs, auth tokens) — backed up via component commands
**External**: layer git repos — not part of project git

### Cross-Machine Sync

Two machines (Mac + Linux). Shared git repo for backups.

```
Machine A                          Shared git repo              Machine B
                                   (backup-state.git)
afb run *.backup ─► backup dir ──► git commit + push ─────► git pull ──► restore
                   (SQLite dumps,                                       (import)
                    config exports)
```

Container images can also be pushed to a registry for cross-machine sharing, avoiding rebuild on the second machine.

Nightly cron: run backup scripts, commit and push to shared repo. Memory data is append-mostly — duplicates are the memory tool's responsibility to handle, not AFB's.

## User Interaction Flows

### Initial Setup
```
afb init                    # scaffold afb.toml + .afb/project/
edit afb.toml               # declare components, layers, container config
afb build                   # generate Containerfile + compose.yaml, build image
afb up                      # start project container (joins shared network)
afb shell                   # enter container, authenticate runtimes
```

### Daily Work
```
# develop inside container via Dev Containers or afb shell...
# runtime modifies its own config (e.g., adds MCP server via Claude Code)
afb diff                    # what changed? (covers .ai/ AND runtime dirs)
# user cherry-picks desired changes into .afb/project/ or a layer dir
afb sync                    # recompose — reverts undesired drift, keeps adopted changes
afb push team               # push layer changes upstream
```

### Change Harness Config
```
# edit afb.toml (add component, change version, modify layer)
afb rebuild                 # build new image + restart container
                            # named volumes (auth) persist
```

### Try New Harness Version
```
# edit afb.toml with new versions
afb build                   # build new image
afb up --project afb-myproject-test   # run alongside production
# test, validate
afb down --project afb-myproject-test # tear down test
# if good: afb rebuild (replaces production)
```

### Add Component
```
# add [components.foo] entry to afb.toml
# if shared MCP server: add to shared services manifest
afb rebuild                 # image includes new component
```

### Remove Component
```
# set enabled=false in afb.toml (or delete the section)
afb rebuild                 # image excludes component, no residue
```

### Fresh Machine
```
# install afb binary (go install or download release)
# install podman + podman-compose
# start shared services (cd ~/afb-shared && afb build && afb up)
git clone <project>
afb build                   # builds everything from manifest
afb up                      # start
# pull backups from shared git repo, restore to named volumes
```

### Template Update
```
afb doctor                  # warns: template upstream has new commits
# user reviews upstream changes
# user merges desired changes into afb.toml
afb rebuild                 # apply changes
```

## Observability

Structured logs to stderr via zerolog:

```
2026-04-26T07:00:00Z INF compose layer=base priority=10 files=23
2026-04-26T07:00:00Z INF compose layer=team priority=20 files=5 merges=3
2026-04-26T07:00:00Z INF compose layer=project files=8 merges=2
2026-04-26T07:00:01Z INF validate command="lnai validate" exit=0
2026-04-26T07:00:01Z INF sync command="lnai sync" exit=0
2026-04-26T07:00:02Z INF build image=afb-myproject:latest duration=45s
2026-04-26T07:00:03Z INF up services=1 project=afb-myproject
```

`AFB_LOG_LEVEL` env var: `debug`, `info` (default), `warn`, `error`.

Container logs are accessible via `podman-compose logs`. AFB doesn't capture or aggregate container logs — that's the container runtime's job.

## Risks & Mitigations

| Risk                                                                    | Impact                                 | Likelihood | Mitigation                                                                                                |
| ----------------------------------------------------------------------- | -------------------------------------- | ---------- | --------------------------------------------------------------------------------------------------------- |
| LNAI breaking changes or abandonment (239 stars)                        | `afb sync` breaks                      | Medium     | Pin version. Sync command is configurable — can swap                                                      |
| Deep merge produces invalid config                                      | Runtime reads bad config               | Medium     | `afb validate` after compose, before sync. `afb diff` for inspection                                      |
| Component install hook fails in container                               | Component unavailable                  | High       | Log error + continue (or fail in --strict). Record failure in lockfile                                    |
| Stdio MCP server sharing complexity                                     | MCP gateway adds moving parts          | Medium     | Start with in-container stdio for single-agent MCP. Graduate to AgentGateway when sharing needed          |
| Container runtime not installed                                         | `afb build` fails                      | Low        | `afb doctor` on host checks prerequisites. Clear error messages                                           |
| macOS container performance                                             | Slow file operations                   | Low        | Acceptable at single-dev scale. Heavy workloads on Linux box                                              |
| Podman-compose compatibility gaps                                       | Generated compose.yaml may need tweaks | Low-Medium | Test with both podman-compose and docker-compose. Stick to v3 compose spec subset. CI matrix              |
| Image build time                                                        | Slow iteration                         | Medium     | Layer caching. Base image with common tools. Only changed layers rebuild                                  |
| OAuth token refresh in container                                        | Auth breaks mid-session                | Low        | Named volume for `~/.claude/`. Token refresh writes to volume                                             |
| Abstraction fatigue (afb wraps compose wraps containers wraps runtimes) | Debugging depth                        | Medium     | Keep AFB scope to generation. Each layer independently inspectable. Structured logging                    |
| Gas City pack system overlaps with afb layers                           | Both try to configure agents           | Unknown    | Defer until Gas City evaluation. Different scopes: afb = harness config, Gas City = agent orchestration   |
| AgentGateway breaking changes                                           | Shared MCP access breaks               | Low        | Pin version. Gateway is optional — fallback to in-container stdio                                         |
| Lockfile can't track all component versions                             | Imperfect reproducibility              | Medium     | Best-effort: track what's trackable. Layers always get commit hashes. Document limitations                |

## Future Work

| Item                            | Phase                                  | Notes                                                                      |
| ------------------------------- | -------------------------------------- | -------------------------------------------------------------------------- |
| Gas City integration            | 3                                      | Install as component inside container. Evaluate pack overlap. Becomes entrypoint when ready |
| Container registry              | 2                                      | Push images for cross-machine sharing without rebuild                      |
| Multi-project compose           | 2                                      | Single compose file managing multiple project containers                   |
| Handoff system                  | After memory                           | claude-handoff or similar, as component inside container                   |
| Skillshare integration          | After LNAI validated                   | Complementary skill distribution                                           |
| `afb adopt <file> <layer>`      | If drift cherry-picking proves painful | Copy runtime config change back to a layer                                 |
| Firewall rules in Containerfile | 2                                      | Claude Code's devcontainer firewall pattern — whitelist API domains only   |
| Host harness management         | 3+                                     | `afb` on host lists running harness containers, attach commands            |
| Continuous improvement metrics  | 4+                                     | Track build times, drift frequency. Couple with afb logging                |
| HUD integration                 | 3                                      | Evaluate if Gas City subsumes workflow state machine                       |

## Architecture Decision Records

### ADR-001: Go as implementation language

**Status**: Accepted
**Context**: Candidates were shell, Python, TypeScript, Go. User knows Python best. TypeScript aligns with LNAI ecosystem. Shell is fastest to prototype.
**Decision**: Go.
**Rationale**: Single binary (no runtime deps on target machines), fast CLI startup, strong test stdlib, aligns with Gas City (Go). User accepted trade-off of less familiarity for long-term fit.
**Consequences**: Need to learn Go idioms. Ecosystem tooling (cobra, zerolog, toml parser) is mature.

### ADR-002: LNAI for config translation, not Chezmoi or custom

**Status**: Accepted
**Context**: Chezmoi manages personal dotfiles (wrong abstraction). Custom canonical.toml + Jinja2 is a fragile SPOF. LNAI has per-runtime plugins that understand native formats.
**Decision**: Delegate config translation to LNAI. AFB composes layers; LNAI translates to runtime-native formats.
**Rationale**: LNAI solves the format translation problem correctly.
**Consequences**: Dependency on a 239-star project. Mitigated: coupling is a single configurable shell command, swappable without changing afb.
**Supersedes**: fusion_response.md proposal for Chezmoi + canonical.toml.

### ADR-003: Clone layers to .afb/layers/ (gitignored)

**Status**: Accepted
**Context**: Options: git subtrees (pollute project history), git submodules (notorious UX), git clones to a gitignored cache dir.
**Decision**: Clone to `.afb/layers/<name>/`, gitignored. Support `ref` field for pinning.
**Rationale**: No nested-repo errors. Clean separation without history pollution or submodule UX pain.
**Consequences**: Layers not browseable in GitHub project view. `afb layer pull` required after clone. afb.lock records the resolved commit hash.

### ADR-004: Deep merge via mergo library

**Status**: Accepted
**Decision**: Use `dario.cat/mergo` (9k+ stars) for recursive map merging.
**Rationale**: Eliminates external tool dependencies and custom merge code.
**Consequences**: Requires `mergo.WithOverride` and `mergo.WithOverwriteWithEmptyValue` for replace semantics. Budget test time for edge cases.

### ADR-005: Shell out to git CLI, not go-git

**Status**: Accepted
**Decision**: Shell out to the `git` CLI.
**Rationale**: Respects user's git config, SSH keys, credential helpers.

### ADR-006: Array replace as default merge strategy

**Status**: Accepted
**Decision**: Incoming array replaces existing array entirely.
**Rationale**: Predictable, avoids duplication bugs. Layers that want to extend must include the full list.

### ADR-007: Container-first isolation

**Status**: Accepted (rev 2)
**Context**: HOME/XDG override is fragile. Containers provide kernel-level isolation proven to work with both Claude Code and OpenCode.
**Decision**: Containers as the single isolation mechanism.
**Rationale**: Eliminates dual-system complexity. Enables safe permissive mode. MCP sharing via compose networking. Image versioning for blue-green deployment. Podman provides rootless operation.
**Consequences**: Requires podman or docker on host. Image build adds latency. OAuth auth per-container (mitigated by named volumes).
**Supersedes**: ADR-007 rev 1 (dual-tier HOME override + containers). `afb test` command (superseded by container isolation).

### ADR-008: .afb/project/ as authored config, .ai/ as composed output

**Status**: Accepted
**Decision**: User-authored project config lives in `.afb/project/` (committed). `.ai/` is composed output (gitignored).
**Rationale**: Named "project" because it contains the same content types as layer dirs.

### ADR-009: Integer priority, not directory-name ordering

**Status**: Accepted
**Decision**: Mandatory `priority` integer field per layer. Higher wins.
**Rationale**: Decoupled from filesystem. Explicit, inspectable.

### ADR-010: Components as opaque lifecycle hooks

**Status**: Accepted (rev 2 — composable commands)
**Context**: Could type components or treat all identically. Fixed hooks (backup, health) assume all components have the same needs.
**Decision**: Components are opaque. AFB runs hook commands without understanding what the component does. Beyond `install` and `version`, components define arbitrary named commands in `[commands]`.
**Rationale**: Most composable design. Any tool with a CLI is manageable. No assumptions about what commands a component needs.
**Consequences**: No `afb backup` top-level command. Backup orchestration lives in user scripts that call `afb run component.command`. `afb doctor` calls the `doctor` command if defined.

### ADR-011: Structured logging, not OpenTelemetry

**Status**: Accepted
**Decision**: Structured JSON logs to stderr via zerolog.
**Rationale**: afb is a short-lived CLI. OTel adds dependency weight for no benefit at this scale.

### ADR-012: Sync command as configurable shell command

**Status**: Accepted
**Decision**: `[sync].command` in afb.toml (default: `"lnai sync"`).
**Rationale**: Minimal coupling. LNAI replaceable by changing one line.

### ADR-013: No Temporal, Redis, ChromaDB, MCP proxy

**Status**: Accepted
**Decision**: Exclude all. Lightweight alternatives at every layer.
**Supersedes**: fusion_response.md infrastructure proposals.

### ADR-014: AFB generates container files, delegates lifecycle to compose

**Status**: Accepted
**Decision**: Generate and delegate. AFB writes Containerfile + compose.yaml. Lifecycle delegated to `podman-compose` or `docker-compose`.
**Rationale**: Keeps AFB's scope tight. Compose tools are mature. Generated files are inspectable.

### ADR-015: Podman preferred, Docker compatible

**Status**: Accepted
**Decision**: Default to podman. Support docker as fallback. `[container].runtime` in afb.toml.
**Rationale**: Rootless, daemonless, 15-20% less memory overhead. CLI-compatible with Docker.
**Consequences**: Test both in CI matrix.

### ADR-016: No Kubernetes for v1

**Status**: Accepted
**Decision**: Podman pods or compose networking is sufficient for 2-10 containers on 1-2 machines.

### ADR-017: AgentGateway for shared MCP servers

**Status**: Accepted (revised — replaces "MCP gateway TBD")
**Context**: Need to share stdio MCP servers across container boundaries. Options evaluated:

| Gateway | Stars | Runtime | Transport | Verdict |
|---------|-------|---------|-----------|---------|
| AgentGateway | 2.3k | Rust, Linux Foundation, v1.0 | stdio/HTTP/SSE/Streamable HTTP | **Selected** |
| Docker MCP Gateway | 1.3k | Go, Docker Inc | stdio/SSE/Streamable HTTP | Rejected: requires Docker Desktop — incompatible with Podman |
| Supergateway | 2.4k | TypeScript | stdio→SSE/WS | Not a full gateway — simple bridge only |
| mcp-proxy | ~small | Python, beta | stdio↔Streamable HTTP | Too immature |

**Decision**: AgentGateway for shared MCP servers. Three-tier approach:
1. Streamable HTTP MCP servers: run in own container, connect via compose network
2. Stdio MCP servers used by one agent: run inside that agent's container
3. Stdio MCP servers shared across agents: run behind AgentGateway

**Rationale**: Most mature (v1.0, Linux Foundation, 119 contributors). Runtime-agnostic — works with Podman. Supports all transports including Streamable HTTP (SSE deprecated). Tool federation aggregates multiple MCP servers behind a single endpoint.
**Note**: SSE transport is deprecated in MCP. New integrations should use Streamable HTTP.

### ADR-018: Ports & Adapters application architecture

**Status**: Accepted
**Context**: AFB has 4-5 external dependencies designed to be swappable. Need testability without real external tools.
**Decision**: Ports & Adapters (Hexagonal) architecture, kept lean. Ports only for external/swappable dependencies. Core domain is pure logic.
**Rationale**: Makes swappability structural. Go's implicit interfaces keep it lightweight. Unit tests use in-memory adapters. Integration tests use real adapters.
**Consequences**: Slightly more code than package-per-feature. Interface definitions add files but keep each package focused.

### ADR-019: No afb uninstall command

**Status**: Accepted
**Context**: With containers, the lifecycle is: change manifest → rebuild. Containers are disposable.
**Decision**: No user-facing `afb uninstall` command. To remove a component: set `enabled = false` in afb.toml, `afb rebuild`.
**Rationale**: `uninstall` creates a side-path where container state can drift from manifest. The container is the isolation mechanism — rebuild it.

### ADR-020: Composable component commands, not fixed hooks

**Status**: Accepted
**Context**: Fixed hooks (backup, health) assume all components have the same needs. Skill files don't need backup. Some components need custom commands.
**Decision**: Beyond `install` and `version`, components define arbitrary named commands in `[components.NAME.commands]`. Invoked via `afb run component.command`.
**Rationale**: Most composable. No assumptions. Scripts orchestrate commands.
**Consequences**: No `afb backup` top-level command. User writes backup scripts.

### ADR-021: afb doctor replaces afb status and health hooks

**Status**: Accepted
**Context**: `afb status` was overloaded (health checks + lockfile comparison). `health` hook was a fixed name.
**Decision**: Single `afb doctor` command. Components define a `doctor` command (optional). Doctor checks lockfile, drift, template, and component health in one pass.
**Rationale**: Consistent terminology. One command for all diagnostics. Context-aware (project vs host).

### ADR-022: Containerfile customization via extra_packages and extra_run

**Status**: Accepted
**Context**: Users need custom system packages and build steps. Approaches evaluated:

| Approach | Used by | Verdict |
|----------|---------|---------|
| Declarative package list | Devbox, Aptfile, Nix | `extra_packages` — selected |
| Arbitrary commands | Most escape hatches | `extra_run` — selected |
| Feature/plugin system | Dev Containers | Overkill for v1 |
| Buildpacks | Cloud Native | Wrong abstraction |
| Fork the Dockerfile | Docker Compose | Always available as last resort |

**Decision**: `[container].extra_packages` (list of apt packages) + `[container].extra_run` (list of arbitrary shell commands). Packages installed in dedicated layer. Commands run after component installs.
**Rationale**: Follows well-understood Aptfile/Devbox pattern. Simple, covers common needs. Users needing more control can inspect and fork the generated Containerfile.
**Consequences**: Cache-busting documented — extra_packages changes invalidate subsequent layers.

### ADR-023: Compose project naming convention

**Status**: Accepted
**Decision**: Default project name is `afb-{dirname}`. Shared services use `afb-shared`. Override via `[container].project_name` or `--project` flag.
**Rationale**: Predictable, readable in `podman-compose ps`, unique enough for single-machine use. No UUID noise.

## Unresolved Questions

1. **Shared services management**: should `~/afb-shared/` be a standard convention documented by AFB, or should AFB provide a built-in `afb shared init/up/down` command? Leaning convention — it's just another afb project.
2. **Per-file merge strategy overrides**: needed, or per-layer sufficient?
3. **Statistical process control metrics**: what to track, how to couple with logging?
4. **AgentGateway configuration generation**: how much of the gateway config should AFB generate from `[mcp]` declarations? Investigate AgentGateway's config format.
5. **afb.local.toml merge edge cases**: what if local manifest adds a layer? Changes priority? Need clear semantics for what local overrides can and cannot do.
