# 0114 — Foundation refactor: lanes, dispatch, core, surfaces

**Date:** 2026-06-13
**Status:** Accepted

## Decision

Adopt `docs/reference/contributor-conventions.md` as the authoritative
standard for layer structure, naming, and testing conventions. Apply it
across the codebase in one breaking-change migration.

## Motivation

Vocabulary drift (`zone`/`lane`, `handler`/`fetch`, `domain`/`core`) and
mixed-concern namespaces (`domain/policy/` holding runtime auth + manifest
config objects) made every change require resolving ambiguity. A single
conventions doc + one migration eliminates the drift permanently.

## Changes

See `docs/reference/contributor-conventions.md`. Key moves:
- `zone` -> `lane` everywhere (YAML + Ruby)
- `from: handler/project/command` -> `from: fetch/derive/external`
- `intake_handler_allowlist` -> `handler_permit`
- `domain/policy/` dissolved: auth -> `dispatch/auth.rb`; config objects -> `manifest/policy/`
- `domain/` -> `core/`; `cli/`+`mcp/` -> `surfaces/`
- `Dispatch::Auth` replaces Guard/GuardFactory/BaseGuards/Evaluation/predicates
- `data/` root for all entry content
- Step base classes declare STAGE/BURN/INPUT/OUTPUT; `kind` removed

## Breaking changes

All manifests must replace `zones:` with `lanes:` and `zone:` with `lane:`
in entries. Source blocks replace `from: handler` with `from: fetch`, etc.
