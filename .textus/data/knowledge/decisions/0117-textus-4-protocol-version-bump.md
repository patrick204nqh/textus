# ADR 0117: Bump Protocol Version — `textus/3` → `textus/4`

**Status:** Accepted
**Date:** 2026-06-17

## Context

The `textus/3` specification accumulated significant drift from the
reference implementation. Key divergences:

- **Lanes vs zones** — the manifest key `zones:` was renamed to `lanes:`
  (ADR 0034); the spec still uses "zones" throughout.
- **Source discriminators** — `from: fetch` and `from: derive` were removed
  and replaced by `from: external` + the `Textus.workflow` DSL. The spec
  still documents the old discriminators as primary paths.
- **Hooks DSL removed** — `§5.9 Hooks` documents `Textus.hook`/`reg.on`
  which no longer exists in the implementation.
- **Template engine changed** — the spec references Mustache; the
  implementation uses ERB (ADR 0094).
- **`raw` lane and `ingest` verb added** — ADR 0116 added a fifth lane kind
  (`raw`) and a new verb (`ingest`), undocumented in the spec.
- **`from: fetch` intake source removed** — ADR 0089 made ingest system-
  pushed; `§5.4 Intake source (from: fetch)` is vestigial.
- **Stale sections** — `§14 Open questions` and `§15 Implementation
  checklist` describe decisions already resolved.

The Ruby gem already carries `version: textus/4` in its default manifests
and uses `textus/4` in test fixtures. The spec identifier is the last
artifact still labelled `textus/3`.

## Decision

Bump the spec protocol identifier from `textus/3` to `textus/4` and update
the spec content to match the current implementation:

1. Replace `textus/3` with `textus/4` in the protocol identifier, all
   manifest examples, and all `version:` fields.
2. Rename "zones" → "lanes" throughout (vocabulary, section headings, lane
   table, manifest syntax examples).
3. Add `raw` lane to the lane table (`raw → ingest → write-once intake`).
4. Replace `§5.4 Intake source (from: fetch)` with `§5.4 Raw lane and
   ingest verb`, documenting write-once semantics, the three source kinds
   (`url`/`file`/`asset`), and the `access` field.
5. Remove `§5.9 Hooks` (DSL removed — event reactions are workflows).
6. Replace Mustache template references with ERB.
7. Remove `.textus/steps/` references.
8. Replace `from: derive` and `from: fetch` with `from: external` +
   workflow DSL as the extension mechanism.
9. Remove `§14 Open questions` and `§15 Implementation checklist`.
10. Update conformance fixture descriptions to current vocabulary.

## Consequences

- Manifests declaring `version: textus/3` are rejected at load with a
  migration hint (this was already the case — the validator checked `textus/4`
  before this ADR).
- A second implementation targeting the spec will build against the current
  wire format, not the 2023-era format.
- The `SPEC.md` file (published from `knowledge.spec` via drain) reflects
  the live protocol.
