# Architecture Rev 5 — All Fixes Complete

> Source: architecture-review.md findings + user comments
> Status: **25 of 25 items complete**
> Date: 2026-04-26

## Decisions made during interview (not in review doc)

- **text/template**: user approved Beck's suggestion to use Go stdlib `text/template` for Containerfile and compose.yaml generation
- **afb.local.toml**: shallow merge for v1 per Beck
- **Podman-only v1**: no docker adapter in v1, but keep `ContainerRuntime` port interface so docker slots in later
- **CLI**: keep `afb push` and `afb layer pull` (user disagrees with Beck here), defer only `afb shell`
- **Priority collision**: validation error, caught before proceeding
- **mergo + TOML**: research done (see mergo-toml-research.md), stick with TOML, add characterization tests for zero-value edge cases

## All items

1. ✅ schema_version = 1 added to afb.toml data model
2. ✅ .ai/ directory format defined as versioned contract with .ai-format-version marker
3. ✅ FS port deleted
4. ✅ SyncCommand port deleted
5. ✅ text/template for Containerfile + compose.yaml generation
6. ✅ Shallow merge for afb.local.toml (both mentions + data lifecycle diagram)
7. ✅ Podman-only v1, ContainerRuntime port kept, docker adapter deferred
8. ✅ Adapter table, project structure, dependency wiring updated
9. ✅ afb shell deferred with trigger
10. ✅ Acceptance criteria section added (measurable thresholds table)
11. ✅ Mid-tier validation added (hadolint, podman-compose config) + fitness functions
12. ✅ mergo characterization test plan added (incl zero-value cases)
13. ✅ Integration tests run real sync command (mock only for unit tier)
14. ✅ ADR-024: TOML as manifest format
15. ✅ ADR-025: .ai/ directory as versioned contract
16. ✅ ADR-026: text/template for container file generation
17. ✅ Deferred Decisions table with triggers (replaces Unresolved Questions)
18. ✅ ADR-006 reversibility reclassified to expensive
19. ✅ ADR-009 reversibility reclassified to expensive + alternatives documented
20. ✅ Priority collision = validation error (Manifest Validation subsection added)
21. ✅ Compose Spec Compliance subsection added (safe feature subset documented)
22. ✅ CI updated to podman-only
23. ✅ mergo zero-value caveat added to deep merge semantics + risks table
24. ✅ Technology choices table updated (podman/podman-compose v1 only)
25. ✅ ADR-015 updated to "Podman only (v1), Docker deferred (v2)"

## Additional changes made

- ADR-018 updated to reflect reduced port count (rev 2)
- User interaction flows updated (`afb shell` → `podman exec`)
- External runtime dependencies updated (podman-only)
- "Not using" list updated (removed template engine note)
- Podman-compose risk row updated
- Data lifecycle diagram updated (shallow merge)
