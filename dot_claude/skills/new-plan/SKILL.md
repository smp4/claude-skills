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
- [ ] Phase 1: Specification (write dev-docs/<feature-slug>/SPEC.md)
- [ ] Phase 2: Architecture & Plan (write dev-docs/<feature-slug>/PLAN.md)
- [ ] Phase 3: Approval & Handoff (user sign-off → GH issue or dev-docs/)
```

---

## Phase 0 — Discovery Interview

**Goal**: Understand what the user actually needs before writing anything.

This is the most important phase. Do NOT skip it. Do NOT assume requirements.

### GitHub issue input (optional)

If invoked with a GitHub issue reference (`#N`):

```bash
gh issue view <N> --json title,body,comments --jq '{title, body, comments: .comments[].body}'
```

Record `$ISSUE_NUM = N`. Use the issue title and body as starting context
for the interview. If the issue has a `domain-complete` label or a comment
linking to DOMAIN.md, fetch and read that file before the interview.

If invoked without an issue reference, `$ISSUE_NUM` is empty. At handoff
(Phase 3b), **create** a new GitHub issue if the repo has a GitHub remote.

### Domain context check

Before starting the interview, check for existing domain artefacts:

Look for: `dev-docs/domain/DOMAIN.md` or `dev-docs/domain/*/DOMAIN.md`

If found: read all DOMAIN.md files and validate they contain the expected
sections from `/domain-interview`:
- [ ] `## Actors` table exists
- [ ] `## Business Rules` with numbered BR-NN entries exists
- [ ] `## Glossary` with at least one term exists
- [ ] `## Bounded Context` section exists

If any section is missing, warn the user:
```
Found DOMAIN.md but it appears incomplete — missing: [list].
This may have been written outside /domain-interview.
Continue anyway, or run /domain-interview first to fill the gaps?
```

If valid: use actors, business rules, glossary terms, and examples as
context during the interview. The interview still runs — but the answers
will be richer because you have domain context. Reference specific business
rules (BR-NN) and glossary terms when asking follow-up questions.

If not found: proceed normally. No change to interview flow.

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

**Goal**: Produce `dev-docs/<feature-slug>/SPEC.md` — the single source of truth.

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

### When domain artefacts exist

If `dev-docs/domain/DOMAIN.md` was loaded in Phase 0:

1. **USE GLOSSARY TERMS**: Every business concept in SPEC.md must use the
   exact term from the DOMAIN.md glossary. Do not rename domain concepts
   to developer vocabulary. If you want a different name, note the reason
   and ask the user to confirm.

2. **TRACEABILITY**: Every acceptance criterion must trace to:
   - A business rule in DOMAIN.md (by BR-NN id), or
   - A key example in DOMAIN.md (by quote)

   Format:
   - AC-01: <criterion text> [-> BR-03]
   - AC-02: <criterion text> [-> Example: "customer clicks archive..."]

3. **DSL INTERFACE PROPOSAL**: After writing acceptance criteria, propose
   DSL interfaces using glossary terms as method names.
   - Python: `typing.Protocol` in `acceptance_tests/dsl/interfaces.py`
   - TypeScript: interfaces in `acceptance-tests/dsl/interfaces.ts`
   - See `~/.claude/skills/shared/reference/python-atdd-guide.md` for
     Python patterns.

4. **GLOSSARY UPDATE**: For each DSL method proposed, update the glossary
   entry's DSL mapping in DOMAIN.md:
   - Change: `TODO: not yet implemented`
   - To: `acceptance_tests/dsl/interfaces.py::ClassName.method_name`

5. **SOURCE OF TRUTH RULE**: At creation time, the DSL MUST match the
   glossary — not the other way around. The domain expert approved these
   terms. Name your DSL methods to match them.

---

## Phase 2 — Architecture & Plan

**Goal**: Produce `dev-docs/<feature-slug>/PLAN.md` — a phased implementation roadmap designed
to be consumed by `/new-task`.

See [reference/planning-guide.md](reference/planning-guide.md) for the
full planning methodology.

### Planning principles

Read `~/.claude/skills/shared/reference/personas/beck.md` — section
"Mode: Plan Review". Apply those heuristics when reviewing the plan structure.

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

## Fitness functions (if architectural decisions exist)
| Property | Check | Automation |
|---|---|---|
| [what to preserve] | [how to detect drift] | [linter/test/CI gate] |

## Decision reversibility (if architectural decisions exist)
| Decision | Reversibility | Notes |
|---|---|---|
| [choice] | Reversible / Irreversible | [cost to reverse] |

## External dependencies (if any)
| Dependency | Failure mode | Stability pattern | Fallback |
|---|---|---|---|
| [service/DB/API] | [what breaks] | [timeout/circuit breaker/etc] | [degraded behaviour] |
```

### Architectural fitness and stability

After writing units, read `~/.claude/skills/shared/reference/architectural-fitness.md`.
For plans with architectural decisions: add a fitness functions table and a
decision reversibility table to PLAN.md. Skip for trivial single-unit plans.

If the plan involves external dependencies (network calls, external services,
databases), also read `~/.claude/skills/shared/reference/stability-patterns.md`.
Add an external dependencies table to PLAN.md. Skip when no external deps.

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
**Spec**: dev-docs/<feature-slug>/SPEC.md — [X requirements, Y acceptance criteria]
**Plan**: dev-docs/<feature-slug>/PLAN.md — [N implementation units]

### What will be built
- [2-3 sentence summary of planned functionality]

### What is explicitly out of scope
- [items from spec non-goals]

### Deliverables to be packaged
- SPEC.md (specification — source of truth)
- PLAN.md (implementation plan with unit breakdown)

### Handoff options
Once approved, I will:
1. Write SPEC.md + PLAN.md to `dev-docs/<feature-slug>/` **and** create a GitHub issue (if available)
2. Write SPEC.md + PLAN.md to `dev-docs/<feature-slug>/` only (no issue)

When you're ready to implement, run `/new-task` to pick up units from this plan.

**Do you approve this for handoff? Which option do you prefer (1 or 2)?**
If you want changes, tell me what to adjust and we'll revisit the
relevant phase.
```

