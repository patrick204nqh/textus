# textus/2 — Specification

**Status:** Draft v2.0 (2026-05-19)
**Protocol identifier:** `textus/2`
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
| L4 | **Publish** | Byte-for-byte file copy from derived entries to repo-relative paths declared via `publish_to:`. The in-store artifact is the consumer-shaped output; the published file is an identical copy. A sentinel under `.textus/sentinels/<target-rel-path>.textus-managed.json` records the source, sha256, and `mode: "copy"`. |
| L5 | **Consumers** | Anything that reads the published files or calls the CLI — editors, LLM tools, MCP servers, CI jobs, dashboards. textus is agnostic about who consumes; the envelope is the contract. |

## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/2`) any language can speak.
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
- Not a fetcher. textus declares sources; external runners invoke actions to materialize them.
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

### 3.1 Store location precedence (v0.3)

Implementations MUST resolve the store root in this order; the first match wins:

1. `--root <path>` flag passed to the CLI (or `root:` kwarg to `Store.discover`).
2. `TEXTUS_ROOT` environment variable.
3. Walk up from cwd looking for a `.textus/` directory containing `manifest.yaml`.

When (1) or (2) names a path that has no `manifest.yaml`, the CLI exits with `io_error` and a message naming the resolved absolute path. When (3) reaches the filesystem root without finding a store, the CLI exits with `io_error` naming the search start point.

## 4. Manifest

The manifest declares: (a) which zones exist and which roles may write to each, (b) the key-to-subtree mapping, (c) the schema applied to entries in each subtree, and (d) the owner string recorded in writes.

```yaml
# .textus/manifest.yaml
version: textus/2

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

**Key grammar (enforced from v1.2):** dotted segments matching `/^[a-z0-9][a-z0-9-]*$/`. Segments are joined by `.`. A key has at most 8 segments; each segment is at most 64 characters. Segments MUST NOT contain dots, slashes, uppercase letters, or underscores. Example: `working.projects.acme.dashboard`. Enforcement points: manifest load (rejects illegal `key:` declarations and illegal nested file/directory names), `put` (rejects illegal keys before any write), `enumerate` (filters and warns on illegal filenames so existing trees still load with a clear migration message). Run-once migration: `textus key migrate --dry-run` then `--write` (see §audit).

**Per-entry `format:` (enforced from v1.2):** an entry MAY declare `format:` to be one of `markdown` (default), `json`, `yaml`, or `text`. The `format` controls the on-disk shape and which path extension is required:

| `format`   | Path extension              | `template:`           | `schema:` |
|------------|-----------------------------|------------------------|-----------|
| `markdown` | `.md` (or appended if absent) | required for derived | optional  |
| `json`     | `.json` required            | optional (escape hatch) | optional (top-level keys) |
| `yaml`     | `.yaml` or `.yml` required  | optional (escape hatch) | optional (top-level keys) |
| `text`     | `.txt` or no extension      | required for derived | MUST be null |

For `nested: true`, the recursive glob matches the format's extension (markdown→`**/*.md`, json→`**/*.json`, yaml→`**/*.{yaml,yml}`, text→`**/*.txt`). All files under one nested entry share one format and one schema.

**Per-leaf publishing (`publish_each:`, v1.2).** A nested manifest entry MAY declare `publish_each:` to byte-copy every leaf to a templated repo-relative path. `publish_each:` and `publish_to:` are mutually exclusive on the same entry, and `publish_each:` requires `nested: true`. The template substitutes these variables (using `{name}` syntax):

| Variable     | Value                                                                                  |
|--------------|----------------------------------------------------------------------------------------|
| `{leaf}`     | Remaining key segments after the entry prefix, joined with `/`.                        |
| `{basename}` | Last segment only.                                                                     |
| `{key}`      | Full dotted key.                                                                       |
| `{ext}`      | Primary extension for the entry's format, without the leading dot (`md`/`json`/`yaml`/`txt`). |

Validation at manifest load: any unknown variable raises `UsageError`; the template MUST reference at least one of `{leaf}`, `{basename}`, `{key}` (otherwise every leaf would clobber the same target). A computed target outside the repo root is refused at build time with `PublishError`. Example:

```yaml
- key: working.skills
  path: working/skills
  zone: working
  schema: skill
  nested: true
  publish_each: "skills/{basename}/SKILL.md"
