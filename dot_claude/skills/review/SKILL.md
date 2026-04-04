---
name: review
description: >
  Review a SPEC.md, PLAN.md, or source code through distilled persona lenses
  (Beck, Farley, Feathers, Ford/Parsons, Kua) and concept lenses (architecture,
  resilience). Produces structured critique with specific, actionable feedback.
  Use when the user says "review this", "critique my plan", "review my spec", or
  invokes /review with a file or directory path.
---

# /review — Persona-Driven Artefact Review

## Overview

This skill reviews planning artefacts and source code through distilled
persona lenses. Each lens produces a distinct critique section with specific
feedback traced to line numbers and requirements.

## Fresh Context Requirement

**This skill MUST run in a new conversation**, not in the same session that
produced the artefact being reviewed. If Claude wrote the code or plan, it
cannot objectively critique its own output — confirmation bias is inevitable
when the reasoning that produced the work is still in context.

If invoked in a conversation that contains `/new-plan` or `/new-task` output,
warn the user:

```
This review will be less effective because I wrote the artefact being
reviewed in this same session. My own reasoning is still in context,
which creates confirmation bias.

For an independent review, start a new conversation and run:
  /review <path> --lens <name>
```

Proceed if the user insists, but flag this limitation in the review output.

## Usage

```
/review dev-docs/auth/PLAN.md --lens beck      # explicit single lens
/review dev-docs/auth/PLAN.md                   # lazy mode (Claude proposes lenses)
/review dev-docs/auth/                          # directory mode (review all artefacts found)
/review src/auth/handler.py --lens feathers     # source code review
```

The `$ARGUMENTS` value is parsed as:
- Path to a file → review that file
- Path to a directory → review all artefacts found (SPEC.md, PLAN.md, source)
- `--lens <name>` → apply that specific persona lens (beck, farley, feathers)
- No `--lens` → lazy mode (propose lenses, user selects)

## Available Lenses

### Persona lenses (inhabitable decision-making styles)

| Lens | Reference file | Best for |
|---|---|---|
| beck | `~/.claude/skills/shared/reference/personas/beck.md` | Simple design, TDD, intention-revealing code |
| farley | `~/.claude/skills/shared/reference/personas/farley.md` | Verification architecture, ATDD, testability |
| feathers | `~/.claude/skills/shared/reference/personas/feathers.md` | Legacy code safety, seams, characterization |
| metz | `~/.claude/skills/shared/reference/personas/metz.md` | OO design, dependency direction, single responsibility |
| kerr | `~/.claude/skills/shared/reference/personas/kerr.md` | Sociotechnical alignment, team/module boundaries |
| ford-parsons | `~/.claude/skills/shared/reference/personas/ford-parsons.md` | Evolvability, fitness functions, coupling, implicit bets |
| kua | `~/.claude/skills/shared/reference/personas/kua.md` | Decision reversibility, ADR quality, deferral attractors |

### Concept lenses (framework checklists)

| Lens | Reference file | Best for |
|---|---|---|
| architecture | `~/.claude/skills/shared/reference/architectural-fitness.md` | Fitness functions, reversibility, architectural drift |
| resilience | `~/.claude/skills/shared/reference/stability-patterns.md` | External dependency failure modes, blast radius |

## Workflow

### Step 1 — Read and validate the artefact(s)

Read the file or directory contents. For a directory, look for:
- `SPEC.md` — specification
- `PLAN.md` — implementation plan
- Source files (`.py`, `.ts`, `.js`, `.go`, `.rs`, etc.)

**Validate upstream artefact structure** (spot check, not full semantic review):

If reviewing a **SPEC.md**, confirm:
- [ ] Contains numbered functional requirements (FR-x)
- [ ] Contains numbered acceptance criteria (AC-x)
- [ ] Has a problem statement section

If reviewing a **PLAN.md**, confirm:
- [ ] Contains numbered implementation units
- [ ] Each unit has a "Tests first" section
- [ ] Each unit has "Traces to" referencing spec requirements

If validation fails, warn before proceeding:
```
This [SPEC/PLAN].md appears incomplete — missing: [list].
It may not have been produced by /new-plan. I can still review what's
here, but findings may be limited. Continue, or run /new-plan first?
```

If the user says continue, proceed with the review on what exists.

### Step 2 — Determine lens(es)

**Mandatory lens**: When reviewing **source code** (any language, new or existing),
the **farley** lens always runs — it checks cohesion, separation of concerns,
information hiding, and coupling. This is automatic and not optional. Other
lenses are added on top.

**Explicit mode** (`--lens <name>`): Load the specified persona file. For source
code, Farley is added automatically if not already specified. Skip to Step 3.

**Lazy mode** (no `--lens`): Examine the artefact type and propose relevant lenses.

See [reference/review-guide.md](reference/review-guide.md) for lens proposal
heuristics by artefact type.

Present the proposal:

