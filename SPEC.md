# textus/1 — Specification

**Status:** Draft v1.0 (2026-05-19)
**Protocol identifier:** `textus/1`
**Reference implementation:** Ruby gem `textus`

> *textus* — Latin for "the fabric a text is woven from," same root as *context* (from *con-texere*, "to weave together"). This spec defines a storage shape and wire protocol for that fabric.

---

## 1. What textus is

A storage convention and JSON wire protocol that lets humans, scripts, and AI agents read and write structured project memory **deterministically**, with addressable dotted keys, schema validation, role-based write gates, declarative compute, and copy-based publish targets.

The storage lives in a `.textus/` directory at the project root. Each entry is a Markdown file with YAML frontmatter. A manifest binds dotted keys to subtrees and declares which roles may write to each zone. Schemas (also YAML) define what frontmatter shape each entry must have. Derived entries are computed from other entries via pure projections and a vendored Mustache template engine, then optionally published to repo-relative paths as byte-for-byte file copies. The CLI surface (`textus get/put/list/where/schema/build/...` `--format=json`) returns a versioned envelope any caller can parse without knowing Markdown.

You **shape your own memory structure** inside `.textus/`. The protocol manages how it's read, written, addressed, validated, gated, computed, and published. The contents are entirely yours.

### 1.1 The five layers

textus is organized as five composable layers. Each layer has a single responsibility; later layers build on earlier ones.

| Layer | Name | Responsibility |
|---|---|---|
| L1 | **Store** | Plain-file backend: `.textus/zones/<zone>/...` with YAML frontmatter + Markdown body, addressed by dotted keys, schema-validated, etag-versioned. |
| L2 | **Sources** | Declared external inputs (`intake` zone): URLs, files, feeds with declared parsers and TTLs. textus *describes* sources; external runners fetch and pipe results through `textus put`. |
| L3 | **Compute** | Pure transforms from store entries to derived entries. Projections (select/pluck/sort/limit/format) plus a vendored Mustache template subset. No shell execution. |
| L4 | **Publish** | Byte-for-byte file copy from derived entries to repo-relative paths declared via `publish_to:`. The in-store artifact is the consumer-shaped output; the published file is an identical copy with a `.textus-managed.json` sentinel. |
| L5 | **Consumers** | Anything that reads the published files or calls the CLI — editors, LLM tools, MCP servers, CI jobs, dashboards. textus is agnostic about who consumes; the envelope is the contract. |

## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/1`) any language can speak.
- Deterministic read/write of structured Markdown via a CLI returning JSON.
- Schema-validated frontmatter using YAML schemas as data.
- Role-based write gates (humans, scripts, AI, build runners get different permissions per zone).
- Optimistic concurrency via ETags.
- Pure declarative compute: derived entries computed from projections + Mustache, no shell-out.
- Publish derived entries to well-known paths as body-only plain files.
- Plain-file backend — consumers can also read raw if they prefer.

**Non-goals**
- Not a database. No queries, indexes, joins, or full-text search.
- Not a graph store. Keys are hierarchical strings; cross-links are unindexed.
- Not a sync protocol. Single-writer per file, ETag-checked.
- Not a transport. Spawn the CLI or wrap it in MCP/HTTP downstream.
- Not a UI. Filesystem + CLI. Viewers ship elsewhere.
- Not a fetcher. textus declares sources; external runners fetch them.
- Not an executor. textus computes pure projections but never spawns shell commands.

## 3. Storage layout

The root is `.textus/` at the project working directory. A typical v1.0 tree:

```
.textus/
  manifest.yaml          # internal: key → subtree mapping + zones declarations
  audit.log              # internal, append-only NDJSON log of every successful write
  role                   # internal, role token (one line, e.g. "human")
  schemas/               # internal: YAML schema files
  templates/             # internal: Mustache templates referenced by derived entries
  parsers/               # internal: project-local parser extensions
  zones/                 # ALL user content lives here
    canon/               # zone: canon (human-only)
    working/             # zone: working (human, ai, script)
    intake/              # zone: intake (script — declared external inputs)
    pending/             # zone: pending (ai proposals awaiting accept)
    derived/             # zone: derived (build only — computed outputs)
```

Textus internals (`manifest.yaml`, `audit.log`, `role`, `schemas/`, `templates/`, `parsers/`) live directly under `.textus/`. **All user content lives under `.textus/zones/`.** Manifest `path:` fields are relative to `.textus/zones/` — they do **not** include the `zones/` prefix. Implementations MUST prepend `zones/` to every `path:` when resolving a key to a filesystem location.

Zone directories under `zones/` are conventional; their write semantics are declared in the manifest, not the directory name.

