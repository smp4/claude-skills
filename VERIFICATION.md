# Verification — Unit Handoff for /new-task

## Traceability matrix

| AC | Criterion | Covering location | Status |
|---|---|---|---|
| AC-1 | handoff-unit-N.md written to dev-docs/<slug>/ | SKILL.md line ~312 | ✓ |
| AC-2 | Handoff doc has all sections from format spec | SKILL.md lines ~317-350 | ✓ |
| AC-3 | Handoff doc committed to feature branch | SKILL.md lines ~354-356 | ✓ |
| AC-4 | Claude outputs stop message with next-session instructions | SKILL.md lines ~361-370 | ✓ |
| AC-5 | `--continuous` runs all units without stopping | SKILL.md lines 28, 36, 308 | ✓ |
| AC-6 | Default (no flags) stops after each unit | SKILL.md lines 130, 143 | ✓ |
| AC-7 | Next command in handoff doc is copy-pasteable and correct | SKILL.md lines ~326-328 | ✓ |
| AC-8 | Last unit produces modified handoff — proceeds to Phase 3 | SKILL.md lines 309-310 | ✓ |

## Test summary

All acceptance criteria verified by grep inspection of new-task/SKILL.md.
No regressions introduced — all pre-existing content preserved except
targeted insertions at three seams: Usage, Phase 0, Phase 2, Phase 5.

## Open items

None.
