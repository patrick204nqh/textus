# textus/3 — Specification

**Status:** Draft v3.0
**Protocol identifier:** `textus/3`
**Reference implementation:** Ruby gem `textus`

> *textus* — Latin for "the fabric a text is woven from," same root as *context* (from *con-texere*, "to weave together"). This spec defines a storage shape and wire protocol for that fabric.

---

## 1. What textus is

A storage convention and JSON wire protocol that lets humans, agents, and runners read and write structured project memory **deterministically**, with addressable dotted keys, schema validation, role-based write gates, declarative compute, and copy-based publish targets.

The storage lives in a `.textus/` directory at the project root. Each entry is a Markdown file with YAML frontmatter. A manifest binds dotted keys to subtrees and declares which roles may write to each zone. Schemas (also YAML) define what frontmatter shape each entry must have. Derived entries are computed from other entries via pure projections and a vendored Mustache template engine, then optionally published to repo-relative paths as byte-for-byte file copies. The CLI surface (`textus get/put/list/where/schema/build/...` `--output=json`) returns a versioned envelope any caller can parse without knowing Markdown.

You **shape your own memory structure** inside `.textus/`. The protocol manages how it's read, written, addressed, validated, gated, computed, and published. The contents are entirely yours.

### 1.1 Vocabulary axes

textus/3 names its concepts along six axes. Reviewers who internalize these can map any part of the spec to the right category:

- **Actor** — who is interacting: `human`, `agent`, `runner`, `builder`.
- **Place** — where data lives: zones such as `identity`, `working`, `intake`, `review`, `output`.
- **Thing** — what is stored: entries, fields, keys.
- **Operation** — how you act on things: RPC and CLI verbs (`get`, `put`, `refresh`, `build`, …).
- **Event** — what gets fired after an operation: hook event names, split into RPC events (`:resolve_intake`, `:transform_rows`, `:validate`) and pub-sub events (`:entry_put`, `:build_completed`, …).
- **Rule** — constraints declared in the top-level `rules:` array of the manifest.

### 1.2 The five layers

textus is organized as five composable layers. Each layer has a single responsibility; later layers build on earlier ones.

| Layer | Name | Responsibility |
|---|---|---|
| L1 | **Store** | Plain-file backend: `.textus/zones/<zone>/...` with YAML frontmatter + Markdown body, addressed by dotted keys, schema-validated, etag-versioned. |
| L2 | **Sources** | Declared external inputs (the `intake` zone in the default scaffold; any zone writable by `runner`): URLs, files, feeds with declared parsers and TTLs. textus *describes* sources; external runners fetch and pipe results through `textus put`. |
| L3 | **Compute** | Pure transforms from store entries to derived entries. Projections (select/pluck/sort/limit/format) plus a vendored Mustache template subset. No shell execution. |
| L4 | **Publish** | Byte-for-byte file copy from derived entries to repo-relative paths declared via `publish_to:`. The in-store artifact is the consumer-shaped output; the published file is an identical copy. A sentinel under `.textus/sentinels/<target-rel-path>.textus-managed.json` records the source, sha256, and `mode: "copy"`. |
| L5 | **Consumers** | Anything that reads the published files or calls the CLI — editors, LLM tools, MCP servers, CI jobs, dashboards. textus is agnostic about who consumes; the envelope is the contract. |

## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/3`) any language can speak.
- Deterministic read/write of structured Markdown via a CLI returning JSON.
- Schema-validated frontmatter using YAML schemas as data.
- Role-based write gates (humans, agents, runners, builders get different permissions per zone).
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

The root is `.textus/` at the project working directory. A typical tree:

```
.textus/
  manifest.yaml          # internal: key → subtree mapping + zones declarations
  audit.log              # internal, append-only NDJSON log of every successful write
  role                   # internal, role token (one line, e.g. "human")
  schemas/               # internal: YAML schema files
  templates/             # internal: Mustache templates referenced by derived entries
  parsers/               # internal: project-local parser extensions
  zones/                 # ALL user content lives here
    identity/            # zone: identity (human-only)
    working/             # zone: working (human, agent, runner)
    intake/              # zone: intake (runner — declared external inputs)
    review/              # zone: review (agent/human — proposals awaiting accept)
    output/              # zone: output (builder only — computed outputs)
```

Textus internals (`manifest.yaml`, `audit.log`, `role`, `schemas/`, `templates/`, `parsers/`) live directly under `.textus/`. **All user content lives under `.textus/zones/`.** Manifest `path:` fields are relative to `.textus/zones/` — they do **not** include the `zones/` prefix. Implementations MUST prepend `zones/` to every `path:` when resolving a key to a filesystem location.

Zone directories under `zones/` are conventional; their write semantics are declared in the manifest, not the directory name.

`.textus/audit.log` is an append-only NDJSON file written under a file lock by every successful `put`, `delete`, `accept`, and `build`. `.textus/role` (one line containing a role name) is optional and participates in the role-resolution order (§5).

### 3.1 Store location precedence

Implementations MUST resolve the store root in this order; the first match wins:

1. `--root <path>` flag passed to the CLI (or `root:` kwarg to `Store.discover`).
2. `TEXTUS_ROOT` environment variable.
3. Walk up from cwd looking for a `.textus/` directory containing `manifest.yaml`.

When (1) or (2) names a path that has no `manifest.yaml`, the CLI exits with `io_error` and a message naming the resolved absolute path. When (3) reaches the filesystem root without finding a store, the CLI exits with `io_error` naming the search start point.

## 4. Manifest

The manifest declares: (a) which zones exist and which roles may write to each, (b) the key-to-subtree mapping, (c) the schema applied to entries in each subtree, and (d) the owner string recorded in writes.

```yaml
# .textus/manifest.yaml
version: textus/3

zones:
  - name: identity
    write_policy: [human]
  - name: working
    write_policy: [human, agent, runner]
  - name: intake
    write_policy: [runner]
  - name: review
    write_policy: [agent, human]
  - name: output
    write_policy: [builder]

entries:
  - key: identity.self
    path: identity/self.md
    zone: identity
    schema: identity

  - key: working.network.org
    path: working/network/org
    zone: working
    schema: person
    owner: textus:network
    nested: true

  - key: output.catalogs.people
    path: output/catalogs/people.md
    zone: output
    schema: null
    owner: textus:build

rules:
  - match: intake.**
    refresh: { ttl: 6h, on_stale: warn }

audit:
  max_size: 10485760   # bytes before rotating (default: 10 485 760 = 10 MiB)
  keep: 5              # rotated files to retain (default: 5)
```

Zone names are conventional — the manifest is the source of truth for write permissions; rename freely.

**Key grammar:** dotted segments matching `/^[a-z0-9][a-z0-9-]*$/`. Segments are joined by `.`. A key has at most 8 segments; each segment is at most 64 characters. Segments MUST NOT contain dots, slashes, uppercase letters, or underscores. Example: `working.projects.acme.dashboard`. Enforcement points: manifest load (rejects illegal `key:` declarations and illegal nested file/directory names), `put` (rejects illegal keys before any write), `enumerate` (filters and warns on illegal filenames).

**Per-entry `format:`** an entry MAY declare `format:` to be one of `markdown` (default), `json`, `yaml`, or `text`. The `format` controls the on-disk shape and which path extension is required:

