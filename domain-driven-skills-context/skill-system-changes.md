# Skill System Changes

## Overview

This document describes the changes required to the existing `/new-plan` and
`/new-task` skills to integrate the new `/domain-interview` skill, and
specifies the new shared reference file `domain-language-guide.md`.

The existing skills were designed and delivered as a zip package
(`claude-code-skills.zip`) containing:

```
new-plan/
  SKILL.md
  reference/interview-guide.md
  reference/planning-guide.md
  reference/handoff-guide.md
new-task/
  SKILL.md
  reference/worktree-guide.md
  reference/doc-sync-guide.md
shared/reference/
  SKILL.md
  tdd-guide.md
  verification-guide.md
```

The changes below modify existing files and add new ones. The result is a
three-skill system:

```
/domain-interview (NEW)   →   /new-plan (MODIFIED)   →   /new-task (MODIFIED)
```

---

## End-to-End Flow (Updated)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 1: /domain-interview                                               │
│                                                                         │
│ - Claude plays BA, Tester, Developer roles                              │
│ - Interviews domain expert (not developer)                              │
│ - Extracts: actors, business rules, concrete examples, vocabulary       │
│ - Drafts: GLOSSARY.md, DOMAIN.md, .feature files                       │
│ - EXPLICIT DOMAIN EXPERT SIGN-OFF required before writing files         │
│                                                                         │
│ Output: docs/domain/DOMAIN.md                                           │
│         docs/domain/GLOSSARY.md                                         │
│         features/*.feature  (STATUS: DRAFT)                             │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 2: /new-plan                                                       │
│                                                                         │
│ - Detects domain artefacts → skips Phase 0 interview                   │
│ - Reads DOMAIN.md, GLOSSARY.md, draft .feature files as context        │
│ - Writes SPEC.md: every criterion traced to BDD scenario or BR-NN      │
│ - Writes PLAN.md: units reference DSL interface methods by name         │
│ - Proposes DSL interface (acceptance_tests/dsl/interfaces.py)           │
│ - Updates GLOSSARY DSL mapping fields (TODO → interface reference)      │
│ - Updates .feature file headers (PENDING → approved)                   │
│ - Developer approval gate                                               │
│ - Handoff via GH issue or docs/<slug>/                                  │
└─────────────────────────────┬───────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STEP 3: /new-task                                                       │
│                                                                         │
│ - Loads SPEC.md, PLAN.md                                               │
│ - Creates worktree + feature branch                                     │
│ - TDD: red → green → refactor per unit                                  │
│ - Verification: run acceptance tests, type check (mypy/pyright)        │
│ - Doc-sync (Phase 4): check GLOSSARY vs DSL interfaces for drift       │
│ - Submit: PR or commit                                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Changes to `/new-plan`

### `new-plan/SKILL.md` — Phase 0 Modification

**Current Phase 0**: runs a developer-facing discovery interview.

**Change**: Phase 0 becomes conditional:

```
## Phase 0 — Discovery

Check for domain artefacts:

  IF docs/domain/DOMAIN.md AND docs/domain/GLOSSARY.md exist:
    → PATH A: Domain artefacts found. Skip interview.
      Load DOMAIN.md and GLOSSARY.md as context.
      Read all features/*.feature files (STATUS: DRAFT).
      Proceed to Phase 1.

  ELSE:
    → PATH B: No domain artefacts. Run technical discovery interview.
      (Original Phase 0 interview protocol — unchanged)
      Proceed to Phase 1.
```

### `new-plan/SKILL.md` — Phase 1 (Spec) New Requirements

Add to the Phase 1 instructions:

```
## Phase 1 — Specification

[... existing content ...]

### Additional requirements when domain artefacts exist (Path A)

1. GLOSSARY TERMS MUST BE USED: Every business concept in SPEC.md must use
   the exact term from GLOSSARY.md. Do not rename domain concepts to
   developer vocabulary. If you want to use a different name, update
   GLOSSARY.md first and note the change.

2. TRACEABILITY REQUIRED: Every acceptance criterion in SPEC.md must be
   traced to one of:
   - A BDD scenario in features/ (by Feature + Scenario name)
   - A business rule in DOMAIN.md (by BR-NN id)

   Format:
   - AC-01: <criterion text> [→ Scenario: "User archives completed todo"]
   - AC-02: <criterion text> [→ BR-03]

3. DSL INTERFACE PROPOSAL: After writing acceptance criteria, propose the
   DSL interface that satisfies them. Use GLOSSARY terms as method names.
   Python: typing.Protocol classes in acceptance_tests/dsl/interfaces.py
   TypeScript: interfaces in acceptance-tests/dsl/interfaces.ts

4. GLOSSARY UPDATE: For each DSL method proposed, fill in the
   corresponding GLOSSARY entry's DSL mapping field:
   Change: `**DSL mapping**: TODO: not yet implemented`
   To:     `**DSL mapping**: acceptance_tests/dsl/interfaces.py::ClassName.method_name`
```

### `new-plan/reference/interview-guide.md` — Add Path A Entry

Add a note at the top:

```markdown
> **Note**: this guide is for Path B (no prior domain interview). If
> `docs/domain/DOMAIN.md` exists, Phase 0 is skipped — see SKILL.md.
```

---

## Changes to `/new-task`

### `new-task/SKILL.md` — Phase 4 (Doc-Sync) Extension

The existing doc-sync phase scans project docs for drift against what was
built. Add a GLOSSARY drift check:

```
## Phase 4 — Doc Sync

[... existing content ...]

### GLOSSARY drift check (new — runs when GLOSSARY.md exists)

4a: Load docs/domain/GLOSSARY.md and acceptance_tests/dsl/interfaces.py
    (or acceptance-tests/dsl/interfaces.ts)

4b: For each GLOSSARY entry with a non-TODO DSL mapping:
    - Verify the referenced class and method exist in the interfaces file
    - If NOT found: flag as drift violation (term was renamed in code
      without updating GLOSSARY)

4c: For each DSL interface method:
    - Verify a corresponding GLOSSARY entry exists
    - If NOT found: create a GLOSSARY entry stub with TODO fields and
      ask the user to fill in the definition and example before submitting

4d: Report drift violations to the user:
    - Renamed methods: show old name (GLOSSARY) and new name (DSL) and
      ask which is correct
    - Missing GLOSSARY entries: show stubs created, ask user to complete
    - Never silently resolve drift — always ask

4e: Apply fixes to GLOSSARY.md on the feature branch. Include in the
    same commit as the doc-sync changes.
```

### `new-task/reference/doc-sync-guide.md` — Add GLOSSARY Section

Add after the existing drift patterns section:

```markdown
## GLOSSARY Drift

GLOSSARY drift occurs when a DSL method is renamed in code without updating
the GLOSSARY, or when new DSL methods are added without GLOSSARY entries.

### Detection

Compare every `**DSL mapping**` field in GLOSSARY.md against the actual
method signatures in the DSL interfaces file. A mismatch is drift.

### Resolution priority

1. If the DSL method was renamed: the DSL is correct (it's the source of
   truth). Update GLOSSARY mapping field and definition if needed.
2. If the GLOSSARY term was changed: ask the domain expert. Don't assume.
3. If the method is new (no GLOSSARY entry): create a stub, ask developer
   to confirm definition before submitting.

### Never auto-resolve naming conflicts

If GLOSSARY says `archiveTodo` and DSL says `archive_todo` (Python naming),
that's a convention difference, not drift. The mapping field should reference
the Python name: `TodoDSL.archive_todo`.

If GLOSSARY says `archiveTodo` and DSL says `deleteTodo`, that is a semantic
change. Flag it. Ask which is correct.
```

---

## New File: `shared/reference/domain-language-guide.md`

This file is referenced by both `/domain-interview` and `/new-plan`.

```markdown
# Domain Language Guide

## The Three-Layer Persistence Structure

Domain language is maintained across three layers, each serving a different
audience and purpose:

| Layer | File | Audience | Source of truth? |
|-------|------|----------|-----------------|
| Reasoning | docs/domain/DOMAIN.md | Claude Code, developers | No — context only |
| Vocabulary | docs/domain/GLOSSARY.md | Domain experts, developers | No — view only |
| Contracts | dsl/interfaces.py (.ts) | Tests, code, Claude Code | **YES** |

The DSL interfaces file is the single source of truth for domain operation
names. The GLOSSARY maps human terms to DSL names. DOMAIN.md records the
reasoning behind decisions.

## The Fundamental Rule

  If GLOSSARY ≠ DSL → GLOSSARY is wrong. Fix GLOSSARY.
  If code ≠ DSL → code is wrong. Fix code.
  Never change the DSL to match ad-hoc naming choices elsewhere.

## Naming Convention Alignment

Python DSL methods use snake_case. GLOSSARY terms may be written in any
case (camelCase, Title Case, plain English). The GLOSSARY mapping field
is the bridge — it holds the exact Python identifier, not a conceptual
approximation.

Example:
  GLOSSARY term: "Archive Todo"
  DSL mapping:   `acceptance_tests/dsl/interfaces.py::TodoDSL.archive_todo`

## Bounded Context Isolation

Terms in one bounded context must not silently overlap with terms in another.
If the same word appears in two contexts with different meanings, both GLOSSARY
files must have the term with a clear bounded-context note explaining the
difference.

Example:
  "Order" in the ordering context: a customer's purchase request
  "Order" in the fulfilment context: a pick-and-pack instruction
  These are different concepts. Different DSL methods. Both in GLOSSARY.

## Adding a New Term (checklist)

  [ ] Term appears in DOMAIN.md (as part of a business rule or example)
  [ ] GLOSSARY entry created with definition and example
  [ ] DSL interface method added (or TODO marked if not yet implemented)
  [ ] GLOSSARY DSL mapping field updated
  [ ] All drivers updated to implement the new method
  [ ] Doc-sync validates in /new-task before PR submission

## Removing a Term (checklist)

  [ ] Confirm with domain expert that the concept no longer applies
  [ ] Remove DSL interface method
  [ ] Update GLOSSARY entry to "DEPRECATED — removed YYYY-MM-DD — reason"
      (do not delete — preserve audit trail)
  [ ] Update DOMAIN.md if it referenced the term in a business rule
  [ ] Remove from all drivers and acceptance tests
```

---

## Updated Directory Structure After All Changes

```
skills/
├── domain-interview/          ← NEW
│   ├── SKILL.md
│   └── reference/
│       ├── interview-guide.md
│       └── ddd-practitioner-persona.md  ← NEW (loaded by SKILL.md)
├── new-plan/                  ← MODIFIED
│   ├── SKILL.md               ← Phase 0 conditional, Phase 1 traceability
│   └── reference/
│       ├── interview-guide.md ← Add Path A note
│       ├── planning-guide.md  ← unchanged
│       └── handoff-guide.md   ← unchanged
├── new-task/                  ← MODIFIED
│   ├── SKILL.md               ← Phase 4 GLOSSARY drift check added
│   └── reference/
│       ├── worktree-guide.md  ← unchanged
│       └── doc-sync-guide.md  ← GLOSSARY drift section added
└── shared/
    └── reference/
        ├── SKILL.md           ← unchanged
        ├── tdd-guide.md       ← unchanged (Python section added separately
        │                           in farley-atdd-reference.md)
        ├── verification-guide.md ← unchanged
        └── domain-language-guide.md  ← NEW
```

---

## Notes for Claude Code When Building These Skills

1. **Read `farley-atdd-reference.md` first** — it provides the conceptual
   foundation and the Python implementation details that the skills build on.

2. **Read `domain-interview-skill-design.md`** — it contains the full
   specification for the new skill including role definitions, phase
   structure, validation gate, and output artefact templates.

3. **Read `ddd-practitioner-persona.md`** — it defines the expert
   practitioner persona that supervises all three interview roles. It
   should be installed as `domain-interview/reference/ddd-practitioner-persona.md`
   and referenced from the interview SKILL.md. The quick reference card
   at the bottom of that file should be inlined into SKILL.md directly.

4. **Read `domain-persistence-design.md`** — it defines the output contract:
   file structure, template formats, drift-prevention rules, and lifecycle
   of a domain term.

5. **This file (skill-system-changes.md)** — defines exactly what to change
   in the existing skills and what new shared file to create.

6. **The existing skill zip** — the current skills are already installed at
   `~/.claude/skills/`. Modify them in place (or rebuild the zip with the
   changes applied).

7. The Python `tdd-guide` addition: the `farley-atdd-reference.md` contains
   the full Python implementation section. Extract the relevant parts into
   `shared/reference/tdd-guide.md` as a Python subsection, preserving the
   existing TypeScript content.