```

A leaf at `working.skills.writing.voice-writer` (authored at `.textus/zones/working/skills/writing/voice-writer.md`) publishes to `skills/voice-writer/SKILL.md`.

**`inject_intro:` (v1.1).** A derived entry with a `template:` MAY declare `inject_intro: true`. When the builder materializes the entry, it merges the `textus intro` envelope (§9) into the projection data under the key `intro`, so the template can render orientation content (zones, write flows, CLI catalog) alongside its projected rows. The flag is rejected at manifest load on (a) non-derived entries or (b) derived entries without a `template:` — agents reading the rendered file should be able to trust the preamble was produced by the same source of truth `textus intro` exposes.

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

A sentinel is written for each published file at `<store_root>/sentinels/<target-relative-to-repo>.textus-managed.json`, recording `source`, `target`, the target's sha256, and `mode: "copy"`. Sentinels live under the store rather than beside the consumer file so target directories stay clean. The sentinel exists so out-of-band edits can be detected on the next publish — textus refuses to clobber a destination that is not either missing or marked as managed. Legacy sibling sentinels (`<target>.textus-managed.json`) are still recognised as managed and are migrated to the new location on the next publish.

**Per-leaf publishing.** A nested entry MAY declare `publish_each:` instead of `publish_to:` (see §4). When the build runs, every leaf reachable under the nested entry is byte-copied to the path produced by substituting `{leaf}` / `{basename}` / `{key}` / `{ext}` in the template, with a sentinel written under `<store_root>/sentinels/` at the mirrored target path. The build envelope grows a `published_leaves` array — one row per leaf, with `key`, `source`, and `target` — alongside the existing `built` array. Targets that would resolve outside the repo root are refused.

### 5.4 Intake (declared, refreshed via registered fetch hook)

Intake entries declare an external source by naming a **fetch hook** — a registered, named function that pulls data into the entry. textus itself still makes no implicit network calls: a fetch hook only runs in intake mode when explicitly invoked by `textus refresh KEY --as=script`. The declaration is data only:

```yaml
- key: intake.calendar.events
  zone: intake
  source:
    fetch: ical-events
    config:
      url: "https://calendar.google.com/.../basic.ics"
    ttl: 6h
```

`fetch` names a registered `:fetch` hook (see §5.10 for the hook contract); `config` is an opaque hash handed to the hook; `ttl` is the staleness budget. Implementations MUST reject legacy `source.from`, `source.parse`, `source.fetcher`, and `source.action` with a clear usage error.

In intake mode the hook MUST return one of three shapes, all normalized by the store into its internal `{_meta, body, content}` representation (§5.12):

- `{ _meta:, body: }` — markdown-friendly; `_meta` becomes the entry's parsed metadata hash.
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content.
- `{ body: }` — raw bytes for `text` or for any format that prefers verbatim writes; the store re-parses and validates per `format:`.

**Built-in fetch hooks.** `json`, `csv`, `markdown-links`, `ical-events`, `rss` are always available. They expect raw bytes in `config["bytes"]` and produce structured `_meta`/body. Built-ins do not perform I/O themselves — the caller (or an outer hook) is responsible for supplying bytes.

**Refresh paths.** Two are supported:

1. **In-process** — `textus refresh KEY --as=script` resolves the entry's `source.fetch`, invokes the registered `:fetch` hook with `(config:, store:, args: {})`, and writes the result under role `script`.
2. **External runner** — a cron job or agent harness reads `textus list --zone=intake --stale --format=json`, fetches the source out of band, and pipes bytes back through `textus put KEY --as=script --stdin`.

Both paths share the same role gate, audit-log entry, and `:refresh` event. User-supplied hooks live in `.textus/hooks/**/*.rb` and auto-load at `Store#initialize` — see §5.10 for the full hook contract.

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

Every successful write appends one compact JSON object (NDJSON) to `.textus/audit.log`. The file is opened with `flock(LOCK_EX)` for the duration of each append so concurrent writers serialize cleanly.

Schema (one JSON object per line, no interior whitespace):

```json
{"ts":"<iso8601-utc>","role":"<role>","verb":"<verb>","key":"<key>","etag_before":<etag-or-null>,"etag_after":<etag-or-null>}
```

`ts` is the wall-clock timestamp in UTC with second precision. `role` is the resolved role for the invocation. `verb` is the audit-log payload string identifying the operation (`put`, `delete`, `accept`, `compute`, `migrate-keys`, `mv`, ...). Note that `migrate-keys` here is the on-disk payload key — the CLI surface is `textus key migrate`; the payload string is retained for log stability. `key` is the affected entry key. `etag_before` and `etag_after` are the entry etags before and after the write, or JSON `null` when not applicable (e.g. create has no before-etag, delete has no after-etag). `key migrate --write` emits one line per renamed file (with payload `verb: "migrate-keys"`) using the new key as `key` and the file's pre- and post-rename etags.