| `format`   | Path extension              | `template:`           | `schema:` |
|------------|-----------------------------|------------------------|-----------|
| `markdown` | `.md` (or appended if absent) | required for derived | optional  |
| `json`     | `.json` required            | optional (escape hatch) | optional (top-level keys) |
| `yaml`     | `.yaml` or `.yml` required  | optional (escape hatch) | optional (top-level keys) |
| `text`     | `.txt` or no extension      | required for derived | MUST be null |

For `nested: true`, the recursive glob matches the format's extension (markdown→`**/*.md`, json→`**/*.json`, yaml→`**/*.{yaml,yml}`, text→`**/*.txt`). All files under one nested entry share one format and one schema.

**Per-entry `index_filename:`.** A nested entry MAY declare `index_filename:` to surface a single fixed basename (e.g. `SKILL.md`) per directory as the row, with the row's key segments derived from the directory path. Sibling files are not enumerated. The basename's extension MUST match the entry's `format:`. This lets entries project spec-mandated filenames whose casing would otherwise be rejected by the key-segment grammar. Example:

```yaml
- key: skills
  path: skills
  zone: skills
  nested: true
  index_filename: SKILL.md
```

A file at `.textus/zones/skills/ask/SKILL.md` enumerates as `skills.ask`; `.textus/zones/skills/ask/references/algorithm.md` is not enumerated. Resolving `skills.ask` returns the `SKILL.md` path. `index_filename:` requires `nested: true`; the value must be a bare basename (no slashes).

**Per-leaf publishing (`publish_each:`).** A nested manifest entry MAY declare `publish_each:` to byte-copy every leaf to a templated repo-relative path. `publish_each:` and `publish_to:` are mutually exclusive on the same entry, and `publish_each:` requires `nested: true`. The template substitutes these variables (using `{name}` syntax):

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

**`inject_boot:`.** A derived entry with a `template:` MAY declare `inject_boot: true`. When the builder materializes the entry, it merges the `textus boot` envelope (§9) into the projection data under the key `boot`, so the template can render orientation content (zones, write flows, CLI catalog) alongside its projected rows. The flag is rejected at manifest load on (a) non-derived entries or (b) derived entries without a `template:` — agents reading the rendered file should be able to trust the preamble was produced by the same source of truth `textus boot` exposes.

**Lookup rule:** to resolve a key, find the entry with the longest `key:` prefix that matches. If that entry has `nested: true`, the remaining segments map to subdirectories under its `path`. Otherwise the key must equal an entry exactly. The resolved filesystem path is `<.textus root>/zones/<entry.path>[/<remaining>...].md` — implementations MUST prepend `zones/` to the manifest `path:` when constructing the filesystem location.

## 5. Zones and role-based write gates

Each zone declares which **roles** may write to it via `write_policy:` in the manifest. An optional `read_policy:` (default `[all]`) gates reads. Writes are gated; reads are unrestricted by default.

| Zone | `write_policy` | Use case |
|---|---|---|
| `identity` | `[human]` | Identity, voice, immutable principles — things only a human edits. |
| `working` | `[human, agent, runner]` | Active project state: notes, decisions, network — what humans and agents update day-to-day. |
| `intake` | `[runner]` | Declared external inputs (calendar, feeds, scraped pages). Refreshed by external runner scripts; never by humans or agents directly. |
| `review` | `[agent, human]` | Agent-generated proposals awaiting human review via `textus accept`. Lets agents stage changes without touching `working`. |
| `output` | `[builder]` | Computed outputs (catalogs, indexes, published context). Written only by the build runner via `textus build`. |

A write is gated by the caller's **role**, supplied via `--as=<role>`. If the role is not in the target zone's `write_policy` list, the write returns `write_forbidden`.

### 5.1 Role resolution

The effective role for any CLI invocation is resolved in this order; the first match wins:

1. `--as=<role>` flag on the command line.
2. `TEXTUS_ROLE` environment variable.
3. `.textus/role` file (one line, role name) at the project root.
4. Default: `human`.

**Canonical actors (textus/3):**

| Actor | Meaning |
|---|---|
| `human` | Interactive user at a terminal. |
| `agent` | Long-running AI or LLM process. |
| `runner` | Scheduled or one-shot automation script. |
| `builder` | Build/derive output (catalogs, indexes). |

Unknown role values are rejected with `invalid_role`.

Every successful write records the resolved role and a wall-clock timestamp in `.textus/audit.log`, so reviewers can later distinguish a human edit from an agent edit even though both live in the same file.

#### 5.1.1 Role kinds (engine semantics)

Internally the engine recognizes four **role kinds** — abstract capability
markers — rather than the four default role names. A manifest may declare a
`roles:` block to map any role name to a kind:

```yaml
roles:
  - { name: owner,    kind: accept_authority }
  - { name: compiler, kind: generator }
  - { name: proposer, kind: proposer }
  - { name: fetcher,  kind: runner }
```

Kind allow-list: `accept_authority`, `generator`, `proposer`, `runner`.
At most one role may have `accept_authority`. When `roles:` is declared,
every entry in `zones[*].write_policy` must be a declared role name.

When the `roles:` block is omitted, the default mapping applies:

| Default name | Kind |
|---|---|
| `human`   | `accept_authority` |
| `agent`   | `proposer` |
| `builder` | `generator` |
| `runner`  | `runner` |

This means existing manifests continue to work byte-for-byte. Wire protocol
`textus/3` is unchanged — kinds are an internal-semantics concept and never
appear on the wire.

The promotion DSL predicate `:human_accept` is now `:accept_authority_signed`;
the old symbol works as an alias for backwards compatibility.

### 5.2 Compute layer (derived entries)

Derived entries live in a zone whose `write_policy:` list includes `builder` — `output` in the default scaffold. They are not authored by hand; their body is produced by projecting over other entries. A derived entry declares a `compute:` block with a `kind:` discriminator.

#### 5.2.1 Projection compute (`kind: projection`)

```yaml
- key: output.catalogs.people
  zone: output
  compute:
    kind: projection
    select: working.network.org    # prefix OR [list of prefixes]
    pluck:  [name, relationship, org]
    sort_by: name                  # optional
    limit: 1000                    # default 1000, max 1000
    format: yaml-list-in-md        # one of: list, hash, yaml-list-in-md, json, markdown-table
    transform: rank_by_recency     # optional — names a :transform_rows hook
  template: people.mustache        # optional; if absent, format determines body
```

`select` is either a single dotted-key prefix or a list of prefixes. Every entry whose key starts with one of those prefixes is included. `pluck` names the frontmatter fields to retain in the projection result. `sort_by` is optional; when absent, entries are sorted by key. `limit` is bounded at 1000 entries (hard cap); requests above 1000 are rejected.

`format` controls the body serialization when no template is supplied. Permitted values: `list`, `hash`, `yaml-list-in-md`, `json`, `markdown-table`.

`transform:` (optional) names a registered `:transform_rows` hook (see §5.10). The hook receives the projected rows array and may reorder, filter, or augment before serialization.

If `template` is given, it names a Mustache template under `.textus/templates/`. textus implements a deliberately restricted Mustache subset:

- `{{var}}` — variable interpolation.
- `{{#section}}...{{/section}}` — section (iteration / truthy block).
- `{{^inverted}}...{{/inverted}}` — inverted section.
- `{{!comment}}` — comment.

No partials. No lambdas. No HTML escaping (output is raw text, intended for Markdown). Template recursion depth is bounded at 8; exceeding the limit is an error.

#### 5.2.2 External compute (`kind: external`)

