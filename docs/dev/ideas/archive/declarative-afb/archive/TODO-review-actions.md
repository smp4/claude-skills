# Review Actions — PLAN-REVIEW.md Comments

> Generated: 2026-04-27
> Source: PLAN-REVIEW.md user comments
> Targets: PLAN.md, architecture.md

Status key: [ ] todo, [x] done, [~] partial, [-] skipped

---

## A. Structural moves (do first — other edits depend on these)

- [x] A1. Move risk register, fitness functions, decision reversibility, external dependencies sections from PLAN.md → architecture.md (merge, don't duplicate)
- [x] A2. Restructure Phase 5 = sync pipeline only (no lockfile). Phase 6 = lockfile (all: read/write, staleness, lock commands, install failure handling)
- [x] A3. Move Unit 1.3 (Local Manifest Merge) from Phase 1 → Phase 5
- [x] A4. Move Unit 1.4 (Variable Expansion) from Phase 1 → Phase 2
- [x] A5. Move mergo characterization tests (Unit 4.2) to new spike between Phase 0 and Phase 1

## B. Phase 0 changes

- [x] B1. Collapse Phase 0: keep Unit 0.1 (cobra skeleton), lefthook (0.2), linting (0.3), boilerplate (0.4). Removed CI, justfile, changelog
- [x] B2. Rename/clarify Phase 0 acceptance test — now labeled "smoke test", not ATDD

## C. Acceptance test architecture

- [x] C1. Add acceptance test DSL package (`test/acceptance/harness/`) to plan. Noted domain.md reference
- [x] C2. Write ADR-027 for acceptance tests via os/exec — documented as ATDD best practice for Go CLI
- [x] C3. Phase 2 acceptance test: e2e variant (actual podman build) is now primary. `--generate-only` is CI shortcut

## D. Missing verification

- [x] D1. Add FR11 test: Unit 5.6 — `afb sync` with `TERM=dumb`, no TTY → no ANSI codes
- [x] D2. Add FR7 test: Unit 5.7 — `afb sync` with `AFB_LOG_LEVEL=debug` → valid JSON on stderr
- [x] D3. Add LNAI contract characterization test: Unit 5.5 in Phase 5
- [x] D4. Add `afb layer pull` implementation: Unit 5.3 in Phase 5

## E. Fitness functions & CI (target: architecture.md)

- [x] E1. Tier isolation enforcement: CI container job + grep for os/exec in domain
- [x] E2. Unit test speed: CI step with < 5s threshold
- [x] E3. Sync idempotency: detailed CI job structure using per-file SHA-256 (ADR-028)
- [x] E4. Domain package purity: grep-based fitness function added
- [x] E5. Build reproducibility: noted as risk, aspirational, deferred

## F. New features / fields

- [x] F1. Add `merge_arrays` field per layer. Updated data model, ADR-006, validation, compose tests
- [x] F2. Add descoping strategy — defined shippable state at each dogfood milestone

## G. Idempotency check mechanism

- [x] G1. ADR-028: per-file SHA-256 selected over tar+hash. Justified, added to architecture.md

## H. Reversibility corrections

- [x] H1. Correct cobra reversibility: Moderate → Cheap (in new Decision Reversibility table)
- [x] H2. Correct mergo reversibility: Moderate → Expensive
- [x] H3. Document container-first isolation cost (rebuild latency) — in reversibility table + caching strategy section

## I. Risk & architecture additions

- [x] I1. Add caching strategy section to architecture.md (Containerfile layer ordering, dev tips, production tips)
- [x] I2. Add build time + CLI startup time as risks (user dissatisfaction, no mitigations yet)
- [x] I3. Shared services: updated deferred decisions — no built-in convention, user specifies own
- [x] I4. Gas City: clarified as user component in risks table + future work. No AFB plan dependency
- [x] I5. Deferral triggers updated (per-file merge strategy trigger, shared services trigger)

## J. Deep analysis — version propagation problem

- [x] J1. Analyzed and solved. New §Layer Version Consistency in architecture.md. `afb push` updates afb.toml pin + lockfile. Behavior documented by ref type (mutable/pinned/tag). LLM config evolution flow documented. Plan Phase 9 Unit 9.3 updated with new tests.

## K. Phase 8 — runtime diff simplification

- [x] K1. Answered: no simpler viable alternative exists. Runtime drift detection is necessary (LLMs change own configs). Justification documented in Plan Unit 8.2 with comparison of alternatives.

---

All items complete.