```
This is a [type] artefact. Relevant lenses:
- **farley** — complexity management (mandatory for source code)
- **beck** — [why relevant to this artefact]
- ...

Which additional lenses should I apply? (comma-separated, or "all")
Farley lens runs automatically for source code.
```

Wait for user selection before proceeding.

### Step 3 — Load persona and review

For each selected lens:
1. Read the reference file (persona or concept) from `~/.claude/skills/shared/reference/`
2. For persona lenses, identify the relevant mode section for the artefact type:
   - SPEC.md → Farley "Verification", Beck "Plan Review", Kerr "Domain Review"
   - PLAN.md → Beck "Plan Review", Farley "ATDD Planning", Metz "Plan Review", Kerr "Plan Review"
   - Source code (greenfield) → Farley "Code Review" (mandatory), Beck "Code Review", Metz "Code Review"
   - Source code (modifying existing) → Farley "Code Review" (mandatory), Feathers "Code Review (Legacy)"
3. For concept lenses, apply the reference's checklist/framework to the artefact:
   - architecture → evaluate fitness functions, reversibility, dependency direction
   - resilience → evaluate external dependency failure modes, timeout/circuit breaker coverage
4. Apply the heuristics/checklist systematically to the artefact
5. Produce a critique section for this lens

### Step 4 — Produce output

#### Single lens output

```markdown
## Review: [file] — [Persona] Lens

### Findings

1. **[Issue category]** (line N): [specific observation]
   - [what the persona's heuristic says about this]
   - **Suggestion**: [concrete action]

2. ...

### Summary
[2-3 sentence overall assessment through this persona's values]
```

#### Multiple lens output (lazy mode with multiple selections)

```markdown
## Review: [file or directory]

### Beck Lens — Simple Design
[findings as above]

### Farley Lens — Verification Architecture
[findings as above]

### Alignment Critique (when reviewing SPEC + PLAN together)
- Does the plan trace to the spec? Gaps?
- Over-engineering beyond spec?
- Missing acceptance criteria coverage?

### Summary
[consolidated assessment across lenses, noting agreements and tensions]
```

### Directory mode (SPEC + PLAN together)

When given a directory containing both SPEC.md and PLAN.md, review both with
distinct critique sections:

- **Spec critique**: Right requirements? Missing edge cases? Ambiguous criteria?
- **Plan critique**: Right approach? Simplest thing? Units correctly scoped?
- **Alignment critique**: Does the plan trace to the spec? Gaps? Over-engineering?

If the directory contains only one file, review just that file.

## Domain Term Drift Check

**When**: a DOMAIN.md exists (`dev-docs/domain/DOMAIN.md` or
`dev-docs/domain/*/DOMAIN.md`). Runs automatically alongside any lens
when reviewing source code, tests, SPEC.md, or PLAN.md.

**Skip** if no DOMAIN.md exists.

1. Read DOMAIN.md glossary
2. Read `~/.claude/skills/shared/reference/domain-language-guide.md` for
   source-of-truth rules
3. Scan the artefact under review for domain concept references:
   - Variable/function/class names that correspond to glossary terms
   - Test names that describe domain behaviour
   - Comments and docstrings that reference domain concepts
   - SPEC.md requirement text and acceptance criteria wording
   - PLAN.md unit names and "Delivers" descriptions
4. Flag drift:
   - Developer jargon used where a glossary term exists (e.g., "remove" instead of "archive")
   - Glossary terms used inconsistently (different names for same concept across files)
   - New domain concepts in code that have no glossary entry
5. Present findings in a **Domain language** section of the review output

This is broader than `/new-task` Phase 4c+ (which only checks DSL interface
methods against glossary mappings). The review checks vocabulary consistency
across all code and documentation.

## Review Rules

- **Be specific**: reference line numbers, requirement IDs, test names
- **Be actionable**: every finding must have a concrete suggestion
- **Sound like the persona**: Beck critique should be about communication and simplicity,
  not generic "code quality". Farley critique should be about verification architecture.
  Feathers critique should be about safety and seams.
- **Don't invent problems**: if the artefact is good, say so. Not every review
  finds issues.
- **Respect scope**: review what's there, don't critique what's absent unless
  the absence violates the persona's core values

## What Happens Next

After presenting the review, suggest next steps based on what was reviewed:

**After reviewing SPEC.md or PLAN.md:**
```
Review complete.

Next steps:
  Address findings above, then:
  /new-task dev-docs/<slug>/     — implement the plan
  /review dev-docs/<slug>/ --lens <other>  — review with a different lens
```

**After reviewing source code:**
```
Review complete.

Next steps:
  Address findings above, then:
  /review <path> --lens <other>  — review with a different lens
  Run tests to verify changes    — ensure nothing broke
```

**After reviewing a directory (SPEC + PLAN together):**
```
Review complete.

Next steps:
  Address findings above, then:
  /new-task dev-docs/<slug>/     — start implementing
  /review dev-docs/<slug>/ --lens <other>  — try another lens
```

Replace paths with actual values. Only show relevant options.
