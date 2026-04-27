# AFB Architecture

> Status: Draft (rev 5)
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

**afb.local.toml**: user-specific overrides that shallow-merge over `afb.toml` — top-level keys in local override the same top-level keys in the manifest. Gitignored. Use case: personal tool preferences, local paths, dev-mode overrides (e.g., `mount_workspace = true` for bind-mount debugging). Processed after `afb.toml`, before layer composition. Deep merge deferred until real use cases demand it.

`.afb/project/` is functionally a layer — the highest-priority one. Named "project" because it contains the same type of content as `.afb/layers/*` dirs (rules, skills, settings), just committed to the project repo instead of pulled from an external source.

### `.ai/` Directory Contract

The `.ai/` directory is the primary integration surface between AFB (producer) and LNAI (consumer). This is an explicit, versioned contract:

```
.ai/
├── .ai-format-version          # contains "1" — format version marker
├── AGENTS.md
├── rules/
├── skills/
├── settings.yaml
└── config.yaml
```

AFB writes `.ai-format-version` during composition. LNAI's expected format is characterized by tests (see Test Strategy). If LNAI changes its expectations, the characterization tests break before users hit mysterious sync failures.

**Format version semantics**: the version tracks the directory structure and file semantics, not content. Version bump = structural change to what files exist or what they mean. Content within files is layer-driven and versioned by the layers themselves.

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

AFB has 2 external tools that justify Go-level port interfaces:
- **Container runtime**: podman today, docker later (`[container].runtime`)
- **Git**: shell out to `git` CLI (could become go-git later)

Other external tools use simpler mechanisms:
- **Sync command**: swappable via `[sync].command` config field — config-level abstraction suffices, no Go interface needed
- **Filesystem**: use `os` directly, test with `os.MkdirTemp`

The architecture makes swappability structural where it matters and avoids ports that mirror stdlib 1:1. Go's implicit interfaces keep this lightweight — define the interface where it's consumed, not in a separate package.

### Port Definitions

