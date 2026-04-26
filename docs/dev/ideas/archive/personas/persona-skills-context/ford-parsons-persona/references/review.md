# Ford/Parsons — Review Mode Protocol

Use this when critiquing an existing plan, spec, or architectural proposal.

## Anti-Anchoring Rule

If the plan contains a stated rationale or hypothesis document, **do not read it first**.
Analyze the plan itself for implicit bets and assumptions, then compare against the stated
rationale. Reading the rationale first introduces confirmation bias.

## Review Dimensions

Work through these in order. Each produces a findings list.

### 1. Fitness Function Audit

For every architectural characteristic mentioned in the plan:
- Is it stated as a measurable threshold? (If not: flag)
- Is there an identified measurement mechanism? (If not: flag)
- Is there an identified owner? (If not: flag)
- Is it enforced in a pipeline or only in documentation? (If only docs: flag)

Rate each characteristic: **measurable / vague / unmeasured**.

### 2. Coupling Analysis

For each significant boundary (service, module, data store):
- What crosses this boundary?
- Is the coupling acknowledged in the plan?
- Is the justification stated?
- What would change in one side require in the other?

Flag: **unacknowledged coupling**, **unjustified coupling**, **data coupling across service
boundaries**, **shared mutable state**.

### 3. Implicit Bet Extraction

Read the plan looking for assumptions that are not labelled as assumptions. Common forms:
- "We will use X" (assumes X is the right tool and will remain appropriate)
- "The team will grow to Y" (assumes hiring goes as planned)
- "This will handle Z load" (assumes load profile is understood)
- Any statement about the future stated as fact

For each: extract the assumption, rate its reversibility, flag if it's load-bearing and
unacknowledged.

### 4. Evolution Blocker Scan

Identify things in the plan that will actively resist change in 12–24 months:
- Shared databases across team/service boundaries
- Synchronous coupling chains that can't be broken without broad coordination
- Data formats or protocols that will be hard to version
- Deployment dependencies that couple release schedules

### 5. Fitness Function Gaps (New)

Are there architectural characteristics the system obviously needs that aren't mentioned
at all? Common omissions:
- Testability / deployability (often assumed, never measured)
- Observability (often mentioned in prose, never in fitness functions)
- Security posture (often deferred entirely)

## Output Format

```markdown
## Evolutionary Architecture Review

### Fitness Function Audit
| Characteristic | Status | Issue |
|---------------|--------|-------|
| [name] | measurable / vague / unmeasured | [detail] |

### Coupling Concerns
- **[Concern]**: [Location in plan] — [Why it matters] — [Suggested approach]

### Implicit Bets Extracted
| Bet | Assumption | Reversibility | Risk Level |
|-----|-----------|---------------|------------|
| [decision] | [what must be true] | cheap/expensive/irreversible | low/med/high |

### Evolution Blockers
- [Blocker]: [Why it blocks change] — [Cost to address now vs later]

### Missing Fitness Criteria
- [Characteristic]: [Why it matters for this system] — [How it could be measured]

### Summary Verdict
[2–3 sentences: overall evolvability assessment, the highest-priority concern,
and the one thing that most needs resolution before this plan proceeds]
```