For `mv`, the structural fields `from_key`, `to_key`, and `uid` appear at the top level of the JSON object. Remaining verb-specific data (e.g. `from_path`, `to_path`) is nested under an `extras` key. The `extras` key is omitted entirely when empty.

**Backward compatibility (v0.5):** files written by v0.4 and earlier contain TSV rows. Readers MUST accept mixed-format files: lines starting with `{` are parsed as JSON; other lines are treated as legacy TSV (`ts\trole\tverb\tkey\tetag_before\tetag_after[\tjson_extras]`). TSV write support is removed in v0.6.

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

`textus schema migrate NAME` consults `evolution.migrate_from` when invoked without `--rename=OLD:NEW`, applying every declared rename across affected entries in one pass. An explicit `--rename` flag overrides the schema-declared map for that invocation.

**Backwards compat:** v1.0 schemas (no `fields:`, no `evolution:`) continue to parse and behave identically. `schema.maintained_by(field)` returns `nil` for every field; `schema.evolution` returns `{}`.

**Override rule:** the role `human` is permitted to write any `maintained_by` field, regardless of declared owner. This preserves human authority over AI/script-managed data — humans curating canon over AI-written embeddings is a feature, not a bug. All other role mismatches are reported by `doctor --check=schema_violations` with code `role_authority`, including fields `key`, `field`, `expected`, and `last_writer`.

### 5.9 Reducers (v1.2)

Reducers are RPC hooks on the `:reduce` event. See §5.10.

### 5.10 Hooks

textus has a single hook verb: `Textus.hook(event, name, **opts) { ... }`. The EVENTS table below defines every extension point. Files in `.textus/hooks/` are `load`ed at `Store#initialize`: top-level `*.rb` files first, then each plugin subdirectory's entry file (see "Plugin layout" below).

#### Plugin layout (0.8.3+)

Subdirectories under `.textus/hooks/` are treated as plugins. For each subdir `<name>/`:

- If `<name>/lib/` exists, it is prepended to `$LOAD_PATH`. Plugin code can then `require "<name>/foo"` against files under `<name>/lib/<name>/foo.rb`.
- The entry file is `load`ed first. Resolution order: `<name>/<name>.rb`, then `<name>/hook.rb`. A subdir with neither is rejected with `UsageError`.
- The plugin subtree is **not** auto-globbed. The entry file is responsible for pulling in the rest via `require`.

Top-level `.textus/hooks/*.rb` continue to load as before — use them for simple single-file hooks.

```
.textus/hooks/
  notify.rb                       # single-file hook
  patrick/                        # plugin
    patrick.rb                    # entry
    lib/
      patrick/
        runner.rb
        config.rb
```

The registered event and name come from the DSL call, not the file path.

#### Sugar surface (0.8.2+)

Per-event methods are provided for ergonomics. They delegate to the same registry as `Textus.hook`.

