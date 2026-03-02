# Planning Guide — Reference

## How to decompose into units

A good implementation unit is:

- **Small**: completable in one focused session
- **Testable**: has clear pass/fail criteria
- **Vertical**: delivers a thin slice of real functionality (not "write all
  models first, then all controllers")
- **Demonstrable**: after completion, you can show something working
- **Traceable**: maps directly to spec requirements

### Decomposition heuristic

1. List all acceptance criteria from the spec
2. Group related criteria into clusters
3. Order clusters by dependency (what must exist first?)
4. Each cluster becomes a unit, with its criteria as test targets
5. Split any unit that would take more than ~1 hour to implement

### Vertical slice example

❌ Horizontal (bad):
```
Unit 1: Define all data models
Unit 2: Write all validation logic
Unit 3: Build all API endpoints
Unit 4: Write all tests
```

✅ Vertical (good):
```
Unit 1: Create user → POST /users returns 201 with ID
Unit 2: Get user → GET /users/:id returns user or 404
Unit 3: Update user → PATCH /users/:id with validation
Unit 4: Delete user → DELETE /users/:id with soft-delete
```

Each vertical unit includes its model, validation, endpoint, AND tests.

## Ordering principles

1. **Foundation first**: data shapes, core types, shared utilities
2. **Happy path second**: the simplest successful flow end to end
3. **Sad paths third**: error handling, validation, edge cases
4. **Polish last**: performance, logging, documentation refinement

## Kent Beck's design heuristics

### Start with the test name
The test name is a design decision. Write the name before the body:
```
test_user_creation_with_valid_email_returns_201
```
This forces you to think about the interface (what's called), the scenario
(valid email), and the expectation (201) before writing any code.

### Fake it till you make it
First make the test pass with a hardcoded value. Then gradually replace
constants with computed values. This keeps you moving and avoids big design
jumps.

### Triangulate
If one test can pass with a hardcoded value, add a second test with
different data. Now you MUST generalise. Two concrete examples force the
real implementation.

### Obvious implementation
If the implementation is obvious (you can see the whole thing in your
head), just write it. Don't fake it. Save faking for when the path is
unclear.

### One-to-many
Get it working for one item first. Then make it work for a collection.
Don't start with the general case.

## Risk assessment

When building the risk register, consider:

| Category | Questions |
|----------|-----------|
| Technical | New technology? Complex algorithm? Uncertain performance? |
| Integration | External API? Database migration? Auth system? |
| Scope | Likely to grow? Ambiguous requirements? |
| Knowledge | Unfamiliar domain? Missing examples? |

For each risk, provide:
- **Likelihood**: Low / Medium / High
- **Impact**: Low / Medium / High
- **Mitigation**: What we'll do to reduce it (spike, prototype, fallback)