A derived entry that is produced by a build tool *outside* textus — `rake`, `just`, a shell script, anything — declares `compute: { kind: external, ... }`. textus does **not** execute the command (consistent with §2); the external runner is responsible for writing the file. textus records `sources:` so `textus freshness` can compare source mtimes against the derived file's `_meta.generated.at` and report staleness.

```yaml
- key: output.catalogs.skills
  path: output/catalogs/skills.md
  zone: output
  owner: build:catalog-skills
  compute:
    kind: external
    command: "rake catalog:skills"   # informational; the runner invokes it
    sources:                          # dotted keys OR repo-relative paths
      - working.projects
      - working.network
```

**`sources:`** is a list. Each element is either a dotted key prefix (matched against manifest entries) or a filesystem path (relative to the repo root, or absolute). For each key prefix, every matching entry's file mtime is checked. For each path, file or directory mtime is checked.

**`command:`** is recorded in the staleness row's `generator` field but never executed. It exists so `textus freshness` output can carry a hint about how to refresh.

**Freshness contract.** An entry with `compute: { kind: external }` is reported by `textus freshness` as `stale` when:
- The derived file does not exist, OR
- `_meta.generated.at` is missing or unparseable, OR
- Any `sources:` element has been modified after `_meta.generated.at`.

**Frontmatter contract.** The external runner is responsible for writing the `generated:` frontmatter block when it produces the file:

```yaml
generated:
  by: "rake catalog:skills"
  at: "2026-05-25T12:00:00Z"
  from: [working.projects, working.network]
```

`generated.from` SHOULD match `compute.sources` — they're the same list, recorded twice so a diff proves what was actually consumed.

`kind: external` and `kind: projection` are alternatives — exactly one per entry. Templates are not required for `kind: external`: the runner produces the bytes directly.

### 5.3 Publish layer (`publish_to:`)

A derived entry MAY declare `publish_to:` in its frontmatter, listing one or more destination paths relative to the project root:

```yaml
publish_to:
  - CLAUDE.md
  - .ai/instructions.md
```

When the entry is recomputed, textus copies the in-store file byte-for-byte to each destination. The in-store artifact under `.textus/zones/<output-zone>/…` is already the consumer-shaped output (per the format strategy — see §5.x), so publish is a verbatim file copy with no parsing or stripping.

A sentinel is written for each published file at `<store_root>/sentinels/<target-relative-to-repo>.textus-managed.json`, recording `source`, `target`, the target's sha256, and `mode: "copy"`. Sentinels live under the store rather than beside the consumer file so target directories stay clean. The sentinel exists so out-of-band edits can be detected on the next publish — textus refuses to clobber a destination that is not either missing or marked as managed. Legacy sibling sentinels (`<target>.textus-managed.json`) are still recognised as managed and are migrated to the new location on the next publish.

**Per-leaf publishing.** A nested entry MAY declare `publish_each:` instead of `publish_to:` (see §4). When the build runs, every leaf reachable under the nested entry is byte-copied to the path produced by substituting `{leaf}` / `{basename}` / `{key}` / `{ext}` in the template, with a sentinel written under `<store_root>/sentinels/` at the mirrored target path. The build envelope grows a `published_leaves` array — one row per leaf, with `key`, `source`, and `target` — alongside the existing `built` array. Targets that would resolve outside the repo root are refused.

### 5.4 Intake (declared, refreshed via registered intake handler)

Intake entries declare an external source by naming an **intake handler** — a registered, named function that pulls data into the entry. textus itself still makes no implicit network calls: an intake handler only runs when explicitly invoked by `textus refresh KEY --as=runner` (or by `textus refresh stale`). The declaration is data only:

```yaml
- key: intake.calendar.events
  zone: intake
  intake:
    handler: ical-events
    config:
      url: "https://calendar.google.com/.../basic.ics"

rules:
  - match: intake.calendar.**
    refresh:
      ttl: 6h
      on_stale: warn            # warn | sync | timed_sync (default: warn)
      sync_budget_ms: 500       # only used when on_stale: timed_sync (default: 500)
```

`handler` names a registered `:resolve_intake` hook (see §5.10 for the hook contract); `config` is an opaque hash handed to the handler. The freshness budget (`ttl`, `on_stale`, `sync_budget_ms`) lives in a top-level **`rules:`** block matched by key glob (§5.11).

#### `on_stale:` semantics

`on_stale:` declares what happens when `textus get` (or any read path that annotates freshness) encounters a stale intake entry. The value lives on the matching policy block, not on the entry. Vocabulary: `warn | sync | timed_sync`.

| Value | Behaviour |
|---|---|
| `warn` (default) | Return the entry immediately with `stale: true`, `stale_reason:` populated, and `refreshing: false`. No blocking. |
| `sync` | Block the `get` call, run the intake handler in-process, write the refreshed result, then return the fresh envelope. The caller waits. |
| `timed_sync` | Like `sync`, but with a `sync_budget_ms` deadline (default 500 ms). If the handler finishes within the budget the fresh envelope is returned. If it does not finish in time, return the stale envelope (with `stale: true`, `refreshing: true`) and let the refresh complete in the background. Fires `:refresh_backgrounded` when the deadline is exceeded. |

> **Note:** `list`/`where` paths do **not** annotate freshness — only `get` does.

In intake mode the handler MUST return one of three shapes, all normalized by the store into its internal `{_meta, body, content}` representation (§5.12):

- `{ _meta:, body: }` — markdown-friendly; `_meta` becomes the entry's parsed metadata hash.
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content.
- `{ body: }` — raw bytes for `text` or for any format that prefers verbatim writes; the store re-parses and validates per `format:`.

**Built-in intake handlers.** `json`, `csv`, `markdown-links`, `ical-events`, `rss` are always available. They expect raw bytes in `config["bytes"]` and produce structured `_meta`/body. Built-ins do not perform I/O themselves — the caller (or an outer hook) is responsible for supplying bytes.

**Refresh paths.** Two are supported:

1. **In-process** — `textus refresh KEY --as=runner` resolves the entry's `intake.handler`, invokes the registered `:resolve_intake` hook with `(caps:, config:, args: {})`, and writes the result under role `runner`.
2. **External runner** — a cron job or agent harness reads `textus list --zone=intake --stale --output=json`, fetches the source out of band, and pipes bytes back through `textus put KEY --as=runner --stdin`. The CLI verb `textus refresh stale [--prefix=K] [--zone=Z]` drives this loop in one shot.

Both paths share the same role gate, audit-log entry, and `:entry_refreshed` event. User-supplied hooks live in `.textus/hooks/**/*.rb` and auto-load at `Store#initialize` — see §5.10 for the full hook contract.

### 5.5 Pending / accept workflow

Proposal entries are full patches authored into a zone whose `write_policy:` list includes `agent` — `review` in the default scaffold — typically by agents or runners. The entry's frontmatter describes the patch it proposes against another zone:

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

`textus accept <proposal-key>` is **human-only**: the resolved role must be `human`. It copies the patch into the target zone, records provenance (originating proposal key, original role, original timestamp) in the audit log, and removes the proposal entry. Agents and runners can propose but cannot accept.

### 5.6 Audit log

Every successful write appends one compact JSON object (NDJSON) to `.textus/audit.log`. The file is opened with `flock(LOCK_EX)` for the duration of each append so concurrent writers serialize cleanly.

Schema (one JSON object per line, no interior whitespace):

```json
{"seq":<integer>,"ts":"<iso8601-utc>","role":"<role>","verb":"<verb>","key":"<key>","etag_before":<etag-or-null>,"etag_after":<etag-or-null>}
```

