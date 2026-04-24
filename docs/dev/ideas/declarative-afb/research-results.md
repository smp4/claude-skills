# Research Results: Declarative AFB Architecture

> Date: 2026-04-24
> Status: Raw research compiled from multiple agent investigations
> Purpose: Reusable reference for future conversations

---

## 1. LNAI — Unified AI Config Management

**Repo**: https://github.com/KrystianJonca/lnai
**Stars**: 239 | **License**: MIT | **Version**: v0.6.91 (Apr 15, 2026)
**Language**: TypeScript (98.1%) | **Structure**: pnpm monorepo + Turbo

### What it does

Centralises AI tool configuration in a single `.ai/` directory, then exports to native formats for each supported runtime via `lnai sync`. Uses symlinks where possible, generates format-specific files where needed.

### Supported runtimes

| Tool | Output Dir | Rules | Skills | MCP | Settings |
|------|-----------|-------|--------|-----|----------|
| Claude Code | `.claude/` | Yes | Yes | Yes (→ `.mcp.json`) | Yes |
| OpenCode | `.opencode/` | Yes | Yes | Yes | Yes |
| Codex | `.codex/` | Yes | Yes | Yes | No |
| Cursor | `.cursor/` | Yes | Yes | Yes | Yes |
| Gemini CLI | `.gemini/` | Yes | Yes | Yes | Yes |
| GitHub Copilot | `.github/` | Yes | Yes | Yes | Yes |
| Windsurf | `.windsurf/` | Yes | Yes | No | No |

### Architecture

- `packages/core/src/plugins/` — one plugin per runtime
- Plugin interface: `detect()`, `import()`, `export()`, `validate()`
- `UnifiedState` struct: agents (AGENTS.md), rules (markdown files), skills (markdown files), settings (permissions, MCP servers), config (tool enable/disable)
- Claude Code plugin: symlinks CLAUDE.md → .ai/AGENTS.md, symlinks rules/ and skills/, generates settings.json, generates .mcp.json at project root
- OpenCode plugin: has dedicated transforms (`transformMcpToOpenCode`, `transformPermissionsToOpenCode`), generates opencode.json, symlinks rules/skills, symlinks AGENTS.md to project root

### CLI

```bash
lnai init      # Create .ai/ directory structure
lnai validate  # Check for errors
lnai sync      # Export to all enabled tool configs
```

### Drift detection

**Not implemented.** Plugin interface has `detect()` and `import()` methods but both return `false`/`null` for every plugin. One-way export only. The interface scaffolding exists for future implementation.

### Gaps

