# Manifest Entry Simplification — "entry just entry"

**Date:** 2026-07-02
**Status:** Design — approved for implementation

## Context

After protocol textus/4 (ADR 0126) hardcoded roles and lanes in code, the manifest
entry declarations still carry fields that the system can infer from disk or that
belong in other layers (workflow, doctor). Every additional field adds complexity
to parsing, validation, schema contracts, and the mental model.

The principle: **an entry in the manifest is a registration, not a policy.** Policy
belongs in governance (naming, tracked), workflow (publish), or doctor (schema).
The system infers what it can from disk at read time.

## Design

### Entry fields (final set)

Only these fields appear in manifest entry declarations:

| Field | Required | Purpose |
|-------|----------|---------|
| `key`  | yes | entry identity (e.g. `knowledge.execution`) |
| `format` | no | override for non-markdown files (`json`, `yaml`) |
| `tracked` | no | `false` excludes from git (scratchpad default) |
| `naming` | no | naming convention for subtree or file (`sequential`, `dated`) |

### Removed from manifest declarations

| Field | Disposition |
|-------|-------------|
| `path` | **inferred** from key via `key.tr(".", "/")` |
| `kind`  | **inferred** from disk — directory → Nested, file → Leaf, absent → Leaf |
| `schema` | **removed** — moves to doctor check (key-pattern-based) |
| `ignore` | **removed entirely** — files in `data/` are meaningful, no README.md pollution |
| `publish` | **removed from manifest** — workflow is the sole publisher |
| `source` | **removed** — dead since `Produced` class deleted (ADR 0126) |

### What the parser does

1. Read `key` and `lane` from manifest raw data
2. Derive path from key: `key.split(".").join("/")`
3. Check filesystem: directory → Nested, file → Leaf, neither → Leaf
4. For Leaf: infer format from file extension on disk; fallback to declared `format` or `"markdown"`
5. For Nested: format is always `"markdown"` (directories have no format)
6. Build entry object with derived `path`, `format`, `kind` plus declared `tracked`, `naming`

### What gets removed from the codebase

- `lib/textus/manifest/entry/ignore_matcher.rb` — entire file deleted (102 lines)
- `Entry::Base#ignore` stub — `def ignore = []` removed
- `Entry::Base#ignored?` stub — `def ignored?(_rel_path) = false` removed
- `Entry::Nested#ignore` attr, `Nested#ignored?` override — removed
- `Manifest::Resolver` line 75 — `return nil if entry.ignored?(rel)` removed
- `Entry::Publish::SubtreeMirror` — ignore-related branches removed (lines 41, 59)

### What stays on Entry internals (back-compat, not declared)

These fields remain on the entry object for back-compat. They are no longer read
from the manifest raw data. They default to nil/empty.

- `schema` — present as `nil`, consumed by doctor/writer/envelope
- `naming` — present as `nil` or declared value
- `publish_targets`, `publish_to`, `publish_tree` — present as empty, consumed by publish/doctor/resolver
- `publish_mode`, `publish_via` — present, consumed by produce engine
- `source` — present as `nil`, consumed by drift detector

## File-by-file breakdown

### Production files to modify

| File | Change |
|------|--------|
| `lib/textus/manifest/entry/parser.rb` | Stop reading `path`, `schema`, `naming`, `ignore`, `publish`, `source` from raw. Infer path from key, format from disk+ext, kind from disk. Keep `tracked` passthrough. Remove `publish_targets` and `parse_source` methods. |
| `lib/textus/manifest/entry/base.rb` | Constructor: `schema: nil`, `naming: nil`, `publish_targets: []` defaults. Remove `def ignore` and `def ignored?` stubs. Keep all existing attr_readers and internal fields for back-compat. |
| `lib/textus/manifest/entry/nested.rb` | `from_raw` no longer reads `raw["ignore"]`. `initialize` still accepts `ignore: nil` for back-compat but it's never populated from manifest. Remove `attr_reader :ignore` and `def ignored?`. |
| `lib/textus/manifest/entry/ignore_matcher.rb` | **DELETE** entire file. |
| `lib/textus/manifest/entry/publish/subtree_mirror.rb` | Remove two `honor_ignore` branches (lines 41, 59). |
| `lib/textus/manifest/resolver.rb` | Remove `return nil if entry.ignored?(rel)` guard (line 75). |
| `lib/textus/init.rb` | `DEFAULT_MANIFEST`: drop `path:` from all entries, use `format:` + `tracked:` where needed. `AGENT_ENTRIES`: drop `path:`, `schema:`, `publish:`. |
| `.textus/manifest.yaml` | Drop `path:`, `schema:`, `ignore:`, `kind:`, `owner:` from all entries. Keep `format: json` on artifacts, `format: yaml` on raw, `tracked: false` where needed. |

### Test/support files to modify

| File | Change |
|------|--------|
| `spec/support/contexts/conformance_fixture.rb` | Update manifest entries to new shape (drop `path:`, `schema:`, `source:`, keep `key` only). |
| `spec/support/fixtures.rb` | Update `minimal_store`, `machine_store`, `workflow_store` manifests to new shape. Update `migrate_legacy_manifest` to strip removed fields. |
| `spec/unit/manifest/entry/parser_spec.rb` | Update expectations for format/path inference from disk. |
| `spec/conformance/manifest/schema_evolution_spec.rb` | Update inline manifests to new shape. |
| `spec/conformance/role_gates_spec.rb` | Already uses new shape in latest commit. Verify. |

### Files to delete

| File | Reason |
|------|--------|
| `spec/unit/manifest/entry/ignore_matcher_spec.rb` | Tests removed `IgnoreMatcher`. |

### Files to verify (no change expected)

- `lib/textus/manifest/entry/leaf.rb` — unchanged (passes common through)
- `lib/textus/manifest/entry/base.rb` — existing readers (`schema`, `publish_to`, etc.) stay
- `lib/textus/manifest/entry/publish/` — all modes stay (back-compat)
- `lib/textus/manifest/policy.rb` — unchanged
- `lib/textus/surface/mcp/server.rb` — unchanged
- All production code reading `entry.schema`, `entry.publish_to`, etc. — unchanged

## Testing strategy

1. Run full suite after each batch of changes
2. No new tests needed — existing tests exercise the same behaviors with simplified manifests
3. Key risk: format inference from disk extension (was previously from `path:` declaration)

## Rollback

All changes are in the manifest shape and parser. The old format (`path:`, `schema:`, etc.) is rejected by `migrate_legacy_manifest` which only converts `roles:`/`lanes:`/`entries:` to `data:`. After this change, old-format entries are simply ignored for removed fields (they pass through as extra keys in `raw` but are not read). No data loss — the filesystem state is the source of truth.
