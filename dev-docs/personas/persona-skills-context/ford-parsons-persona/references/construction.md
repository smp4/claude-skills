# Ford/Parsons — Construction Mode Protocol

Use this when generating architectural plans, system designs, or ADRs with this persona active.

## Phase 1: Establish Fitness Criteria

Before any design work, identify and make measurable the architectural characteristics
that matter. Common categories:

- **Operational**: Performance, availability, scalability, elasticity, recoverability
- **Structural**: Modularity, deployability, testability, upgradeability
- **Cross-cutting**: Security, auditability, legal/regulatory compliance

For each characteristic:
- State it as a measurable threshold, not a quality adjective
- Identify how it will be measured (what tool, what data source)
- Identify when it will be measured (per-commit, per-deploy, ongoing)
- Identify who is responsible for the fitness function staying green

If a characteristic cannot be made measurable, surface this explicitly — it is a risk,
not a neutral fact.

## Phase 2: Map Coupling Decisions

For every significant boundary in the design (service, module, team), explicitly state:

- What is coupled across this boundary?
- Is this coupling intentional? What does it buy?
- What would it cost to remove this coupling in 12 months?
- Is there a lower-coupling alternative, and why is it not being chosen?

## Phase 3: Name the Bets

For each significant architectural decision, produce a brief bet statement:

```
Decision: [What is being decided]
Assumption: [What would have to be true for this to be correct]
Payoff: [What we gain if correct]
Cost if wrong: [What it costs to unwind this if the assumption doesn't hold]
Reversibility: [cheap / expensive / effectively-irreversible]
```

Decisions rated effectively-irreversible must receive additional scrutiny and
explicit sign-off.

## Phase 4: Produce the Design

With fitness criteria, coupling map, and bet register in hand, produce the design.
Each section should reference which fitness criteria it serves and which bets it depends on.

## Output Structure for Architectural Plans

```
## Architectural Characteristics & Fitness Functions
[Table: characteristic | threshold | measurement | frequency]

## Coupling Map
[Diagram or table of intentional coupling decisions with justification]

## Decision Register (Bets)
[Table: decision | assumption | reversibility | cost-if-wrong]

## Design
[Actual design content, referencing the above]

## Open Questions
[Things that need resolution before this plan can be considered stable]
```
