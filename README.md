# Claude Code Skills: /domain-interview + /new-plan + /new-task + /review + /write-docs + /adversarial-plan-review

A skill chain for disciplined feature development with Claude Code.

## Architecture

```
/domain-interview          /new-plan (planning)        /new-task (execution)
┌─────────────────┐       ┌──────────────────────┐    ┌──────────────────────────┐
│ Phase 0: Orient │       │ Phase 0: Interview    │    │ Phase 0: Load spec+plan  │
│ Phase 1: Examples│──────▶│ Phase 1: Spec        │────▶│ Phase 1: Worktree setup  │
│ Phase 2: Language│ domain│   + DSL proposal ●   │spec │ Phase 2: TDD per unit    │
│ Phase 3: Bounds  │  .md  │ Phase 2: Plan        │plan │   + DSL code written ●   │
│ Phase 4: Draft   │       │ Phase 3: Handoff     │     │ Phase 3: Verify vs spec  │
└─────────────────┘       │   → GH issue + docs  │     │ Phase 4: Doc sync        │
                           └──────────────────────┘    │   + DSL drift audit ●    │
                                                        │ Phase 5: PR + cleanup    │
                                                        └──────────────────────────┘

/write-docs (documentation)
┌─────────────────────────────────────────┐
│ Phase 0: Detect Diátaxis usage          │
│ Phase 1: Classify (if Diátaxis in use)  │
│ Phase 2: Enforce quadrant rules + style │
│ — Invoked by /new-task Phase 4c         │
│ — Available standalone                  │
└─────────────────────────────────────────┘

/review (critique)                   shared/reference/
┌──────────────────────┐            ┌──────────────────────────────┐
│ Read artefact        │            │ tdd-guide.md                 │
│ Select persona lens  │◀───────────│ verification-guide.md        │
│ Produce critique     │  personas/ │ personas/beck.md             │
└──────────────────────┘            │ personas/farley.md           │
                                    │ personas/feathers.md         │
/adversarial-plan-review            │ personas/ford-parsons.md     │
┌──────────────────────┐            │ personas/kua.md              │
│ Read plan/spec       │◀───────────│ farley-atdd-reference.md     │
│ Spawn 4 parallel     │  personas/ └──────────────────────────────┘
│ reviewer subagents   │
│ Collect findings     │
│ Synthesis doc →      │
│ human decides        │
└──────────────────────┘

● DSL: /new-plan proposes
  interface names (from glossary);
  /new-task writes the code;
  /new-task audits drift between DSL implementation and DOMAIN.md glossary.
```

## Workflow

1. **`/domain-interview`** _(optional)_ — Three Amigos interview with a domain
   expert. Extracts business rules, examples, and vocabulary. Produces
   `dev-docs/domain/DOMAIN.md`. Can be initiated with a GitHub issue (`#N`)
   or a free-form business description.

2. **`/new-plan`** — Interviews you, produces SPEC.md + PLAN.md (using domain
   context if available), gets your approval, hands off via GitHub issue or
   `dev-docs/<feature>/` directory. Can be initiated with an issue reference.

3. **`/new-task #42`** or **`/new-task dev-docs/my-feature/`** — Picks up the
   plan, creates a git worktree, implements units using strict TDD
   (red → green → refactor), verifies against the spec, submits via PR or commit.

4. **`/review dev-docs/auth/PLAN.md --lens beck`** — Reviews artefacts or
   source code through distilled persona lenses (Beck, Farley, Feathers,
   Ford/Parsons, Kua). Lazy mode (no `--lens`) proposes relevant lenses and
   lets you choose.

5. **`/adversarial-plan-review dev-docs/my-feature/PLAN.md`** _(optional)_ —
   Stress-tests a plan using four reviewer personas in parallel subagents
   (Ford/Parsons, Kua, Farley, Feathers). Each reviews independently. Produces
   a synthesis document with cross-cutting patterns and human decision questions.
   Run after `/new-plan` when architectural decisions are significant.

6. **`/write-docs`** — Writes or improves documentation. Detects whether the
   project uses Diátaxis; if so, classifies content into the correct quadrant
   (Tutorial / How-To / Explanation) and enforces quadrant rules before
   writing. Otherwise applies style rules only. Invoked automatically by
   `/new-task` Phase 4c when new doc files are proposed.

## GitHub issue lifecycle

When the repo has a GitHub remote, issues serve as navigation hubs — they
link to docs in the repo rather than duplicating content.

| Stage                             | Issue state                                                      |
| --------------------------------- | ---------------------------------------------------------------- |
| `/domain-interview #N` completes  | Comment: link to DOMAIN.md on `main`                             |
| `/new-plan #N` completes          | Body updated: links to SPEC.md + PLAN.md on `feat/<slug>`        |
| `/new-task` verification complete | Comment: link to VERIFICATION.md on `feat/<slug>`                |
| PR merged, docs archived          | Comment: links to all 3 docs under `dev-docs/archive/` on `main` |