`.textus/audit.log` is an append-only NDJSON file written under a file lock by every successful `put`, `delete`, `accept`, and `build`. `.textus/role` (one line containing a role name) is optional and participates in the role-resolution order (§5).

## 4. Manifest

The manifest declares: (a) which zones exist and which roles may write to each, (b) the key-to-subtree mapping, (c) the schema applied to entries in each subtree, and (d) the owner string recorded in writes.

```yaml
# .textus/manifest.yaml
version: textus/1

zones:
  - name: canon
    writable_by: [human]
  - name: working
    writable_by: [human, ai, script]
  - name: intake
    writable_by: [script]
  - name: pending
    writable_by: [ai]
  - name: derived
    writable_by: [build]

entries:
  - key: canon.identity
    path: canon/identity.md
    zone: canon
    schema: identity

  - key: working.network.org
    path: working/network/org
    zone: working
    schema: person
    owner: textus:network
    nested: true

  - key: derived.catalogs.people
    path: derived/catalogs/people.md
    zone: derived
    schema: null
    owner: textus:build
```

**Backward compatibility.** If the manifest omits the `zones:` block, the legacy v0.1 three-zone model is synthesized:

```yaml
zones:
  - name: fixed
    writable_by: [human]
  - name: state
    writable_by: [human, ai, script]
  - name: derived
    writable_by: [build]
```

Old manifests written against textus/1 draft v0.1 therefore parse without modification, and any tooling expecting `fixed`/`state`/`derived` continues to work.

**Key grammar (enforced from v1.2):** dotted segments matching `/^[a-z0-9][a-z0-9-]*$/`. Segments are joined by `.`. A key has at most 8 segments; each segment is at most 64 characters. Segments MUST NOT contain dots, slashes, uppercase letters, or underscores. Example: `working.projects.acme.dashboard`. Enforcement points: manifest load (rejects illegal `key:` declarations and illegal nested file/directory names), `put` (rejects illegal keys before any write), `enumerate` (filters and warns on illegal filenames so existing trees still load with a clear migration message). Run-once migration: `textus migrate-keys --dry-run` then `--write` (see §audit).

**Per-entry `format:` (enforced from v1.2):** an entry MAY declare `format:` to be one of `markdown` (default), `json`, `yaml`, or `text`. The `format` controls the on-disk shape and which path extension is required:

| `format`   | Path extension              | `template:`           | `schema:` |
|------------|-----------------------------|------------------------|-----------|
| `markdown` | `.md` (or appended if absent) | required for derived | optional  |
| `json`     | `.json` required            | optional (escape hatch) | optional (top-level keys) |
| `yaml`     | `.yaml` or `.yml` required  | optional (escape hatch) | optional (top-level keys) |
| `text`     | `.txt` or no extension      | required for derived | MUST be null |

For `nested: true`, the recursive glob matches the format's extension (markdown→`**/*.md`, json→`**/*.json`, yaml→`**/*.{yaml,yml}`, text→`**/*.txt`). All files under one nested entry share one format and one schema.

**Lookup rule:** to resolve a key, find the entry with the longest `key:` prefix that matches. If that entry has `nested: true`, the remaining segments map to subdirectories under its `path`. Otherwise the key must equal an entry exactly. The resolved filesystem path is `<.textus root>/zones/<entry.path>[/<remaining>...].md` — implementations MUST prepend `zones/` to the manifest `path:` when constructing the filesystem location.

## 5. Zones and role-based write gates

Each zone declares which **roles** may write to it via `writable_by:` in the manifest. Reads are unrestricted across all zones; only writes are gated.

| Zone | `writable_by` | Use case |
|---|---|---|
| `canon` | `[human]` | Identity, voice, immutable principles — things only a human edits. |
| `working` | `[human, ai, script]` | Active project state: notes, decisions, network — what humans and agents update day-to-day. |
| `intake` | `[script]` | Declared external inputs (calendar, feeds, scraped pages). Refreshed by external runner scripts; never by humans or AI directly. |
| `pending` | `[ai]` | AI-generated proposals awaiting human review via `textus accept`. Lets agents stage changes without touching `working`. |
| `derived` | `[build]` | Computed outputs (catalogs, indexes, published context). Written only by the build runner via `textus build`. |

A write is gated by the caller's **role**, supplied via `--as=<role>`. If the role is not in the target zone's `writable_by` list, the write returns `write_forbidden`.

### 5.1 Role resolution

The effective role for any CLI invocation is resolved in this order; the first match wins:

1. `--as=<role>` flag on the command line.
2. `TEXTUS_ROLE` environment variable.
3. `.textus/role` file (one line, role name) at the project root.
4. Default: `human`.

