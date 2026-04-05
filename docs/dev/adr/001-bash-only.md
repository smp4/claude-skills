# ADR-001: Bash + python3 only

**Status**: Accepted
**Date**: 2026-04-05
**Traces to**: NFR-1

## Decision

Implement `afb` entirely in bash, using python3 only for JSON parsing (accounts.json, settings.json, rate-status.json). No other languages, runtimes, or package managers.

## Context

`afb` must run on macOS and Linux without any installation beyond cloning the repo. Target systems already have bash and python3. The tool manages Claude Code infrastructure — it must be present when other tools are not.

## Consequences

All logic is bash. Python3 is used in inline heredocs (`python3 - <<'PYEOF' ... PYEOF`) where JSON parsing is required. Python3 calls include a 2-second timeout to protect NFR-3 (50ms dispatch).

## Alternatives rejected

| Option | Reason rejected |
|---|---|
| Pure Python CLI | Requires pip/venv, adds bootstrap complexity |
| Go / Rust | Requires compilation and distribution artefact management |
| jq | Not universally installed; adds a dependency with no clear benefit |
| Node.js | Not reliably present on all target systems |

## Reversibility

Expensive — a language change would require a full rewrite.