- No layered config (enterprise → team → personal merge)
- No drift detection (runtime configs modified by tools won't be detected)
- No cross-project sync (per-project `.ai/` only)
- 239 stars — relatively small community
- Recent bug fix: Claude Code MCP servers must go in `.mcp.json`, not `settings.json` (fixed Mar 2026)

### Key commit history

- Mar 2026: Fix Claude Code MCP servers → .mcp.json (upstream CC issue #24477)
- Apr 2026: Normalize .gitignore paths, version bumps
- Active development with external contributors

---

## 2. Gas Town — Multi-Agent Workspace Manager

**Repo**: https://github.com/gastownhall/gastown
**Stars**: 14,582 | **License**: MIT | **Language**: Go
**Contributors**: 30+ | **Last push**: Apr 22, 2026

### What it does

Coordinates multiple AI coding agents (Claude Code, Codex, Gemini, OpenCode, etc.) working in parallel on different tasks. Agents run in tmux panes. Three-tier watchdog system (Witness/Deacon/Dogs) keeps agents healthy. Merge queue ("Refinery") uses Bors-style bisecting.

### Key design

- GUPP principle: when an agent finds work on their hook, it executes immediately
- Git-backed work state persistence via "hooks" (not git hooks — work state files)
- Designed for 5-10+ parallel agents across multiple Pro Max ($200/mo) accounts

### What it replaces

tmux management, task dispatch, merge queue tooling, agent health monitoring, cross-agent state persistence

### Cost model

Designed for multiple $200/mo Pro Max accounts. The docs explicitly state it's "expensive." Overkill for 1-2 Pro subs.

---

## 3. Gas City — Orchestration SDK

**Repo**: https://github.com/gastownhall/gascity
**Stars**: 340 | **License**: MIT | **Language**: Go
**Version**: v1.0.0 (Apr 21, 2026) | **Last push**: Apr 24, 2026

### What it does

SDK extracted from Gas Town for building custom orchestration. Declarative config via `city.toml`, multiple runtime providers, beads-backed work tracking, controller/supervisor loop.

### city.toml controls

- Agent definitions (name, provider, description, working dirs)
- Runtime providers (tmux, subprocess, exec, ACP, Kubernetes)
- Session setup/teardown scripts and commands
- Inject fragments (prompt injection into agent sessions)
- Overlay directories (files copied into agent workdirs at startup)
- Named sessions, session sleep, site bindings
- Pack system for composable config bundles
- Rig-scoped orchestration for multi-project setups

### What city.toml does NOT control

- Runtime-internal config (what's in .claude/ or .opencode/)
- Config portability across runtimes
- Memory system configuration
- API keys or billing

### Pack system (composable config)

Packs are composable config bundles. Key features:
- Packs can include other packs
- Override agent settings per-pack
- Append to lists (pre_start_append, session_setup_append, etc.)
- MCP resolution across pack hierarchies
- Pack graph with ordered precedence (low → high)
- Rig-level pack overrides

### Dependencies

- Required: tmux, git, jq, pgrep, lsof
- Optional: dolt (1.86.1+), bd (1.0.0+), flock (for beads)
- `GC_BEADS=file` skips Dolt requirement

### Pro subscription compatible

Yes. Gas City launches agent processes; each agent authenticates independently. Claude Code uses Pro sub OAuth as normal.

### Code maturity

71 files in `internal/config/` alone, comprehensive test coverage, well-structured Go codebase. Substantial engineering despite being v1.0.0.

---

## 4. oh-my-openagent

**Repo**: https://github.com/code-yeongyu/oh-my-openagent (successor to oh-my-opencode)
**Stars**: 53,910 | **License**: SUL-1.0 | **Language**: TypeScript
**Last push**: Apr 24, 2026

### What it does

Plugin harness for OpenCode. Adds specialised agents (Sisyphus orchestrator, Hephaestus worker, Prometheus planner, Oracle debugger, Librarian docs, Frontend Engineer). Routes tasks to models by category (visual, deep, quick, ultrabrain). LSP/AST integration, hash-anchored edits, Ralph Loop (self-referential iteration).

### Relevance to multi-runtime problem

**None.** OpenCode-internal enhancement only. Doesn't solve cross-runtime coordination.

### Constraints

- Requires API keys, not Pro subscriptions
- Author "cannot recommend" use with Claude Code subscriptions due to ToS concerns (Jan 2026 Anthropic OAuth restriction)
- SUL-1.0 license — non-standard, check terms

---

## 5. ACFS (Agentic Coding Flywheel Setup)

**Repo**: https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup
**Stars**: 1,416 | **Contributors**: 2 | **Version**: v0.6.0 (Feb 2026)
**Language**: TypeScript (54%), Shell (45%) | **License**: unspecified

### What it bundles

- Shell env: zsh, tmux (via ntm)
- Languages: Node.js/Bun, Python, Go, Ruby, Docker, Tailscale
- First-class agents: Claude Code, Codex CLI, Gemini CLI
- Coordination: Agent Mail (MCP), ntm, CASS, cm (cass_memory), dcg
- Safety: checksum verification, destructive command guard

### Critical blockers

- **Ubuntu VPS only** — uses apt, systemd, Linux-specific paths
- **Requires API keys** — not Pro-subscription compatible
- **OpenCode not first-class** — CASS indexes OpenCode sessions, but ACFS doesn't install/configure it
- **2 contributors** — essentially solo project (Jeff Emanuel)
- **Not composable** — monolithic bootstrap script, can't easily add/remove parts

---

## 6. Memory Tool Backup Assessment

| Tool | Storage | Backup method | Derived/Rebuildable? | One-liner |
|------|---------|--------------|---------------------|-----------|
| **CASS** | SQLite (truth) + Tantivy (speed) + FSVI (semantic) | Copy SQLite file | Tantivy + FSVI rebuildable via `cass index --full --force-rebuild` | `cp ~/.config/cass/*.db backup/` |
| **cq** | SQLite at `~/.local/share/cq/local.db` | Copy file or `.backup` | Primary | `sqlite3 ~/.local/share/cq/local.db ".backup cq.bak"` |
| **mcp-memory-service** | SQLite-vec at configurable path (default `./data/sqlite_vec.db`), built-in `backups/` dir | Copy SQLite or use built-in backup | Embeddings regenerable from content | `cp data/sqlite_vec.db backup/` |
| **cass_memory_system** | Files at `~/.cass-memory/` — playbook.yaml, diary/*.json, config.json, toxic_bullets.log | tar the directory | Primary, text files, git-friendly | `tar czf cass-mem-backup.tar.gz ~/.cass-memory/` |
| **Vestige** | SQLite with WAL mode, 22MB binary | Copy SQLite | Primary | `cp vestige.db backup/` |
| **Basic Memory** | Markdown files + SQLite | Copy directory | Primary | `cp -r basic-memory/ backup/` |
| **Napkin** | Per-repo markdown scratchpad | Git tracks it | Primary | Already in git |

### Storage observations

- All tools use either SQLite or plain files — no complex databases requiring admin
- SQLite backup is a file copy (with WAL checkpoint for consistency: `sqlite3 db "PRAGMA wal_checkpoint(TRUNCATE)"` then copy)
- A single cron script backing up all stores: ~10 lines of shell
- CASS's Tantivy index is fully derived from session logs — disposable and rebuildable
- cass_memory_system is the most git-friendly (YAML + JSON files)
- mcp-memory-service embeddings are regenerable — only the content matters, not the vectors

---

## 7. Temporal (Workflow Orchestration)

**Investigated because fusion_response.md proposed it.**

### Local deployment requirements

- Temporal server process (Go binary)
- Backing database: PostgreSQL, MySQL, or Cassandra
- Temporal worker process
- Temporal CLI for administration

### Verdict

Designed for distributed microservices orchestration across data centres. Requires running a database server. Massive overkill for 2-10 agents on one machine. Not compatible with "no database maintenance" preference.

### Alternatives investigated

- **Gas City**: Lightweight, Go binary, tmux-based. File-based beads mode available. More appropriate scale.
- **Beads + hooks + Agent Mail**: Minimal coordination primitives. No orchestration server needed. Already validated.

---

## 8. Chezmoi (Config Sync)

**Investigated because fusion_response.md proposed it for config sync.**

### What Chezmoi does well

- Manages personal dotfiles across machines (.zshrc, .gitconfig, etc.)
- Go templates for per-machine customisation
- Deterministic, conflict-safe application

### Why it's wrong for this problem

- Designed for **user-level dotfiles**, not **project-level config**
- No native multi-source layering (enterprise → team → personal)
- Template language is Go templates, not the Jinja2 the fusion response assumed
- Doesn't understand runtime config formats — it's a file copier, not a config translator
- The problem requires format-aware translation (AGENTS.md → CLAUDE.md vs opencode.json), not file copying
- LNAI solves this correctly by understanding each runtime's native format

---

## 9. Infrastructure Tools Comparison

| Tool | Declarative? | macOS + Linux? | Learning curve | Composability |
|------|-------------|----------------|---------------|---------------|
| **Nix flakes** | Fully | Yes | Very high | Excellent |
| **Devbox** (Nix wrapper) | Fully | Yes | Medium | Good |
| **mise** (formerly rtx) | Partially | Yes | Low | Good |
| **Docker Compose** | Fully | Yes | Low | Good |
| **Makefile + scripts** | No | Yes | None | Manual |

Nix provides the strongest guarantees but highest onboarding cost. Devbox wraps Nix with dramatically simpler UX. For a solo dev, Devbox or mise is the pragmatic middle ground.

---

## 10. Key Tools Not Recommended

| Tool/Approach | Reason |
|--------------|--------|
| Temporal | Requires database server, overkill for scale |
| Redis | Unnecessary at 2-10 agent scale, SQLite/filesystem sufficient |
| ChromaDB | Redundant when mcp-memory-service/Basic Memory handle embeddings |
| Mem0 | Resource-heavy self-hosted, cloud dependency for full features |
| MCP proxy | Unnecessary indirection, runtimes connect directly |
| Chezmoi | Wrong abstraction for project-level config translation |
| ACFS | Ubuntu-only, not composable, not Pro-compatible |
| oh-my-openagent | OpenCode-internal only, doesn't solve cross-runtime |
| Gas Town | Over-engineered/over-budget for 1-2 Pro subs |
| Ansible | Imperative, user correctly prefers declarative |