Recognized roles in v1.0: `human`, `ai`, `script`, `build`. Unknown roles are rejected with `invalid_role`. The roles list is intentionally open-ended: a future minor revision MAY introduce additional roles without breaking the wire string.

Every successful write records the resolved role and a wall-clock timestamp in `.textus/audit.log`, so reviewers can later distinguish a human edit from an agent edit even though both live in the same file.

### 5.2 Compute layer (derived entries)

Derived entries live in the `derived` zone. They are not authored by hand; their body is produced by projecting over other entries. A derived entry's frontmatter declares a `projection` block:

```yaml
- key: derived.catalogs.people
  zone: derived
  projection:
    select: working.network.org    # prefix OR [list of prefixes]
    pluck:  [name, relationship, org]
    sort_by: name                  # optional
    limit: 1000                    # default 1000, max 1000
    format: yaml-list-in-md        # one of: list, hash, yaml-list-in-md, json, markdown-table
  template: people.mustache        # optional; if absent, format determines body
```

`select` is either a single dotted-key prefix or a list of prefixes. Every entry whose key starts with one of those prefixes is included. `pluck` names the frontmatter fields to retain in the projection result. `sort_by` is optional; when absent, entries are sorted by key. `limit` is bounded at 1000 entries (hard cap); requests above 1000 are rejected.

`format` controls the body serialization when no template is supplied. Permitted values: `list`, `hash`, `yaml-list-in-md`, `json`, `markdown-table`.

If `template` is given, it names a Mustache template under `.textus/templates/`. textus implements a deliberately restricted Mustache subset:

- `{{var}}` — variable interpolation.
- `{{#section}}...{{/section}}` — section (iteration / truthy block).
- `{{^inverted}}...{{/inverted}}` — inverted section.
- `{{!comment}}` — comment.

No partials. No lambdas. No HTML escaping (output is raw text, intended for Markdown). Template recursion depth is bounded at 8; exceeding the limit is an error.

### 5.3 Publish layer (`publish_to:`)

A derived entry MAY declare `publish_to:` in its frontmatter, listing one or more destination paths relative to the project root:

```yaml
publish_to:
  - CLAUDE.md
  - .ai/instructions.md
```

When the entry is recomputed, textus copies the in-store file byte-for-byte to each destination. The in-store artifact under `.textus/zones/derived/…` is already the consumer-shaped output (per the format strategy — see §5.x), so publish is a verbatim file copy with no parsing or stripping.

A sentinel `.textus-managed.json` is written alongside each published file recording the source path, the target's sha256, and `mode: "copy"`. The sentinel exists so out-of-band edits can be detected on the next publish — textus refuses to clobber a destination that is not either missing or marked as managed.

### 5.4 Intake (declared, refreshed via registered fetcher)

Intake entries declare an external source by naming a **fetcher** — a registered, named function that pulls data into the entry. textus itself still makes no implicit network calls: a fetcher only runs when explicitly invoked by `textus refresh KEY --as=script`. The declaration is data only:

```yaml
- key: intake.calendar.events
  zone: intake
  source:
    fetcher: ical-events
    config:
      url: "https://calendar.google.com/.../basic.ics"
    ttl: 6h
```

`fetcher` names a registered fetcher; `config` is an opaque hash handed to the fetcher; `ttl` is the staleness budget. Implementations MUST reject legacy `source.from` and `source.parse` with a clear usage error.

**Fetcher contract.** A fetcher is registered via `Textus.fetcher(:name) do |config:, store:| ... end` and MUST return one of three shapes, all normalized by the store into its internal `{frontmatter, body, content}` representation (§5.12):

- `{ frontmatter:, body: }` — markdown-friendly (current shape).
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content.
- `{ body: }` — raw bytes for `text` or for any format that prefers verbatim writes; the store re-parses and validates per `format:`.

The `store:` argument is a read-only `Textus::StoreView` (§5.11). Every fetcher call is wrapped in `Timeout.timeout(2)`; exceptions and timeouts surface as `usage` errors that abort the refresh.

**Built-in fetchers.** `json`, `csv`, `markdown-links`, `ical-events`, `rss` are always available. They expect raw bytes in `config["bytes"]` and produce structured frontmatter/body. Built-ins do not perform I/O themselves — the caller (or an outer fetcher) is responsible for supplying bytes.

**Refresh paths.** Two are supported:

1. **In-process** — `textus refresh KEY --as=script` resolves the entry's `source.fetcher`, invokes it with `(config:, store:)`, and writes the result under role `script`.
2. **External runner** — a cron job or agent harness reads `textus list --zone=intake --stale --format=json`, fetches the source out of band, and pipes bytes back through `textus put KEY --as=script --stdin`.

Both paths share the same role gate, audit-log entry, and `:refresh` event (§5.10). User-supplied fetchers live in `.textus/extensions/*.rb` and auto-load at `Store#initialize` (§5.11).

