---
name: domain-interview
description: >
  Conduct a structured Three Amigos domain interview. Claude plays BA,
  tester, developer roles to extract business meaning, concrete examples,
  and domain vocabulary. Produces docs/domain/DOMAIN.md with glossary.
  Use before /new-plan when building features that need domain understanding.
  Use when: "domain interview", "let's capture requirements",
  "example mapping", "three amigos".
---

# /domain-interview — Extract Domain Knowledge

## Overview

This skill interviews a domain expert (not a developer) to extract
business meaning, concrete examples, and vocabulary. It produces a
single artefact — `docs/domain/DOMAIN.md` — containing business rules,
examples, and a glossary that flows into `/new-plan` and `/new-task`.

Claude plays three roles during the interview, each with a distinct lens:

- **Business Analyst** — goals, actors, business rules, terminology
- **Tester** — concrete examples, edge cases, unhappy paths
- **Developer** — state, boundaries, dependencies, failure modes

<!-- persona reference: TBD -->

## Critical caveat

An LLM will confidently draft domain language that quietly encodes wrong
assumptions. The domain expert is the final arbiter of meaning. This
skill is structured so it **cannot complete** without explicit expert
approval of all drafted artefacts.

At the review gate, say explicitly:

> "I've drafted these based on what you told me. I may have made
> assumptions or used language that doesn't quite capture your meaning.
> Please correct anything that doesn't sound right — including terms
> that seem close but are not quite the word you'd use."

---

## Workflow phases

```
Interview Progress:
- [ ] Phase 0: Orient (scope the conversation)
- [ ] Phase 1: Examples (collect concrete cases — BA + Tester voices)
- [ ] Phase 2: Language Precision (nail down terminology — BA voice)
- [ ] Phase 3: Boundaries (scope edges, dependencies — Developer voice)
- [ ] Phase 4: Draft and Validate (present DOMAIN.md, get approval)
```

---

## Phase 0 — Orient

Establish the interview scope in 1-2 questions max:

- "What is the feature or capability we're exploring today?"
- "Who is the primary person using this, and what are they trying to do?"

Do not go deeper here. The goal is orientation, not depth.

### Existing context check

Before starting the interview, scan for existing domain artefacts:

```
Look for: docs/domain/DOMAIN.md       (single-context project)
          docs/domain/*/DOMAIN.md      (multi-context project)
```

If existing DOMAIN.md files are found:
1. Read their glossary sections and note all existing terms
2. Keep this term list available throughout the interview — you will
   check new terms against it for collisions in Phase 2
3. Tell the expert: "I see existing domain context for [context names].
   I'll check for overlapping terms as we go."

If none found: proceed normally.

---

## Phase 1 — Example Collection (BA + Tester voices)

Drive toward concrete examples, not abstract rules. The BA names actors
and goals; the Tester insists on specifics.

Cycle through:
1. "Walk me through the normal case — what happens step by step?"
2. "Can you give me a real example?" (if the answer was abstract)
3. "What needs to be true before this can start?"
4. "What does success look like exactly?"
5. "What's a case where this should NOT be allowed?"
6. "What's a case where this is tricky or edge-case-y?"

### Rules

- **At most 2-3 questions per turn.** Wait for answers.
- **Summarise what you heard** before asking the next set.
- **Record examples verbatim.** Do not paraphrase. These raw examples
  are the most valuable output of the interview. Copy the expert's
  exact words.
- If the expert gives a vague answer, probe: "Can you give me a
  concrete example of that?"

See [reference/interview-guide.md](reference/interview-guide.md) for
the full question bank.

---

## Phase 2 — Language Precision (BA voice)

Focus on terminology. This is where DSL vocabulary comes from.

- "You've used the words X and Y — are these the same thing or different?"
- "What do you call this thing? What does your team call it?"
- "Is there a word you'd use that I haven't used yet?"
- "When you say 'process the order', what specifically happens?"

### Rules

- Every noun and verb from the examples must be named explicitly
  and confirmed by the expert.
- These become DSL method names and parameter names.
- If two terms seem to mean the same thing, pick one as canonical
  and note the synonym.

### Concept collision detection

