# ADR 0006 — Format-strategy extraction (Phase 2 of facade cleanup)

**Date:** 2026-05-26
**Status:** Accepted
**Depends on:** [ADR 0005](./0005-store-facade-final-removal.md)

## Context

After v0.12.4 the Operations facade was the only public use-case
entry point. But format-specific behavior was still scattered across
6 sites with `case format when "markdown"/"json"/"yaml"/"text"` branches:

- `Manifest#nested_glob` — glob pattern per format.
- `Manifest::EXT_TO_FORMAT` — constant mapping extensions to formats.
- `Manifest::Entry#validate_format_matrix!` — path-extension validation
  per format (rubocop-disabled for complexity).
- `Manifest::Entry#resolve_format!` — format inference from declared
  format + path extension.
- `Store::Writer#ensure_uid` — uid injection per format.
- `Store::Writer#enforce_name_match!` — name/basename match per format.
- `Store::Writer#serialize_for_put` — serialization per format.
- `Application::Writes::Mv#rewrite_name_for_mv!` — name rewrite per format.

This made adding a new format (or modifying an existing format's
extension set, schema validation rules, or serialization shape) a
6-file change.

## Decision

Push every format-specific branch down into the `Textus::Entry::*`
strategy classes. The contract on `Entry::Base` grows by 7 methods:

- `nested_glob` — glob pattern for nested directory enumeration.
- `inject_uid(meta, content, existing_uid)` — add uid to meta or content
  per format conventions.
- `enforce_name_match!(path, meta)` — raise if meta.name disagrees with
  basename.
- `rewrite_name(parsed, basename)` — rebuild bytes with new basename.
- `serialize_for_put(payload, path)` — full serialize-for-write pipeline.
- `validate_path_extension(path, nested)` — raise if path extension
  doesn't match format.
- `infer_from_extension(ext)` (class-level on `Entry`) — replaces the
  EXT_TO_FORMAT constant.

`Entry.for_format(fmt)` (already exists) is the entry point. The 6
caller sites collapse to single-line delegations.

## Consequences

- Adding a new format is a one-file change: write `lib/textus/entry/<new>.rb`
  inheriting `Base`, implementing the now-larger interface. Register via
  Zeitwerk's autoload + an `Entry.formats` registry.
- The 3 rubocop `disable` blocks in `Manifest::Entry#validate_format_matrix!`
  go away (the method becomes 3 lines).
- The `Manifest::EXT_TO_FORMAT` constant is removed. Callers that referenced
  it (mostly internal) use `Entry.infer_from_extension(ext)`.
- Public API expands by 7 methods on `Entry::Base`. External embedders
  who subclassed `Entry::Base` (rare) must implement them — that's why
  this ships as 0.13.0 minor bump, not a patch.
- No new compile-time strategy registration system. Zeitwerk autoloads
  the format files; `Entry.formats` returns the four concrete subclasses
  via `Base.subclasses` filtered to `Entry::*` namespace.

## Out of scope (Phases 3, 4)

- `Manifest::Entry` (260 LOC) split into parser + per-rule validators.
- `Application::Writes::Build` split into `Build` + `Publish`.
- Envelope `Data.define` replacing string-keyed hashes.