### 5.5 Pending / accept workflow

Pending entries are full proposal patches authored into the `pending` zone, typically by agents or scripts. A pending entry's frontmatter describes the patch it proposes against another zone:

```yaml
---
proposal:
  target_key: working.network.org.bob
  action: put
frontmatter:
  name: bob
  relationship: peer
  org: acme
---
Proposed body content.
```

`proposal.target_key` names the entry the patch would create or modify, and `proposal.action` is `put` or `delete`. The remaining frontmatter and body are the proposed new content.

`textus accept <pending-key>` is **human-only**: the resolved role must be `human`. It copies the patch into the target zone, records provenance (originating pending key, original role, original timestamp) in the audit log, and removes the pending entry. Agents and scripts can propose but cannot accept.

### 5.6 Audit log

Every successful write appends one line to an append-only TSV file at `.textus/audit.log`. The file is opened with `flock(LOCK_EX)` for the duration of each append so concurrent writers serialize cleanly.

Schema (tab-separated, one record per line):

```
<iso8601-utc>\t<role>\t<verb>\t<key>\t<etag-before-or-NULL>\t<etag-after-or-NULL>
```

`<iso8601-utc>` is the wall-clock timestamp in UTC with second (or finer) precision. `<role>` is the resolved role for the invocation. `<verb>` is the CLI verb (`put`, `delete`, `accept`, `compute`, `migrate-keys`, ...). `<key>` is the affected entry key. `<etag-before>` and `<etag-after>` are the entry etags before and after the write, or the literal string `NULL` when not applicable (e.g. create has no before-etag, delete has no after-etag). `migrate-keys --write` emits one line per renamed file using the new key as `<key>` and the file's pre- and post-rename etags.

### 5.7 Security bounds

textus enforces fixed bounds to keep behavior predictable under hostile or buggy input:

- **Projection result:** 1000 entries (hard cap).
- **Template recursion:** depth 8.
- **Manifest size:** 256 KB.
- **Entry size:** 1 MB.
- **Audit log:** unbounded; rotation is the user's problem.

### 5.8 Schema evolution (v1.1)

Schemas may declare per-field ownership and version history. These keys are additive: a schema may omit both `fields:` and `evolution:` and still parse as in v1.0.

**`fields:` block** — keyed by field name. Each entry is an object with at least `type`, plus optional `maintained_by` and any vendor extensions:

```yaml
fields:
  full_name: { type: string, maintained_by: human }
  embedding: { type: array,  maintained_by: ai }
  updated_at: { type: time,  maintained_by: script }
```

`maintained_by` values are free-form strings. The recognized set is `human | ai | script | build | derived`. Unrecognized values do not affect role-authority validation; they pass through unchanged.

**`evolution:` block** — top-level, declares the schema's history and migration intent:

```yaml
evolution:
  added_in: 2026-05-19
  deprecated_at: null
  migrate_from:
    OLD_FIELD: NEW_FIELD
```

`textus schema-migrate NAME` consults `evolution.migrate_from` when invoked without `--rename=OLD:NEW`, applying every declared rename across affected entries in one pass. An explicit `--rename` flag overrides the schema-declared map for that invocation.

**Backwards compat:** v1.0 schemas (no `fields:`, no `evolution:`) continue to parse and behave identically. `schema.maintained_by(field)` returns `nil` for every field; `schema.evolution` returns `{}`.

**Override rule:** the role `human` is permitted to write any `maintained_by` field, regardless of declared owner. This preserves human authority over AI/script-managed data — humans curating canon over AI-written embeddings is a feature, not a bug. All other role mismatches are reported by `validate-all` with code `role_authority`, including fields `key`, `field`, `expected`, and `last_writer`.

### 5.9 Reducers (v1.2)

Reducers are pure, named functions that shape projection rows into projection rows. Registered via the module-level DSL:

```ruby
Textus.reducer(:rank_by_recency) do |rows:, config:|
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
```

**Declaration.** A projection opts into a reducer via `projection.reducer`, with optional `projection.reducer_config`:

```yaml
projection:
  select: [working.projects]
  pluck:  [name, status, updated_at]
  reducer: rank_by_recency
  reducer_config: { tiebreak: name }
  sort_by: updated_at
  limit: 50
```

The reducer runs **between pluck and sort**. `config:` receives the manifest's `reducer_config` hash (or `{}`). Rows in, rows out.

**Purity.** A reducer MUST NOT perform I/O or mutate the store; no `store:` kwarg is passed.

**Timeout.** Each invocation is wrapped in `Timeout.timeout(Textus::Projection::REDUCER_TIMEOUT_SECONDS)` (2s). Timeouts, exceptions, and unknown names raise `usage` errors and abort the build.