```ruby
Textus.fetch(:local_file)        { |config:, args:, **|  … }
Textus.reduce(:rank_by_recency)  { |rows:, **|            … }
Textus.check(:storage_writable)  { |store:|               … }
Textus.put(:audit, keys: ["working.*"]) { |key:, envelope:, **| … }
Textus.publish(:git_add, keys: ["derived.*"]) { |target:, **| `git add #{target.shellescape}` }
```

The primitive `Textus.hook(:event, :name, &blk)` remains supported and is the authoritative entry point; sugar methods are thin wrappers.

| Event    | Mode    | Args                              | Return        | Failure |
|----------|---------|-----------------------------------|---------------|---------|
| :fetch   | rpc     | store:, config:, args:                       | {_meta:, body:}       | aborts op |
| :reduce  | rpc     | store:, rows:, config:                       | rows array            | aborts op |
| :check   | rpc     | store:                                       | issues array          | aborts doctor |
| :put     | pubsub  | store:, key:, envelope:                      | (discarded)           | logged   |
| :delete  | pubsub  | store:, key:                                 | (discarded)           | logged   |
| :refresh | pubsub  | store:, key:, envelope:, change:             | (discarded)           | logged   |
| :build   | pubsub  | store:, key:, envelope:, sources:            | (discarded)           | logged   |
| :accept  | pubsub  | store:, key:, target_key:                    | (discarded)           | logged   |
| :publish | pubsub  | store:, key:, envelope:, source:, target:    | (discarded)           | logged   |

**Signature invariant** — every hook receives `store:` as its first keyword argument. Event-specific kwargs follow in stable left-to-right order. The primary entity is always `key:` (for `:accept`, `key:` is the pending key being accepted and `target_key:` is the destination).

**RPC mode** — exactly one handler per (event, name). The manifest references the handler by name (`source.fetch: NAME`, `projection.reduce: NAME`). Failure or timeout aborts the calling operation.

**Pub-sub mode** — zero or more handlers per event. All matching handlers fire. The `keys:` option restricts a handler to keys matching one of the given globs (`File.fnmatch?` rules). Absence of `keys:` fires on every event of that type. Handler failures and 2s timeouts are logged to `audit.log` as `event_error` rows; they NEVER abort the triggering operation.

The `store:` argument is always a read-only store proxy. Write attempts raise `UsageError`.

Each handler runs under `Timeout.timeout(2)`.

### 5.12 Storage formats (v1.2)

An entry's `format:` selects a storage strategy. All strategies expose the same `parse(bytes) → {_meta, body, content}` and `serialize(meta:, body:, content:) → bytes` contract. The store, audit, etag, and projection layers operate on the parsed shape; only (de)serialization differs.

- **markdown** — YAML frontmatter between `---` fences, free-form body. Parse: Psych `safe_load` on the frontmatter block; body is the remainder. Serialize: emit `---\n<yaml>\n---\n<body>`. `content` is always `nil`. `_meta` holds the parsed frontmatter hash.
- **json** — entire file is a JSON document. Parse: `JSON.parse`. Serialize: `JSON.pretty_generate(content)` + trailing newline. `_meta` is populated from the top-level `_meta` hash (if present, else `{}`); `body` is the raw bytes; `content` is the parsed object with `_meta` stripped.
- **yaml** — entire file is a YAML mapping. Parse: `YAML.safe_load(bytes, permitted_classes: [Date, Time], aliases: false)`; anchors/aliases rejected. Serialize: `YAML.dump(content).sub(/\A---\n/, "")`. Same `_meta` / `body` / `content` rules as JSON.
- **text** — raw UTF-8 bytes. Parse: body is the file verbatim, `_meta` is `{}`, `content` is `nil`. Serialize: write `body` bytes (with trailing newline if missing).

**Envelope shape.** Every envelope carries `format:` (always present, defaults to `markdown` for back-compat). For `json|yaml`, the envelope additionally carries `content:` (parsed object). `body` is always the raw on-disk bytes. `_meta` always exists in the envelope: for `markdown` it holds the parsed YAML frontmatter; for `json|yaml` it mirrors the top-level `_meta` block (`{}` if absent); for `text` it is `{}`.

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

**`uid:` (Textus UID).** Entries MAY carry a stable identity field that survives renames and moves. Optional. When present:

- Lives at top-level `uid:` in markdown frontmatter, or `_meta.uid` in `json`/`yaml` entries.
- Format: lowercase hex string, 12 or more characters. The reference impl mints 16 hex chars (`SecureRandom.hex(8)`). This is a **Textus UID**, not a UUID — short on purpose.
- Auto-assigned on the first successful `Store#put` if the payload has no uid. Preserved on subsequent puts.
- Existing files without a uid continue to work. The envelope shows `"uid": null` until a put mints one.
- `text` entries have no metadata channel and therefore no uid; their envelope always shows `"uid": null`.

Entries in `zone: derived` SHOULD additionally carry the `generated:` block defined in §5.2. Implementations MUST treat unknown frontmatter fields as warnings, not errors, so build runners can extend the metadata without breaking conformance.

## 8. Envelope (the wire format)

