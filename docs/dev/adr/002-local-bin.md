# ADR-002: ~/.local/bin for PATH symlink

**Status**: Accepted
**Date**: 2026-04-05
**Traces to**: FR-4

## Decision

Symlink `afb` into `~/.local/bin/afb` during `afb install`.

## Context

`afb` needs to be accessible as a command on PATH after install. The installer runs without sudo and should have no system-wide side effects.

## Consequences

`afb install` creates `~/.local/bin/` if absent, writes the symlink, and warns if `~/.local/bin` is not on PATH (with instructions to add it). `afb uninstall` removes the symlink.

macOS users may need to add `~/.local/bin` to their PATH; the installer prints the exact command. Linux users typically already have it via default shell profile.

## Alternatives rejected

| Option | Reason rejected |
|---|---|
| `/usr/local/bin` | System-wide; requires sudo; violates "no sudo" principle |
| Shell alias in ~/.zshrc | Doesn't work in non-interactive contexts (scripts, cron, launchd) |
| PATH injection via shell rc | Invasive; requires sourcing; ordering fragile |
| User-configurable install prefix | Adds complexity; `~/.local/bin` is the right default (XDG/FHS convention) |

## Reversibility

Cheap — one symlink to remove.