Issues are **never closed automatically** — that's a manual user decision.

## Manual user gates

The skills stop and wait for your explicit approval at these points:

| Gate             | Skill               | What you approve                           |
| ---------------- | ------------------- | ------------------------------------------ |
| DOMAIN.md review | `/domain-interview` | Domain model correctness (expert sign-off) |
| SPEC.md sign-off | `/new-plan`         | Requirements completeness and accuracy     |
| PLAN.md sign-off | `/new-plan`         | Implementation units and approach          |
| Submit results   | `/new-task`         | Changes before PR/commit is created        |
| Archive push     | `/new-task`         | Commit moving docs to `dev-docs/archive/`  |
| Lens selection   | `/review`           | Which persona lenses to apply (lazy mode)  |
| Synthesis review | `/adversarial-plan-review` | Which findings to act on before proceeding |
| Issue close      | (manual)            | You close the issue when satisfied         |

## Installation

```bash
# Symlink mode (recommended) — stays in sync with this repo
afb install

# Copy mode — standalone snapshot, no sync
afb install --copy

# Uninstall
afb uninstall
```

On first run, `afb install` auto-creates `accounts.json` pointing at `~/.claude` if no `accounts.json` exists. Skills, hooks, commands, CLAUDE.md, and statusline-command.sh are symlinked from `dot_claude/` in this repo into each account's config dir. `settings.json` is generated from `dot_claude/settings.json.template`.

See [docs/install.md](docs/install.md) for full install instructions, [docs/usage.md](docs/usage.md) for command reference, and [docs/uninstall.md](docs/uninstall.md) for removal steps.

### Staying in sync

With symlink mode, edits in `~/.claude/skills/` are edits to the repo. Pull to update all machines:

```bash
git pull   # skills update immediately via symlinks
```

Restart Claude Code after pulling changes to reload skill metadata.

## Multi-account setup

Run multiple Claude Code accounts on one machine, each with its own `CLAUDE_CONFIG_DIR`, sharing a single common config from this repo.

### Step 0 — bootstrap `dot_claude/` (one-time, per machine)

After cloning, populate `dot_claude/` from your existing `~/.claude/`:

```bash
cp ~/.claude/CLAUDE.md                     dot_claude/CLAUDE.md
cp ~/.claude/hooks/warn-sensitive-files.sh dot_claude/hooks/warn-sensitive-files.sh
cp ~/.claude/statusline-command.sh         dot_claude/statusline-command.sh
# Edit dot_claude/settings.json.template:
#   replace all hardcoded paths with {{CLAUDE_HOME}}
```

This is a one-time step per machine. Commit the result — other machines get it via `git pull`.

### Setup

```bash
# 1. Copy the example and edit for your accounts
cp accounts.json.example accounts.json

# 2. Run the installer
afb install

# 3. Load the generated aliases
echo "source $(pwd)/aliases.sh" >> ~/.zshrc  # or ~/.profile
source aliases.sh
```

`accounts.json` is gitignored — each machine maintains its own.

### accounts.json format

```json
{
  "accounts": [
    { "name": "claudea", "claude_home": "~/.claude/.claudea", "default": true },
    { "name": "claudeb", "claude_home": "~/.claude/.claudeb" }
  ]
}
```

Exactly one account should have `"default": true`. If absent, `accounts.json` is auto-created with a single account at `~/.claude`.

### Aliases

`afb install` generates `aliases.sh` (gitignored):

```bash
alias claudea='CLAUDE_CONFIG_DIR=~/.claude/.claudea claude'
alias claudeb='CLAUDE_CONFIG_DIR=~/.claude/.claudeb claude'
alias claude='CLAUDE_CONFIG_DIR=~/.claude/.claudea claude'  # default
```

**Caveat**: the `claude` alias overrides any `CLAUDE_CONFIG_DIR` already set in an interactive shell. Use the named alias (`claudea`, `claudeb`) when you need a specific account explicitly.

### Plugins

Plugins are **not shared** across accounts — each account maintains its own plugin state and cache under its `CLAUDE_CONFIG_DIR`. This is intentional: plugins write runtime state to their config dir, so sharing would cause conflicts.

You are responsible for keeping plugin versions in sync across accounts. Install or update plugins separately in each account. Use `afb check` to verify that `enabledPlugins` in each account's `settings.json` matches the template:

```bash
afb check
```

To add a plugin to all accounts, update `dot_claude/settings.json.template` and re-run `afb install`.

### Updating common config

