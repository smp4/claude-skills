# Domain Persistence Design

## Purpose

This document defines how domain knowledge is stored, structured, and kept
consistent across Claude Code sessions and across the full skill pipeline.
It is the output contract of `/domain-interview` and the input contract of
`/new-plan` and `/new-task`.

---

## The Problem: Domain Knowledge Degrades Between Sessions

Claude Code has no memory between sessions. Without explicit persistence,
domain knowledge established in an interview is lost. Worse, Claude may
silently introduce different vocabulary or different interpretations of
business concepts in a later session, causing drift between:
- What the domain expert approved
- What the spec says
- What the code implements

The persistence design prevents this by creating a single source of truth
for domain language that every skill reads and none can silently override.

---

## Three-Layer Persistence Structure

### Layer 1: `docs/domain/DOMAIN.md` — Reasoning and Context

**Purpose**: captures the *why* behind domain decisions. This is the layer
that gets lost most easily and is most expensive to reconstruct.

**Contents**:
- Named actors and their goals
- Business rules (numbered: BR-01, BR-02, ...)
- Bounded context boundaries — where this context starts and ends
- Concepts borrowed from adjacent contexts (and how they differ)
- Unresolved questions (checkbox list — checked off as resolved)
- Raw verbatim examples from the domain interview
- Interview metadata (date, participants)

**Audience**: Claude Code (loaded as context at session start), developers
reviewing decisions

**Rule**: never paraphrase the raw examples. Copy them verbatim from the
interview. Paraphrasing introduces the exact ambiguity the interview was
designed to remove.

**Size target**: under 200 lines. If it grows beyond this, split into
bounded context subdirectories.

---

### Layer 2: `docs/domain/GLOSSARY.md` — Human-Readable Vocabulary

**Purpose**: maps business terms to their precise definitions and to their
DSL counterparts. This is the human-readable face of the domain language.

**Contents**: for each term:
- Definition in business language (one sentence)
- Concrete example (verbatim from interview if possible)
- DSL mapping (added after implementation — see below)
- Notes on bounded context scope, related terms, or ambiguities

**Audience**: domain experts (can read and correct), developers (reference
during implementation), Claude Code (context for naming decisions)

**Rule**: the GLOSSARY is NOT the source of truth. It is a *view* of the
source of truth, which lives in the DSL interfaces. The GLOSSARY maps terms
*to* DSL implementations — it does not define them independently.

**DSL mapping field**: initially left as `TODO` when the interview produces
the GLOSSARY. Filled in by `/new-plan` or `/new-task` when the DSL interface
is created. A term with no DSL mapping is either not yet implemented (mark
`TODO: not yet implemented`) or has been silently renamed in code (a drift
violation — see below).

---

### Layer 3: DSL Interfaces — Authoritative Domain Language in Code

**Purpose**: the DSL interface file IS the domain language. It is the
source of truth. Everything else maps to it.

**Python**: `acceptance_tests/dsl/interfaces.py` — `typing.Protocol` classes
**TypeScript**: `acceptance-tests/dsl/interfaces.ts` — TypeScript interfaces

**Rule**: the DSL interface is the canonical name for every domain operation.
If the GLOSSARY uses a different name than the DSL, the GLOSSARY is wrong
and must be updated. If the code uses a different name than the DSL, the
code is wrong.

**Rule**: DSL interfaces are the *only* place where domain operation names
are defined authoritatively. They are not derived from the GLOSSARY — the
GLOSSARY is derived from them.

---

## File Structure

```
project/
├── docs/
│   └── domain/
│       ├── DOMAIN.md          # Reasoning, business rules, bounded context
│       └── GLOSSARY.md        # Human-readable terms → DSL mapping
├── features/                  # Gherkin .feature files (if using Gherkin)
│   └── *.feature              # Draft status until /new-plan approves
├── acceptance_tests/          # (Python) or acceptance-tests/ (TypeScript)
│   └── dsl/
│       └── interfaces.py      # THE source of truth for domain language
└── ...
```

For multi-context projects, namespace by bounded context:

```
docs/domain/
├── ordering/
│   ├── DOMAIN.md
│   └── GLOSSARY.md
└── fulfilment/
    ├── DOMAIN.md
    └── GLOSSARY.md

acceptance_tests/dsl/
├── ordering/
│   └── interfaces.py
└── fulfilment/
    └── interfaces.py
```

---

## Drift Prevention Rules

Drift is when the GLOSSARY, the DSL, and the code describe the same concept
with different words, or with the same word meaning different things.

### Rule 1: DSL is the source of truth