`seq` is a monotonic integer counter, auto-incremented on each append. It is the foundation for cursor-based queries: `textus audit --seq-since=N` returns only rows with `seq > N`, and `textus pulse --since=N` builds its `changed` array from the same cursor. When an agent's cursor falls below the oldest available seq (due to log rotation), the operation raises `CursorExpired`.

`ts` is the wall-clock timestamp in UTC with second precision. `role` is the resolved role for the invocation. `verb` is the audit-log payload string identifying the operation (`put`, `delete`, `accept`, `compute`, `mv`, ...). `key` is the affected entry key. `etag_before` and `etag_after` are the entry etags before and after the write, or JSON `null` when not applicable (e.g. create has no before-etag, delete has no after-etag).

For `mv`, the structural fields `from_key`, `to_key`, and `uid` appear at the top level of the JSON object. Remaining verb-specific data (e.g. `from_path`, `to_path`) is nested under an `extras` key. The `extras` key is omitted entirely when empty.

**Rotation.** After every successful append the implementation checks whether `audit.log` exceeds `max_size` bytes (checked inside the held `flock`, so the check sees the post-write size). If it does, the active log is rotated:

1. The seq range (`min_seq`, `max_seq`) of the active log is scanned, and a JSON sidecar (`audit.log.1.meta.json`) is written with those values plus a `rotated_at` ISO 8601 timestamp.
2. Existing rotated files are shifted: `audit.log.(N)` → `audit.log.(N+1)` for N = `keep-1` down to 1 (with their `.meta.json` sidecars).
3. `audit.log` is renamed to `audit.log.1`.
4. The file that would be shifted to `audit.log.(keep+1)` — i.e., `audit.log.keep` and its sidecar — is deleted before the shift.
5. The next append creates a fresh `audit.log` via `O_CREAT`. Seq numbering continues from the previous maximum; there is no reset.

Rotation is triggered by **byte size only** — there is no row-count or time-based trigger.

**Rotation knobs** (configured via the optional `audit:` block in `manifest.yaml`):

| Key        | Default      | Meaning |
|------------|--------------|---------|
| `max_size` | `10485760`   | Maximum size of `audit.log` in bytes (10 MiB) before rotation is triggered. |
| `keep`     | `5`          | Number of rotated files retained on disk. When this limit is exceeded the oldest rotated file and its sidecar are deleted. |

Both keys are optional. Omitting `audit:` entirely uses the defaults above.