Edit files under `dot_claude/`, commit, pull on other machines, re-run `afb install`. Skills, hooks, CLAUDE.md, and statusline-command.sh update immediately via symlinks; `settings.json` is regenerated with controlled fields merged from the template.

### Migrating an existing single-account install

If you already have a working `~/.claude/` and want to move it to a named account directory (e.g. `~/.claude/.claudea`):

```bash
# 1. Copy to a temp location outside ~/.claude/ (can't move a dir into itself)
cp -r ~/.claude /tmp/claude_migrate

# 2. Move to the new account location
mv /tmp/claude_migrate ~/.claude/.claudea
```

Then create `accounts.json`:

```json
{
  "accounts": [
    { "name": "claudea", "claude_home": "~/.claude/.claudea", "default": true }
  ]
}
```

Run `afb install`. It will overwrite `skills/`, `hooks`, `commands`, `CLAUDE.md`, `statusline-command.sh`, and regenerate `settings.json` from the template. Your runtime state (`history.jsonl`, `sessions/`, `plans/`, `projects/`, `tasks/`, `todos/`, `cache/`) is preserved from the copy.

If you don't need to preserve history, skip the copy and let `afb install` create a fresh directory.

### Other flags

```bash
afb check         # read-only sync check; exits 1 if controlled fields diverge
afb install --force      # overwrite real files/dirs with symlinks
afb install --skip-diff  # skip settings.json diff prompt
```

## File layout

```
~/.claude/skills/
├── adversarial-plan-review/
│   ├── SKILL.md                    # Multi-persona parallel plan stress-test
│   └── references/
│       └── subagent-setup.md       # Subagent prompt templates and wiring
├── domain-interview/
│   ├── SKILL.md                    # Three Amigos interview workflow
│   └── reference/
│       └── interview-guide.md      # Question bank + anti-patterns
├── new-plan/
│   ├── SKILL.md                    # Planning workflow
│   └── reference/
│       ├── interview-guide.md      # Requirements interview questions
│       ├── planning-guide.md       # Kent Beck decomposition heuristics
│       └── handoff-guide.md        # GH issue vs local docs packaging
├── new-task/
│   ├── SKILL.md                    # Execution workflow
│   └── reference/
│       ├── doc-sync-guide.md       # Keep docs in sync with code
│       └── worktree-guide.md       # Git worktree + issue comment lifecycle
├── review/
│   ├── SKILL.md                    # Persona-driven artefact review
│   └── reference/
│       └── review-guide.md         # Lens proposal heuristics, critique structure
├── write-docs/
│   ├── SKILL.md                    # Detect Diátaxis, classify, enforce, write
│   └── references/
│       ├── diataxis.md             # Quadrant rules (tutorial/how-to/explanation)
│       └── style.md                # Voice, tone, formatting rules
└── shared/
    └── reference/
        ├── SKILL.md                # Discovery-only (disabled for auto-invoke)
        ├── tdd-guide.md              # Red-green-refactor, test naming
        ├── verification-guide.md    # Spec compliance, traceability matrix
        ├── farley-atdd-reference.md # Deep reference: four-layer model, Python examples
        ├── architectural-fitness.md # Fitness functions, reversibility assessment
        ├── stability-patterns.md    # Circuit breaker, timeout, bulkhead, fallback
        └── personas/
            ├── beck.md             # Kent Beck — TDD, simple design, Tidy First
            ├── farley.md           # Dave Farley — verification, ATDD, releasability
            ├── feathers.md         # Michael Feathers — legacy code, seams, safety
            ├── metz.md             # Sandi Metz — OO design, dependencies, single responsibility
            ├── kerr.md             # Jessica Kerr — sociotechnical, team/module boundary alignment
            ├── ford-parsons.md     # Ford + Parsons — evolvability, fitness functions, implicit bets
            └── kua.md              # Patrick Kua — decision reversibility, ADR quality
```

## Design decisions

- **Skills, not commands**: Uses the newer Agent Skills format with YAML
  frontmatter, progressive disclosure, and model-invoked triggering.
- **Separated concerns**: Planning and execution are independent skills
  that compose through SPEC.md + PLAN.md as the contract.
- **Issues as navigation hubs**: GitHub issues link to repo docs at the
  correct branch; they don't duplicate content. The repo is the source of truth.
- **Shared references**: TDD and verification guides live in
  `shared/reference/` with `disable-model-invocation: true` to avoid
  phantom triggering.
- **Graceful degradation**: All skills detect git/GitHub availability
  and fall back to local-only workflows.
- **Contextual triggering**: Personas and concept references are loaded
  at specific workflow phases, not by user request. The user knows these
  principles but wouldn't always think to invoke them at the right moment.
  The workflow injects them contextually — Beck during TDD, Feathers when
  modifying existing code, fitness functions when plans have architectural
  decisions, stability patterns when external dependencies exist.

