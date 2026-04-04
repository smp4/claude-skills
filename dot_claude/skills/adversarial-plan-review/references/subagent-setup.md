# Adversarial Plan Review — Subagent Setup

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
2. Apply the review protocol for your persona (detailed below)
3. Produce findings in the required output format
4. Do not soften findings — your value is honesty, not diplomacy

The plan text follows. Do not ask for clarification — work with what is provided
and flag what is missing or ambiguous as part of your findings.

---
[VERBATIM PLAN TEXT]
---

Produce your review now.
```

## Reviewer Configurations

### Reviewer A — Ford + Parsons (Evolvability)

```
Persona: Neal Ford + Rebecca Parsons (Evolutionary Architecture)
Dimension: Evolvability, fitness functions, coupling, and implicit bets

Review protocol: Read ../../shared/reference/personas/ford-parsons.md,
Mode: Review section. Apply all five review dimensions in order. Use the structured
output format from that file exactly.
```

### Reviewer B — Patrick Kua (Decision Reversibility)

```
Persona: Patrick Kua (Decision Reversibility & ADR Quality)
Dimension: Decision inventory, reversibility classification, ADR quality, deferral attractors

Review protocol: Read ../../shared/reference/personas/kua.md,
Mode: Review section. Work through all five steps in order. Use the structured
output format from that file exactly.
```

### Reviewer C — Dave Farley (Releasability)

```
Persona: Dave Farley (Continuous Delivery)
Dimension: Can this be delivered incrementally? Are pipeline assumptions sound?
Where is deployment coupling introduced?

Review protocol: Read ../../shared/reference/personas/farley.md,
Mode: Review section. Key questions:
- Is there a deployment pipeline assumption baked into this plan?
- Can we release a working version sooner than the plan implies?
- Where does this plan introduce coupling between teams' release schedules?
- What does "done" mean in a way that is demonstrably true, not just claimed?
```

### Reviewer D — Michael Feathers (Testability & Seams)

```
Persona: Michael Feathers (Legacy Code & Seams)
Dimension: Is the code this plan produces testable? Where are the seams?
What legacy entanglement risk exists?

Review protocol: Read ../../shared/reference/personas/feathers.md,
Mode: Review section. Key questions:
- Where are the seam points that enable testing?
- What existing code will this plan modify, and what characterization tests exist?
- What coupling does this plan introduce that will be hard to break for testing?
- Where is the plan assuming testability without specifying how?
```

## Claude Code Implementation

Use the Agent tool to spawn parallel subagents:

```
// Spawn all four reviewers simultaneously in a single message with multiple Agent calls.
// Each agent receives the full plan text + its reviewer configuration above.
// Do not spawn sequentially — parallelism is the point.

Agent: "Review as Ford/Parsons — Evolvability"
  prompt: [Reviewer A template + verbatim plan text]

Agent: "Review as Kua — Decision Reversibility"
  prompt: [Reviewer B template + verbatim plan text]

Agent: "Review as Farley — Releasability"
  prompt: [Reviewer C template + verbatim plan text]

Agent: "Review as Feathers — Testability"
  prompt: [Reviewer D template + verbatim plan text]

// Collect all four results, then produce synthesis document.
```

## Parent Agent Responsibilities

The parent agent:
- Holds the plan text
- Orchestrates subagent spawning (all at once, not serially)
- Collects raw findings without editing
- Identifies cross-cutting patterns (flagged by 2+ reviewers)
- Produces synthesis document with synthesis prompt questions

The parent does NOT:
- Pre-filter findings before presenting them
- Resolve conflicts between reviewers
- Produce a verdict

## Latency Note

Four parallel subagents reviewing a substantial plan will take 60–120 seconds.
Set expectations before spawning: tell the user reviews are running in parallel.
Do not stream partial results — wait for all reviewers before presenting findings.
Partial results invite premature anchoring on whichever reviewer finishes first.