**`CursorExpired`.** When `audit --seq-since=N` or `pulse --since=N` is called with a cursor `N`, the implementation checks whether `N` is below the oldest sequence number still available on disk (`min_available_seq`, derived from the oldest retained rotated file's sidecar). The condition that raises `CursorExpired` is:

```
N < min_available_seq - 1
```

The error includes `requested` (the supplied cursor value) and `min_available` (the oldest seq still on disk).

**Recommended caller behavior on `CursorExpired`.** Call `textus boot` (without `--since`) to obtain a fresh `latest_seq` from the current audit log state, then resume `pulse` calls using that new cursor. Do not attempt to replay from an expired cursor — the intervening rows are gone.

### 5.7 Security bounds

textus enforces fixed bounds to keep behavior predictable under hostile or buggy input:

- **Projection result:** 1000 entries (hard cap).
- **Template recursion:** depth 8.
- **Manifest size:** 256 KB.
- **Entry size:** 1 MB.
- **Audit log:** unbounded; rotation is the user's problem.

### 5.8 Schema evolution

Schemas may declare per-field ownership and version history. The `fields:` and `evolution:` blocks are both optional; a schema may omit them and still parse.

**`fields:` block** — keyed by field name. Each entry is an object with at least `type`, plus optional `maintained_by` and any vendor extensions:

```yaml
fields:
  full_name: { type: string, maintained_by: human }
  embedding: { type: array,  maintained_by: agent }
  updated_at: { type: time,  maintained_by: runner }
```

`maintained_by` values are free-form strings. The recognized set is `human | agent | runner | builder | derived`. Unrecognized values do not affect role-authority validation; they pass through unchanged.

**`evolution:` block** — top-level, declares the schema's history and migration intent:

```yaml
evolution:
  added_in: 2026-05-19
  deprecated_at: null
  migrate_from:
    OLD_FIELD: NEW_FIELD
```

`textus schema migrate NAME` consults `evolution.migrate_from` when invoked without `--rename=OLD:NEW`, applying every declared rename across affected entries in one pass. An explicit `--rename` flag overrides the schema-declared map for that invocation.

**Defaults:** when `fields:` and `evolution:` are absent, `schema.maintained_by(field)` returns `nil` for every field and `schema.evolution` returns `{}`.

**Override rule:** the role `human` is permitted to write any `maintained_by` field, regardless of declared owner. This preserves human authority over agent/runner-managed data — humans curating canon over agent-written embeddings is a feature, not a bug. All other role mismatches are reported by `doctor --check=schema_violations` with code `role_authority`, including fields `key`, `field`, `expected`, and `last_writer`.

### 5.9 Row transforms

Row transforms are RPC hooks on the `:transform_rows` event. See §5.10.

### 5.10 Hooks

textus has a single hook registration verb: `Textus.hook { |reg| reg.on(event, name, **opts) { ... } }`. The EVENTS table below defines every extension point. Files in `.textus/hooks/**/*.rb` are `load`ed at `Store#initialize` in alphabetical order by full path; the store-scoped loader drains the queued blocks and invokes each with its own registry.

The subdirectory layout under `hooks/` is organizational only; the registered event and name come from the DSL call, not the file path.

#### Registration DSL

```ruby
# Canonical form — works for every event:
Textus.hook do |reg|
  reg.on(:resolve_intake,  :my_source)              { |caps:, config:, args:, **|  … }
  reg.on(:transform_rows,  :rank_by_recency)         { |caps:, rows:, **|            … }
  reg.on(:validate,        :storage_writable)        { |caps:|                        … }
  reg.on(:entry_put,       :audit, keys: ["working.*"]) { |ctx:, key:, envelope:, **| … }
  reg.on(:file_published,  :git_add, keys: ["derived.*"]) { |ctx:, target:, **| `git add #{target.shellescape}` }
end
```

`Textus.hook` is the sole entry point. The block receives the store's `Hooks::Registry`; `reg.on` is the only registration primitive.

#### Event table

| Event                   | Mode    | Args                                                      | Return                | Failure       |
|-------------------------|---------|-----------------------------------------------------------|-----------------------|---------------|
| `:resolve_intake`       | rpc     | caps:, config:, args:                                     | {_meta:, body:}       | aborts op     |
| `:transform_rows`       | rpc     | caps:, rows:, config:                                     | rows array            | aborts op     |
| `:validate`             | rpc     | caps:                                                     | issues array          | aborts doctor |
| `:entry_put`            | pubsub  | ctx:, key:, envelope:                                     | (discarded)           | logged        |
| `:entry_deleted`        | pubsub  | ctx:, key:                                                | (discarded)           | logged        |
| `:entry_refreshed`      | pubsub  | ctx:, key:, envelope:, change:                            | (discarded)           | logged        |
| `:build_completed`      | pubsub  | ctx:, key:, envelope:, sources:                           | (discarded)           | logged        |
| `:proposal_accepted`    | pubsub  | ctx:, key:, target_key:                                   | (discarded)           | logged        |
| `:file_published`       | pubsub  | ctx:, key:, envelope:, source:, target:                   | (discarded)           | logged        |
| `:entry_renamed`        | pubsub  | ctx:, key:, from_key:, to_key:, envelope:                 | (discarded)           | logged        |
| `:proposal_rejected`    | pubsub  | ctx:, key:, target_key:                                   | (discarded)           | logged        |
| `:store_loaded`         | pubsub  | ctx:                                                      | (discarded)           | logged        |
| `:refresh_started`      | pubsub  | ctx:, key:, mode:                                         | (discarded)           | logged        |
| `:refresh_failed`       | pubsub  | ctx:, key:, error_class:, error_message:                  | (discarded)           | logged        |
| `:refresh_backgrounded` | pubsub  | ctx:, key:, started_at:, budget_ms:                       | (discarded)           | logged        |

The three `:refresh_*` lifecycle events report the progress and failures of background (timed_sync) refreshes.

**`:refresh_started`** fires immediately before an intake handler is invoked. `mode:` is one of `"sync"` or `"timed_sync"`.

**`:refresh_failed`** fires when an intake handler raises. `error_class:` is the exception class name string; `error_message:` is `e.message`.

**`:refresh_backgrounded`** fires when a `timed_sync` refresh exceeds its budget and is handed off to a background thread. `started_at:` is an ISO-8601 UTC string; `budget_ms:` is the configured deadline as an integer.

**Signature invariant** — hooks receive a capability handle as their first keyword argument; the name depends on the mode:

- **RPC hooks** (`rpc` mode) receive `caps:` — a `ReadCaps` or `WriteCaps` slice (`Textus::Application::ReadCaps` / `WriteCaps`). Event-specific kwargs (`config:`, `args:`, `rows:`) follow in the stable order shown in the table above.
- **Pub-sub hooks** (`pubsub` mode) receive `ctx:` — a `Textus::Hooks::Context` that wraps the session and exposes a narrow surface: `get`, `list`, `deps`, `freshness` (reads), `put`, `delete`, `audit` (authorized writes), `publish_followup`, plus `role` and `correlation_id`. The raw `Store` is not handed out.

Declaring `store:` instead of `caps:` in an RPC callable will pass registration but raise `UsageError` at call time (`Hooks::RpcRegistry#invoke` rejects `store:` — there is no shim).

The primary entity is always `key:` (for `:proposal_accepted`, `key:` is the pending key being accepted and `target_key:` is the destination). For `:entry_renamed`, `key:` is present and equals `to_key:` — it is the entry's post-move home, present so `keys:` glob filters route correctly; `from_key:` is the prior key. For `:proposal_rejected`, `key:` is the pending key being rejected. For `:store_loaded`, no key — the event observes store readiness, not an entry.

**RPC mode** — exactly one handler per (event, name). The manifest references the handler by name (`intake.handler: NAME`, `compute.transform: NAME`). Failure or timeout aborts the calling operation.

**Pub-sub mode** — zero or more handlers per event. All matching handlers fire. The `keys:` option restricts a handler to keys matching one of the given globs (`File.fnmatch?` rules). Absence of `keys:` fires on every event of that type. Handler failures and 2s timeouts are logged to `audit.log` as `event_error` rows; they NEVER abort the triggering operation.

Each handler runs under `Timeout.timeout(2)`.

### 5.11 Rules

A manifest MAY declare a top-level `rules:` block — a list of rule blocks matched against entry keys by glob. Each block carries one or more slots:

```yaml
rules:
  - match: intake.**
    refresh: { ttl: 6h, on_stale: warn }

  - match: intake.calendar.**
    refresh: { ttl: 30m, on_stale: timed_sync, sync_budget_ms: 800 }
    intake_handler_allowlist: [ical-events]

  - match: review.**
    promotion:
      requires: [schema_valid, human_accept]
```

**Slots (all optional within a block):**

| Slot | Type | Meaning |
|---|---|---|
| `refresh` | `{ ttl, on_stale, sync_budget_ms }` | Freshness budget for intake entries. `on_stale` is `warn` (default), `sync`, or `timed_sync`. |
| `intake_handler_allowlist` | list of strings | Constrains which `intake.handler:` names may be used by entries matched by this block. Enforced by `textus doctor`. |
| `promotion` | `{ requires: [...] }` | Predicates a `review` entry must satisfy before `textus accept` will promote it. Built-in predicates: `schema_valid` (entry passes schema validation) and `human_accept` (the accepting role must be `human`). Additional predicates may be registered via `:validate` hooks. Enforced — `textus accept` refuses if any predicate fails. |
| `retention` | (reserved) | Slot reserved for future retention policy (cap by age / count). Implementations parse it but otherwise ignore. |

**Match grammar.** `match:` is a single glob using `*` (single segment) and `**` (any depth). A literal segment ranks more specifically than `*`; `*` ranks more specifically than `**`.

**Resolution.** For each key textus computes a `RuleSet { refresh, intake_handler_allowlist, promotion, retention }` by walking every block whose `match` matches the key, ranked by specificity. **Per slot, the most specific block wins.** Two blocks of equal specificity that match the same key and fill the same slot is a manifest error reported by `textus doctor` (`rule_ambiguity`).

**Read surface.** `textus rule list` dumps every block. `textus rule explain KEY` shows the resolved `RuleSet` for one key plus which block won each slot.

### 5.12 Storage formats

An entry's `format:` selects a storage strategy. All strategies expose the same `parse(bytes) → {_meta, body, content}` and `serialize(meta:, body:, content:) → bytes` contract. The store, audit, etag, and projection layers operate on the parsed shape; only (de)serialization differs.

- **markdown** — YAML frontmatter between `---` fences, free-form body. Parse: Psych `safe_load` on the frontmatter block; body is the remainder. Serialize: emit `---\n<yaml>\n---\n<body>`. `content` is always `nil`. `_meta` holds the parsed frontmatter hash.
- **json** — entire file is a JSON document. Parse: `JSON.parse`. Serialize: `JSON.pretty_generate(content)` + trailing newline. `_meta` is populated from the top-level `_meta` hash (if present, else `{}`); `body` is the raw bytes; `content` is the parsed object with `_meta` stripped.
- **yaml** — entire file is a YAML mapping. Parse: `YAML.safe_load(bytes, permitted_classes: [Date, Time], aliases: false)`; anchors/aliases rejected. Serialize: `YAML.dump(content).sub(/\A---\n/, "")`. Same `_meta` / `body` / `content` rules as JSON.
- **text** — raw UTF-8 bytes. Parse: body is the file verbatim, `_meta` is `{}`, `content` is `nil`. Serialize: write `body` bytes (with trailing newline if missing).

**Envelope shape.** Every envelope carries `format:` (always present, defaults to `markdown` for back-compat). For `json|yaml`, the envelope additionally carries `content:` (parsed object). `body` is always the raw on-disk bytes. `_meta` always exists in the envelope: for `markdown` it holds the parsed YAML frontmatter; for `json|yaml` it mirrors the top-level `_meta` block (`{}` if absent); for `text` it is `{}`.

**`_meta` convention.** Derived structured entries (json, yaml) embed a `_meta` hash as the first top-level key. Builder-injected keys appear in a fixed order for etag stability:

```
generated_at, from, template, transform
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

Every successful CLI response (`--output=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/3",
  "key": "working.network.org.jane",
  "zone": "working",
  "owner": "textus:network",
  "path": "/absolute/path/to/.textus/zones/working/network/org/jane.md",
  "format": "markdown",
  "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body in Markdown.\n",
  "etag": "sha256:8f3c…",
  "schema_ref": "person",
  "uid": "a1b2c3d4e5f60718",
  "stale": false,
  "stale_reason": null,
  "refreshing": false
}
```

**Field rules:**
- `protocol` MUST be the exact string `textus/3`.
- `key` MUST be the canonical resolved key.
- `zone` MUST be one of the zones declared in the manifest (`identity`, `working`, `intake`, `review`, `output` in the default scaffold).
- `path` MUST be an absolute filesystem path.
- `format` MUST be one of `markdown`, `json`, `yaml`, `text` (§5.12). Absent envelopes are treated as `markdown` for back-compat.
- `body` is the raw on-disk bytes as a UTF-8 string for every format.
- `content` is present only when `format` is `json` or `yaml`; equals the parsed object. For `json|yaml`, `_meta` mirrors the top-level `_meta` block (or `{}` if absent). For `markdown`, `_meta` holds the parsed YAML frontmatter. For `text`, `_meta` is `{}`.
- `etag` MUST be `sha256:<hex>` of the raw file bytes, computed identically for every format.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.
- `uid` is the stable Textus UID (§7) if the entry carries one, else `null`. Always present in the envelope.
- `stale` is `true` when the entry's TTL has elapsed and the data has not yet been refreshed; `false` otherwise. Only populated for entries matched by a `refresh:` rule slot (typically `intake` zone); always `false` elsewhere.
- `stale_reason` is a short human-readable string describing why the entry is stale (e.g. `"ttl_exceeded"`, `"never_refreshed"`), or `null` when `stale` is `false`.
- `refreshing` is `true` when a `timed_sync` background refresh is in flight for this entry; `false` otherwise. Callers observing `stale: true, refreshing: true` SHOULD retry after a short delay.

> **Note:** `list`/`where` envelopes do **not** include `stale`, `stale_reason`, or `refreshing` — freshness annotation is only provided by `get`.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/3",
  "ok": false,
  "code": "write_forbidden",
  "message": "zone 'identity' is not writable by role 'agent' for key 'identity.self'",
  "details": { "key": "identity.self", "zone": "identity", "role": "agent" }
}
```