**Do NOT proceed to 3b until the user explicitly approves.**

### 3b — Handoff: GitHub issue or local docs

Use the option the user chose in 3a. **Always write docs locally (Path B).
If the user also chose option 1, additionally create or update a GitHub issue (Path A).**

#### Path A — GitHub issue (when repo is available)

**Detection**: Check if we're in a git repo with a GitHub remote:
```bash
git remote get-url origin 2>/dev/null
```

If a GitHub remote exists and `gh` is authenticated, use Path A.
If no GitHub remote: skip Path A entirely (no issue, no error).

**Write frontmatter** into SPEC.md and PLAN.md before creating/updating the issue:

```yaml
---
issue: "#N"
slug: <feature-slug>
date: YYYY-MM-DD
---
```

If `$ISSUE_NUM` is set (invoked from an existing issue): **update** the existing
issue body (do not create a new issue). Otherwise: **create** a new issue.

Get the repo URL:
```bash
REPO_URL=$(gh repo view --json url -q .url)
```

**Issue body** — links only, no content pasted. SPEC.md and PLAN.md link to
**main** — no worktree or feature branch exists until `/new-task` runs:

```markdown
## Docs

| Document | Link |
|---|---|
| Domain Model | [DOMAIN.md]($REPO_URL/blob/main/dev-docs/domain/DOMAIN.md) |
| Specification | [SPEC.md]($REPO_URL/blob/main/dev-docs/<slug>/SPEC.md) |
| Plan | [PLAN.md]($REPO_URL/blob/main/dev-docs/<slug>/PLAN.md) |

## Execution notes

- Generated by `/new-plan`, approved [date]
- Run `/new-task #N` or `/new-task dev-docs/<slug>/` to implement
- Each unit lists tests first
- Trace every PR back to FR-x, AC-x in SPEC.md
```

Omit the Domain Model row if no `dev-docs/domain/DOMAIN.md` exists.

**Create or update**:

```bash
# Create new issue
gh issue create \
  --title "[Feature Spec] <feature-name>" \
  --body-file /tmp/issue-body.md \
  --label "claude,spec,plan,ready-for-implementation"

# OR update existing issue body
gh issue edit $ISSUE_NUM \
  --body-file /tmp/issue-body.md \
  --add-label "spec,plan,ready-for-implementation" \
  --remove-label "domain-complete"
```

Ensure required labels exist (create if missing):
```bash
gh label create spec --description "Contains a formal specification" --color "0075ca" 2>/dev/null
gh label create plan --description "Contains an implementation plan" --color "006b75" 2>/dev/null
gh label create ready-for-implementation --description "Approved for pickup" --color "0e8a16" 2>/dev/null
gh label create claude --description "Written by Claude" --color "0e8a75" 2>/dev/null
```

Report the issue URL to the user.

#### Path B — Local docs directory (no GitHub or user prefers local)

If no GitHub remote is detected, or the user prefers local packaging:

1. Create a feature docs directory:
   ```
   dev-docs/<feature-slug>/
   ├── SPEC.md
   └── PLAN.md
   ```
2. Copy the finalised documents into this directory
3. If in a git repo, stage and commit:
   ```bash
   git add dev-docs/<feature-slug>/
   git commit -m "docs(<feature-slug>): add spec and plan"
   ```
4. Report the file paths to the user

### Handoff rules

- **Always write SPEC.md and PLAN.md to `dev-docs/<feature-slug>/` (Path B is mandatory).**
- If using GitHub, check that `gh` CLI is authenticated before attempting
  issue creation. If it fails, skip the issue and inform the user.
- Tag the handoff in the progress checklist:
  ```
  - [x] Phase 3: Approved by user. Handed off via [GH issue #N / dev-docs/<feature-slug>/]
  ```
- **STOP after handoff. Do NOT begin implementation. Do NOT invoke `/new-task`.**
  Tell the user:

```
Plan complete and handed off.

Next steps (in a NEW conversation — so the reviewer hasn't seen the planning reasoning):
  /review dev-docs/<feature-slug>/       — review spec + plan before implementing (recommended)

Then, to implement:
  /new-task dev-docs/<feature-slug>/     — start implementing units from the plan
  /new-task #N                           — same, using the GitHub issue as entry point
```

Replace `<feature-slug>` and `#N` with actual values.

---

## Quick reference: When to go back

| Current Phase | Trigger | Go back to |
|---------------|---------|------------|
| Phase 1 | User changes requirements | Phase 0 (re-interview delta) |
| Phase 2 | Plan reveals spec gap | Phase 1 (update spec) |
| Phase 3 | User requests changes | Phase that owns the change |
| Phase 3 | `gh` CLI fails | Path B (local docs fallback) |
