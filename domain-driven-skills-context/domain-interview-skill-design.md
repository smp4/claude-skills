# `/domain-interview` Skill Design

## Purpose

`/domain-interview` is a Claude Code skill that runs **before** `/new-plan`.
Its job is to extract business meaning from a domain expert — not technical
requirements from a developer. It conducts a structured Three Amigos style
conversation, with Claude playing all three roles simultaneously, and produces
domain artefacts that the expert must explicitly validate before any technical
work begins.

This skill is the mechanism by which business knowledge enters the system
cleanly, with human sign-off, rather than being silently assumed by the AI.

---

## Where It Fits in the Skill System

```
/domain-interview   →   /new-plan   →   /new-task
     (new)            (refactored)     (extended)

Domain expert         Developer         Implementation
conversation          planning          execution
```

`/domain-interview` is optional. `/new-plan` can still be run without it
for purely technical features where domain elicitation is not needed.
When run, its output artefacts become the input context for `/new-plan`
Phase 0 (which is bypassed when domain artefacts exist).

---

## The Critical Caveat — and How It Is Mitigated

**The caveat**: an LLM will confidently draft domain language that quietly
encodes wrong assumptions. Plausible-sounding vocabulary can carry incorrect
business semantics. The domain expert must be the final arbiter of meaning —
this cannot be delegated to the AI.

**The mitigation**: the skill is explicitly structured so that it cannot
complete without the domain expert reviewing and approving three artefacts:

1. **The GLOSSARY** — every term the AI extracted, with its definition
2. **The concrete examples** — verbatim from the conversation, unparaphrased
3. **The draft BDD scenarios** — Given/When/Then, proposed by Claude

At the review gate, Claude must say explicitly:

> "I've drafted these based on what you told me. I may have made assumptions
> or used language that doesn't quite capture your meaning. Please correct
> anything that doesn't sound right — including terms that seem close but
> are not quite the word you'd use."

This framing matters. It positions the AI output as a draft requiring expert
correction, not a finished specification awaiting rubber-stamping.

The gate is **blocking**: the skill does not write any output files until
the domain expert has confirmed or corrected all three artefacts. If the
expert identifies errors, Claude revises and presents again. This loop
continues until explicit approval is given.

---

## The Three Roles

Claude plays all three roles. Each has a distinct lens and a distinct
mode of questioning.

### Business Analyst
- Asks about goals, actors, business rules, terminology precision
- "Who does this? What do they want to achieve?"
- "You used the word X — do you mean Y or Z?"
- "What rule governs when this is allowed?"
- Drives toward: named actors, business rules, acceptance criteria
- Flags: ambiguous terms, undefined actors, rules stated as assumptions

### Tester
- Asks for concrete examples, insists on specifics
- "Can you show me a real case of that?"
- "What does the screen/response/output look like exactly?"
- "What happens if the customer doesn't have an account yet?"
- "What's the unhappy path?"
- Drives toward: Given/When/Then scenarios, edge cases, boundary conditions
- Flags: vague success criteria, missing negative scenarios

### Developer
- Asks about state, boundaries, dependencies, failure modes
- "What state needs to exist before this can happen?"
- "What does the system need to know at this point?"
- "What happens if the external service is unavailable?"
- "Is this the same 'order' as in the fulfilment context, or a different concept?"
- Drives toward: bounded context boundaries, system inputs/outputs, failure handling
- Flags: concept collisions, missing preconditions, unhandled failures

---

## Interview Structure

### Phase 0 — Orient
Establish the scope of the interview in one or two questions:
- "What is the feature or capability we're exploring today?"
- "Who is the primary person using this, and what are they trying to do?"

Do not ask more than two questions here. The goal is orientation, not depth.

### Phase 1 — Example Collection (BA + Tester voices)
Drive toward concrete examples, not abstract rules. The BA names actors and
goals; the Tester insists on specifics.

Cycle through:
1. "Walk me through the normal case — what happens step by step?"
2. "Can you give me a real example of that?" (if the answer was abstract)
3. "What needs to be true before this can start?"
4. "What does success look like exactly?"
5. "What's a case where this should NOT be allowed?"
6. "What's a case where this is tricky or edge-case-y?"

**Rule**: when the domain expert gives a concrete example, record it
verbatim. Do not paraphrase. These raw examples are the most valuable
output of the interview.

**Rule**: ask at most 2–3 questions per turn. Wait for answers. Summarise
what you heard before asking the next set.

### Phase 2 — Language Precision (BA voice)
Focus on terminology. This is where the domain DSL vocabulary comes from.

- "You've used the words X and Y — are these the same thing or different?"
- "What do you call this thing? What does your team call it?"
- "Is there a word you'd use that I haven't used yet?"
- "When you say 'process the order', what specifically happens?"

**Rule**: every noun and verb that appears in the examples should be named
explicitly and confirmed. These become the DSL method names and parameter
names.

### Phase 3 — Boundaries (Developer voice)
Establish what this feature is NOT, and where it connects to other things.

- "What is outside the scope of what we're designing today?"
- "Does this touch any other part of the system? What does it depend on?"
- "What happens when something goes wrong?"

