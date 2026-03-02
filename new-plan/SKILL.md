---
name: new-plan
description: >
  Interview the user to elicit a high-quality specification, then generate a
  multiphase implementation plan with docs-first discipline. Produces SPEC.md
  and PLAN.md, gets user approval, and hands off via GitHub issue or local
  docs directory. Use when the user says "new plan", "plan a feature",
  "let's design something", "start a new project", or wants to go from idea
  to structured implementation. Pairs with /new-task for execution.
---

# /new-plan — Interview → Specify → Plan → Handoff

## Overview

This command transforms a vague idea into an approved, packaged
specification and implementation plan. It is a **planning-only** skill —
it produces documents, not code. Execution is handled by `/new-task`.

## Workflow phases

Copy this checklist and update it as you progress:

```
Plan Progress:
- [ ] Phase 0: Discovery Interview (elicit requirements from user)
- [ ] Phase 1: Specification (write docs/<feature-slug>/SPEC.md)
- [ ] Phase 2: Architecture & Plan (write docs/<feature-slug>/PLAN.md)
- [ ] Phase 3: Approval & Handoff (user sign-off → GH issue or docs/)
```

---

## Phase 0 — Discovery Interview

**Goal**: Understand what the user actually needs before writing anything.

This is the most important phase. Do NOT skip it. Do NOT assume requirements.

### Interview protocol

Conduct a structured conversation. Ask questions **one area at a time** to
avoid overwhelming the user. Use the following interview areas in order:

1. **Problem & motivation** — What problem are you solving? Who is it for?
   Why now?
2. **Desired outcomes** — What does "done" look like? What can the user do
   when this is finished that they cannot do today?
3. **Scope boundaries** — What is explicitly OUT of scope? What is the
   minimum viable version?
4. **Constraints** — Technology stack, existing codebase, performance
   targets, security requirements, deployment environment?
5. **Interfaces** — What are the inputs and outputs? Who/what calls this?
   What does it call? What data shapes are involved?
6. **Edge cases & failure modes** — What happens when things go wrong?
   What are the known tricky cases?
7. **Acceptance criteria** — How will we know each piece works? What are
   the concrete, testable conditions for success?

### Interview rules

- Ask **at most 3 questions per turn**. Wait for answers.
- **Summarise what you heard** after each answer before moving on.
- If an answer is vague, probe deeper: "Can you give me a concrete example?"
- If the user says "you decide", state your assumption explicitly and ask
  them to confirm or correct it.
- When the user says something contradicts an earlier answer, flag it
  gently and ask them to resolve the conflict.
- After covering all areas, present a **structured summary** of everything
  you've learned and ask: "Does this capture it? Anything to add or change?"

### Interview exit criteria

Do NOT leave Phase 0 until:
- You have concrete acceptance criteria (not vibes)
- Scope boundaries are explicit
- The user has confirmed the summary

See [reference/interview-guide.md](reference/interview-guide.md) for
example questions and anti-patterns.

---

## Phase 1 — Specification

**Goal**: Produce `docs/<feature-slug>/SPEC.md` — the single source of truth.

Using the confirmed interview summary, write a specification document.

### Spec structure template

```markdown
# [Feature/Project Name] — Specification

## 1. Problem statement
[One paragraph. What problem, for whom, why it matters.]

## 2. Goals and non-goals
### Goals
- [Concrete, measurable goal]
### Non-goals
- [Explicitly excluded item]

## 3. User stories / use cases
- As a [role], I want to [action] so that [outcome].

## 4. Functional requirements
- FR-1: [Requirement with acceptance criterion]
- FR-2: ...

## 5. Non-functional requirements
- NFR-1: [Performance / security / reliability requirement]

## 6. Interface contracts
[Input/output shapes, API signatures, data schemas]

## 7. Edge cases and error handling
[Table of edge case → expected behaviour]

## 8. Acceptance criteria checklist
- [ ] AC-1: [Testable condition]
- [ ] AC-2: ...
```

### Spec rules

- Every requirement MUST have an ID (FR-1, NFR-1, AC-1, etc.)
- Every requirement MUST be testable — if you can't write a test for it,
  rewrite it until you can
- Present the spec to the user and get explicit sign-off before Phase 2
- The spec is a living document — update it if later phases reveal gaps

---

## Phase 2 — Architecture & Plan

**Goal**: Produce `docs/<feature-slug>/PLAN.md` — a phased implementation roadmap designed
to be consumed by `/new-task`.

See [reference/planning-guide.md](reference/planning-guide.md) for the
full planning methodology.

### Planning principles (Kent Beck style)

- **Do the simplest thing that could possibly work** first
- **YAGNI** — don't build what isn't in the spec
- Break work into **small, independently testable units**
- Each unit delivers **vertical slices** of working functionality
- Order units so that **each builds on the last** and is demo-able
- Identify **what to test first** for each unit — the test IS the design

### Plan structure template