Only genuinely external/swappable dependencies get ports. Internal operations (filesystem, sync command shelling) use stdlib directly.

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
```

**Sync command**: no port. The `[sync].command` config field already provides swappability — shelling out to a configurable string doesn't need a Go interface on top. Call `os/exec` directly.

**Filesystem**: no port. Use `os` directly. Unit-test composition with `os.MkdirTemp`. An FS abstraction that mirrors stdlib 1:1 is indirection without abstraction. Add a port if a genuine need emerges (e.g., remote storage).

### Adapter Implementations

| Port | Adapter | Implementation | Phase |
|------|---------|---------------|-------|
| `Git` | `GitCLI` | Shells out to `git` binary | v1 |
| `ContainerRuntime` | `PodmanRuntime` | Shells out to `podman` + `podman-compose` | v1 |
| `ContainerRuntime` | `DockerRuntime` | Shells out to `docker` + `docker-compose` | v2 (port interface exists, adapter deferred) |

### Dependency Wiring

Cobra commands wire ports to adapters in `cmd/afb/`. No DI framework — constructor injection:

```go
func newSyncCmd() *cobra.Command {
    return &cobra.Command{
        Use: "sync",
        RunE: func(cmd *cobra.Command, args []string) error {
            manifest := manifest.MustLoad("afb.toml")
            git := gitcli.New()
            return sync.Run(manifest, git)
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
│   │   │   ├── local.go        # afb.local.toml shallow merge
│   │   │   └── manifest_test.go
│   │   ├── lock/               # afb.lock read/write/check
│   │   │   ├── lock.go
│   │   │   └── lock_test.go
│   │   ├── compose/            # layer composition algorithm, deep merge
│   │   │   ├── compose.go
│   │   │   ├── merge.go        # deep merge orchestration (delegates to mergo)
│   │   │   └── *_test.go
│   │   └── generate/           # Containerfile + compose.yaml generation
│   │       ├── containerfile.go      # text/template-based
│   │       ├── containerfile.tmpl    # Containerfile template
│   │       ├── composefile.go        # text/template-based
│   │       ├── composefile.tmpl      # compose.yaml template
│   │       └── *_test.go
│   ├── ports/                  # interface definitions (small file per port)
│   │   ├── git.go
│   │   └── runtime.go
│   ├── adapters/               # external tool implementations
│   │   ├── gitcli/
│   │   │   └── git.go          # Git port via git CLI
│   │   └── podman/
│   │       └── runtime.go      # ContainerRuntime port via podman (v1)
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

Core domain packages (`internal/domain/*`) have zero external tool dependencies — they depend only on port interfaces and stdlib. Unit-testable with `os.MkdirTemp` for filesystem operations.

Adapter packages (`internal/adapters/*`) implement ports by shelling out to external tools. Integration-tested. Docker adapter deferred to v2 — the `ContainerRuntime` port exists so it slots in without changing core logic.

## Container Architecture

### Design Principles

1. **Self-contained**: each project container includes the harness (AFB, LNAI, runtimes), project code (cloned from git), and composed config. No host mounts for project files.
2. **Shared services via network**: MCP servers and databases run in their own containers (or on host), accessed over the network. Agent containers connect to them via Compose networking.
3. **Podman only (v1)**: rootless, daemonless, no sudo. Docker adapter deferred to v2 — the `ContainerRuntime` port interface exists so it slots in later. Compose files use the subset of Compose Specification features with known podman-compose support (see Compose Spec Compliance below).
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

The Containerfile is generated via Go's `text/template` (stdlib). The template file (`containerfile.tmpl`) looks like the output with `{{.Field}}` placeholders — readable, diffable, inspectable. Same approach for `compose.yaml`.

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

### Compose Spec Compliance

Generated compose.yaml uses only features with known podman-compose support:

| Feature | Used for | podman-compose support |
|---------|----------|----------------------|
| `services` | Container definitions | Yes |
| `build` (context, dockerfile, args) | Image builds | Yes |
| `networks` (bridge driver) | Internal networking | Yes |
| `networks` (external: true) | Join shared services network | Yes |
| `volumes` (named) | Persistent data (auth, DBs) | Yes |
| `environment` | Runtime env vars | Yes |
| `stdin_open`, `tty` | Interactive shells | Yes |
| `ports` | Host port mapping | Yes |
| `image` | Pre-built images | Yes |

**Explicitly avoided** (incomplete or absent podman-compose support):
- `depends_on` with conditions — use startup scripts instead
- `healthcheck` — use component doctor commands
- `deploy` — Swarm/k8s only
- `configs`, `secrets` — use environment variables or volumes
- `profiles` — use separate compose files instead

Validated in CI by `podman-compose config --quiet` as a fitness function.

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
schema_version = 1              # manifest schema version — enables future migration

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
# merge_arrays: replace (default) | append

[layers.team]
source = "git@github.com:team/ai-config.git"
priority = 20
ref = "v1.2.0"                 # pin to specific tag
merge_arrays = "append"         # this layer appends arrays instead of replacing

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

User-specific overrides. Shallow-merged over `afb.toml` — top-level TOML table keys in local replace the corresponding table in the manifest. Gitignored.

Common uses:
- `mount_workspace = true` for local bind-mount development
- Local tool paths
- Dev-mode settings
- Override `strict = true` for local builds

Deep merge for local overrides deferred to v2. Stated use cases are all flat scalar overrides — shallow merge covers them without the complexity and edge cases of full deep merge.

### Manifest Validation

Validation runs at parse time, before any operation proceeds:

| Check | Error |
|-------|-------|
| `schema_version` missing or unsupported | "unsupported schema version N — this afb requires schema_version 1" |
| Two layers with same `priority` integer | "layers 'base' and 'team' have duplicate priority 10" |
| Component missing `install` field | "component 'foo' missing required field: install" |
| Layer missing `source` field | "layer 'bar' missing required field: source" |
| `[container].runtime` not "podman" | "unsupported runtime — v1 supports podman only" |

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

Array replace is the safe default — predictable, avoids duplication. Uses `mergo.WithOverride` and `mergo.WithOverwriteWithEmptyValue` flags.

**Per-layer array merge override**: `merge_arrays` field per layer. Values: `replace` (default) | `append`. When `append`, incoming arrays are concatenated to existing arrays instead of replacing them. This is an escape hatch for the common case where a layer needs to extend a list (e.g., adding MCP servers) without duplicating the base layer's entries. Optional field — omitting it means `replace`.

**Known risk — mergo zero-value behavior**: mergo may treat empty/zero values (empty string, 0, false) as "unset" and skip override even with `WithOverride`. This contradicts the "incoming wins at leaf" rule. `WithOverwriteWithEmptyValue` is documented to handle this but has reported inconsistencies (mergo issues #54, #190). Characterization tests for all zero-value combinations are required before trusting merge semantics. If unreliable, implement a custom `mergo.WithTransformers` for leaf override. See `mergo-toml-research.md`.

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

**Deferred to v2**:
| Command | Trigger to reconsider |
|---------|----------------------|
| `afb shell [service]` | When AFB needs to discover and manage running harness containers from the host |

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
| **podman**                          | Container runtime (v1). Shell out for build/up/down. Rootless, daemonless. Docker adapter deferred to v2 |
| **podman-compose**                  | Multi-container orchestration (v1). AFB generates compose.yaml, delegates lifecycle. docker-compose deferred to v2 |
| **AgentGateway**                    | MCP gateway for shared stdio servers. Linux Foundation, Rust, v1.0, runtime-agnostic   |

External runtime dependencies (v1): `git`, `podman`, `podman-compose`, configured sync command (default: `lnai` — installed inside container).

**Not using**: k3s/minikube/kind (overkill for 2-10 containers on 1-2 machines), Docker MCP Gateway (requires Docker Desktop — incompatible with Podman), yq/jq (mergo handles merge in-process), go-git (shell git is simpler).

## Test Strategy

### Acceptance Criteria

Core operations must satisfy these measurable criteria before v1:

| Criterion | Measurement | Threshold |
|-----------|------------|-----------|
| Composition correctness | Composition with N layers produces expected file tree (golden-file tests) | 100% match |
| Containerfile validity | Generated Containerfile passes hadolint | Zero errors (warnings allowed) |
| Compose spec validity | Generated compose.yaml passes `podman-compose config` | Exit 0 |
| Sync idempotency | `afb sync` run twice produces identical `.ai/` output | Byte-identical |
| Build reproducibility | Same lockfile + same manifest = same image digest | Digest match |
| Unit test speed | `go test ./internal/domain/...` | < 5s |
| Tier isolation | No unit test requires git, container runtime, or network | Zero external deps |

### Fitness Functions

Automated checks that run in CI to prevent architectural drift:

- **Composition idempotency**: CI job runs `afb sync` twice, computes SHA-256 of each file in `.ai/` (sorted by path), compares — any difference = failure. Structured as a dedicated CI job that (1) runs `afb sync`, (2) captures hashes, (3) runs `afb sync` again, (4) captures hashes, (5) asserts identical. See ADR-028
- **Containerfile lint**: hadolint on generated Containerfile — catches structural errors without building
- **Compose validation**: `podman-compose config --quiet` on generated compose.yaml — catches spec violations
- **Test tier isolation**: Enforced two ways: (a) CI job runs `go test ./internal/domain/...` inside a container image with no git/podman/network installed — if it fails, tier boundary is broken; (b) CI step greps for `os/exec` in `internal/domain/` — any match = failure (domain packages must not shell out)
- **Domain package purity**: `internal/domain/` must have no imports of `os/exec` or adapter packages. Enforced by grep in CI: `grep -r 'os/exec\|internal/adapters' internal/domain/` must return empty
- **Unit test speed**: CI step asserts `go test ./internal/domain/...` completes in < 5s. `time` wrapper + threshold check. Catches performance regressions
- **Conventional commits**: commit-msg hook regex via lefthook — enforced locally on every commit
- **Lint clean**: golangci-lint in pre-commit hook + CI — prevents lint regressions

### Three Tiers

| Tier | Tag | Dependencies | What's tested | Speed |
|------|-----|-------------|---------------|-------|
| **Unit** | (none) | None | Manifest parsing, composition algorithm, merge logic, Containerfile generation, lockfile read/write | Fast (< 5s) |
| **Validation** | (none) | hadolint | Generated Containerfile lint, generated compose.yaml validation via `podman-compose config` | Fast |
| **Integration** | `//go:build integration` | git, lnai | Real layer cloning, composition with real git repos, real sync command | Medium |
| **E2E** | `//go:build e2e` | podman | Build real images, start containers, verify harness inside, check logs, tear down | Slow |

### Unit Tests

Core domain packages (`internal/domain/*`) are pure logic. Test with `os.MkdirTemp`. No git, no containers.

- Parse sample manifests from `testdata/`
- Compose layers from temp dir file trees
- Assert merge results via golden files
- Generate Containerfile from template, assert content
- Generate compose.yaml from template, assert content
- Lockfile round-trip: write → read → compare
- **Manifest validation**: priority collision → error, missing required fields → error, schema_version mismatch → error

**mergo characterization tests** (must exist before writing composition logic):

| Case | Expected behavior |
|------|------------------|
| nil src + populated dst | dst preserved |
| empty map src + populated dst | dst preserved |
| populated src + nil dst | src wins |
| TOML table-array merged | incoming replaces (array replace rule) |
| mixed-type leaf conflict | incoming wins |
| **empty string src + non-empty dst** | **incoming wins (verify — mergo zero-value bug risk)** |
| **zero integer src + non-zero dst** | **incoming wins (verify)** |
| **false bool src + true dst** | **incoming wins (verify)** |
| empty slice src + populated dst | incoming wins (array replace) |

The zero-value cases are critical. mergo may treat empty/zero as "unset" and skip them even with `WithOverride`. If `WithOverwriteWithEmptyValue` is unreliable, implement a custom `mergo.WithTransformers` for leaf override. See `mergo-toml-research.md`.

### Integration Tests

Adapter packages + cross-package workflows. Require git and lnai installed.

- Clone a test layer repo to temp dir, checkout ref, verify files
- Compose real layers from temp dirs, compare output
- Full sync workflow: parse → clone → compose → validate → **run real `lnai sync`** (not mock)
- If lnai unavailable in CI environment, tag as `//go:build integration_lnai` and run in dedicated environment

Mock sync command is acceptable for unit tests of AFB's orchestration logic. Integration tests that mock the integration point are not integration tests.

### E2E Tests

Full harness lifecycle. Require podman.

```
1. Parse test manifest from testdata/
2. afb build → generates Containerfile + compose.yaml, builds image
3. afb up → starts container
4. Exec inside container: verify .ai/ exists, .ai-format-version = "1", runtime configs exist, components installed
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
      # podman is pre-installed on ubuntu runners
      - run: go test -tags integration ./...

  e2e:
    runs-on: ubuntu-latest
    steps:
      # podman is pre-installed on ubuntu runners
      - run: go test -tags e2e ./...
```

Podman-only for v1. Docker adapter and CI matrix deferred to v2. E2E tests tagged and slow — run on merge to main, not on every push.

### Limitations

- Full e2e tests require podman installed
- E2e test duration scales with number of components installed in test image
- mergo zero-value behavior requires characterization tests before trusting override semantics

## Data Lifecycle

```
afb.toml (authored, committed)
    │
    ├─── afb.local.toml (user overrides, gitignored)
    │         │
    │         ▼ shallow merge
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
podman exec -it <container> bash   # enter container, authenticate runtimes
```

### Daily Work
```
# develop inside container via Dev Containers or podman exec...
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

## Layer Version Consistency

### The Problem

When a user (or an LLM runtime) modifies config that the user wants to promote to a layer, a version consistency gap arises:

1. `afb.toml` pins `[layers.team].ref = "v1.2.0"` (resolved to commit `abc123`)
2. User edits files in `.afb/layers/team/` locally (e.g., LLM added an MCP server via its UI, user spotted it via `afb diff`, cherry-picked it into the team layer)
3. `afb push team` pushes the change to the upstream layer repo → new commit `def456`
4. **Gap**: `afb.toml` still says `ref = "v1.2.0"`. Next `afb sync` pulls the old pinned version, overwriting the just-pushed change
5. **Secondary gap**: the container image was built with old layer content — it's now stale

### Solution: `afb push` updates the manifest pin

`afb push <layer>` does the following:

```
1. git -C .afb/layers/<layer>/ add -A
2. git -C .afb/layers/<layer>/ commit -m "<message>"  (if uncommitted changes)
3. git -C .afb/layers/<layer>/ push
4. new_hash ← git -C .afb/layers/<layer>/ rev-parse HEAD
5. Update afb.toml: [layers.<layer>].ref = new_hash
6. Update afb.lock: [layers.<layer>].ref_resolved = new_hash
7. Log: "pushed team → def456, updated afb.toml pin"
```

**Behavior by ref type:**

| Original ref | After push | Rationale |
|---|---|---|
| Mutable branch (`main`) | ref stays `main`, lockfile updated with new commit hash | Branch tracks HEAD. Next `afb sync --pull` gets the new content naturally |
| Pinned tag (`v1.2.0`) | ref updated to new commit hash. Warning: "ref was tag v1.2.0, now pinned to commit def456. Create a new tag if needed" | Tag is immutable. Push creates a new commit beyond the tag. User may want to tag the new commit |
| Pinned commit hash (`abc123`) | ref updated to new commit hash `def456` | Explicit pin must be updated to stay consistent |

**Why update afb.toml, not just lockfile?** The lockfile is generated — `afb sync` overwrites it. If we only update lockfile, the next sync reads the manifest's stale pin and pulls the old version. The manifest is the source of truth and must reflect the new state.

**Consequence**: `afb push` modifies a committed file (`afb.toml`). This is intentional — the push is a deliberate act that changes the desired state. The user should commit the updated `afb.toml` alongside their next commit. `afb push` logs a reminder: "afb.toml updated — commit to persist the new layer pin."

### Container staleness after push

After `afb push`, the container image is stale (built with old layer content). The user must `afb rebuild` to get a container with the new config. This is already the documented workflow for any config change.

For cross-machine consistency:
- **Same machine**: `afb rebuild` after push. Immediate
- **Other machines**: run `afb sync` (which runs `afb layer pull` if `--pull` flag or if layers missing) → gets new content via the updated ref → `afb rebuild`. Or pull the rebuilt image from a container registry if available

Container image tagging remains `afb-{dirname}:latest`. Content-addressable image tags (based on manifest + lockfile hash) deferred — adds complexity without clear need at solo-dev scale.

### The LLM config evolution flow

A common workflow: an LLM runtime modifies its own config (e.g., Claude Code adds an MCP server via UI). The user wants to make this permanent:

```
# Inside container
afb diff                           # spots runtime drift: .claude/settings.json changed
# User inspects the change, decides to keep it
# User copies the relevant config into .afb/project/ or a layer dir
afb sync                           # recompose — adopted change now in .ai/
afb push team                      # push to upstream layer (if it went to a layer)
                                   # afb.toml pin updated automatically
# On host
afb rebuild                        # new container with updated config
```

This flow lets config evolve from runtime experiments → layer permanence → cross-project sharing, without manual version juggling.

## Caching Strategy

Every `afb.toml` change that affects the container requires `afb rebuild` — a full image build. With component installs (npm, apt, go install), this can take minutes. Caching reduces iteration time for both AFB developers and AFB users.

### Containerfile Layer Ordering

The generated Containerfile orders layers for maximum cache reuse:

1. **System deps** (apt-get) — changes rarely
2. **Extra packages** — changes occasionally
3. **AFB binary** — changes per AFB release
4. **Component installs** — changes when versions bump
5. **Extra run commands** — changes occasionally
6. **Project clone** — changes per commit
7. **afb sync** — changes when config changes

Changing a component version invalidates layers 4-7 but preserves 1-3. Changing only project code invalidates only 6-7.

### For AFB developers

- **Podman build cache**: default behavior, no configuration needed. Podman caches intermediate layers
- **Multi-stage builds**: if component installs become slow, consider a pre-built base image with common tools, referenced via `base_image` in manifest
- **`--generate-only`**: validate Containerfile + compose without building. Fast feedback loop for template changes

### For AFB users in production

- **Base image pinning**: use a specific digest for `base_image` to avoid upstream surprises
- **Container registry**: push built images to a registry. Other machines pull instead of rebuilding. Avoids rebuild latency on fresh machines
- **Layer caching in CI**: CI runners can use `--cache-from` to pull previous image layers

### Unmitigated

Harness config changes (adding/removing layers, changing merge strategy) always require a full `afb sync` + `afb rebuild`. No incremental composition yet — the atomic-replace design of `.ai/` means every sync recomputes from scratch. This is acceptable at current scale but could become a bottleneck with many layers or large config trees.

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
| Podman-compose compatibility gaps                                       | Generated compose.yaml may need tweaks | Low-Medium | Stick to documented safe feature subset (see Compose Spec Compliance). Validate with `podman-compose config` in CI |
| Image build time                                                        | Slow iteration                         | Medium     | Layer caching. Base image with common tools. Only changed layers rebuild                                  |
| OAuth token refresh in container                                        | Auth breaks mid-session                | Low        | Named volume for `~/.claude/`. Token refresh writes to volume                                             |
| Abstraction fatigue (afb wraps compose wraps containers wraps runtimes) | Debugging depth                        | Medium     | Keep AFB scope to generation. Each layer independently inspectable. Structured logging                    |
| Gas City pack system overlaps with afb layers                           | Both try to configure agents           | Unknown    | Gas City is a user component — users may add it to their harness or not. It is not a required part of AFB. Different scopes: afb = harness config, Gas City = agent orchestration. No AFB plan dependency |
| AgentGateway breaking changes                                           | Shared MCP access breaks               | Low        | Pin version. Gateway is optional — fallback to in-container stdio                                         |
| Lockfile can't track all component versions                             | Imperfect reproducibility              | Medium     | Best-effort: track what's trackable. Layers always get commit hashes. Document limitations                |
| mergo zero-value override bug                                           | Empty/zero values silently not merged  | Medium     | Characterization tests before writing composition logic. Custom transformer if `WithOverwriteWithEmptyValue` unreliable |
| E2E tests slow CI                                                       | Slow feedback loop                     | Medium     | Run e2e only on merge to main. Unit tests on every push. `--generate-only` enables validation without podman |
| Build reproducibility aspirational                                      | "Same lockfile = same image" may not hold | Medium  | Container image reproducibility is notoriously hard (apt timestamps, network fetches, layer caching). Stated as acceptance criterion but not enforced. Deferred — note as aspirational, revisit when lockfile is stable |
| Container rebuild latency                                               | Slow iteration when changing harness config | Medium | See §Caching Strategy. Layer ordering in Containerfile optimized for cache hits. No full mitigation yet |
| Build time / CLI startup time                                           | User dissatisfaction                   | Low        | No mitigations yet. Risk is low for v1 (solo dev). Monitor if user base grows |

## Decision Reversibility

Consolidated view of key decisions and their cost to reverse. Informs risk management and investment sequencing.

| Decision | Reversibility | Notes |
|---|---|---|
| TOML manifest format | Irreversible | All config depends on it (ADR-024) |
| Array replace as merge default | Expensive | All layer content assumes this (ADR-006) |
| Integer priority ordering | Expensive | All manifests assume numeric order (ADR-009) |
| mergo for deep merge | Expensive | Composition algorithm, characterization tests, and custom transformer all bind to mergo's specific behavior. Replacing means re-verifying all merge semantics (ADR-004) |
| Container-first isolation | Expensive | Every `afb.toml` change requires `afb rebuild`. Once workflows depend on containers, effectively irreversible (ADR-007) |
| Podman only (v1) | Cheap | ContainerRuntime port exists for Docker (ADR-015) |
| lefthook for hooks | Cheap | Swap for any git hook manager |
| cobra for CLI | Cheap | Thin wiring in `cmd/afb/`. Core logic in `internal/`. Swapping changes ~10 files in `cmd/`, zero in domain |
| LNAI for sync | Cheap | Single configurable shell command (ADR-002) |
| text/template for generation | Cheap | Stdlib, no dep (ADR-026) |

## External Dependencies

| Dependency | Failure mode | Stability | Fallback |
|---|---|---|---|
| git CLI | Layer clone/push fails | Stable | None needed |
| podman + podman-compose | Container build/lifecycle fails | Stable | Docker adapter v2 |
| lnai | Sync command fails | Medium (239 stars) | Configurable `[sync].command` |
| mergo | Merge edge cases | Stable (9k stars) | Custom transformer |
| hadolint | Containerfile lint unavailable | Stable | Non-blocking skip |

## Future Work

| Item                            | Phase                                  | Notes                                                                      |
| ------------------------------- | -------------------------------------- | -------------------------------------------------------------------------- |
| Gas City integration            | User decision                          | Gas City is a user component, not an AFB dependency. Users may install it via `[components.gascity]`. No AFB plan phase depends on it |
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
**Reversibility**: **Expensive** — every layer configuration depends on this semantic. Changing after real users have layers = breaking change to all existing layer content.
**Decision**: Incoming array replaces existing array entirely.
**Rationale**: Predictable, avoids duplication bugs. Layers that want to extend must include the full list.
**Escape hatch added**: optional `merge_arrays = "append"` per layer. Default remains `replace`. Cost: one extra field in validation + one branch in merge logic. Cheaper to add now than after layers exist in the wild.
**Reconsider when**: users consistently need per-file (not per-layer) array merge control.

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
**Reversibility**: **Expensive** — all manifests and documentation assume numeric priority ordering. Changing to a different ordering scheme (alphabetical, dependency graph) breaks all existing configurations.
**Context**: Alternatives considered: directory-name alphabetical ordering (fragile, rename = reorder), explicit dependency declarations (overkill for config layers).
**Decision**: Mandatory `priority` integer field per layer. Higher wins. Duplicate priorities are a validation error.
**Rationale**: Decoupled from filesystem. Explicit, inspectable. Simple to reason about.
**Reconsider when**: layer count per project regularly exceeds 5-10 and priority management becomes painful.

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

### ADR-015: Podman only (v1), Docker deferred (v2)

**Status**: Accepted (rev 2)
**Context**: v1 needs one working runtime, not two. Podman is preferred for rootless, daemonless operation.
**Decision**: v1 ships PodmanRuntime adapter only. `ContainerRuntime` port interface exists so DockerRuntime slots in at v2. `[container].runtime` field exists in manifest but only accepts "podman" in v1.
**Rationale**: Rootless, daemonless, 15-20% less memory overhead. GitHub Actions ubuntu runners have podman pre-installed — no docker-in-docker needed for CI. Halves adapter code and test surface for v1.
**Consequences**: Users who only have Docker must wait for v2 or contribute the adapter. CI matrix is podman-only.
**Trigger to add Docker**: user request or deployment target that requires Docker.

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

**Status**: Accepted (rev 2 — reduced port count)
**Context**: AFB has 2 external dependencies that justify Go-level port interfaces (Git, ContainerRuntime). Other external tools (sync command, filesystem) use simpler mechanisms.
**Decision**: Ports & Adapters (Hexagonal) architecture, kept lean. Ports only for genuinely swappable dependencies with multiple planned implementations. Core domain is pure logic. No port for sync command (config-level swappability suffices) or filesystem (stdlib is not an abstraction).
**Rationale**: Makes swappability structural where it matters. Avoids interfaces that mirror stdlib 1:1. Go's implicit interfaces mean ports can be added later if needed.
**Consequences**: Two ports (Git, ContainerRuntime). Unit tests use `os.MkdirTemp` for filesystem. Sync command tested via real execution in integration tier.

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

### ADR-024: TOML as manifest format

**Status**: Accepted
**Reversibility**: **Effectively irreversible** once users have manifests.
**Context**: Candidates: YAML (ubiquitous but whitespace-sensitive, implicit typing), JSON (no comments, verbose), HCL (Terraform-specific ecosystem), CUE (powerful but steep learning curve), TOML (explicit typing, human-readable, good error messages).
**Decision**: TOML for `afb.toml`, `afb.local.toml`, and `afb.lock`.
**Rationale**: Explicit typing avoids YAML's "Norway problem." Comments supported. BurntSushi/toml parser is mature with clear error messages. Config-file convention (Cargo.toml, pyproject.toml). Works with mergo for deep merge via `map[string]interface{}` (see `mergo-toml-research.md`).
**Consequences**: mergo zero-value behavior must be characterized and tested. TOML table-arrays are less intuitive than YAML lists for some users.

### ADR-025: .ai/ directory as versioned integration contract

**Status**: Accepted
**Reversibility**: Expensive — primary integration surface between AFB and LNAI.
**Context**: `.ai/` is produced by AFB (composition) and consumed by LNAI (sync). No schema, no version, no compatibility check existed. LNAI is a 239-star project — breaking changes likely.
**Decision**: `.ai/` is an explicit, versioned contract. AFB writes `.ai-format-version` (currently "1") during composition. Format documented in architecture. Characterized by tests against LNAI's expectations.
**Rationale**: Low cost now (one file + tests). High cost to retrofit after mysterious sync failures.
**Consequences**: Must maintain characterization tests against LNAI. Version bump on structural change.
**References**: LNAI docs: https://lnai.sh/getting-started/introduction/, source: https://github.com/KrystianJonca/lnai

### ADR-026: text/template for container file generation

**Status**: Accepted
**Context**: Containerfile and compose.yaml are 90% static text with variable insertions. Line-by-line `fmt.Fprintf` in Go tangles format with logic. `text/template` is stdlib.
**Decision**: Use Go's `text/template` for Containerfile and compose.yaml generation. Template files (`.tmpl`) live alongside generation code.
**Rationale**: Template looks like the output with `{{.Field}}` holes — readable, diffable, inspectable. Simpler than line-by-line string concatenation. Zero external dependencies (stdlib).
**Consequences**: Template files are an additional artifact to maintain. Logic in templates should be minimal (loops and conditionals only, no complex expressions).

### ADR-028: Idempotency check via per-file SHA-256

**Status**: Accepted
**Context**: `afb sync` must be idempotent — running it twice with no changes must produce byte-identical `.ai/` output. The idempotency check is both a Phase 5 acceptance test and a CI fitness function. Two candidates:

| Method | How it works | Pros | Cons |
|--------|-------------|------|------|
| **Per-file SHA-256** | Walk `.ai/`, hash each file, sort by path, compare hash lists | Pinpoints which file changed. Debuggable. Reusable as a library function | Slightly more code |
| **tar + hash** | `tar cf - .ai/ | sha256sum` | One-liner | Sensitive to metadata (mtime, permissions, ordering). tar output varies by platform. Opaque — if it fails, you don't know which file changed |

**Decision**: Per-file SHA-256, sorted by relative path.
**Rationale**: Debuggability wins. When idempotency breaks, you need to know *which* file changed, not just that something changed. Platform-independent (no tar metadata sensitivity). The hash list can be serialized for CI artifacts. Reusable in `afb diff` for composition drift detection.
**Implementation**: Walk `.ai/` recursively, skip `.git/`, compute `sha256.Sum256` per file, sort entries by relative path, compare entry-by-entry. Report first difference with file path and both hashes.

### ADR-027: Black-box acceptance tests via os/exec

**Status**: Accepted
**Reversibility**: Moderate — all acceptance tests depend on this convention.
**Context**: Acceptance tests for a Go CLI can test at multiple levels: (a) call domain functions directly from test code, (b) call cobra command handlers in-process, (c) build binary and exercise via `os/exec`. Option (a) tests domain logic but not CLI wiring. Option (b) couples to cobra internals. Option (c) tests the actual user-facing binary end-to-end.
**Decision**: All acceptance tests exercise the compiled `afb` binary as a black box via `os/exec`. A thin DSL package (`test/acceptance/harness/`) wraps CLI invocations to absorb output format changes.
**Rationale**: Best practice for ATDD with Go CLIs — tests exactly what the user runs. Catches wiring bugs that in-process tests miss (wrong flag name, missing subcommand registration, exit code errors). The DSL layer prevents coupling to specific output strings. Go's `TestMain` can build the binary once per test suite.
**Consequences**: Acceptance tests are slower than unit tests (process spawn per invocation). DSL package must be maintained alongside CLI changes. Binary must be built before acceptance tests run.
**References**: Dave Farley's ATDD approach — test the system from the outside, through its public interface.

## Deferred Decisions

| Decision | Current stance | Trigger to revisit |
|----------|---------------|-------------------|
| Shared services management | No built-in convention. User specifies own naming and directory organization for shared services. AFB is not opinionated about how users structure their harness (except: harnesses run in a container) | When multiple users independently arrive at conflicting conventions and request guidance |
| Per-file merge strategy overrides | Per-layer only (`merge_arrays` field available) | When a user creates a layer solely to get different merge strategies for different files within the same layer |
| Statistical process control metrics | Not tracked | When build/sync frequency data is available from structured logs |
| AgentGateway config generation | Manual gateway config | When first shared MCP server is configured across project containers |
| afb.local.toml deep merge | Shallow merge only (v1) | When a user needs to override a nested key without replacing the entire top-level table |
| Docker adapter | Deferred to v2 | User request or deployment target requiring Docker |
| `afb shell` command | Deferred to v2 | When AFB needs to discover and manage running harness containers from host |
