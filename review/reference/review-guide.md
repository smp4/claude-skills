# Review Guide — Reference

## Lens Proposal Heuristics

When no `--lens` flag is provided, propose lenses based on artefact type:

| Artefact type | Default proposals | Rationale |
|---|---|---|
| SPEC.md | Beck (simplicity), Farley (testability) | Specs need clear scope + verifiable criteria |
| SPEC.md with domain artefacts | + Kerr (boundary alignment) | Multi-stakeholder context needs discipline boundaries |
| PLAN.md | Beck (simple design), Farley (ATDD), architecture (fitness) | Plans need slices + verification + evolvability |
| PLAN.md with external deps | + resilience (stability patterns) | External deps need failure mode analysis |
| PLAN.md with domain artefacts | + Kerr (module/team alignment) | Module structure should match discipline boundaries |
| SPEC.md + PLAN.md | Beck (alignment), Farley (verification), architecture | Alignment + verification + architectural fitness |
| Source code (greenfield) | Beck (four rules), Metz (OO design) | New code needs communication + clean object design |
| Source code (modifying existing) | Feathers (seam safety, characterization) | Existing code needs safe change practices |
| PR diff | Beck (simple design), Feathers (legacy safety) | PRs touch existing code and add new behaviour |

### How to detect "modifying existing"

- File already exists in the repo (not newly created)
- File has git history (not just created in this branch)
- The diff shows modifications to existing functions, not just new additions

When ambiguous, propose both Beck and Feathers and let the user choose.

### Domain term drift

Domain term drift checking is **not a lens** — it runs automatically whenever
DOMAIN.md exists, regardless of which lens is selected. Mention it in the
lens proposal message:

```
Note: DOMAIN.md detected — domain term drift will be checked automatically.
```

## Critique Structure

Each lens critique follows this structure:

### 1. Findings (ordered by severity)

Each finding must include:
- **Category**: what aspect of the persona's values this relates to
- **Location**: file path, line number, or requirement ID
- **Observation**: what the persona would notice
- **Heuristic**: which specific persona heuristic applies
- **Suggestion**: concrete, actionable change

Severity ordering:
1. Violations of the persona's core values (e.g., untested code for Farley)
2. Missing elements the persona would expect (e.g., no test list for Beck)
3. Opportunities to better embody the persona's principles

### 2. Summary

2-3 sentences through the persona's voice. What's the overall assessment?
What's the single most important thing to address?

## Persona Mode Selection

Map artefact types to persona modes:

| Artefact | Beck | Farley | Feathers | Metz | Kerr |
|---|---|---|---|---|---|
| SPEC.md | Plan Review | Verification | — | — | Domain Review |
| PLAN.md | Plan Review | ATDD Planning | — | Plan Review | Plan Review |
| Source (new) | Code Review | Verification | — | Code Review | — |
| Source (existing) | Code Review | — | Code Review (Legacy) | — | — |
| Source (existing) | — | — | Modifying Existing Code | — | — |

## Concept Lens Application

Concept lenses (architecture, resilience) use checklists, not persona modes.

### architecture lens

Apply the review checklist from `architectural-fitness.md`:
- Are fitness functions defined for key architectural properties?
- Are irreversible decisions identified and given proportional analysis?
- Is dependency direction enforced (domain layer has no framework imports)?
- Are there complexity or coupling ceilings that should be automated?

### resilience lens

Apply the review checklist from `stability-patterns.md`:
- Does every external dependency have an explicit timeout?
- Is there a defined failure mode for each dependency (what breaks, what degrades)?
- Can failure in one dependency affect unrelated features (blast radius)?
- Are retry strategies bounded (backoff + cap, not infinite)?
- Is there a fallback/degradation path for each critical dependency?

## Alignment Critique (SPEC + PLAN)

When reviewing both SPEC.md and PLAN.md together, add an alignment section:

1. **Traceability**: Does every plan unit trace to spec requirements?
   List any FR-x or AC-x that no unit covers.

2. **Scope creep**: Does any plan unit deliver something not in the spec?
   Flag additions that aren't traced to requirements.

3. **Ordering**: Does the unit ordering match dependency reality?
   Flag units that depend on things not yet built.

4. **Completeness**: Do the plan's tests cover all acceptance criteria?
   List any AC-x without a corresponding "Tests first" entry.

## Output Quality Checks

Before presenting the review, verify:
- [ ] Every finding references a specific location (line, ID, file)
- [ ] Every finding has a concrete suggestion, not just "improve this"
- [ ] The critique sounds like the persona, not generic code review
- [ ] Positive aspects are acknowledged, not just problems
- [ ] The summary captures the most important insight
