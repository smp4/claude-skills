# Claude Code Skills: /domain-interview + /new-plan + /new-task + /review + /write-docs

A four-skill chain for disciplined feature development with Claude Code.

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
● DSL: /new-plan proposes          │ farley-atdd-reference.md     │
  interface names (from glossary); └──────────────────────────────┘
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
   source code through distilled persona lenses (Beck, Farley, Feathers).
   Lazy mode (no `--lens`) proposes relevant lenses and lets you choose.

5. **`/write-docs`** — Writes or improves documentation. Detects whether the
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
| Issue close      | (manual)            | You close the issue when satisfied         |

## Installation

```bash
chmod +x install.sh

# Symlink mode (recommended) — skills stay in sync with this repo
./install.sh

# Copy mode — standalone snapshot, no sync
./install.sh --copy

# Uninstall
./install.sh --uninstall
```

### Staying in sync

With symlink mode (the default), your workflow is:

```bash
# Edit skills directly (either location works — they're the same files)
vim ~/.claude/skills/new-plan/SKILL.md
# or
vim ~/repos/claude-skills/new-plan/SKILL.md

# Commit and push from the repo
cd ~/repos/claude-skills
git add -A && git commit -m "improve interview questions" && git push

# On another machine, pull to update
git pull   # skills update immediately via symlinks
```

Restart Claude Code after pulling changes to reload skill metadata.

## File layout

```
~/.claude/skills/
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
            └── kerr.md             # Jessica Kerr — sociotechnical, team/module boundary alignment
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