Every successful CLI response (`--format=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/2",
  "key": "working.network.org.jane",
  "zone": "working",
  "owner": "textus:network",
  "path": "/absolute/path/to/.textus/zones/working/network/org/jane.md",
  "format": "markdown",
  "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body in Markdown.\n",
  "etag": "sha256:8f3c…",
  "schema_ref": "person",
  "uid": "a1b2c3d4e5f60718"
}
```

**Field rules:**
- `protocol` MUST be the exact string `textus/2`.
- `key` MUST be the canonical resolved key.
- `zone` MUST be one of the zones declared in the manifest (`canon`, `working`, `intake`, `pending`, `derived` for the default v1.0 model; legacy v0.1 manifests synthesize `fixed`, `state`, `derived` per §4).
- `path` MUST be an absolute filesystem path.
- `format` MUST be one of `markdown`, `json`, `yaml`, `text` (§5.12). Absent envelopes are treated as `markdown` for back-compat.
- `body` is the raw on-disk bytes as a UTF-8 string for every format.
- `content` is present only when `format` is `json` or `yaml`; equals the parsed object. For `json|yaml`, `_meta` mirrors the top-level `_meta` block (or `{}` if absent). For `markdown`, `_meta` holds the parsed YAML frontmatter. For `text`, `_meta` is `{}`.
- `etag` MUST be `sha256:<hex>` of the raw file bytes, computed identically for every format.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.
- `uid` is the stable Textus UID (§7) if the entry carries one, else `null`. Always present in the envelope.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/2",
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
| `schema show K` | read | any |
| `stale [--prefix=K] [--strict]` | read | any |
| `deps K` / `rdeps K` | read | any |
| `published` | read | any |
| `hook list` | read | any |
| `doctor [--check=NAME[,NAME]] [--format=json]` | read | any |
| `intro [--format=json]` | read | any |
| `put K --stdin --as=R [--fetch=NAME]` | write | per zone |
| `delete K --if-etag=E --as=R` | write | per zone |
| `refresh K --as=script` | write | per zone (typically `script`) |
| `build [--prefix=K] [--dry-run]` | write | `build` (default) |
| `accept K --as=human` | write | `human` |
| `init` | write | `human` |
| `schema init NAME` / `schema diff NAME` / `schema migrate NAME [--rename=OLD:NEW]` | write | `human` |
| `key migrate [--dry-run\|--write]` | write (with `--write`) | `human` |
| `key mv OLD NEW [--as=R] [--dry-run]` | write | per zone (same-zone only) |
| `key uid K` | read | any |
| `hook run NAME` | write | any |

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
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

`textus schema show K` prints the schema for entry `K`. `textus schema init NAME` writes a stub schema. `textus schema diff NAME` compares the on-disk schema against entries that claim it and prints the deltas. `textus schema migrate NAME --rename=OLD:NEW` rewrites the `_meta` key `OLD` to `NEW` across every entry that uses the named schema, in a single transactional sweep that logs each touched file.

## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.

## 10.1 Errors carry hints

Every `Textus::Error` exposes `code`, `message`, and an optional `hint:`. The hint is a single short string suggesting the next action — the file to edit, the role to pass, the command to run. Errors in the wire envelope include the hint as a top-level `hint:` field when present. The CLI prints failures to stderr as `code: message` followed by `  → hint` (when a hint exists), in addition to the JSON envelope on stdout. Hints are advisory: implementations MAY omit or rephrase them without breaking conformance.

## 10.2 `textus doctor`

`textus doctor` returns a health-check envelope: `{ "protocol": "textus/2", "ok": bool, "issues": [...], "summary": {error, warning, info} }`. Each issue carries `code`, `level` (`error|warning|info`), `subject`, `message`, and optionally `fix`. `ok` is true iff no error-level issues are present; warnings and info do not flip the bit. Builtin checks: `manifest_files`, `schemas`, `templates`, `hooks`, `illegal_keys`, `sentinels`, `audit_log`, `unowned_schema_fields`, `schema_violations`. Additional registered `:check` hooks (§5.10) run after the builtin set. Exit code is 0 on `ok`, 1 otherwise.

## 11. Versioning

- The current wire string is `textus/2`. It was introduced in gem v0.5, which unified the `_meta` block across all storage formats (markdown, json, yaml, text) and replaced the legacy TSV audit-log write path with NDJSON.
- `textus/1` was the original protocol (gem ≤ v0.4). Manifests declaring `version: textus/1` are still accepted for backward compatibility (§4).
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/2`.
- Breaking changes (renamed/removed envelope fields, zone semantics, key grammar) require a new wire string `textus/3`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently. The current gem version is `0.8.0`, which speaks `textus/2`.

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
Given a manifest entry with `publish_to: <path>`, a successful `textus build` for that entry leaves a plain file at `<path>` whose contents are byte-identical to the in-store artifact at `.textus/zones/<...>`, accompanied by a sentinel at `.textus/sentinels/<path>.textus-managed.json` recording `source`, `target`, `sha256`, and `mode: "copy"`. Re-running `build` is idempotent.

**Fixture H — Audit log format:**
Every successful write verb (`put`, `delete`, `build`, `accept`, `schema migrate`) appends exactly one line per affected key to the audit log, in the canonical format defined in §audit (timestamp, actor role, verb, key, etag-before, etag-after). No write produces zero or multiple lines per key.

**Fixture I — Pending → accept:**
Given a pending entry `pending.canon.identity.patch` proposing a change to `canon.identity`, `textus accept canon.identity --as=human` copies the patch body into `canon.identity`, deletes the pending entry, and appends two audit lines (one for the canon write, one for the pending delete) in that order.

## 13. Why not X?

- **Why not MCP?** MCP is a transport; textus is a data model. The two compose: a 50-line MCP server can wrap `textus get/put` as tools. textus exists because the *shape* of agent-readable project memory deserves a standalone spec, separate from how it's served.

- **Why doesn't textus execute generator commands itself?** textus is a dataflow oracle, not a build runner. The moment a spec includes process execution, it inherits shell-injection surface, OS-portability concerns, and signal-handling semantics — and ends up duplicating whatever build system the consumer already runs (make, rake, just, lefthook, CI). Keeping execution external means a Python or TypeScript port of `textus/2` only has to parse YAML and emit JSON; it doesn't have to spawn processes safely. Build runners stay the executor; textus stays a data tool.

- **Why not plain Markdown vaults (Obsidian / Foam)?** No schema enforcement, no write-gating, no addressable wire format. Fine for human notes; underspecified for agents that must act on the contents deterministically.

- **Why not Notion / Coda?** Closed, hosted, lossy export. textus is local-first, plain-files, diffable in git.

- **Why not JSON Schema for the schemas?** Considered. Bespoke YAML chosen for v1: simpler implementation, lighter dependency footprint, matches the reference impl's house language. JSON Schema MAY be added as an alternate schema-language adapter in a future minor revision without breaking `textus/2`.

- **Why not a database (SQLite, kv store)?** textus's whole point is that the storage is plain files agents and humans both read. A binary store loses git-diff, grep, and editor support.

- **Why not vector embeddings?** Different problem. textus is for facts agents act on deterministically; embeddings are for fuzzy retrieval. They compose — index a textus tree into a vector store if you need both.

## 14. Open questions (v2.x scope)

- **Locking on `put`:** the reference impl uses sha256 etags. Should the spec also define a file-lock fallback for systems where read-before-write is racy?
- **Schema imports:** can one schema reference another (`type: $ref: person`)? Defer to v1.1.
- **Internationalization:** non-ASCII in keys? Spec currently restricts segments to `[a-z0-9_-]`. Revisit if community wants Unicode.
- **Generated content in `derived/`:** the spec says `schema: null` is allowed, but should there be a separate marker (`generated: true`) for clarity?

## 15. Implementation checklist

A `textus/2` implementation MUST:

- [ ] Parse `.textus/manifest.yaml` and accept `version: textus/2` (and `textus/1` for backward compat per §11).
- [ ] Resolve keys via longest-prefix match against manifest entries.
- [ ] Read `_meta` + body from `.md` files; validate against the named schema.
- [ ] Read `_meta` from the top-level `_meta` hash in `.json` / `.yaml` files; validate against the named schema.
- [ ] Compute `sha256:<hex>` etags over raw file bytes.
- [ ] Refuse writes whose resolved role is not in the target zone's `writable_by` list with `write_forbidden`.
- [ ] Return envelopes matching the shape in §8 exactly (with `_meta`, not `frontmatter`).
- [ ] Use the error codes in §8 and the exit-code table.
- [ ] Implement `textus stale` per §5.1 and §9, comparing each derived entry's `generator.sources` against its `generated.at` timestamp without invoking any commands.
- [ ] Pass the conformance fixtures A–I in §12.

A `textus/2` implementation MAY:

- Add additional CLI verbs (e.g. `move`, vendor-specific reporters) beyond the current set in §9.
- Provide alternate output formats (`--format=yaml`, `--format=table`) for human use.
- Support additional schema field types beyond §6, marked as `vendor:<name>` extensions.

---

**Spec word count target:** <2500 words (allowance widened from 2000 to fit Level-A/B derived provenance + staleness in v1).
**Reviewed against community-testing checklist (idea file §"Community-testing"):** ✅ <2500 words; ✅ implementable in a day in TS/Python (four concepts: manifest, schema, envelope, staleness check); ✅ conformance fixtures A–I; ✅ "Why not X?" section present (incl. why no execution); ✅ name picked.
