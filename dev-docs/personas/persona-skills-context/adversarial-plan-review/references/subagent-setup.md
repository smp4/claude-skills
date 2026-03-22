# Adversarial Plan Review — Subagent Setup

This file describes how to wire up the parallel reviewer subagents in Claude Code.

## Context Isolation Rule

Each subagent must receive **only** the plan text and its reviewer instructions.
It must NOT receive:
- Other reviewers' findings
- The author's stated rationale or hypothesis document
- Summaries or paraphrases of the plan (use the verbatim text)

This is not optional. Context contamination defeats the purpose of independent review.

## Subagent Prompt Template

Each subagent is spawned with a prompt of this form:

```
You are acting as [REVIEWER PERSONA] reviewing the following plan.

Your review dimension is: [DIMENSION]

Your task:
1. Read the plan carefully and completely before writing any findings
2. Apply the review protocol from your persona skill
3. Produce findings in the required output format
4. Do not soften findings — your value is honesty, not diplomacy

The plan text follows. Do not ask for clarification — work with what is provided
and flag what is missing or ambiguous as part of your findings.

---
[VERBATIM PLAN TEXT]
---

Produce your review now.
```

## Claude Code Implementation

In Claude Code, use the `Task` tool to spawn parallel subagents:

```javascript
// In a Claude Code custom command or CLAUDE.md task definition

const plan = await fs.readFile(planPath, 'utf8');

const reviewers = [
  {
    persona: 'Ford + Parsons (Evolutionary Architecture)',
    dimension: 'Evolvability, fitness functions, coupling, and implicit bets',
    skillRef: 'persona-ford-parsons review mode — use the structured output format from references/review.md'
  },
  {
    persona: 'Patrick Kua (Decision Reversibility)',
    dimension: 'Decision inventory, reversibility classification, ADR quality, deferral attractors',
    skillRef: 'persona-kua review mode — use the structured output format from the SKILL.md review section'
  },
  {
    persona: 'Dave Farley (Releasability)',
    dimension: 'Can this be delivered incrementally? Are pipeline assumptions sound? Where is deployment coupling introduced?',
    skillRef: 'persona-farley review mode'
  },
  {
    persona: 'Michael Feathers (Testability & Seams)',
    dimension: 'Is the code this plan produces testable? Where are the seams? What legacy entanglement risk exists?',
    skillRef: 'persona-feathers review mode'
  }
];

// Spawn as parallel tasks
const reviewTasks = reviewers.map(r => ({
  description: `Review as ${r.persona}`,
  prompt: buildReviewerPrompt(r, plan)
}));

// Claude Code Task tool call (parallel)
const findings = await Promise.all(
  reviewTasks.map(t => Task(t.description, t.prompt))
);
```

## CLAUDE.md Slash Command Pattern

If you prefer a slash command over programmatic invocation:

```markdown
## /adversarial-review

Run when: user invokes `/adversarial-review [plan-file]`

Steps:
1. Read the specified plan file into `$PLAN_TEXT`
2. Spawn four parallel Task subagents, one per reviewer in the standard panel
3. Each subagent receives only `$PLAN_TEXT` and its reviewer instructions
4. Collect all findings
5. Identify cross-cutting concerns (flagged by 2+ reviewers)
6. Produce synthesis document with synthesis prompt questions
7. Present to user and await direction — do not proceed to implementation
```

## Handling Missing Personas

If a persona skill hasn't been built yet, use an inline description instead:

```
You are acting as Dave Farley reviewing this plan through the lens of continuous
delivery. Farley's core concern: can this be delivered incrementally and safely?
Key questions he asks:
- Is there a deployment pipeline assumption baked into this plan?
- Can we release a working version sooner than the plan implies?
- Where does this plan introduce coupling between teams' release schedules?
- What does "done" mean in a way that is demonstrably true, not just claimed?
```

This is a stopgap. Build the full persona skills as soon as practical — inline
descriptions degrade over longer review sessions.

## Sharing Context Across the Parent + Subagents

The parent agent:
- Holds the plan text
- Orchestrates subagent spawning
- Collects raw findings without editing
- Identifies cross-cutting patterns
- Produces synthesis document

The parent does NOT:
- Pre-filter findings before presenting them
- Resolve conflicts between reviewers
- Produce a verdict

The human:
- Reads the synthesis document
- Decides which findings to act on
- Determines what plan changes are needed before proceeding

This is the human-in-the-loop gate. Do not automate past it.

## Latency Note

Four parallel subagents reviewing a substantial plan will take time. Set expectations:
- Tell the user reviews are running in parallel
- Estimated time: 60–120 seconds for a typical plan.md
- Do not stream partial results — wait for all reviewers before presenting findings
  (partial results invite premature anchoring on whichever reviewer finishes first)
