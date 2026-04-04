# Architectural Fitness Functions — Concept Reference

last-updated: 2026-03-08

## Core Concept

A fitness function is an automated check that guards an architectural
property over time. Architecture degrades not from a single bad decision
but from many small ones that nobody notices. Fitness functions detect
drift before it accumulates.

## When to Apply

Ask "what properties must this system preserve?" during planning. Not
every project needs fitness functions — but every project with more than
one unit benefits from asking the question.

## Categories

| Property | Example fitness function |
|---|---|
| Dependency direction | No import from `api/` into `domain/` — verify with linter rule or test |
| Module coupling | Public API surface area stays below threshold — count exports |
| Domain boundary | Domain layer has zero framework imports — grep/lint check |
| Performance budget | Response time < Nms for critical paths — benchmark in CI |
| Complexity ceiling | No function exceeds N lines or cyclomatic complexity N — linter |
| Test coverage floor | Coverage for `domain/` never drops below N% — CI gate |
| Dependency freshness | No dependency more than N major versions behind — automated check |

## Reversibility Assessment

For each architectural decision in the plan, classify:

**Reversible** (one-way door you can reopen):
- Library/framework choice within a bounded module
- Internal data structure selection
- API response shape (before consumers exist)

**Irreversible** (or very expensive to reverse):
- Database schema deployed to production
- Public API contract with external consumers
- Choice of programming language for a core module
- Authentication/authorization architecture

**Heuristic**: spend proportional time on irreversible decisions. Reversible
decisions should be made quickly — you can fix them later. Irreversible
decisions deserve a prototype, spike, or explicit tradeoff analysis in the
plan.

## Plan Integration

When writing a PLAN.md, add after the risk register:

```markdown
## Fitness functions

| Property | Check | Automation |
|---|---|---|
| [what to preserve] | [how to detect drift] | [linter/test/CI gate] |

## Decision reversibility

| Decision | Reversibility | Notes |
|---|---|---|
| [architectural choice] | Reversible / Irreversible | [cost to reverse, if high] |
```

Skip this section for trivial plans (single unit, no architectural decisions).
Only include fitness functions the team will actually automate — aspirational
checks are noise.
