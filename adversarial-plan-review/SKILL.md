---
name: adversarial-plan-review
description: >
  Run a structured adversarial review of a PLAN.md or SPEC.md using multiple practitioner
  personas in parallel subagents. Use when the user wants to stress-test a plan before
  committing to it, asks for a "red team review", "adversarial review", or "multi-persona
  review", or wants specialist perspectives (evolvability, reversibility, testability,
  operability) reviewed independently. Produces a structured findings report and a synthesis
  prompt for human decision-making.
---

# /adversarial-plan-review — Multi-Persona Plan Stress-Test

## What This Is

A structured multi-persona review of a plan or spec. Several reviewer personas examine
the plan independently in parallel subagents, each checking a specific dimension. Their
findings are collected and presented for human synthesis.

**This workflow does not produce a decision.** It produces *what the human needs to
decide* — surfacing tradeoffs, conflicts, and risks that a single-perspective review
would miss.

## When to Use

- After `/new-plan` produces a draft plan, before committing to implementation
- When a spec covers significant architectural decisions
- When a plan involves effectively-irreversible decisions (per Kua's classification)
- When the human wants explicit challenge of their own assumptions

## Usage

```
/adversarial-plan-review dev-docs/my-feature/PLAN.md
/adversarial-plan-review dev-docs/my-feature/
/adversarial-plan-review #42
```

The `$ARGUMENTS` value is parsed as:
- Path to a PLAN.md or SPEC.md → review that file
- Path to a directory → review PLAN.md and SPEC.md found within
- `#N` → fetch the plan from the linked GitHub issue docs

## Architecture: Why Subagents

Reviews run in parallel subagents for three reasons:

1. **Independence**: Each reviewer must not see other reviewers' findings before
   completing their own. Shared context produces anchoring and false consensus.
2. **Parallelism**: Reviews run concurrently, not serially.
3. **Separation of concerns**: Each reviewer is genuinely focused on one dimension.

Each subagent receives only the plan text and its reviewer instructions — nothing else.
See `references/subagent-setup.md` for the Claude Code implementation.

## Standard Reviewer Panel

For most plans:

| Reviewer | Persona | Dimension |
|---------|---------|-----------|
| A | Ford + Parsons | Evolvability, fitness functions, implicit bets |
| B | Kua | Decision reversibility, ADR quality, deferral attractors |
| C | Farley | Releasability, pipeline assumptions, deployment coupling |
| D | Feathers | Testability, seam quality, legacy entanglement risk |

For architecture-heavy plans, add:
| E | Nygard | Operability, stability patterns, failure modes |

For greenfield / DDD-heavy plans, add:
| F | Fowler | Domain boundary appropriateness, pattern fit |

## Workflow

### Step 1: Pre-flight

Before spawning reviewers, confirm:
- [ ] Plan/spec file is identified and readable
- [ ] Reviewer panel is agreed (default above, or customised)
- [ ] Human understands they will synthesise findings — no automated verdict

Tell the user: "Running 4 parallel reviews. This will take 60–120 seconds."

### Step 2: Spawn reviewers in parallel

Spawn four (or more) parallel subagents simultaneously. Each receives only the plan
text and its reviewer instructions. See `references/subagent-setup.md`.

### Step 3: Collect findings

Gather each reviewer's output. Do not edit or filter findings.

### Step 4: Present synthesis document

```markdown
# Plan Review: [Plan name] — [Date]

## Reviewer Panel
[List of reviewers and their dimensions]

## Findings by Reviewer

### Reviewer A — Ford/Parsons: Evolvability
[Full output from subagent A]

### Reviewer B — Kua: Decision Reversibility
[Full output from subagent B]

### Reviewer C — Farley: Releasability
[Full output from subagent C]

### Reviewer D — Feathers: Testability/Seams
[Full output from subagent D]

## Cross-Cutting Patterns
[Things flagged by 2+ reviewers — these are highest priority]

## Synthesis Prompt
The following questions need human decisions before this plan can proceed:

1. [Question derived from findings — specific, actionable]
2. [Question]
3. [Question]

No automated verdict is produced. The above questions are what the review has
determined require your judgment.
```

### Step 5: Human decides

Present the synthesis document. Do not proceed with implementation until the
human has addressed the synthesis prompt questions.

---

## Reference Files

- `references/subagent-setup.md` — Subagent prompt templates and Claude Code wiring
