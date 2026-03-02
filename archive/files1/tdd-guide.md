# TDD Guide — Shared Reference

## The red-green-refactor cycle

```
┌─────────────────────────────────────────────┐
│                                             │
│   ┌───────┐   ┌───────┐   ┌──────────┐     │
│   │  RED  │──▶│ GREEN │──▶│ REFACTOR │──┐  │
│   └───────┘   └───────┘   └──────────┘  │  │
│       ▲                                  │  │
│       └──────────────────────────────────┘  │
│                                             │
└─────────────────────────────────────────────┘
```

### RED — write a failing test

1. Choose the next behaviour from the plan's test list
2. Write the test name: `test_[unit]_[scenario]_[expected]`
3. Write the test body — it should fail because the production code
   doesn't exist yet or doesn't handle this case
4. Run the test — confirm it fails for the RIGHT reason
   (not a syntax error, not an import error — the BEHAVIOUR is missing)

**If the test passes immediately**, either:
- The behaviour already exists (skip to next test), or
- The test isn't testing what you think (fix the test)

### GREEN — make it pass

1. Write the **minimum** code to make the failing test pass
2. It's OK if the code is ugly, repetitive, or hardcoded
3. Do NOT add code for future tests — only this one
4. Run the test — confirm it passes
5. Run the full suite — confirm no regressions

**"Minimum" means minimum.** If a hardcoded return value makes the test
pass, start there. The next test will force generalisation.

### REFACTOR — clean up

1. Look for duplication — extract it
2. Look for unclear names — rename them
3. Look for long functions — split them
4. Look for unnecessary complexity — simplify it
5. Run the full suite after each change — stay green

**Refactoring rules:**
- No new behaviour during refactoring (tests don't change)
- Each refactoring step is small and reversible
- If a refactoring breaks tests, revert it and try smaller

## Test naming convention

```
test_[unit]_[scenario]_[expected_outcome]
```

Examples:
```
test_parser_empty_input_returns_empty_list
test_parser_single_valid_line_returns_one_item
test_parser_malformed_line_raises_parse_error
test_calculator_divide_by_zero_raises_value_error
test_api_create_user_duplicate_email_returns_409
```

The test name should read as a sentence that describes the contract.

## Test structure: Arrange-Act-Assert

```python
def test_parser_single_valid_line_returns_one_item():
    # Arrange — set up the preconditions
    input_text = "name,age\nAlice,30"
    parser = CsvParser()

    # Act — perform the action under test
    result = parser.parse(input_text)

    # Assert — verify the outcome
    assert len(result) == 1
    assert result[0].name == "Alice"
    assert result[0].age == 30
```

Keep each section focused. If Arrange is long, consider a test fixture.
If Act is more than one call, the interface might be too complex.

## What to test (and what not to)

### Always test
- Public interfaces (what users/callers depend on)
- Edge cases listed in the spec
- Error handling paths
- State transitions
- Boundary values

### Usually skip
- Private helper functions (tested through public interface)
- Framework boilerplate (the framework's tests cover it)
- Logging and telemetry (observe these manually)
- Third-party library internals

### Test doubles (in order of preference)

1. **No double** — use the real thing if it's fast and deterministic
2. **Stub** — return canned data for a dependency
3. **Fake** — simplified in-memory implementation (e.g., in-memory DB)
4. **Mock** — verify interaction patterns (use sparingly; couples to impl)

Prefer stubs and fakes over mocks. Mocks test HOW code works; stubs and
fakes test WHAT it does.

## Kent Beck's four rules of simple design (priority order)

1. **Passes all the tests**
2. **Reveals intention** — code reads like prose
3. **No duplication** (DRY, but only after rule 2)
4. **Fewest elements** — delete anything that doesn't serve rules 1-3

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
constants with computed values.

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

## Common TDD mistakes

### Writing too many tests at once
❌ Write 10 test shells, then implement all of them
✅ Write ONE test, make it pass, refactor, then write the next

### Testing implementation details
❌ `assert mock_db.save.called_with(user)` (brittle — breaks on refactor)
✅ `assert db.get_user(user_id) == expected_user` (tests outcome)

### Skipping the RED step
❌ Write code first, then write tests that pass
✅ Always see the test fail first — this proves the test works

### Gold-plating in GREEN
❌ "While I'm here, let me also add caching and logging"
✅ Only what makes THIS test pass. Nothing else.

### Not refactoring
❌ Test passes → move to next test (debt accumulates)
✅ Test passes → look at the code → clean up → THEN next test
