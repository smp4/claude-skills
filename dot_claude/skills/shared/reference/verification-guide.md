# Verification Guide — Shared Reference

## Purpose

Verification confirms that the implementation satisfies the specification
AND that documentation remains accurate. It is the final quality gate
before handoff.

## Verification checklist

```
Verification:
- [ ] Walk through every AC-x in SPEC.md — does it pass?
- [ ] Run full test suite — all green?
- [ ] Check SPEC.md is still accurate (update if not)
- [ ] Check PLAN.md reflects what was actually built
- [ ] Generate verification report
```

## Procedure

### Step 1 — Acceptance criteria sweep

Open SPEC.md. For each AC-x:

1. Identify the test(s) that cover this criterion
2. Run the specific test(s) and confirm they pass
3. If no test exists for an AC — write one now, run it
4. Record the mapping: AC-x → test name(s) → pass/fail

### Step 2 — Full test suite

Run the entire test suite, not just the tests for the current unit.
Regressions in earlier units must be caught here.

```bash
# Adapt to your project's test runner
pytest -v --tb=short
# or
npm test
# or
cargo test
```

### Step 3 — Doc accuracy check

Read SPEC.md and PLAN.md end to end. For each statement, ask:
- Is this still true given what was actually built?
- Did any requirements change during implementation?
- Are there new behaviours not captured in the spec?

Update the docs to match reality. Docs are the source of truth — they
must reflect what exists, not what was planned.

### Step 4 — Generate verification report

## Verification report template

```markdown
# Verification Report — [Feature Name]

**Date**: [date]
**Verified by**: [user / Claude]

## Spec compliance

| Requirement | Status    | Evidence          | Notes          |
|-------------|-----------|-------------------|----------------|
| FR-1        | ✅ Pass    | test_xxx          |                |
| FR-2        | ✅ Pass    | test_yyy          |                |
| AC-1        | ✅ Pass    | test_zzz          |                |
| AC-2        | ⚠️ Partial | test_aaa          | [explanation]  |
| NFR-1       | ✅ Pass    | benchmark results |                |

## Test summary

- **Total tests**: X
- **Passing**: X
- **Failing**: 0
- **Skipped**: 0
- **Coverage**: [percentage if measurable]

## Doc accuracy

| Document  | Status                          |
|-----------|---------------------------------|
| SPEC.md   | ✅ Accurate / 🔄 Updated in unit N |
| PLAN.md   | ✅ Accurate / 🔄 Updated in unit N |

## Open items

- [Anything deferred, discovered, or flagged during implementation]
- [Known limitations or future work]

## Conclusion

[Pass / Fail — with summary of any issues]
```

## Failure handling

| Situation | Action |
|-----------|--------|
| AC fails | Go back and fix the implementation for that unit |
| Test regression in earlier unit | Fix before proceeding |
| Spec is inaccurate | Update SPEC.md, note the change |
| Plan diverged significantly | Update PLAN.md, note what changed and why |
| New requirement discovered | Add to SPEC.md, create a new unit in PLAN.md |
