---
name: '0121-textus-native-links'
uid: ''
refines: knowledge.architecture.conventions
---

# ADR-0121: Textus-native link resolution

## Status

Accepted

## Date

2026-06-30

## Context

Templates and generated docs currently use hardcoded relative paths for
cross-document references:

```erb
For lane semantics, see [`../reference/lanes.md`](../reference/lanes.md).
```

This couples the link to the current publish path of `artifacts.reference.lanes`.
When a key's publish target changes, every template containing that path must
be updated manually. There is no way to query "what links to this artifact?"
and no way to render the same content for different output targets (local
filesystem, GitHub permalinks, CLI-only artifacts with no file path).

The textus protocol already has the information needed to resolve any artifact
or knowledge entry to its current publish path — the manifest's `publish:`
block is the authoritative mapping. The gap is that templates cannot speak in
terms of keys; they must hard-code paths.

## Decision

Introduce a **`textus:` URI scheme** for cross-references in templates and
knowledge content. A `textus:` URI identifies the *semantic target* by its
store key, independent of where it currently publishes.

### URI syntax

```
textus:KEY
textus:KEY#ANCHOR
```

Examples:
- `textus:artifacts.reference.lanes` — links to the lanes reference
- `textus:knowledge.decisions.0120-atomic-canon-composed-artifacts` — links to an ADR
- `textus:artifacts.decisions.log#accepted` — links to the decisions log, anchor `#accepted`

### Resolution

A **link resolver** module (`Textus::Links::Resolver`) resolves `textus:` URIs
at render time. Given a source key (the entry being rendered), a target URI,
and an output mode, it returns the appropriate link representation:

| Output mode | Resolution strategy |
|---|---|
| `filesystem` | Relative path from the source entry's publish path to the target's publish path. Default mode. |
| `github` | Absolute permalink: `{base_url}/blob/{sha}/{publish_path}`. Base URL and SHA from a configured `github.base_url` manifest field or `TEXTUS_GITHUB_URL` env. |
| `cli` | No file link — renders as `textus get KEY` (for protocol-accessible entries) or omitted (for entries with no non-filesystem publish target). |

If a key has no publish target (e.g., a knowledge atom with no `publish:` or
`publish_tree:`), the resolver falls back to `textus get KEY` regardless of
mode — the entry is accessible via the protocol but has no URL.

### Template integration

Templates use a `textus_link` ERB helper injected by the render engine:

```erb
For lane semantics, see <%= textus_link("artifacts.reference.lanes", "lanes reference") %>.
```

The helper renders to a Markdown link: `[lanes reference](../reference/lanes.md)`.

For knowledge content (non-template markdown written by humans), a
`textus:` URI is valid inline Markdown link syntax and renders as-is until
a publish step processes it:

```markdown
For lane semantics, see [lanes reference](textus:artifacts.reference.lanes).
```

The publish pipeline converts all `textus:` URIs in the rendered output to
their resolved form before writing to disk.

### Deps tracking

Because `textus:` URIs are explicit key references, the link resolver registers
each resolved link as a dependency edge in the SQLite index. `textus rdeps KEY`
then surfaces all entries that link to a given key — both data deps (workflow
sources) and link deps (cross-references).

This makes "what breaks if I rename this key?" answerable without a full grep.

### Single-point rename

When a key's publish path changes (e.g., `artifacts.reference.lanes` moves
from `docs/reference/lanes.md` to `docs/lanes.md`), no templates change.
The resolver recomputes all relative paths on the next `drain`. The only change
needed is the manifest's `publish:` block.

### Migration

Existing hardcoded relative paths in templates migrate to `textus_link` calls.
Existing `textus get KEY` prose references stay as-is (they are already
protocol-native). Migration is incremental — hardcoded paths and `textus_link`
calls coexist until all templates are migrated.

## Consequences

- **Positive:** Rename a key's publish path once in the manifest; all links
  update on next drain. Zero template churn.
- **Positive:** `textus rdeps KEY` returns both data and link dependents —
  full impact analysis before any restructuring.
- **Positive:** Multi-target rendering (filesystem, GitHub, CLI) from one
  template source.
- **Positive:** Broken links caught at drain time (unknown key → resolver
  error), not discovered post-publication.
- **Neutral:** Templates require `textus_link` helper knowledge. The helper is
  simple and documented; the old pattern (relative path) still works during
  migration.
- **Negative:** Render engine must be extended with the resolver and the
  `textus:` URI post-processor. This is a non-trivial change to
  `Produce::Render` and the template context.
- **Deferred:** GitHub and CLI output modes; `TEXTUS_GITHUB_URL` config.
  Phase 1 ships filesystem mode only.

### Implementation decisions (2026-07-01 architecture review)

The Phase 1 resolver + filesystem mode was partially implemented (Resolver, UriRewriter, LinkEdgeStore in `lib/textus/links/`). The architecture review deepened the implementation plan with concrete decisions:

**Storage backend:** Edge table in the existing `store.db` SQLite (`link_edges(from_key, to_key)`), not a separate file or in-memory Hash. Two columns only — keeps the seam simple. The in-memory LinkEdgeStore served Phase 1 prototyping and is replaced.

**Recording timing:** Edges recorded at both write time (publish pipeline rewrites textus:KEY URIs and inserts edges inline) and via a background sweep job (catches any missed edges — e.g. manual edits, entries written before the link table existed).

**Query API:** Two verbs share the graph:
  - `rdeps` — existing verb, backfilled from SQLite instead of in-memory. Returns both produced-entry manifest deps AND textus:KEY link backlinks in one unified response (supersedes the dual-vocabulary model).
  - `graph` — new verb returning `neighbors(key)` and `reachable(key, depth=N)` via BFS/DFS. Agent- and human-queryable for impact analysis.

**Surface scope:** Both verbs surfaced to CLI and MCP.

**No edge metadata.** Directional `(from_key, to_key)` only. Future link types (references, depends_on, implements) would be a separate schema change.

## Implementation phases

**Phase 1 — Resolver + filesystem mode**
- `Textus::Links::Resolver` — resolves `textus:KEY` to relative path
- `textus_link(key, text)` helper injected into ERB template context
- `textus:` URI post-processor in `Produce::Render`
- Migrate existing template cross-links to `textus_link`
- `rdeps` extended to include link edges

**Phase 2 — GitHub + CLI modes**
- `TEXTUS_GITHUB_URL` / `github.base_url` config
- `--link-mode=github|cli|filesystem` drain flag
- Link mode surfaced in `boot` output for agents

**Phase 3 — Content-level links**
- `textus:` URIs in human-authored knowledge markdown (not just templates)
- Publish pipeline post-processes all published files