```markdown
# [Feature/Project Name] — Implementation Plan

## Architecture overview
[Brief description of components and how they connect.
Diagram if helpful — keep it simple.]

## Implementation units

### Unit 1: [Name] — [one-sentence goal]
- **Delivers**: [What works after this unit]
- **Files**: [files to create or modify]
- **Tests first**:
  - test_[what]_[condition]_[expected] — [description]
  - ...
- **Implementation notes**: [Key decisions, patterns]
- **Traces to**: FR-1, FR-2, AC-1

### Unit 2: [Name]
...

## Dependency graph
Unit 1 → Unit 2 → Unit 3
              ↘ Unit 4

## Risk register
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ...  | ...       | ...    | ...        |
```

### Plan rules

- Every unit MUST trace back to spec requirements (FR-x, AC-x)
- Every unit MUST list its tests BEFORE its implementation notes
- Units are designed to be picked up individually by `/new-task`
- Prefer existing established, actively maintained free open source solutions to building functionality from scratch. If in doubt, ask the user to decide.
- Name the implemented patterns using industry-accepted names
- Present the plan to the user and get sign-off before Phase 3
- If the plan reveals spec gaps, go back to Phase 1 and update

---

## Phase 3 — Approval & Handoff

**Goal**: Get explicit user sign-off, then package deliverables for
downstream consumption — either as a GitHub issue or a local docs bundle.

See [reference/handoff-guide.md](reference/handoff-guide.md) for full
details on both paths.

### 3a — Final approval gate

Present the user with a concise approval summary:

```
## Final Approval Request

**Feature**: [name]
**Spec**: docs/<feature-slug>/SPEC.md — [X requirements, Y acceptance criteria]
**Plan**: docs/<feature-slug>/PLAN.md — [N implementation units]

### What will be built
- [2-3 sentence summary of planned functionality]

### What is explicitly out of scope
- [items from spec non-goals]

### Deliverables to be packaged
- SPEC.md (specification — source of truth)
- PLAN.md (implementation plan with unit breakdown)

### Next step
Run `/new-task` to pick up units from this plan and execute them.

**Do you approve this for handoff?**
If you want changes, tell me what to adjust and we'll revisit the
relevant phase.
```

**Do NOT proceed to 3b until the user explicitly approves.**

### 3b — Handoff: GitHub issue or local docs

Ask the user which handoff path they prefer. If they've already stated a
preference, use it.

#### Path A — GitHub issue (when repo is available)

**Detection**: Check if we're in a git repo with a GitHub remote:
```bash
git remote get-url origin 2>/dev/null
```

If a GitHub remote exists, offer this path. Create an issue using the
`gh` CLI:

1. Derive a slug from the feature name:
   `feature-slug` (lowercase, hyphens, no spaces, 30 characters max)
2. Compose the issue body from SPEC.md + PLAN.md
3. Create the issue with appropriate labels

```bash
# Ensure required labels exist in the repo (create if missing)
for label in "claude" "spec" "plan" "ready-for-implementation"; do
  gh label list --json name --jq '.[].name' | grep -qx "$label" \
    || gh label create "$label" --color "#0075ca" --force
done

gh issue create \
  --title "[Feature Spec] <feature-name>" \
  --body-file /tmp/issue-body.md \
  --label "claude,spec,plan,ready-for-implementation"

# Verify labels were applied
gh issue view <issue-number> --json labels --jq '.labels[].name'
```

**Issue body structure**:
```markdown
## Specification

<!-- Contents of SPEC.md -->

---

## Implementation Plan

<!-- Contents of PLAN.md -->

---

## Execution notes

- Generated by `/new-plan` and approved by [user] on [date]
- Execute units with `/new-task <issue-number>` or
  `/new-task docs/<feature-slug>/`
- Each unit lists tests first — start with the tests
- Trace every PR back to requirement IDs (FR-x, AC-x) in this issue
```

4. Report the issue URL to the user

#### Path B — Local docs directory (no GitHub or user prefers local)

If no GitHub remote is detected, or the user prefers local packaging:

1. Create a feature docs directory:
   ```
   docs/<feature-slug>/
   ├── SPEC.md
   └── PLAN.md
   ```
2. Copy the finalised documents into this directory
3. If in a git repo, stage and commit:
   ```bash
   git add docs/<feature-slug>/
   git commit -m "docs(<feature-slug>): add spec and plan"
   ```
4. Report the file paths to the user

### Handoff rules

- If using GitHub, check that `gh` CLI is authenticated before attempting
  issue creation. If it fails, fall back to Path B.
- Tag the handoff in the progress checklist:
  ```
  - [x] Phase 3: Approved by user. Handed off via [GH issue #N / docs/<feature-slug>/]
  ```

---

## Quick reference: When to go back

| Current Phase | Trigger | Go back to |
|---------------|---------|------------|
| Phase 1 | User changes requirements | Phase 0 (re-interview delta) |
| Phase 2 | Plan reveals spec gap | Phase 1 (update spec) |
| Phase 3 | User requests changes | Phase that owns the change |
| Phase 3 | `gh` CLI fails | Path B (local docs fallback) |