**Error codes:**

| Code | Meaning | Default exit |
|---|---|---|
| `unknown_key` | Key does not resolve | 1 |
| `bad_frontmatter` | YAML parse failed or `name:` mismatch | 1 |
| `schema_violation` | Required field missing or wrong type | 1 |
| `write_forbidden` | Resolved role is not in the zone's `write_policy` | 1 |
| `etag_mismatch` | Concurrent write detected | 1 |
| `io_error` | Filesystem failure | 64 |
| `usage` | CLI argument error | 2 |

## 9. CLI surface

The reference binary is `textus`. Conforming implementations MAY use any binary name; the protocol is in the JSON.

All verbs accept `--output=json` and emit a canonical envelope (success or error). Write verbs require `--as=<role>`; the role must satisfy the target zone's write gate (§5). The per-entry `format:` field in the manifest is unchanged — `--output` controls only the CLI envelope rendering.

| Verb | Reads / writes | Role required |
|---|---|---|
| `list [--prefix=K] [--zone=Z]` | read | any |
| `where K` | read | any |
| `get K` | read | any |
| `schema show K` | read | any |
| `freshness [--prefix=K] [--zone=Z]` | read | any |
| `audit [--key=K] [--zone=Z] [--role=R] [--verb=V] [--since=X] [--correlation-id=ID] [--limit=N]` | read | any |
| `blame KEY` | read | any |
| `rule list` / `rule explain KEY` | read | any |
| `deps K` / `rdeps K` | read | any |
| `published` | read | any |
| `hook list` | read | any |
| `hook run NAME` | write | any |
| `doctor [--check=NAME[,NAME]] [--output=json]` | read | any |
| `boot [--output=json]` | read | any |
| `pulse [--since=N]` | read | any |
| `put K --stdin --as=R [--fetch=NAME]` | write | per zone |
| `delete K --if-etag=E --as=R` | write | per zone |
| `refresh KEY --as=runner` | write | per zone (typically `runner`) |
| `refresh stale [--prefix=K] [--zone=Z] [--as=runner]` | write | per zone (typically `runner`) |
| `build [--prefix=K] [--dry-run]` | write | `builder` (default) |
| `accept K --as=human` | write | `human` |
| `init` | write | `human` |
| `schema {show,init,diff,migrate}` | read/write | `human` for writes |
| `key mv OLD NEW [--as=R] [--dry-run]` | write | per zone (same-zone only) |
| `key uid K` | read | any |

**`textus boot` envelope extras.** In addition to zones, entries, hooks, write flows, and the `cli_verbs` catalog, the boot envelope includes an `agent_quickstart` block synthesized from the manifest's role-kind declarations:

```json
{
  "agent_quickstart": {
    "read_verbs":     ["boot", "get", "list", "audit", "pulse", "freshness", "doctor"],
    "write_verbs":    ["put KEY --as=<proposer-role> --stdin"],
    "writable_zones": ["review"],
    "propose_zone":   "review",
    "latest_seq":     1842
  }
}
```

`latest_seq` is the current high-water mark of the audit log; agents should use it as the starting cursor for `pulse`.

**`textus pulse` output shape:**

```json
{
  "cursor":         1845,
  "changed":        [ { "seq": 1843, "key": "working.x", "verb": "put", "role": "human", "ts": "..." } ],
  "stale":          [ "output.marketplace" ],
  "pending_review": [ "review.proposal.123" ],
  "doctor":         { "ok": true, "warn": 0, "fail": 0 }
}
```

`cursor` is the new high-water mark; pass it as `--since` on the next call. `changed` is sourced from `audit --seq-since`. `stale` is sourced from `freshness`. `pending_review` lists all keys in the review zone. `doctor` is an `{ok, warn, fail}` count summary. When `--since` is below the oldest available seq (due to audit log rotation), pulse returns `CursorExpired`.

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body.\n",
  "if_etag": "sha256:8f3c…" }
