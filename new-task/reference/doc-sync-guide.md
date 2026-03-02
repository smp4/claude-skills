# Doc Sync Guide — Reference

## Core principles

### Only document what exists

Never add documentation for:
- Features that are planned but not implemented
- Behaviour that is partially implemented but doesn't pass tests
- Aspirational performance characteristics that aren't measured
- Configuration options that aren't wired up yet

The test suite is the authority. If a behaviour isn't covered by a
passing test, it doesn't go in the docs.

### Match the existing voice

Before writing anything, read at least 2-3 paragraphs of the existing
documentation. Note:

- **Length**: Are descriptions terse (one line) or detailed (full paragraph)?
- **Person**: Is it "you can..." (second person) or "the system..." (third)?
- **Formality**: Casual ("just run...") or formal ("execute the following...")?
- **Structure**: Bullet lists? Numbered steps? Prose paragraphs?
- **Code examples**: Inline, fenced blocks, or separate files?

Then mirror what you find. If the README uses `##` headers and terse
bullets, don't write flowing paragraphs. If the API docs use complete
sentences with type annotations, don't write shorthand.

### Don't restructure what you didn't break

If a doc file has organisational problems that predate your work, leave
them alone. Your job is to make the docs accurate for *this change*, not
to rewrite the project's documentation.

The only exception: if your change makes an existing structural problem
actively misleading (e.g., a feature is now in the wrong section), fix
the minimum needed to avoid confusion.

## Discovery procedure

### Where to look

```bash
# Markdown docs
find . -maxdepth 3 -name "*.md" -not -path "*/node_modules/*" \
  -not -path "*/.git/*" -not -name "SPEC.md" -not -name "PLAN.md" \
  -not -name "VERIFICATION.md"

# ReStructuredText
find . -maxdepth 3 -name "*.rst" -not -path "*/node_modules/*"

# Man pages, text docs
find . -maxdepth 3 \( -name "*.txt" -o -name "*.adoc" \) \
  -not -path "*/node_modules/*"
```

### What to scan for

For each doc file found, skim for references to:

1. **Feature names / module names** that your work touched
2. **API endpoints / CLI commands** that were added or changed
3. **Configuration keys** that are new or modified
4. **File paths / directory structure** that changed
5. **Architecture descriptions** that your work affects
6. **Feature lists** where a new capability should appear
7. **Limitations / known issues** that your work resolved

### Priority order

Not all docs are equally important. Audit in this order:

1. **README.md** (root) — most-read file, highest impact
2. **API / CLI reference docs** — users depend on accuracy
3. **Architecture / design docs** — other developers depend on these
4. **Setup / configuration guides** — affects onboarding
5. **CHANGELOG** — if the project maintains one
6. **Subdirectory READMEs** — lower traffic but still important
7. **Contributing guides** — only if project structure changed

## Drift detection patterns

### Pattern: Feature list is stale

```
README says:  "Supports: auth, logging, export"
Reality:      auth, logging, export, AND the new CSV import
Action:       Add "csv-import" to the list, matching existing format
```

### Pattern: API docs missing new endpoint

```
docs/api.md documents:  GET /users, POST /users
Reality:                GET /users, POST /users, PATCH /users/:id
Action:                 Add PATCH /users/:id section following existing style
```

### Pattern: Config guide missing new option

```
docs/config.md lists:   DATABASE_URL, LOG_LEVEL, PORT
New env var:            IMPORT_BATCH_SIZE (added in Unit 3)
Action:                 Add IMPORT_BATCH_SIZE with description
```

### Pattern: Architecture diagram outdated

```
docs/architecture.md shows:  API → DB
Reality after this work:     API → Queue → Worker → DB
Action:                      Update diagram, explain why
```

### Pattern: Known issue resolved

```
docs/limitations.md says:  "CSV import not yet supported"
Reality:                    CSV import is now implemented and tested
Action:                     Remove or update the limitation entry
```

### Pattern: Example code broken

```
docs/quickstart.md shows:  client.export(data)
Reality:                    client.export(data, format="csv") — new required param
Action:                     Update example to use current signature
```

## Proposing changes

### For updates to existing files

Present the change with context:

```
**docs/api.md** (lines 120-135, "Endpoints" section)
- What's there now: GET /users, POST /users
- What's missing: PATCH /users/:id (implemented in Unit 3, tested)
- Proposed: Add endpoint section following existing format
- Why: Without this, users won't know the endpoint exists

I'll apply this unless you object.
```

Updates to existing files are applied by default — they fix inaccuracies.

### For new files

Always ask explicitly:

```
I'd like to create a new file:

**docs/adr/0003-queue-based-import.md**
- Purpose: Record why we chose a queue-based architecture for CSV import
  instead of synchronous processing
- Why: This was a significant design decision (noted in PLAN.md risk
  register) that future developers will want to understand
- Content: ~30 lines following existing ADR format

May I create this file?
```

Never create new doc files without permission.

## ADR format

If the project already has ADRs, follow their existing format. If not,
use this minimal template:

```markdown
# [Number]. [Decision Title]

**Date**: [date]
**Status**: Accepted

## Context

[What is the situation that requires a decision? 2-3 sentences.]

## Decision

[What was decided? Be specific.]

## Consequences

### Positive
- [benefit]

### Negative
- [tradeoff]

### Neutral
- [something that changed but isn't clearly good or bad]
```

### When to propose an ADR

Only propose an ADR when the implementation involved a decision that:
- Had multiple viable alternatives
- Has consequences that aren't obvious from the code
- Future developers are likely to question ("why didn't they just...")
- Was flagged in the PLAN.md risk register

Don't propose ADRs for:
- Standard patterns (using MVC, REST, etc.)
- Obvious technology choices (using the project's existing stack)
- Implementation details (which algorithm, which data structure)

## CHANGELOG maintenance

If the project maintains a CHANGELOG (CHANGELOG.md, HISTORY.md, etc.):

1. Read the existing format or find the used tooling/ guide — every project does this differently
2. Add an entry under the "Unreleased" section (or equivalent)
3. Categorise appropriately (Added, Changed, Fixed, etc.)
4. Keep it brief — one line per notable change, from the user's perspective
5. Don't add internal refactoring or test changes to the CHANGELOG

Example (if using Keep a Changelog format):
```markdown
## [Unreleased]

### Added
- CSV import via `POST /import` endpoint with batch processing
```

## Post-merge cleanup

### What to delete

After the feature is merged, the planning artefacts have served their
purpose. The code and tests are now the specification:

| Artefact                      | Delete?        | Why                                                |
| ----------------------------- | -------------- | -------------------------------------------------- |
| `docs/<slug>/SPEC.md`         | Yes            | Requirements are expressed as tests now            |
| `docs/<slug>/PLAN.md`         | Yes            | The git log shows what was built and in what order |
| `docs/<slug>/VERIFICATION.md` | Yes            | The CI pipeline is the ongoing verification        |
| `docs/<slug>/` (dir)          | Yes (if empty) | No longer needed                                   |

These are still in git history and/or the GH issue — they're archived,
not lost.

### What to keep

| Artefact          | Keep? | Why                                        |
| ----------------- | ----- | ------------------------------------------ |
| ADRs              | Yes   | They explain *why*, which the code doesn't |
| Updated README    | Yes   | Living documentation                       |
| Updated API docs  | Yes   | Living documentation                       |
| CHANGELOG entries | Yes   | Release history                            |