**Auto-load.** Reducers register from `.textus/extensions/*.rb`, loaded at `Store#initialize` in lexical order (§5.11). The registry is per-Store; reducers do not share state across `Store` instances.

### 5.10 Events (v1.2)

Lifecycle events fire in-process. Subscribers register via `Textus.hook(:event, :name) do |**kwargs| ... end`. Hooks are fire-and-forget: return values are discarded.

**Event set and kwargs:**

| Event     | Fired by                | Kwargs                                                       |
|-----------|-------------------------|--------------------------------------------------------------|
| `:put`    | `Store#put`             | `key:, envelope:, store:`                                    |
| `:delete` | `Store#delete`          | `key:, store:`                                               |
| `:refresh`| `Refresh.call`          | `key:, envelope:, store:, change:` (`:created` or `:updated`)|
| `:build`  | `Builder#materialize`   | `key:, envelope:, store:, sources:`                          |
| `:accept` | `Proposal.accept`       | `pending_key:, target_key:, store:`                          |

`:refresh` with `change: :unchanged` does NOT fire — only `:created` and `:updated` are emitted. The `store:` kwarg is always a `Textus::StoreView` (§5.11).

**Timeout and isolation.** Each hook runs under `Timeout.timeout(2)`. Hook errors and timeouts are recorded as `event_error` rows in `.textus/audit.log` (column 7, JSON-encoded extras with `event`, `hook`, `error`) but do NOT abort the triggering operation. The store write that fired the event is already committed by the time hooks run.

**Manifest declarations.** A manifest entry MAY declare external-runner hooks under an `events:` block, keyed by event name:

```yaml
events:
  refresh:
    - { exec: scripts/reindex.sh, as: script }
  build:
    - { exec: scripts/rebuild-index.sh, as: build }
```

Textus does NOT invoke these — they surface only through `textus extensions list --kind=hook` for orchestrators (lefthook, cron, CI) to consume. Each entry has `exec` (opaque runner-resolvable string) and `as` (role to claim, defaults to `script`).

**Removed.** The v1.1 `on_stale` event is removed in 0.2. Staleness is a poll, surfaced by `textus stale`. The `on_`-prefix convention from v1.1 is gone; events are bare symbols.

### 5.11 Extension surface (v1.2)

Three DSL verbs cover all user-supplied code:

```
Textus.fetcher(:name)       do |config:, store:|   ... end   # returns {frontmatter:, body:} | {content:} | {body:}
Textus.reducer(:name)       do |rows:, config:|    ... end   # returns rows
Textus.hook(:event, :name)  do |**kwargs|          ... end   # side effects; return ignored
```

Files in `.textus/extensions/*.rb` are loaded at `Store#initialize`, in lexical order, with the registry installed as the current registry for that store. Registries are per-Store: two Store instances in the same process do not share state.

Failure modes:

| Surface  | Timeout    | Exception                                   | Bad return |
|----------|------------|---------------------------------------------|------------|
| fetcher  | aborts op  | aborts op (wrapped as `UsageError`)         | aborts op  |
| reducer  | aborts op  | aborts op                                   | aborts op  |
| hook     | logged     | logged (audit `event_error` row)            | n/a        |

Fetchers and reducers are pure transforms; return values flow into the store. Hooks are side effects; return values are discarded.

The `store:` argument is always a `Textus::StoreView` — a read-only proxy exposing `get`, `list`, `where`, `schema_envelope`, `deps`, `rdeps`, `published`, `stale`, `validate_all`. Write attempts raise `Textus::UsageError`.

### 5.12 Storage formats (v1.2)

An entry's `format:` selects a storage strategy. All strategies expose the same `parse(bytes) → {frontmatter, body, content}` and `serialize(frontmatter:, body:, content:) → bytes` contract. The store, audit, etag, and projection layers operate on the parsed shape; only (de)serialization differs.

- **markdown** — YAML frontmatter between `---` fences, free-form body. Parse: Psych `safe_load` on the front matter; body is the remainder. Serialize: emit `---\n<yaml>\n---\n<body>`. `content` is always `nil`.
- **json** — entire file is a JSON document. Parse: `JSON.parse`. Serialize: `JSON.pretty_generate(content)` + trailing newline. `frontmatter` is populated from a top-level `_meta` hash (if present, else `{}`); `body` is the raw bytes; `content` is the parsed object.
- **yaml** — entire file is a YAML mapping. Parse: `YAML.safe_load(bytes, permitted_classes: [Date, Time], aliases: false)`; anchors/aliases rejected. Serialize: `YAML.dump(content).sub(/\A---\n/, "")`. Same `_meta` / `frontmatter` / `body` / `content` rules as JSON.
- **text** — raw UTF-8 bytes. Parse: body is the file verbatim, `frontmatter` is `{}`, `content` is `nil`. Serialize: write `body` bytes (with trailing newline if missing).