```

`if_etag` is optional on `put`, required on `delete`. When provided, the write fails with `etag_mismatch` if the on-disk file's etag differs. When omitted on `put`, the write is unconditional (last-writer-wins).

**`textus freshness` output shape:**

```json
{
  "verb": "freshness",
  "rows": [
    { "key": "intake.upstream.notes",
      "zone": "intake",
      "last_refreshed_at": "2026-05-21T13:21:17Z",
      "age_seconds": 65000,
      "ttl_seconds": 43200,
      "on_stale": "warn",
      "status": "stale",
      "next_due_at": "2026-05-22T01:21:17Z" }
  ]
}
```

Each row reports one entry's verdict (`fresh`, `stale`, `never_refreshed`, or `no_policy`) against its matched `refresh:` rule. `textus build` consumes its own staleness signal and executes derived entries' projections under the `builder` role; `--dry-run` prints the plan without executing.

`textus accept K --as=human` promotes a pending entry into its target zone: it copies the patch body into the target key, deletes the pending entry, and writes one audit line per side (§audit). Only the `human` role may invoke `accept`.

`textus init` scaffolds a fresh `.textus/` tree (manifest, zones, schemas, audit log) under the current directory with a default manifest. Customize by editing `.textus/manifest.yaml` after init.

`textus schema show K` prints the schema for entry `K`. `textus schema init NAME` writes a stub schema. `textus schema diff NAME` compares the on-disk schema against entries that claim it and prints the deltas. `textus schema migrate NAME --rename=OLD:NEW` rewrites the `_meta` key `OLD` to `NEW` across every entry that uses the named schema, in a single transactional sweep that logs each touched file.

## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.

## 10.1 Errors carry hints

Every `Textus::Error` exposes `code`, `message`, and an optional `hint:`. The hint is a single short string suggesting the next action — the file to edit, the role to pass, the command to run. Errors in the wire envelope include the hint as a top-level `hint:` field when present. The CLI prints failures to stderr as `code: message` followed by `  → hint` (when a hint exists), in addition to the JSON envelope on stdout. Hints are advisory: implementations MAY omit or rephrase them without breaking conformance.

## 10.2 `textus doctor`

`textus doctor` returns a health-check envelope: `{ "protocol": "textus/3", "ok": bool, "issues": [...], "summary": {error, warning, info} }`. Each issue carries `code`, `level` (`error|warning|info`), `subject`, `message`, and optionally `fix`. `ok` is true iff no error-level issues are present; warnings and info do not flip the bit. Builtin checks: `manifest_files`, `schemas`, `schema_parse_error`, `templates`, `hooks`, `illegal_keys`, `sentinels`, `audit_log`, `unowned_schema_fields`, `schema_violations`, `rule_ambiguity`, `intake_handler_allowlist`. Additional registered `:validate` hooks (§5.10) run after the builtin set. Exit code is 0 on `ok`, 1 otherwise.

## 11. Versioning

- The current wire string is `textus/3`.
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/3`.
- Breaking changes (renamed/removed envelope fields, zone semantics, key grammar) require a new wire string `textus/4`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently and speaks `textus/3`.

## 11.1 Agent integration

Agents interact with a textus store through two verbs: `boot` (once per session, for orientation) and `pulse` (per turn, for deltas). The `boot` envelope's `agent_quickstart` block gives the agent its starting cursor (`latest_seq`), its writable zones, and its propose zone. The `pulse` verb returns a delta envelope keyed on that cursor. When audit log rotation expires a cursor, `CursorExpired` signals the agent to call `boot` again.

For the full boot → pulse loop with pseudocode and cursor-expiry handling, see [`docs/agent-integration.md`](docs/agent-integration.md).

## 12. Conformance fixtures

A conformant implementation MUST pass these fixtures (the reference test suite ships a YAML file listing inputs and expected envelopes):

**Fixture A — Resolve and read:**
Given a manifest with `working.network.org` → `working/network/org` (nested), schema `person`, and a file `.textus/zones/working/network/org/jane.md` with valid frontmatter, `textus get working.network.org.jane --output=json` returns the canonical envelope with `etag` matching the file's sha256.

**Fixture B — Role gate on write:**
Given a manifest entry where `key: identity.self` lives in the `identity` zone (human-only), `textus put identity.self --stdin --as=agent` (with any valid input) returns the error envelope with `code: "write_forbidden"` and exit code 1.

**Fixture C — Schema violation:**
Given the `person` schema and a `put` whose frontmatter omits `relationship`, the result is the error envelope with `code: "schema_violation"`, `details.missing: ["relationship"]`, and exit code 1.

**Fixture D — Staleness detection:**
Given a manifest entry `intake.notes` matched by a `rules: [{ match: intake.notes, refresh: { ttl: 1h } }]` block and an envelope on disk whose `_meta.last_refreshed_at` is older than `now - ttl`, `textus freshness --output=json` includes a row for `intake.notes` with `status: "stale"`. Calling `textus freshness` does NOT trigger a refresh.

**Fixture E — Projection build:**
Given a manifest entry `derived.catalogs.skills` whose `compute: { kind: projection }` clause selects fields from `working.projects` entries, `textus build derived.catalogs.skills` materializes the derived entry on disk with frontmatter and body matching the projected shape, and updates `generated.at` to the build timestamp.

**Fixture F — Mustache render:**
Given a derived entry with a `template` clause referencing a `.mustache` file and inputs drawn from other keys, `textus build` produces a body whose contents match the expected rendered output byte-for-byte (after trailing-newline normalization).

**Fixture G — Copy publish:**
Given a manifest entry with `publish_to: <path>`, a successful `textus build` for that entry leaves a plain file at `<path>` whose contents are byte-identical to the in-store artifact at `.textus/zones/<...>`, accompanied by a sentinel at `.textus/sentinels/<path>.textus-managed.json` recording `source`, `target`, `sha256`, and `mode: "copy"`. Re-running `build` is idempotent.

**Fixture H — Audit log format:**
Every successful write verb (`put`, `delete`, `build`, `accept`, `schema migrate`) appends exactly one line per affected key to the audit log, in the canonical format defined in §audit (timestamp, actor role, verb, key, etag-before, etag-after). No write produces zero or multiple lines per key.

**Fixture I — Pending → accept:**
Given a review entry `review.identity.self.patch` proposing a change to `identity.self`, `textus accept identity.self --as=human` copies the patch body into `identity.self`, deletes the review entry, and appends two audit lines (one for the identity write, one for the review delete) in that order.

## 13. Why not X?

- **Why not MCP?** MCP is a transport; textus is a data model. The two compose: a 50-line MCP server can wrap `textus get/put` as tools. textus exists because the *shape* of agent-readable project memory deserves a standalone spec, separate from how it's served.

- **Why doesn't textus execute generator commands itself?** textus is a dataflow oracle, not a build runner. The moment a spec includes process execution, it inherits shell-injection surface, OS-portability concerns, and signal-handling semantics — and ends up duplicating whatever build system the consumer already runs (make, rake, just, lefthook, CI). Keeping execution external means a Python or TypeScript port of `textus/3` only has to parse YAML and emit JSON; it doesn't have to spawn processes safely. Build runners stay the executor; textus stays a data tool.

- **Why not plain Markdown vaults (Obsidian / Foam)?** No schema enforcement, no write-gating, no addressable wire format. Fine for human notes; underspecified for agents that must act on the contents deterministically.

- **Why not Notion / Coda?** Closed, hosted, lossy export. textus is local-first, plain-files, diffable in git.

- **Why not JSON Schema for the schemas?** Considered. Bespoke YAML chosen for v1: simpler implementation, lighter dependency footprint, matches the reference impl's house language. JSON Schema MAY be added as an alternate schema-language adapter in a future minor revision without breaking `textus/3`.

- **Why not a database (SQLite, kv store)?** textus's whole point is that the storage is plain files agents and humans both read. A binary store loses git-diff, grep, and editor support.

- **Why not vector embeddings?** Different problem. textus is for facts agents act on deterministically; embeddings are for fuzzy retrieval. They compose — index a textus tree into a vector store if you need both.

## 13.1 Layered architecture (internal)

Textus internals are organized into four layers. The dependency rule is one-way — each layer may only import from the layer beneath it.

- **Interface** (`lib/textus/cli/`, `lib/textus/mcp/`) — CLI verbs and the MCP gate. Parses flags / RPC, calls a use case, formats JSON.
- **Application** (`lib/textus/application/`) — Use cases: `Read::Get`, `Write::Put`, `Write::RefreshWorker`, `Write::RefreshOrchestrator`, `Write::RefreshAll`, `Maintenance::Migrate`, etc. Orchestrate domain + infra; no business rules.
- **Domain** (`lib/textus/domain/`) — Pure values: `Authorizer`, `Permission`, `Freshness::{Policy,Verdict,Evaluator}`, `Action`, `Outcome`, `Sentinel`, `Staleness`. No I/O, no globals, testable without disk.
- **Infrastructure** (`lib/textus/infra/`) — Adapters: `Storage::FileStore`, `AuditLog`, `AuditSubscriber`, `Publisher`, `Clock`, `Refresh::Lock`, `Refresh::Detached`, `BuildLock`. Wrap OS / library primitives.

