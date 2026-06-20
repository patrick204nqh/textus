---
name: '0118-sources-first-class-envelope-field'
uid: fdaec41bd6942fae
---
# ADR-0118: Sources as a first-class envelope field

## Status
Accepted

## Date
2026-06-20

## Context

External source material is ingested into the `raw` lane as write-once URL
bookmarks, files, or assets. Knowledge entries frequently reference these raw
entries to declare provenance — "this doc's facts come from this ingested URL."
Currently this is expressed as ad-hoc frontmatter (`source: raw.xxx` or
`sources: [{raw: ..., url: ..., label: ...}]`), optionally validated by a
per-family schema. This has two problems:

1. **No universal recognition.** Unlike `uid`, `sources` is not a
   protocol-level field — every entry family that wants it must opt into a
   schema. This inverts the cost: adding a provenance link forces either schema
   configuration or an unvalidated convention.

2. **Raw entries have no defined shape.** The raw lane stores free-form YAML.
   The fields that every raw entry carries (`kind`, `url`, `label`,
   `content_hash`, `ingested_at`) are implicit — no format-level enforcement
   guarantees they exist or are well-typed.

## Decision

### 1. Make `sources` a first-class envelope field

The format classes (`markdown`, `json`, `yaml`) already recognize `uid` as a
special `_meta` field — they inject it, preserve it across writes, and return
it in the envelope. `sources` follows the same pattern:

- **Recognition.** Every entry's `_meta` may carry a `sources` key. The format
  classes extract it from frontmatter and include it in the envelope's
  structured output (like `uid`).
- **Validation.** Each element in the `sources` array has a closed shape:
  `raw` (required, a raw-lane key), `url` (optional), `label` (optional).
  The protocol validates that `raw:` values match the raw key grammar and
  resolve to existing raw entries.
- **No per-family schema.** Any entry in any lane can declare `sources`
  without wiring a schema. The validation lives in the format layer, not the
  manifest.

### 2. Define raw entry attributes at the format level

Raw entries (`kind: raw` lane) get a defined content shape enforced by the
format layer:

```yaml
# Every raw entry has:
source:
  kind:    url | file | asset     # required
  url:     string                 # required when kind=url
  label:   string                 # optional, human-readable
content_hash: sha256:<hex>        # required, computed from source bytes
ingested_at: ISO-8601             # required
body:     string | null           # optional, present only for kind=file
asset:    string | null           # optional, present only for kind=asset
```

The `yaml` format class validates this shape on write for entries in the raw
lane. Non-conforming raw entries are rejected.

### 3. The ingest → source → reference chain

With both changes in place, the flow is:

```
1. textus ingest url slug --url=... --label=... --as=agent
   → writes raw.YYYY.MM.DD.url-slug with validated attributes

2. textus put knowledge.how-to.some-doc --stdin --as=human
   → _meta.sources: [{raw: "raw.2026.06.20.url-slug"}]
   → format layer validates raw key exists, includes sources in envelope

3. textus get knowledge.how-to.some-doc
   → envelope returns sources array alongside uid, stale, etc.
```

No schemas, no manifest changes per family.

## Consequences

- **Removes** the need for a custom `knowledge` schema to validate `sources`.
- **Validated by default** — every entry can declare provenance, every raw
  entry has a guaranteed shape.
- **Cleaner envelope** — consumers see `sources` in the same position as `uid`,
  always present (null when absent).
- **Schema directory shrinks** — schemas remain for domain-specific fields
  (project commands, runbook descriptions), not for protocol-level metadata.
- **Cost:** format-class changes to `Markdown`, `Json`, `Yaml` (add `sources`
  extraction and raw-key validation), envelope schema update, and SPEC §7/§8
  updates. No effect on `Text` entries (no metadata channel, so `sources` is
  always null).

## Alternatives Considered

### Status quo: per-family schema
Each knowledge family declares a schema with `sources` if it wants provenance.
Rejected: inverts the cost, inconsistent across families, requires manifest
edits to add a link.

### New `sources` lane
A dedicated lane for provenance metadata, keyed to match knowledge entries.
Rejected: adds a lane, requires sync machinery, no simpler than the envelope
approach.