### Phase 4 — Draft and Validate (all voices)
Claude drafts the three artefacts and presents them for review.

**Draft 1: GLOSSARY candidate**
Present extracted terms with definitions. Ask:
> "Does each of these terms mean what you mean? Are any wrong, missing, or
> slightly off?"

**Draft 2: Concrete examples (verbatim)**
Present the raw examples captured during Phase 1. Ask:
> "Did I capture your examples correctly? Are there any I missed or got wrong?"

**Draft 3: BDD scenarios**
Present Given/When/Then scenarios derived from the examples. Ask:
> "Do these scenarios correctly describe what should happen? Have I put any
> words in your mouth, or missed the point of any example?"

**Revision loop**: if the expert identifies errors in any draft, revise
and re-present that artefact. Do not proceed until all three are explicitly
approved.

**Explicit approval required**: the expert must say something equivalent to
"yes, that's right" or "approved" for each artefact. Silence or vague
acknowledgment is not approval — ask directly: "Are you happy with this, or
is there anything to change?"

---

## Output Artefacts

All written to `docs/domain/` in the project root. These files are created
only after the domain expert has approved the drafts in Phase 4.

### `docs/domain/GLOSSARY.md`

Human-readable. Terms, definitions, examples, and their mapping to DSL
counterparts (populated after `/new-plan` creates the DSL interfaces).

```markdown
# Domain Glossary

<!-- Bounded context: <context name> -->
<!-- Interview date: <date> -->
<!-- Approved by: <domain expert name/role> -->

## <Term>

**Definition**: <one sentence definition in business language>

**Example**: <concrete example from the interview, verbatim if possible>

**DSL mapping**: `dsl/interfaces.py::<ClassName>.<method_name>` (added after implementation)

**Notes**: <any ambiguities, related terms, or bounded context notes>

---
```

### `docs/domain/DOMAIN.md`

Machine-readable context for Claude Code. Records reasoning, business rules,
bounded context boundaries, unresolved questions, and decisions made during
the interview.

```markdown
# Domain Context: <Feature/Context Name>

## Actors
- <Actor>: <role and goal>

## Business Rules
- BR-01: <rule statement>
- BR-02: <rule statement>

## Bounded Context Notes
<any notes on where this context begins and ends, what it depends on,
what concepts from other contexts it touches>

## Unresolved Questions
- [ ] <question that came up but wasn't answered>

## Key Examples (verbatim)
<paste raw examples from the interview — do NOT paraphrase>

## Interview Date and Participants
```

### `features/*.feature` (or `acceptance_tests/test_*.py`)

Draft BDD scenarios. These are proposals — they will be reviewed and
potentially revised during `/new-plan`. They are NOT final specifications
until `/new-plan` approves them as acceptance criteria.

Mark them clearly as drafts:

```gherkin
# STATUS: DRAFT — approved by domain expert, pending technical review
# Source: /domain-interview session <date>

Feature: <feature name from GLOSSARY>

  Scenario: <scenario name>
    Given ...
    When ...
    Then ...
```

---

## Interaction Rules

- **One topic at a time**: don't mix example collection with language
  precision. Complete Phase 1 before moving to Phase 2.
- **No technical language with non-technical experts**: don't say "API",
  "endpoint", "database", "object". Say "the system", "the record",
  "what the user sees".
- **Probe vagueness immediately**: if the expert says "it validates the
  order", ask "what does validation mean exactly? What would make it fail?"
- **Name the role you're speaking from** (optional, for transparency):
  "Putting on my tester hat — what's a case where this shouldn't work?"
- **Record contradictions**: if the expert says something that contradicts
  an earlier answer, flag it gently: "Earlier you said X, but now you're
  saying Y — can you help me understand which is right, or are these
  different cases?"

---

## Skill Frontmatter (for SKILL.md)

```yaml
name: domain-interview
description: >
  Conduct a structured Three Amigos domain interview with a domain expert or
  product stakeholder. Claude plays the BA, tester, and developer roles to
  extract business meaning, concrete examples, and domain vocabulary. Produces
  GLOSSARY.md, DOMAIN.md, and draft BDD scenarios — all subject to explicit
  domain expert sign-off before writing. Use before /new-plan when building
  features that require domain understanding. Use when the user says
  "domain interview", "let's talk to the domain expert", "capture the
  requirements", "example mapping session", or "three amigos".
allowed-tools: Read, Write
```

---

## What `/new-plan` Does Differently When Domain Artefacts Exist

When `/new-plan` detects `docs/domain/GLOSSARY.md` and `docs/domain/DOMAIN.md`:

1. **Phase 0 (discovery interview) is skipped**
2. Claude reads the domain artefacts as input context
3. Phase 1 (spec) must trace every acceptance criterion back to either:
   - A BDD scenario in `features/` (by scenario name)
   - A business rule in `DOMAIN.md` (by BR-NN id)
4. Phase 1 must use GLOSSARY terms in the spec — no silent renaming of
   domain concepts to developer vocabulary

This traceability requirement is what keeps the domain expert's validated
language flowing into the technical spec, rather than being replaced by
developer assumptions.
