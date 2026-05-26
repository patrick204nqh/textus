# ADR 0007 — Envelope as Data.define + Build/Publish split

**Date:** 2026-05-26
**Status:** Accepted
**Depends on:** [ADR 0006](./0006-format-strategy-extraction.md)

## Context

After Phase 3 the Manifest layer is well-decomposed. Two cleanups remained
from the original v0.12.4 review:

1. **Application::Writes::Build (116 LOC) does two things.** The top-level
   `call` method runs two unrelated loops — one materializes generator-zone
   entries via Builder::Pipeline, the other publishes nested leaves to
   `publish_each` targets. The six private helpers split cleanly along
   that line: each helper is used by exactly one branch.

2. **The envelope is a string-keyed Hash.** Every read/write call site
   does `env["_meta"]`, `env["body"]`, `env["etag"]`. Typos silently return
   nil. There's no IDE help, no type signal, no compile-time check. The
   `Envelope.build` factory uses `# rubocop:disable Metrics/ParameterLists`
   because it has 7 kwargs — a soft signal that a structured type would be
   more idiomatic.

## Decision

**Part A.** Split `Application::Writes::Build` into:

- `Build` — materialize generator-zone entries (template + projection).
  Fires `:build_completed`.
- `Publish` — copy nested-leaf files to `publish_each` targets. Fires
  `:file_published`.

The CLI verb `textus build` calls both and merges the results. Hooks
subscribed to `:build_completed` or `:file_published` see no change.
External Ruby callers using `Operations.writes.build.call(...)` see the
return shape narrow (no more `published_leaves` key — that's on the
Publish use case now). Documented as breaking in CHANGELOG.

**Part B.** Replace `Textus::Envelope` (a module with `.build` returning a
Hash) with `Textus::Envelope = Data.define(:protocol, :key, :zone, :owner,
:path, :format, :uid, :etag, :schema_ref, :meta, :body, :content,
:freshness) do ... end`. The class gains:

- `#to_h_for_wire` — returns the existing string-keyed Hash for CLI JSON
  output. The wire format is preserved byte-for-byte.
- `#stale?` / `#refreshing?` — convenience predicates over the freshness
  sub-hash.

All ~17 internal `env["..."]` sites migrate to typed access (`env.meta`,
`env.body`, `env.etag`). The CLI's `emit(envelope.to_h_for_wire)` converts
once at the boundary.

## Consequences

- Public Ruby API: `Operations.reads.get.call(...)` now returns
  `Textus::Envelope` instead of `Hash`. Embedders who consumed the Hash
  shape need to call `.to_h_for_wire` at their boundary. The Hash shape
  itself is unchanged; only the type changed.
- Public CLI API (JSON output): byte-identical. Preserved by `to_h_for_wire`.
- Internal: `env["typo"]` becomes `env.typo` which raises `NoMethodError`
  immediately. Two ~6-month-old bugs may surface; both should be welcomed.
- The `# rubocop:disable Metrics/ParameterLists` on `Envelope.build` goes
  away (the `Data.define` member list serves the same purpose more clearly).

## Out of scope

- A `--format=yaml` CLI output mode (mentioned as a "could" in past plans).
  The `to_h_for_wire` boundary would make that trivial later, but it's
  not part of v0.14.0.
- Removing the `meta` hash from `Envelope` and typing _it_. `_meta` shape
  is schema-defined per entry family — typing it would require generic
  programming or per-schema generated classes. Defer indefinitely.