**Envelope shape.** Every envelope carries `format:` (always present, defaults to `markdown` for back-compat). For `json|yaml`, the envelope additionally carries `content:` (parsed object). `body` is always the raw on-disk bytes. `frontmatter` always exists, and for `json|yaml` mirrors the `_meta` block (`{}` if absent). `text` always has `frontmatter: {}` and no `content`.

**`_meta` convention.** Derived structured entries (json, yaml) embed a `_meta` hash as the first top-level key. Builder-injected keys appear in a fixed order for etag stability:

```
generated_at, from, template, reducer
```

Keys with `nil` values are omitted. User-shaped content (or the reducer's hash) follows `_meta`. The etag (§10) is the sha256 of the on-disk bytes regardless of format; key ordering MUST therefore be deterministic, which Ruby's `Hash` and `JSON.generate` / `YAML.dump` honor via insertion order.

## 6. Schemas

Schemas live in `.textus/schemas/<name>.yaml`. A schema declares the required and optional frontmatter fields for entries that reference it.

```yaml
# .textus/schemas/person.yaml
name: person
required:
  - name
  - relationship
  - org
optional:
  - notes
  - aliases
fields:
  name:         { type: string, max: 80 }
  relationship: { type: enum, values: [peer, manager, report, external] }
  org:          { type: string }
  aliases:      { type: array, items: { type: string } }
  notes:        { type: string, max: 2000 }
```

**Supported types:** `string`, `number`, `boolean`, `enum` (with `values:`), `array` (with `items:`), `object` (with nested `fields:`).

**Validation:** strict required-field check; optional fields may be omitted; unknown fields produce a warning, not an error (forward-compat).

## 7. Entry file format

Every entry is a UTF-8 Markdown file with a YAML frontmatter block:

```markdown
---
name: jane
relationship: peer
org: acme
---
Short body in Markdown.
```

The frontmatter `name:` field, when present, must match the file's basename (without `.md`). Implementations may relax this for backward compat but the reference impl enforces it.

Entries in `zone: derived` SHOULD additionally carry the `generated:` block defined in §5.2. Implementations MUST treat unknown frontmatter fields as warnings, not errors, so build runners can extend the metadata without breaking conformance.

## 8. Envelope (the wire format)

Every successful CLI response (`--format=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/1",
  "key": "working.network.org.jane",
  "zone": "working",
  "owner": "textus:network",
  "path": "/absolute/path/to/.textus/zones/working/network/org/jane.md",
  "format": "markdown",
  "frontmatter": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body in Markdown.\n",
  "etag": "sha256:8f3c…",
  "schema_ref": "person"
}
```

**Field rules:**
- `protocol` MUST be the exact string `textus/1`.
- `key` MUST be the canonical resolved key.
- `zone` MUST be one of the zones declared in the manifest (`canon`, `working`, `intake`, `pending`, `derived` for the default v1.0 model; legacy v0.1 manifests synthesize `fixed`, `state`, `derived` per §4).
- `path` MUST be an absolute filesystem path.
- `format` MUST be one of `markdown`, `json`, `yaml`, `text` (§5.12). Absent envelopes are treated as `markdown` for back-compat.
- `body` is the raw on-disk bytes as a UTF-8 string for every format.
- `content` is present only when `format` is `json` or `yaml`; equals the parsed object. For `json|yaml`, `frontmatter` mirrors the top-level `_meta` (or `{}` if absent).
- `etag` MUST be `sha256:<hex>` of the raw file bytes, computed identically for every format.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/1",
  "ok": false,
  "code": "write_forbidden",
  "message": "zone 'canon' is not writable by role 'ai' for key 'canon.identity'",
  "details": { "key": "canon.identity", "zone": "canon", "role": "ai" }
}
```

**Error codes:**

| Code | Meaning | Default exit |
|---|---|---|
| `unknown_key` | Key does not resolve | 1 |
| `bad_frontmatter` | YAML parse failed or `name:` mismatch | 1 |
| `schema_violation` | Required field missing or wrong type | 1 |
| `write_forbidden` | Resolved role is not in the zone's `writable_by` | 1 |
| `etag_mismatch` | Concurrent write detected | 1 |
| `io_error` | Filesystem failure | 64 |
| `usage` | CLI argument error | 2 |

## 9. CLI surface

The reference binary is `textus`. Conforming implementations MAY use any binary name; the protocol is in the JSON.

All verbs accept `--format=json` and emit a canonical envelope (success or error). Write verbs require `--as=<role>`; the role must satisfy the target zone's write gate (§5).

| Verb | Reads / writes | Role required |
|---|---|---|
| `list [--prefix=K] [--zone=Z] [--stale]` | read | any |
| `where K` | read | any |
| `get K` | read | any |
| `schema K` | read | any |
| `stale [--prefix=K] [--strict]` | read | any |
| `deps K` / `rdeps K` | read | any |
| `published` | read | any |
| `validate-all` | read | any |
| `put K --stdin --as=R [--fetcher=NAME]` | write | per zone |
| `delete K --if-etag=E --as=R` | write | per zone |
| `refresh K --as=script` | write | per zone (typically `script`) |
| `build [--prefix=K] [--dry-run]` | write | `build` (default) |
| `accept K --as=human` | write | `human` |
| `init` | write | `human` |
| `schema-init NAME` / `schema-diff NAME` / `schema-migrate NAME --rename=OLD:NEW` | write | `human` |
| `migrate-keys [--dry-run\|--write]` | write (with `--write`) | `human` |
| `extensions list [--kind=fetcher\|reducer\|hook]` | read | any |

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "frontmatter": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body.\n",
  "if_etag": "sha256:8f3c…" }
```

`if_etag` is optional on `put`, required on `delete`. When provided, the write fails with `etag_mismatch` if the on-disk file's etag differs. When omitted on `put`, the write is unconditional (last-writer-wins).

**`textus stale` output shape:**

```json
[
  { "key": "derived.catalogs.skills",
    "path": "/abs/.textus/zones/derived/catalogs/skills.md",
    "generator": { "command": "rake catalog:skills",
                   "sources": ["working.projects", "working.network"] },
    "reason": "source 'working.projects' modified after generated.at" }
]
```

`textus build` consumes the stale list and executes each `generator.command` itself, writing results back through `put` under the `build` role. `--dry-run` prints the plan without executing.

`textus accept K --as=human` promotes a pending entry into its target zone: it copies the patch body into the target key, deletes the pending entry, and writes one audit line per side (§audit). Only the `human` role may invoke `accept`.

`textus init` scaffolds a fresh `.textus/` tree (manifest, zones, schemas, audit log) under the current directory with a default manifest. Customize by editing `.textus/manifest.yaml` after init.

`textus schema-init NAME` writes a stub schema. `schema-diff NAME` compares the on-disk schema against entries that claim it and prints the deltas. `schema-migrate NAME --rename=OLD:NEW` rewrites the frontmatter key `OLD` to `NEW` across every entry that uses the named schema, in a single transactional sweep that logs each touched file.

## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.

## 11. Versioning

- The wire string `textus/1` is the protocol version.
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/1`.
- Breaking changes (renamed/removed fields, zone semantics, key grammar) require a new wire string `textus/2`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently. Gem 1.x speaks `textus/1`.

## 12. Conformance fixtures

A conformant implementation MUST pass these fixtures (the reference test suite ships a YAML file listing inputs and expected envelopes):

**Fixture A — Resolve and read:**
Given a manifest with `working.network.org` → `working/network/org` (nested), schema `person`, and a file `.textus/zones/working/network/org/jane.md` with valid frontmatter, `textus get working.network.org.jane --format=json` returns the canonical envelope with `etag` matching the file's sha256.

**Fixture B — Role gate on write:**
Given a manifest entry where `key: canon.identity` lives in the `canon` zone (human-only), `textus put canon.identity --stdin --as=ai` (with any valid input) returns the error envelope with `code: "write_forbidden"` and exit code 1.

**Fixture C — Schema violation:**
Given the `person` schema and a `put` whose frontmatter omits `relationship`, the result is the error envelope with `code: "schema_violation"`, `details.missing: ["relationship"]`, and exit code 1.

**Fixture D — Staleness detection:**
Given a manifest entry `derived.catalogs.skills` with `generator.sources: [working.projects]`, and a working-zone entry under `working.projects` whose file mtime is newer than the derived entry's `generated.at` frontmatter timestamp, `textus stale --format=json` includes the derived entry with its declared `generator.command` and a `reason` field naming the stale source. Calling `textus stale` does NOT execute the command.

**Fixture E — Projection build:**
Given a manifest entry `derived.catalogs.skills` whose `projection` clause selects fields from `working.projects` entries, `textus build derived.catalogs.skills` materializes the derived entry on disk with frontmatter and body matching the projected shape, and updates `generated.at` to the build timestamp.

**Fixture F — Mustache render:**
Given a derived entry with a `template` clause referencing a `.mustache` file and inputs drawn from other keys, `textus build` produces a body whose contents match the expected rendered output byte-for-byte (after trailing-newline normalization).

**Fixture G — Copy publish:**
Given a manifest entry with `publish_to: <path>`, a successful `textus build` for that entry leaves a plain file at `<path>` whose contents are byte-identical to the in-store artifact at `.textus/zones/<...>`, accompanied by a `<path>.textus-managed.json` sentinel recording `source`, `sha256`, and `mode: "copy"`. Re-running `build` is idempotent.

**Fixture H — Audit log format:**
Every successful write verb (`put`, `delete`, `build`, `accept`, `schema-migrate`) appends exactly one line per affected key to the audit log, in the canonical format defined in §audit (timestamp, actor role, verb, key, etag-before, etag-after). No write produces zero or multiple lines per key.

**Fixture I — Pending → accept:**
Given a pending entry `pending.canon.identity.patch` proposing a change to `canon.identity`, `textus accept canon.identity --as=human` copies the patch body into `canon.identity`, deletes the pending entry, and appends two audit lines (one for the canon write, one for the pending delete) in that order.

## 13. Why not X?

- **Why not MCP?** MCP is a transport; textus is a data model. The two compose: a 50-line MCP server can wrap `textus get/put` as tools. textus exists because the *shape* of agent-readable project memory deserves a standalone spec, separate from how it's served.

- **Why doesn't textus execute generator commands itself?** textus is a dataflow oracle, not a build runner. The moment a spec includes process execution, it inherits shell-injection surface, OS-portability concerns, and signal-handling semantics — and ends up duplicating whatever build system the consumer already runs (make, rake, just, lefthook, CI). Keeping execution external means a Python or TypeScript port of `textus/1` only has to parse YAML and emit JSON; it doesn't have to spawn processes safely. Build runners stay the executor; textus stays a data tool.

- **Why not plain Markdown vaults (Obsidian / Foam)?** No schema enforcement, no write-gating, no addressable wire format. Fine for human notes; underspecified for agents that must act on the contents deterministically.

- **Why not Notion / Coda?** Closed, hosted, lossy export. textus is local-first, plain-files, diffable in git.

- **Why not JSON Schema for the schemas?** Considered. Bespoke YAML chosen for v1: simpler implementation, lighter dependency footprint, matches the reference impl's house language. JSON Schema MAY be added as an alternate schema-language adapter in a future minor revision without breaking `textus/1`.

- **Why not a database (SQLite, kv store)?** textus's whole point is that the storage is plain files agents and humans both read. A binary store loses git-diff, grep, and editor support.

- **Why not vector embeddings?** Different problem. textus is for facts agents act on deterministically; embeddings are for fuzzy retrieval. They compose — index a textus tree into a vector store if you need both.

## 14. Open questions (v1.x scope)

- **Locking on `put`:** the reference impl uses sha256 etags. Should the spec also define a file-lock fallback for systems where read-before-write is racy?
- **Schema imports:** can one schema reference another (`type: $ref: person`)? Defer to v1.1.
- **Internationalization:** non-ASCII in keys? Spec currently restricts segments to `[a-z0-9_-]`. Revisit if community wants Unicode.
- **Generated content in `derived/`:** the spec says `schema: null` is allowed, but should there be a separate marker (`generated: true`) for clarity?

## 15. Implementation checklist

A v1 implementation MUST:

- [ ] Parse `.textus/manifest.yaml` and validate the `version: textus/1` declaration.
- [ ] Resolve keys via longest-prefix match against manifest entries.
- [ ] Read frontmatter + body from `.md` files; validate against the named schema.
- [ ] Compute `sha256:<hex>` etags over raw file bytes.
- [ ] Refuse writes whose resolved role is not in the target zone's `writable_by` list with `write_forbidden`.
- [ ] Return envelopes matching the shape in §8 exactly.
- [ ] Use the error codes in §8 and the exit-code table.
- [ ] Implement `textus stale` per §5.1 and §9, comparing each derived entry's `generator.sources` against its `generated.at` timestamp without invoking any commands.
- [ ] Pass the conformance fixtures A–I in §12.

A v1 implementation MAY:

- Add additional CLI verbs (e.g. `move`, vendor-specific reporters) beyond the v1.0 set in §9.
- Provide alternate output formats (`--format=yaml`, `--format=table`) for human use.
- Support additional schema field types beyond §6, marked as `vendor:<name>` extensions.

---

**Spec word count target:** <2500 words (allowance widened from 2000 to fit Level-A/B derived provenance + staleness in v1).
**Reviewed against community-testing checklist (idea file §"Community-testing"):** ✅ <2500 words; ✅ implementable in a day in TS/Python (four concepts: manifest, schema, envelope, staleness check); ✅ conformance fixtures A–I; ✅ "Why not X?" section present (incl. why no execution); ✅ name picked.