The `lib/textus/store/`, `lib/textus/manifest/`, `lib/textus/hooks/` namespaces are infrastructure adapters that predate this split and remain at their existing paths for backward-compat with the plugin DSL.

Plugin authors interact only with the Hook DSL (`Textus.hook { |reg| reg.on(:resolve_intake, ...) }`, `reg.on(:entry_refreshed, ...)`, etc.) and the manifest YAML schema. The layering is internal and may evolve.

Both read and write paths flow through the application layer:

- **Reads** flow through `Application::Read::Get` (pure read + freshness annotation) or `Read::GetOrRefresh` (composes Get with `Write::RefreshOrchestrator`). Each takes a `caps:` slice and an `Application::Context`.
- **Writes** flow through `Application::Write::{Put,Delete,Mv,Accept,Reject,Publish,RefreshWorker}`. Permission checks happen at the use-case layer (via `Domain::Authorizer#authorize_write!`); the audit-append invariant lives in `Application::Envelope::Writer`.
- `Application::Context` is the slim request record: `role`, `correlation_id`, `now`, `dry_run`. Ports come from a `Caps` record (Read/Write/Hook), not from the Context.
- `Textus::Session` is the factory CLI verbs and the MCP gate use to dispatch
  use cases. `Session.for(store, role:)` returns a per-call object exposing one
  method per registered use case (`#put`, `#get`, `#refresh`, …); methods are
  generated from `Application::UseCase.entries` so adding a use case is a
  single `UseCase.register(...)` line.

See `ARCHITECTURE.md` for an ASCII diagram and the full read-path walkthrough.

## 14. Open questions (v3.x scope)

- **Locking on `put`:** the reference impl uses sha256 etags. Should the spec also define a file-lock fallback for systems where read-before-write is racy?
- **Schema imports:** can one schema reference another (`type: $ref: person`)?
- **Internationalization:** non-ASCII in keys? Spec currently restricts segments to `[a-z0-9][a-z0-9-]*`. Revisit if community wants Unicode.
- **Generated content in `derived/`:** the spec says `schema: null` is allowed, but should there be a separate marker (`generated: true`) for clarity?

## 15. Implementation checklist

A `textus/3` implementation MUST:

- [ ] Parse `.textus/manifest.yaml` and accept `version: textus/3`.
- [ ] Resolve keys via longest-prefix match against manifest entries.
- [ ] Read `_meta` + body from `.md` files; validate against the named schema.
- [ ] Read `_meta` from the top-level `_meta` hash in `.json` / `.yaml` files; validate against the named schema.
- [ ] Compute `sha256:<hex>` etags over raw file bytes.
- [ ] Refuse writes whose resolved role is not in the target zone's `write_policy` list with `write_forbidden`.
- [ ] Return envelopes matching the shape in §8 exactly (with `_meta`, not `frontmatter`).
- [ ] Use the error codes in §8 and the exit-code table.
- [ ] Implement `textus freshness` per §5.1 and §9, walking each entry, matching it against the top-level `rules:` block, and reporting `fresh|stale|never_refreshed|no_policy` without invoking any refresh.
- [ ] Pass the conformance fixtures A–I in §12.

A `textus/3` implementation MAY:

- Add additional CLI verbs (e.g. `move`, vendor-specific reporters) beyond the current set in §9.
- Provide alternate output formats (`--output=yaml`, `--output=table`) for human use.
- Support additional schema field types beyond §6, marked as `vendor:<name>` extensions.

## 16. Migrating from textus/2

textus 0.12.0 does not ship a built-in migrator. Upgrade path:

1. Install textus **0.11.x** first.
2. Run `textus migrate --to=textus/3` (available in 0.11.x only). This rewrites `manifest.yaml`, renames the `inbox/` zone directory to `intake/`, sweeps frontmatter `owner:` fields, writes an audit-log marker, and reports legacy hook-DSL call sites for manual review.
3. Upgrade to textus **0.12.0**.
4. If `.textus/audit.log` contains pre-0.11.0 rows with `role: ai|script|build`, run `textus audit-rewrite-legacy-roles` once (one-shot verb; removed in 0.13.0).

**textus doctor refuses textus/2 stores.** The doctor check `protocol_version` emits an `error`-level issue when `manifest.yaml` carries `version: textus/2`. Install 0.11.x and migrate before upgrading to 0.12.0.

**Vocabulary summary** (textus/2 → textus/3 rename table, for reference):

| Category | textus/2 | textus/3 |
|---|---|---|
| Actor | `ai` | `agent` |
| Actor | `script` | `runner` |
| Actor | `build` | `builder` |
| Zone | `inbox` | `intake` |
| Manifest | `writable_by:` | `write_policy:` |
| Manifest | `policies:` | `rules:` |
| Manifest | `handler_allowlist:` | `intake_handler_allowlist:` |
| Manifest | `promote_requires:` | `promotion: { requires: [...] }` |
| Manifest | `projection:` | `compute: { kind: projection, ... }` |
| Manifest | `generator:` | `compute: { kind: external, ... }` |
| Hook event | `:intake` | `:resolve_intake` |
| Hook event | `:reduce` | `:transform_rows` |
| Hook event | `:check` | `:validate` |
| Hook event | `:put` | `:entry_put` |
| Hook event | `:deleted` | `:entry_deleted` |
| Hook event | `:refreshed` | `:entry_refreshed` |
| Hook event | `:built` | `:build_completed` |
| Hook event | `:accepted` | `:proposal_accepted` |
| Hook event | `:reject` | `:proposal_rejected` |
| Hook event | `:published` | `:file_published` |
| Hook event | `:mv` | `:entry_renamed` |
| Hook event | `:loaded` | `:store_loaded` |
| Hook event | `:refresh_began` | `:refresh_started` |
| Hook event | `:refresh_detached` | `:refresh_backgrounded` |
| Hook event | `:refresh_failed` | `:refresh_failed` (unchanged) |
| Hook DSL | `Textus.hook(ev, name)` / sugar | `Textus.on(ev, name)` |
| Compute field | `projection.reduce:` | `compute.transform:` |
| `_meta` key | `reducer` | `transform` |
| CLI flag | `--format=json` (envelope) | `--output=json` |
| CLI verb | `refresh-stale` | `refresh stale` |
| CLI verb | `policy list/explain` | `rule list/explain` |

**Notes on hook migration.** The 0.11.x migrator scanner reports each file and call site that uses a legacy event name or DSL method. No automatic rewrite is performed. Update each hook to use `Textus.on(:new_event_name, ...)` before re-enabling the hook. See CHANGELOG §0.11.0 for the full event rename table.

---

**Spec word count target:** <2700 words (allowance widened to fit vocabulary axes intro + migration section).
**Reviewed against community-testing checklist (idea file §"Community-testing"):** ✅ implementable in a day in TS/Python (four concepts: manifest, schema, envelope, staleness check); ✅ conformance fixtures A–I; ✅ "Why not X?" section present (incl. why no execution); ✅ name picked.