Watch for the same word meaning different things at different points in
the conversation. This is the primary signal that you've crossed a
bounded context boundary.

**Same word, different meaning:**
> "You've used 'order' twice — once when the customer places it, and
> once when the warehouse picks it. Are these the same thing, or two
> different concepts that share a name?"

If they're different: these belong in separate bounded contexts. Name
them differently ("Customer Order" vs "Fulfilment Order") and note
that the interview has surfaced two contexts.

**Check against existing contexts:**
If Phase 0 found existing DOMAIN.md files, compare every new term
against existing glossary terms. If a term already exists in another
context with a different meaning, flag it:
> "The term 'Account' already exists in the [billing] context where it
> means [X]. You're using it to mean [Y] here. Are these the same
> concept, or should we use a different word for this context?"

---

## Phase 3 — Boundaries (Developer voice)

Establish what this feature is NOT, and where it connects.

- "What is outside the scope of what we're designing today?"
- "Does this touch any other part of the system?"
- "What happens when something goes wrong?"
- "Is this the same 'order' as in the other context, or different?"

---

## Phase 4 — Draft and Validate

Draft the DOMAIN.md artefact and present it for expert review.

### Step 1: Draft DOMAIN.md

Using the template below, draft the full document including the
glossary section.

### Step 2: Present for review

Present each section and ask for correction:

**Actors and business rules:**
> "Do these actors and rules capture what you described? Are any
> wrong, missing, or slightly off?"

**Key examples:**
> "Did I capture your examples correctly? Are there any I missed
> or got wrong?"

**Glossary terms:**
> "Does each of these terms mean what you mean? Are any wrong,
> missing, or using a word you wouldn't use?"

### Step 3: Revision loop

If the expert identifies errors in any section, revise and re-present.
Do not proceed until all sections are explicitly approved.

**Explicit approval required.** The expert must say something equivalent
to "yes, that's right" or "approved". Silence or vague acknowledgment
is not approval — ask directly: "Are you happy with this, or is there
anything to change?"

### Step 4: Determine output path

Choose the output path based on context:

**Single context, no existing files:**
Write to `docs/domain/DOMAIN.md`

**Multiple contexts detected during interview:**
If the interview surfaced concepts belonging to different bounded
contexts, split into separate files:
```
docs/domain/<context-a>/DOMAIN.md
docs/domain/<context-b>/DOMAIN.md
```
Ask the expert to name each context before writing.

**Existing contexts already present:**
If `docs/domain/` already contains context subdirectories, write new
context to `docs/domain/<context-name>/DOMAIN.md`. If extending an
existing context, update the existing file (add new glossary terms,
new business rules) rather than creating a new one.

### Step 5: Write the file(s)

Only after approval, write the DOMAIN.md file(s) to the determined path.

**Do NOT write any files before the expert has approved the draft.**

---

## DOMAIN.md template

```markdown
# Domain Context: <Feature or Bounded Context Name>

<!-- Source: /domain-interview YYYY-MM-DD -->
<!-- Approved by: <name/role> -->

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

> "<another example>"

## Unresolved Questions

- [ ] <question that needs an answer before implementation>

## Decisions

- **DECISION-01**: <decision made and brief rationale>

---

## Glossary

### <Term>

**Definition**: <one sentence, business language, no technical jargon>

**Example**: <concrete example, verbatim from interview if possible>

**DSL mapping**: `TODO: not yet implemented`

**Notes**: <ambiguities, related terms, bounded context notes>

---

### <Next Term>
...
```

---

## Interaction rules

- **One topic at a time**: complete Phase 1 before Phase 2.
- **No technical language with non-technical experts**: don't say
  "API", "endpoint", "database". Say "the system", "the record",
  "what the user sees".
- **Probe vagueness immediately**: if the expert says "it validates
  the order", ask "what does validation mean exactly?"
- **Record contradictions**: if the expert contradicts an earlier
  answer, flag it gently and ask them to resolve it.

---

## What happens next

After DOMAIN.md is written, tell the expert:

> "Domain context captured. When you're ready to turn this into a
> technical plan, run `/new-plan` — it will use this domain context
> as its starting point."