If GLOSSARY term ≠ DSL method name → GLOSSARY is wrong. Update GLOSSARY.
If code name ≠ DSL method name → code is wrong. Update code.
Never update the DSL to match ad-hoc code naming.

### Rule 2: No silent renaming

If a domain concept is renamed during implementation, three things must
happen in the same commit:
1. DSL interface is updated
2. GLOSSARY DSL mapping field is updated
3. All drivers and tests are updated

The `/new-task` doc-sync phase (Phase 4) enforces this by checking
GLOSSARY entries against DSL interface methods before allowing submission.

### Rule 3: Unimplemented terms are flagged, not deleted

If a GLOSSARY term has no DSL mapping yet, mark it:
```
**DSL mapping**: `TODO: not yet implemented`
```
Do not delete the term. It records intent. It becomes a requirement.

### Rule 4: New terms from implementation must go back to GLOSSARY

If `/new-task` introduces a new DSL method that has no GLOSSARY entry, the
doc-sync phase must create one. New domain concepts cannot live only in code.

---

## What Claude Code Loads at Session Start

For maximum context efficiency, the recommended session context is:

```
1. docs/domain/DOMAIN.md          (~200 lines max — fits in context cleanly)
2. acceptance_tests/dsl/interfaces.py   (compact — Protocol definitions only)
3. features/*.feature              (the specification — what must be true)
```

This gives Claude the vocabulary (DOMAIN.md), the operation contract
(interfaces), and the behaviour specification (features) without loading
the full codebase.

The GLOSSARY.md is human-facing and does not need to be loaded into Claude
Code context on every session — it is referenced when naming decisions are
being made or when drift is being checked.

---

## Lifecycle of a Domain Term

```
1. /domain-interview
   Domain expert uses a word → Claude captures it verbatim →
   Added to GLOSSARY as candidate term (no DSL mapping yet) →
   Domain expert approves GLOSSARY

2. /new-plan
   Spec references GLOSSARY terms →
   Acceptance criteria traced to BDD scenarios →
   DSL interface methods named from GLOSSARY terms →
   GLOSSARY DSL mapping field filled in (TODO → interface reference)

3. /new-task
   DSL method implemented in Protocol Driver →
   Doc-sync phase checks GLOSSARY mapping is correct →
   Any new terms added to GLOSSARY in same PR

4. Ongoing
   Domain expert corrects a term → GLOSSARY updated →
   DSL interface renamed → Code updated → Doc-sync validates in next PR
```

---

## Template Files

### `docs/domain/DOMAIN.md` template

```markdown
# Domain Context: <Feature or Bounded Context Name>

<!-- Generated by: /domain-interview -->
<!-- Interview date: YYYY-MM-DD -->
<!-- Approved by: <name/role> -->
<!-- Status: draft | approved -->

## Actors

| Actor | Role | Goal |
|-------|------|------|
| <name> | <role> | <what they want to achieve> |

## Business Rules

- **BR-01**: <rule statement>
- **BR-02**: <rule statement>

## Bounded Context

**This context covers**: <what is in scope>
**This context does NOT cover**: <explicit exclusions>
**Adjacent contexts**: <what it touches and how>

## Key Examples (verbatim from interview)

> "<exact words the domain expert used, unparaphrased>"
> — <date>

> "<another example>"

## Unresolved Questions

- [ ] <question that needs an answer before implementation>
- [x] <resolved question — leave for audit trail>

## Decisions

- **DECISION-01**: <decision made and brief rationale>
```

### `docs/domain/GLOSSARY.md` template

```markdown
# Domain Glossary: <Bounded Context Name>

<!-- Source: /domain-interview session YYYY-MM-DD -->
<!-- Approved by: <name/role> -->

## <Term>

**Definition**: <one sentence, business language, no technical jargon>

**Example**: <concrete example, verbatim from interview if possible>

**DSL mapping**: `acceptance_tests/dsl/interfaces.py::<Class>.<method>`
(or `TODO: not yet implemented`)

**Bounded context**: <which context this term belongs to>

**Notes**: <ambiguities, related terms, how it differs from similar terms>

---

## <Next Term>
...
```

### `.feature` file header (draft status)

```gherkin
# STATUS: DRAFT
# Source: /domain-interview YYYY-MM-DD
# Approved by domain expert: YES
# Approved by /new-plan technical review: PENDING
#
# This file is a domain expert-validated draft.
# It becomes a formal acceptance criterion when /new-plan
# includes it in SPEC.md.

Feature: <feature name — use GLOSSARY term exactly>
  ...
```
