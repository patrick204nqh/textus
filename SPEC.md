# textus/3 — Specification

**Status:** Draft v3.0
**Protocol identifier:** `textus/3`
**Reference implementation:** Ruby gem `textus`

> *textus* — Latin for "the fabric a text is woven from," same root as *context* (from *con-texere*, "to weave together"). This spec defines a storage shape and wire protocol for that fabric.

---

## Table of contents

- [Conventions](#conventions)
- [1. What textus is](#1-what-textus-is)
  - [1.1 Vocabulary axes](#11-vocabulary-axes)
  - [1.2 The five layers](#12-the-five-layers)
- [2. Goals and non-goals](#2-goals-and-non-goals)
- [3. Storage layout](#3-storage-layout)
  - [3.1 Store location precedence](#31-store-location-precedence)
- [4. Manifest](#4-manifest)
- [5. Zones and capability-based write gates](#5-zones-and-capability-based-write-gates)
  - [5.1 Role resolution](#51-role-resolution)
    - [5.1.1 Capabilities](#511-capabilities)
  - [5.2 Compute layer (derived entries)](#52-compute-layer-derived-entries)
    - [5.2.1 Projection compute](#521-projection-compute-kind-projection)
    - [5.2.2 External compute](#522-external-compute-kind-external)
  - [5.3 Publish layer](#53-publish-layer-publish)
  - [5.4 Intake](#54-intake-declared-fetched-via-registered-intake-handler)
  - [5.5 Pending / accept workflow](#55-pending--accept-workflow)
  - [5.6 Audit log](#56-audit-log)
  - [5.7 Security bounds](#57-security-bounds)
  - [5.8 Schema evolution](#58-schema-evolution)
  - [5.9 Row transforms](#59-row-transforms)
  - [5.10 Hooks](#510-hooks)
  - [5.11 Rules](#511-rules)
  - [5.12 Storage formats](#512-storage-formats)
- [6. Schemas](#6-schemas)
- [7. Entry file format](#7-entry-file-format)
- [8. Envelope (the wire format)](#8-envelope-the-wire-format)
- [9. CLI surface](#9-cli-surface)
- [10. ETag semantics](#10-etag-semantics)
  - [10.1 Errors carry hints](#101-errors-carry-hints)
  - [10.2 `textus doctor`](#102-textus-doctor)
- [11. Versioning](#11-versioning)
  - [11.1 Agent integration](#111-agent-integration)
- [12. Conformance fixtures](#12-conformance-fixtures)
- [13. Why not X?](#13-why-not-x)
  - [13.1 Layered architecture (internal)](#131-layered-architecture-internal)
- [14. Open questions (v3.x scope)](#14-open-questions-v3x-scope)
- [15. Implementation checklist](#15-implementation-checklist)
- [16. Migrating from textus/2](#16-migrating-from-textus2)
  - [16.1 Breaking changes in 0.31.0 (capability-based roles)](#161-breaking-changes-in-0310-capability-based-roles)
  - [16.2 Breaking changes in 0.33.0 (workspace/keep + Setup-1 scaffold)](#162-breaking-changes-in-0330-workspacekeep--setup-1-scaffold)
  - [16.3 Breaking changes in 0.35.0 (proposal target-canon + `author_held`)](#163-breaking-changes-in-0350-proposal-target-canon--author_held)

---

## Conventions

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this
document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119)
and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174): with their normative
meaning **only** when they appear in uppercase. The same words in lowercase
carry their ordinary English sense and impose no requirement.

Requirements are stated against any **conforming implementation** of the
`textus/3` protocol. The Ruby gem `textus` is the reference implementation, but
the contract is the protocol defined here — not the gem. Where this document and
the implementation disagree, this document is the source of truth and the
implementation is the bug.

---

## 1. What textus is

A storage convention and JSON wire protocol for humans, agents, and automation to read and write structured project memory **deterministically**. It provides addressable dotted keys, schema validation, capability-based write gates, declarative compute, and copy-based publish targets.

The storage lives in a `.textus/` directory at the project root. Each entry is a Markdown file with YAML frontmatter. A manifest binds dotted keys to subtrees, declares the capabilities each role holds, and declares each zone's kind — write authority for a zone is derived from the role's capabilities and the zone's kind. Schemas (also YAML) define what frontmatter shape each entry must have. Derived entries are computed from other entries via pure projections and a vendored Mustache template engine, then optionally published to repo-relative paths as byte-for-byte file copies. The CLI surface (`textus get/put/list/where/schema/build/...` `--output=json`) returns a versioned envelope any caller can parse without knowing Markdown.

You **shape your own memory structure** inside `.textus/`. The protocol manages how it's read, written, addressed, validated, gated, computed, and published. The contents are entirely yours.

### 1.1 Vocabulary axes

textus/3 names its concepts along six axes. Reviewers who internalize these can map any part of the spec to the right category:

- **Actor** — who is interacting: roles such as `human`, `agent`, `automation`, each holding a set of capabilities (`propose`, `author`, `keep`, `fetch`, `build`).
- **Place** — where data lives: zones such as `knowledge`, `notebook`, `feeds`, `proposals`, `artifacts`.
- **Thing** — what is stored: entries, fields, keys.
- **Operation** — how you act on things: RPC and CLI verbs (`get`, `put`, `fetch`, `build`, …).
- **Event** — what gets fired after an operation: hook event names, split into RPC events (`:resolve_intake`, `:transform_rows`, `:validate`) and pub-sub events (`:entry_put`, `:build_completed`, …).
- **Rule** — constraints declared in the top-level `rules:` array of the manifest.

### 1.2 The five layers

textus is organized as five composable layers. Each layer has a single responsibility; later layers build on earlier ones.

| Layer | Name | Responsibility |
|---|---|---|
| L1 | **Store** | Plain-file backend: `.textus/zones/<zone>/...` with YAML frontmatter + Markdown body, addressed by dotted keys, schema-validated, etag-versioned. |
| L2 | **Sources** | Declared external inputs (the `feeds` zone in the default scaffold; any `quarantine` zone, writable by a role with `fetch`): URLs, files, feeds with declared parsers and TTLs. textus *describes* sources; external automation fetches and pipes results through `textus put`. |
| L3 | **Compute** | Pure transforms from store entries to derived entries. Projections (select/pluck/sort/limit/format) plus a vendored Mustache template subset. No shell execution. |
| L4 | **Publish** | Byte-for-byte file copy from derived entries to repo-relative paths declared via `publish: { to: [...] }`. The in-store artifact is the consumer-shaped output; the published file is an identical copy. A sentinel under `.textus/.run/sentinels/<target-rel-path>.textus-managed.json` (git-ignored runtime state) records the source, sha256, and `mode: "copy"`. |
| L5 | **Consumers** | Anything that reads the published files or calls the CLI — editors, LLM tools, MCP servers, CI jobs, dashboards. textus is agnostic about who consumes; the envelope is the contract. |

## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/3`) any language can speak.
- Deterministic read/write of structured Markdown via a CLI returning JSON.
- Schema-validated frontmatter using YAML schemas as data.
- Capability-based write gates (roles hold capabilities; write authority per zone is derived from the role's capabilities and the zone's kind).
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
- Not a fetcher. textus declares sources; external automation invokes actions to materialize them.
- Not an executor. textus computes pure projections but never spawns shell commands.

## 3. Storage layout

The root is `.textus/` at the project working directory. A typical tree:

```
.textus/
  manifest.yaml          # internal: key → subtree mapping + role/zone declarations
  audit.log              # internal, append-only NDJSON log of every successful write
  schemas/               # internal: YAML schema files
  templates/             # internal: Mustache templates referenced by derived entries
  hooks/                 # internal: one Ruby file per hook
  .run/sentinels/        # runtime (git-ignored): byte-copied publish bookkeeping, regenerated on build (see §5.3)
  zones/                 # ALL user content lives here
    knowledge/           # zone: knowledge (kind: canon — author-holders write; knowledge.identity.* is the identity convention)
    notebook/            # zone: notebook (kind: workspace — keep-holders write; agent's own durable lane)
    feeds/               # zone: feeds (kind: quarantine — fetch-holders write)
    proposals/           # zone: proposals (kind: queue — propose-holders write)
    artifacts/           # zone: artifacts (kind: derived — build-holders write)
```

Textus internals (`manifest.yaml`, `schemas/`, `templates/`, `hooks/`) live directly under `.textus/`; disposable runtime state (the audit log, publish `sentinels/`, fetch/build locks, pulse cursors) lives under `.textus/.run/` (git-ignored, ADR 0038/0070). **All user content lives under `.textus/zones/`.** Manifest `path:` fields are relative to `.textus/zones/` — they do **not** include the `zones/` prefix. Implementations MUST prepend `zones/` to every `path:` when resolving a key to a filesystem location.

Zone directories under `zones/` are conventional; their write semantics are derived from the zone's declared `kind:` (and the capabilities roles hold), not the directory name.

`.textus/audit.log` is an append-only NDJSON file written under a file lock by every successful `put`, `delete`, `accept`, and `build`. `.textus/role` (one line containing a role name) is optional and participates in the role-resolution order (§5).

### 3.1 Store location precedence

Implementations MUST resolve the store root in this order; the first match wins:

1. `--root <path>` flag passed to the CLI (or `root:` kwarg to `Store.discover`).
2. `TEXTUS_ROOT` environment variable.
3. Walk up from cwd looking for a `.textus/` directory containing `manifest.yaml`.

When (1) or (2) names a path that has no `manifest.yaml`, the CLI exits with `io_error` and a message naming the resolved absolute path. When (3) reaches the filesystem root without finding a store, the CLI exits with `io_error` naming the search start point.

## 4. Manifest

The manifest declares: (a) which roles exist and the capabilities each holds, (b) which zones exist and each zone's `kind:`, (c) the key-to-subtree mapping, (d) the schema applied to entries in each subtree, and (e) the owner string recorded in writes. Write authority is **derived** — a role may write a zone iff it holds the capability the zone's kind requires (§5).

```yaml
# .textus/manifest.yaml
version: textus/3

roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose] }
  - { name: automation, can: [fetch, build] }

zones:
  - name: knowledge
    kind: canon
  - name: notebook
    kind: workspace
    owner: agent              # optional, informational — agent's own lane
    desc: "agent's durable working memory; bytes climb to knowledge only via propose→accept"
  - name: feeds
    kind: quarantine
  - name: proposals
    kind: queue
  - name: artifacts
    kind: derived

entries:
  - key: knowledge.identity.self
    path: knowledge/identity/self.md
    zone: knowledge
    schema: identity

  - key: knowledge.network.org
    path: knowledge/network/org
    zone: knowledge
    schema: person
    owner: human:network
    nested: true

  - key: artifacts.catalogs.people
    path: artifacts/catalogs/people.md
    zone: artifacts
    schema: null
    owner: automation:build

rules:
  - match: feeds.**
    lifecycle: { ttl: 6h, on_expire: warn }

audit:
  max_size: 10485760   # bytes before rotating (default: 10 485 760 = 10 MiB)
  keep: 5              # rotated files to retain (default: 5)
```

Zone names are conventional — write authority comes from each zone's declared `kind:` crossed with the capabilities roles hold (§5); rename zones freely.

**Key grammar:** dotted segments matching `/^[a-z0-9][a-z0-9-]*$/`. Segments are joined by `.`. A key has at most 8 segments; each segment is at most 64 characters. Segments MUST NOT contain dots, slashes, uppercase letters, or underscores. Example: `working.projects.acme.dashboard`. Enforcement points: manifest load (rejects illegal `key:` declarations and illegal nested file/directory names), `put` (rejects illegal keys before any write), `enumerate` (filters and warns on illegal filenames).

**Per-entry `format:`** an entry MAY declare `format:` to be one of `markdown` (default), `json`, `yaml`, or `text`. The `format` controls the on-disk shape and which path extension is required:

| `format`   | Path extension              | `template:`           | `schema:` |
|------------|-----------------------------|------------------------|-----------|
| `markdown` | `.md` (or appended if absent) | required for derived | optional  |
| `json`     | `.json` required            | optional (escape hatch) | optional (top-level keys) |
| `yaml`     | `.yaml` or `.yml` required  | optional (escape hatch) | optional (top-level keys) |
| `text`     | `.txt` or no extension      | required for derived | MUST be null |

For `nested: true`, the recursive glob matches the format's extension (markdown→`**/*.md`, json→`**/*.json`, yaml→`**/*.{yaml,yml}`, text→`**/*.txt`). All files under one nested entry share one format and one schema. Each matching file is enumerated as its own key, with the key segments derived from the path relative to the entry (extension stripped). A nested entry that instead mirrors a whole directory of files to a consumer path — without enumerating any of them as keys — uses `publish: { tree: }` (below); its files are opaque payload. (The former `index_filename:` directory-keyed enumeration was removed in 0.43.0 — ADR 0053.)

**The `publish:` block (ADR 0052).** Publishing is configured by one typed `publish:` block with exactly one of two sub-keys — `publish: { to: [...] }` (file fan-out, §5.3) **xor** `publish: { tree: "dir" }` (subtree mirror, below). Setting both is an error. The legacy top-level `publish_to:` / `publish_tree:` keys are rejected at load with a migration message.

**Subtree mirror (`publish: { tree: }`).** A nested manifest entry MAY declare `publish: { tree: "dir" }` to mirror its entire stored subtree (`zones/<path>/**`) to a single target directory, preserving relative layout (case and extension preserved). It is **path-driven, not key-driven**: no keys are enumerated, no template variables are interpreted, and the mirrored files are opaque payload (never addressable). The entry's `ignore:` globs (§4, ADR 0042) filter the walk; each mirrored file gets its own sentinel; and on every build the whole target directory is pruned of textus-managed files the current source no longer produces (unmanaged files are never touched). When a `publish.tree` target directory overlaps a `derived` entry's `publish.to` (e.g. a derived `SKILL.md` written into the mirrored dir), the mirroring entry **must** `ignore:` that filename or prune will delete it — `doctor` flags this as `publish.tree_index_overlap`. See ADR 0047.

```yaml
- key: working.skills
  path: working/skills
  zone: working
  schema: skill
  nested: true
  publish:
    tree: "skills"
  ignore: ["*.tmp", ".DS_Store"]
```

**`inject_boot:`.** A derived entry with a `template:` MAY declare `inject_boot: true`. When `textus build` materializes the entry, it merges the `textus boot` envelope (§9) into the projection data under the key `boot`, so the template can render orientation content (zones, write flows, CLI catalog) alongside its projected rows. The flag is rejected at manifest load on (a) non-derived entries or (b) derived entries without a `template:` — agents reading the rendered file should be able to trust the preamble was produced by the same source of truth `textus boot` exposes.

**Lookup rule:** to resolve a key, find the entry with the longest `key:` prefix that matches. If that entry has `nested: true`, the remaining segments map to subdirectories under its `path`. Otherwise the key must equal an entry exactly. The resolved filesystem path is `<.textus root>/zones/<entry.path>[/<remaining>...].md` — implementations MUST prepend `zones/` to the manifest `path:` when constructing the filesystem location.

## 5. Zones and capability-based write gates

Write authority is **derived**, never declared per-zone. Each zone declares a `kind:`; each zone-kind requires one capability to write to it. A role may write a zone iff its capability set (`role.can`) contains the verb that zone-kind requires. textus gates **writes, not reads**: reads are unrestricted at the protocol layer (the `.textus/` files are on disk). Per-role read-scoping, if needed, is an agent-surface projection, not a manifest field.

The kind→verb mapping is closed:

| Zone `kind` | Required capability | Meaning |
|---|---|---|
| `canon` | `author` | Authored truth — only the trust anchor writes directly. |
| `workspace` | `keep` | Agent's own durable lane — bytes never auto-promote; climb to `canon` only via propose→accept. |
| `quarantine` | `fetch` | External bytes pending validation. |
| `queue` | `propose` | Proposals awaiting promotion. |
| `derived` | `build` | Computed from other zones. |

`owner:` on a zone is OPTIONAL, INFORMATIONAL metadata (not enforced in 0.33.0 — owner-scoped enforcement is deferred). `desc:` on a zone is optional; the value surfaces as the `purpose` field in `textus boot` zone rows.

Default scaffold — Setup-1 (roles `human=[author, propose]`, `agent=[propose, keep]`, `automation=[fetch, build]`):

| Zone | `kind` | Required capability | Writable by (default) | Use case |
|---|---|---|---|---|
| `knowledge` | `canon` | `author` | `human` | Authored truth: identity, voice, decisions, network. `knowledge.identity.*` is the identity key convention. |
| `notebook` | `workspace` | `keep` | `agent` | Agent's own durable working memory. Bytes climb to `knowledge` only via propose→accept. |
| `feeds` | `quarantine` | `fetch` | `automation` | Declared external inputs (calendar, feeds, scraped pages). Fetched by external automation; never by humans or agents directly. |
| `proposals` | `queue` | `propose` | `agent`, `human` | Proposals awaiting human review via `textus accept`. Lets agents stage changes without touching `knowledge`. |
| `artifacts` | `derived` | `build` | `automation` | Computed outputs (catalogs, indexes, published context). Written via `textus build`. |

A write is gated by the caller's **role**, supplied via `--as=<role>`. If the role does not hold the capability the target zone-kind requires, the write returns `write_forbidden` with the message `writing '<key>' (zone '<zone>') needs capability '<verb>'` and a hint naming the roles that hold it (`held by: <roles>`, or `held by: no declared role` when none do).

Every zone MUST declare a `kind:` describing its role in the data-flow graph.
The vocabulary is closed: `canon` (authored truth), `workspace` (agent's own
durable lane), `quarantine` (external bytes pending validation), `queue`
(proposals awaiting promotion), `derived` (computed from other zones). A
manifest MUST declare at most one `queue` zone. Because authority is derived, a
manifest is rejected at load if it declares a zone whose required verb is held
by **no** declared role (`derived` ⇒ a role with `build`, `queue` ⇒ `propose`,
`quarantine` ⇒ `fetch`, `workspace` ⇒ `keep`, `canon` ⇒ `author`). Coordination
is keyed off the declared kind: a zone is derived only if it declares
`kind: derived`, and proposals route to the declared `queue` zone — there is no
name-based fallback. A manifest with a kind-less zone is rejected at load.

### 5.1 Role resolution

The effective role for any CLI invocation is resolved in this order; the first match wins:

1. `--as=<role>` flag on the command line.
2. `TEXTUS_ROLE` environment variable.
3. `.textus/role` file (one line, role name) at the project root.
4. Default: `human`.

**Canonical roles (default scaffold):**

| Role | Capabilities (`can`) | Meaning |
|---|---|---|
| `human` | `[author, propose]` | Interactive user at a terminal; the single trust anchor. |
| `agent` | `[propose]` | Long-running AI or LLM process; stages proposals. |
| `automation` | `[fetch, build]` | Scheduled or one-shot scripts: fetch external sources, build derived outputs. |

Roles are declared in the manifest's `roles:` block (§5.1.1); the names above are the default mapping when `roles:` is omitted. Unknown role values are rejected with `invalid_role`.

Every successful write records the resolved role and a wall-clock timestamp in `.textus/audit.log`, so reviewers can later distinguish a human edit from an agent edit even though both live in the same file.

#### 5.1.1 Capabilities

Roles declare **capabilities** — verbs from a closed five-element set. A
manifest declares a `roles:` block mapping each role name to the capabilities
it holds via `can:`:

```yaml
roles:
  - { name: owner,    can: [author, propose] }
  - { name: proposer, can: [propose] }
  - { name: fetcher,  can: [fetch] }
  - { name: compiler, can: [build] }
  - { name: keeper,   can: [keep] }
```

Capability allow-list: `propose`, `author`, `keep`, `fetch`, `build`. Each verb is the
required capability for exactly one zone-kind:

| Capability | Authorizes writes to zone-kind |
|---|---|
| `author` | `canon` |
| `keep` | `workspace` |
| `propose` | `queue` |
| `fetch` | `quarantine` |
| `build` | `derived` |

`author` is the single **trust anchor**: **at most one role may hold `author`**
(a manifest declaring two or more is rejected at load). The `accept` and
`reject` transitions also require the `author` capability — `accept` is a
transition verb, not a capability. Because write authority is derived, there is
no `write_policy:` — instead, every declared zone-kind's required verb MUST be
held by at least one role, or the manifest is rejected at load.

When the `roles:` block is omitted, the default mapping applies:

| Default name | Capabilities (`can`) |
|---|---|
| `human`      | `[author, propose]` |
| `agent`      | `[propose, keep]` |
| `automation` | `[fetch, build]` |

Wire protocol `textus/3` is unchanged — capabilities are a manifest/semantics
concept and never appear on the wire.

Every write transition is authorized by **one Guard** (ADR 0031): an ordered
list of predicates over a single evaluation context. Predicate #0 of every write
guard is `zone_writable_by` (the capability gate above); the `author_held`
predicate keys on the `author` capability and is named `author_held` (it passes
when the acting role holds `author`). See §5.11 for composing extra predicates via
`rules[].guard:`.

### 5.2 Compute layer (derived entries)

Derived entries live in a `derived` zone (writable by a role holding `build`; `automation` by default) — `output` in the default scaffold. They are not authored by hand; their body is produced by projecting over other entries. A derived entry declares a `compute:` block with a `kind:` discriminator.

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

A derived entry that is produced by a build tool *outside* textus — `rake`, `just`, a shell script, anything — declares `compute: { kind: external, ... }`. textus does **not** execute the command (consistent with §2); the external automation is responsible for writing the file. textus records `sources:` so `textus freshness` can compare source mtimes against the derived file's `_meta.generated.at` and report staleness.

```yaml
- key: output.catalogs.skills
  path: output/catalogs/skills.md
  zone: output
  owner: automation:catalog-skills
  compute:
    kind: external
    command: "rake catalog:skills"   # informational; external automation invokes it
    sources:                          # dotted keys OR repo-relative paths
      - working.projects
      - working.network
```

**`sources:`** is a list. Each element is either a dotted key prefix (matched against manifest entries) or a filesystem path (relative to the repo root, or absolute). For each key prefix, every matching entry's file mtime is checked. For each path, file or directory mtime is checked.

**`command:`** is recorded in the staleness row's `generator` field but never executed. It exists so `textus freshness` output can carry a hint about how to fetch.

**Freshness contract.** An entry with `compute: { kind: external }` is reported by `textus freshness` as `stale` when:
- The derived file does not exist, OR
- `_meta.generated.at` is missing or unparseable, OR
- Any `sources:` element has been modified after `_meta.generated.at`.

**Frontmatter contract.** The external automation is responsible for writing the `generated:` frontmatter block when it produces the file:

```yaml
generated:
  by: "rake catalog:skills"
  at: "2026-05-25T12:00:00Z"
  from: [working.projects, working.network]
```

`generated.from` SHOULD match `compute.sources` — they're the same list, recorded twice so a diff proves what was actually consumed.

`kind: external` and `kind: projection` are alternatives — exactly one per entry. Templates are not required for `kind: external`: the external automation produces the bytes directly.

### 5.3 Publish layer (`publish:`)

Publishing is configured by one typed `publish:` block with exactly one sub-key (ADR 0052): `to:` (file fan-out) **xor** `tree:` (subtree mirror). Setting both is an error; the legacy top-level `publish_to:` / `publish_tree:` keys are rejected at load with a migration message.

A derived entry MAY declare `publish: { to: [...] }`, listing one or more destination paths relative to the project root:

```yaml
publish:
  to:
    - CLAUDE.md
    - .ai/instructions.md
```

When the entry is recomputed, textus copies the in-store file byte-for-byte to each destination. The in-store artifact under `.textus/zones/<output-zone>/…` is already the consumer-shaped output (per the format strategy — see §5.x), so publish is a verbatim file copy with no parsing or stripping.

A sentinel is written for each published file at `<store_root>/.run/sentinels/<target-relative-to-repo>.textus-managed.json` (git-ignored runtime state — ADR 0070), recording `source`, `target`, the target's sha256, and `mode: "copy"`. Sentinels live under the store's runtime tree rather than beside the consumer file so target directories stay clean, and are regenerated by the next build (via content-identical adoption) rather than committed. The sentinel exists so out-of-band edits can be detected on the next publish — textus refuses to clobber a destination that is not either missing, marked as managed, or **byte-identical to the source being published**. An identical destination is *adopted*: its sentinel is written and management proceeds (the copy is a content no-op), so an artifact tree already on disk onboards without a manual delete. An unmanaged destination whose content **differs**, or any unmanaged symlink, is still refused (ADR 0050). Legacy sibling sentinels (`<target>.textus-managed.json`) are still recognised as managed and are migrated to the new location on the next publish.

**Subtree mirror.** A nested entry MAY declare `publish: { tree: "dir" }` instead of `to:` (see §4). On every build, textus walks the entry's full stored subtree (`zones/<path>/**`), applies the entry's `ignore:` filter, and byte-copies each file to the target directory, preserving relative layout — one sentinel per file under `<store_root>/.run/sentinels/`. The mirror is path-driven: no keys are enumerated, no template variables are interpreted, and mirrored files are opaque payload (never addressable). On rebuild, the entire target directory is pruned of textus-managed files the current source no longer produces; unmanaged files are never touched. The build envelope grows a `published_leaves` array — one row per mirrored file, with `key`, `source`, and `target` — alongside the existing `built` array, plus a `pruned` array listing any orphaned managed files removed on this build. Targets that would resolve outside the repo root are refused. When a `publish.tree` target overlaps a `derived` entry's `publish.to` (e.g. a derived `SKILL.md` written into the mirrored dir), the mirroring entry must `ignore:` that filename or prune will delete it — `doctor` flags this as `publish.tree_index_overlap` (ADR 0047).

### 5.4 Intake (declared, refreshed via registered intake handler)

Intake entries declare an external source by naming an **intake handler** — a registered, named function that pulls data into the entry. textus itself still makes no implicit network calls: an intake handler only runs when a read-through `textus get KEY` encounters a stale entry whose `lifecycle` rule says `on_expire: refresh`. The declaration is data only:

```yaml
- key: feeds.calendar.events
  zone: feeds
  intake:
    handler: ical-events
    config:
      url: "https://calendar.google.com/.../basic.ics"

rules:
  - match: feeds.calendar.**
    lifecycle:
      ttl: 6h
      on_expire: refresh        # refresh | warn | drop | archive
      budget_ms: 500            # bound the in-process refresh (default: 500)
```

`handler` names a registered `:resolve_intake` hook (see §5.10 for the hook contract); `config` is an opaque hash handed to the handler. The freshness budget (`ttl`, `on_expire`, `budget_ms`) lives in a top-level **`rules:`** block matched by key glob (§5.11).

#### `on_expire:` semantics

`on_expire:` declares what happens when `get` encounters an expired (past-TTL) intake entry. `get` is **read-through on every surface** (CLI, Ruby, MCP): it returns the freshest obtainable envelope, refreshing on an expired verdict per the entry's `lifecycle` rule and degrading to a pure on-disk read for keys with no lifecycle rule (ADR 0062). The value lives on the matching policy block, not on the entry. For intake entries the only valid actions are `refresh` and `warn` (`drop`/`archive` apply to stored entries and are enforced by `doctor` via `lifecycle.action_invalid`).

| Value | Behaviour |
|---|---|
| `warn` (default) | Return the entry immediately with `stale: true`, `stale_reason:` populated, and `fetching: false`. No blocking. |
| `refresh` | Block the `get` call, run the intake handler in-process under a `budget_ms` deadline (default 500 ms), write the result, and return the fresh envelope. If the handler does not finish in time, return the stale envelope (with `stale: true`, `fetching: true`) and let the refresh complete in the background. Fires `:fetch_backgrounded` when the deadline is exceeded. |

> **Note:** `list`/`where` paths do **not** annotate freshness — only `get` does.

In intake mode the handler MUST return one of three shapes, all normalized by the store into its internal `{_meta, body, content}` representation (§5.12):

- `{ _meta:, body: }` — markdown-friendly; `_meta` becomes the entry's parsed metadata hash.
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content.
- `{ body: }` — raw bytes for `text` or for any format that prefers verbatim writes; the store re-parses and validates per `format:`.

**Built-in intake handlers.** `json`, `csv`, `markdown-links`, `ical-events`, `rss` are always available. They expect raw bytes in `config["bytes"]` and produce structured `_meta`/body. Built-ins do not perform I/O themselves — the caller (or an outer hook) is responsible for supplying bytes.

**Refresh paths.** Two are supported:

1. **In-process** — a read-through `textus get KEY --as=automation` on a stale entry whose rule says `on_expire: refresh` resolves the entry's `intake.handler`, invokes the registered `:resolve_intake` hook with `(caps:, config:, args: {})`, and writes the result under a role holding `fetch` (`automation` by default).
2. **External automation** — a cron job or agent harness reads `textus freshness --zone=intake --output=json`, fetches sources reported `expired` out of band, and pipes bytes back through `textus put KEY --as=automation --stdin`.

Both paths share the same write gate, audit-log entry, and `:entry_fetched` event. User-supplied hooks live in `.textus/hooks/**/*.rb` and auto-load at `Store#initialize` — see §5.10 for the full hook contract.

### 5.5 Pending / accept workflow

Proposal entries are full patches authored into the `proposals` queue zone (writable by `propose`-holders: `agent` and `human` by default) — `proposals` in the default scaffold (Setup-1) — typically by agents. The entry's frontmatter describes the patch it proposes against another zone:

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

`proposal.target_key` names the entry the patch would create or modify, and `proposal.action` is `put` or `delete`. The remaining frontmatter and body are the proposed new content. A proposal's `target_key` MUST resolve to a `canon` zone; `accept` refuses any other target (`target_is_canon`, ADR 0035).

`textus accept <proposal-key>` is a **transition** (not a capability) that requires the **`author` capability**: the resolved role must hold `author` (the single trust anchor — `human` by default). It copies the patch into the target zone, records provenance (originating proposal key, original role, original timestamp) in the audit log, and removes the proposal entry. The `reject` transition likewise requires `author`. Roles holding only `propose` (e.g. `agent`) can propose but cannot accept or reject.

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
  updated_at: { type: time,  maintained_by: automation }
```

`maintained_by` values are free-form role-name strings (e.g. `human | agent | automation`). They name the role expected to own a field; values that match no declared role do not affect role-authority validation and pass through unchanged.

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

**Override rule:** a role holding the `author` capability (the trust anchor — `human` by default) is permitted to write any `maintained_by` field, regardless of declared owner. The trust anchor overrides agent-maintained fields by design: schema field ownership (`maintained_by:`) makes the boundary explicit, not implicit. All other role mismatches are reported by `doctor --check=schema_violations` with code `role_authority`, including fields `key`, `field`, `expected`, and `last_writer`.

### 5.9 Row transforms

Row transforms are RPC hooks on the `:transform_rows` event. See §5.10.

### 5.10 Hooks

This section is the normative event table. For the hook-author's guide (how to define and test hooks), see [`docs/how-to/writing-hooks.md`](docs/how-to/writing-hooks.md).

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
| `:entry_fetched`        | pubsub  | ctx:, key:, envelope:, change:                            | (discarded)           | logged        |
| `:build_completed`      | pubsub  | ctx:, key:, envelope:, sources:                           | (discarded)           | logged        |
| `:proposal_accepted`    | pubsub  | ctx:, key:, target_key:                                   | (discarded)           | logged        |
| `:file_published`       | pubsub  | ctx:, key:, envelope:, source:, target:                   | (discarded)           | logged        |
| `:entry_renamed`        | pubsub  | ctx:, key:, from_key:, to_key:, envelope:                 | (discarded)           | logged        |
| `:proposal_rejected`    | pubsub  | ctx:, key:, target_key:                                   | (discarded)           | logged        |
| `:store_loaded`         | pubsub  | ctx:                                                      | (discarded)           | logged        |
| `:session_opened`       | pubsub  | ctx:, role:, cursor:                                     | (discarded)           | logged        |
| `:fetch_started`        | pubsub  | ctx:, key:, mode:                                         | (discarded)           | logged        |
| `:fetch_failed`         | pubsub  | ctx:, key:, error_class:, error_message:                  | (discarded)           | logged        |
| `:fetch_backgrounded`   | pubsub  | ctx:, key:, started_at:, budget_ms:                       | (discarded)           | logged        |

The three `:fetch_*` lifecycle events report the progress and failures of background (timed_sync) fetches.

**`:fetch_started`** fires immediately before an intake handler is invoked. `mode:` is one of `"sync"` or `"timed_sync"`.

**`:fetch_failed`** fires when an intake handler raises. `error_class:` is the exception class name string; `error_message:` is `e.message`.

**`:fetch_backgrounded`** fires when a `timed_sync` fetch exceeds its budget and is handed off to a background thread. `started_at:` is an ISO-8601 UTC string; `budget_ms:` is the configured deadline as an integer.

**Signature invariant** — hooks receive a capability handle as their first keyword argument; the name depends on the mode:

- **RPC hooks** (`rpc` mode) receive `caps:` — a `Textus::Container`. Event-specific kwargs (`config:`, `args:`, `rows:`) follow in the stable order shown in the table above.
- **Pub-sub hooks** (`pubsub` mode) receive `ctx:` — a `Textus::Hooks::Context` that exposes a narrow surface: `get`, `list`, `deps`, `freshness` (reads), `put`, `delete`, `audit` (authorized writes), `publish_followup`, plus `role` and `correlation_id`. The raw `Store` is not handed out.

Declaring `store:` instead of `caps:` in an RPC callable will pass registration but raise `UsageError` at call time (`Hooks::RpcRegistry#invoke` rejects `store:` — there is no shim).

The primary entity is always `key:` (for `:proposal_accepted`, `key:` is the pending key being accepted and `target_key:` is the destination). For `:entry_renamed`, `key:` is present and equals `to_key:` — it is the entry's post-move home, present so `keys:` glob filters route correctly; `from_key:` is the prior key. For `:proposal_rejected`, `key:` is the pending key being rejected. For `:store_loaded`, no key — the event observes store readiness, not an entry. For `:session_opened`, no key — it fires once per MCP connection at `initialize` with the connection's resolved `role:` and boot `cursor:` (ADR 0075); distinct from `:store_loaded`, which fires once per process at `Store#initialize` under the default role.

**RPC mode** — exactly one handler per (event, name). The manifest references the handler by name (`intake.handler: NAME`, `compute.transform: NAME`). Failure or timeout aborts the calling operation.

**Pub-sub mode** — zero or more handlers per event. All matching handlers fire. The `keys:` option restricts a handler to keys matching one of the given globs (`File.fnmatch?` rules). Absence of `keys:` fires on every event of that type. Handler failures and 2s timeouts are logged to `audit.log` as `event_error` rows; they NEVER abort the triggering operation.

Each handler runs under `Timeout.timeout(2)`.

### 5.11 Rules

A manifest MAY declare a top-level `rules:` block — a list of rule blocks matched against entry keys by glob. Each block carries one or more slots:

```yaml
rules:
  - match: feeds.**
    lifecycle: { ttl: 6h, on_expire: warn }

  - match: feeds.calendar.**
    lifecycle: { ttl: 30m, on_expire: refresh, budget_ms: 800 }
    intake_handler_allowlist: [ical-events]

  - match: proposals.**
    guard:
      accept: [schema_valid, author_held]
```

**Slots (all optional within a block):**

| Slot | Type | Meaning |
|---|---|---|
| `lifecycle` | `{ ttl, on_expire, budget_ms? }` | Unified age policy (ADR 0079). `on_expire` is `refresh` (re-pull intake), `warn` (flag on read), `drop` (delete), or `archive` (copy to `<store>/archive/<relative-path>` then delete). Non-destructive actions (`refresh`/`warn`) are applied lazily on `get`; destructive actions (`drop`/`archive`) only on the `tend` sweep. `refresh` is valid only for intake entries; `drop`/`archive` only for stored entries (`doctor` `lifecycle.action_invalid` enforces). Age is measured from `_meta.last_fetched_at` (intake) when present, else the leaf file's modification time. `budget_ms` (optional) bounds a `refresh` to a deadline, returning the stale envelope and refreshing in the background when exceeded. |
| `intake_handler_allowlist` | list of strings | Constrains which `intake.handler:` names may be used by entries matched by this block. Enforced by `textus doctor`. |
| `guard` | `{ <transition>: [predicates] }` | Extra predicates composed (AND) onto a write transition's built-in **base** guard (ADR 0031). Keyed by transition (`put`, `delete`, `mv`, `accept`, `reject`, `fetch`). Predicate names are drawn from the closed vocabulary (`zone_writable_by`, `schema_valid`, `author_held`, `target_is_canon`, `etag_match`, `fresh_within`); parameterized predicates use `{ name: param }` form, e.g. `{ fresh_within: "1h" }`. Enforced — the transition refuses (`guard_failed`) if any predicate fails; the topology refusal keeps the `write_forbidden` code. |

The `lifecycle:` slot unifies the former `fetch:` (intake freshness) and
`retention:` (leaf pruning) slots into one age policy (ADR 0079). Generator/build
drift — a derived entry whose sources changed since its `generated.at` — is
dependency-based, not age-based, and is reported by the `textus doctor`
`generator_drift` check rather than this slot.

**Match grammar.** `match:` is a single glob using `*` (single segment) and `**` (any depth). A literal segment ranks more specifically than `*`; `*` ranks more specifically than `**`.

**Resolution.** For each key textus computes a `RuleSet { handler_allowlist, guard, lifecycle }` by walking every block whose `match` matches the key, ranked by specificity. **Per slot, the most specific block wins.** Two blocks of equal specificity that match the same key and fill the same slot is a manifest error reported by `textus doctor` (`rule_ambiguity`).

**Read surface.** `textus rule list` dumps every block. `textus rule explain KEY` shows the resolved `RuleSet` for one key — lean effective `{lifecycle, guard}` by default; `--detail` adds every matched block and the effective guard predicate names for every write transition (ADR 0059).

### 5.12 Storage formats

An entry's `format:` selects a storage strategy. All strategies expose the same `parse(bytes) → {_meta, body, content}` and `serialize(meta:, body:, content:) → bytes` contract. The store, audit, etag, and projection layers operate on the parsed shape; only (de)serialization differs.

- **markdown** — YAML frontmatter between `---` fences, free-form body. Parse: Psych `safe_load` on the frontmatter block; body is the remainder. Serialize: emit `---\n<yaml>\n---\n<body>`. `content` is always `nil`. `_meta` holds the parsed frontmatter hash.
- **json** — entire file is a JSON document. Parse: `JSON.parse`. Serialize: `JSON.pretty_generate(content)` + trailing newline. `_meta` is populated from the top-level `_meta` hash (if present, else `{}`); `body` is the raw bytes; `content` is the parsed object with `_meta` stripped.
- **yaml** — entire file is a YAML mapping. Parse: `YAML.safe_load(bytes, permitted_classes: [Date, Time], aliases: false)`; anchors/aliases rejected. Serialize: `YAML.dump(content).sub(/\A---\n/, "")`. Same `_meta` / `body` / `content` rules as JSON.
- **text** — raw UTF-8 bytes. Parse: body is the file verbatim, `_meta` is `{}`, `content` is `nil`. Serialize: write `body` bytes (with trailing newline if missing).

**Envelope shape.** Every envelope carries `format:` (always present, defaults to `markdown` for back-compat). For `json|yaml`, the envelope additionally carries `content:` (parsed object). `body` is always the raw on-disk bytes. `_meta` always exists in the envelope: for `markdown` it holds the parsed YAML frontmatter; for `json|yaml` it mirrors the top-level `_meta` block (`{}` if absent); for `text` it is `{}`.

**`_meta` convention.** Derived structured entries (json, yaml) embed a `_meta` hash as the first top-level key. Builder-injected keys appear in a fixed order for etag stability:

```
from, template, transform
```

Keys with `nil` values are omitted. The builder injects only **deterministic** provenance: it does **not** stamp a `generated_at` build timestamp into the artifact (ADR 0070). A built artifact is content-addressed — rebuilding unchanged sources reproduces it byte-for-byte, so a rebuild is a no-op and a `git` revert never drifts. (The `generated.at` of §5.2 is a separate convention written by *external* build tools, not by textus's own builder.) User-shaped content (or the reducer's hash) follows `_meta`. The etag (§10) is the sha256 of the on-disk bytes regardless of format; key ordering MUST therefore be deterministic, which Ruby's `Hash` and `JSON.generate` / `YAML.dump` honor via insertion order.

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

Entries in a `derived` zone SHOULD additionally carry the `generated:` block defined in §5.2. Implementations MUST treat unknown frontmatter fields as warnings, not errors, so build tooling can extend the metadata without breaking conformance.

## 8. Envelope (the wire format)

Every successful CLI response (`--output=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/3",
  "key": "knowledge.network.org.jane",
  "zone": "knowledge",
  "owner": "human:network",
  "path": "/absolute/path/to/.textus/zones/knowledge/network/org/jane.md",
  "format": "markdown",
  "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body in Markdown.\n",
  "etag": "sha256:8f3c…",
  "schema_ref": "person",
  "uid": "a1b2c3d4e5f60718",
  "stale": false,
  "stale_reason": null,
  "fetching": false
}
```

**Field rules:**
- `protocol` MUST be the exact string `textus/3`.
- `key` MUST be the canonical resolved key.
- `zone` MUST be one of the zones declared in the manifest (`knowledge`, `notebook`, `feeds`, `proposals`, `artifacts` in the default Setup-1 scaffold).
- `path` MUST be an absolute filesystem path.
- `format` MUST be one of `markdown`, `json`, `yaml`, `text` (§5.12). Absent envelopes are treated as `markdown` for back-compat.
- `body` is the raw on-disk bytes as a UTF-8 string for every format.
- `content` is present only when `format` is `json` or `yaml`; equals the parsed object. For `json|yaml`, `_meta` mirrors the top-level `_meta` block (or `{}` if absent). For `markdown`, `_meta` holds the parsed YAML frontmatter. For `text`, `_meta` is `{}`.
- `etag` MUST be `sha256:<hex>` of the raw file bytes, computed identically for every format.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.
- `uid` is the stable Textus UID (§7) if the entry carries one, else `null`. Always present in the envelope.
- `stale` is `true` when the entry's TTL has elapsed and the data has not yet been refreshed; `false` otherwise. Only populated for entries matched by a `lifecycle:` rule slot (typically `feeds` / quarantine zone); always `false` elsewhere.
- `stale_reason` is a short human-readable string describing why the entry is stale (e.g. `"ttl_exceeded"`, `"never_fetched"`), or `null` when `stale` is `false`.
- `fetching` is `true` when an `on_expire: refresh` background refresh is in flight for this entry; `false` otherwise. Callers observing `stale: true, fetching: true` SHOULD retry after a short delay.

> **Note:** `list`/`where` envelopes do **not** include `stale`, `stale_reason`, or `fetching` — freshness annotation is only provided by `get`.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/3",
  "ok": false,
  "code": "write_forbidden",
  "message": "writing 'knowledge.identity.self' (zone 'knowledge') needs capability 'author'",
  "hint": "held by: human; pass --as=<role>",
  "details": { "key": "knowledge.identity.self", "zone": "knowledge", "verb": "author", "holders": ["human"] }
}
```

**Error codes:**

| Code | Meaning | Default exit |
|---|---|---|
| `unknown_key` | Key does not resolve | 1 |
| `bad_frontmatter` | YAML parse failed or `name:` mismatch | 1 |
| `schema_violation` | Required field missing or wrong type | 1 |
| `write_forbidden` | Resolved role lacks the capability the zone-kind requires | 1 |
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
| `get K [--no-fetch]` | read (read-through by default: refresh-on-stale per the entry's `lifecycle` rule when `on_expire: refresh`, degrades to a pure read; `--no-fetch` / `{fetch:false}` for an explicit pure on-disk read) | any |
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
| `propose K --stdin --as=R` | write | `propose`-holder (auto-prefixes propose_zone) |
| `key delete K --if-etag=E --as=R` | write | per zone |
| `build [--prefix=K] [--dry-run]` | write | `build`-holder (typically `automation`) |
| `tend [--prefix=K] [--zone=Z] [--dry-run] --as=ROLE` | write | per zone (role must write the matched zone) |
| `accept K --as=human` | write | `author`-holder (typically `human`) |
| `reject K --as=human` | write | `author`-holder (typically `human`) |
| `init` | write | `human` |
| `schema {show,init,diff,migrate}` | read/write | `human` for writes |
| `key mv OLD NEW [--as=R] [--dry-run]` | write | per zone (same-zone only) |
| `key uid K` | read | any |

**`textus boot` envelope extras.** In addition to zones, entries, hooks, write flows, and the `cli_verbs` catalog, the boot envelope includes an `agent_quickstart` block synthesized from the manifest's role capabilities:

```json
{
  "agent_quickstart": {
    "read_verbs":     ["get", "list", "pulse", "schema_show", "boot", "rule_explain", "where", "deps", "rdeps"],
    "write_verbs":    ["accept", "delete", "mv", "propose", "put", "reject"],
    "writable_zones": ["proposals"],
    "propose_zone":   "proposals",
    "latest_seq":     1842
  }
}
```

`read_verbs` is derived from the MCP verb catalog — the verbs the agent can actually call over its transport — so it lists the read/discovery verbs (`schema_show` for an entry's field shape, `rule_explain` for its freshness/guard policy, and the graph reads `where`/`deps`/`rdeps`, ADR 0060) and never the CLI-only `audit`/`freshness`/`doctor` (ADR 0056). An agent learns an entry's `_meta` shape by calling the `schema_show` verb before a `put`/`propose`, not by shelling out to a CLI. The graph reads `deps`/`rdeps` return a structured `{key, deps}`/`{key, rdeps}` envelope on every surface (CLI, Ruby, MCP) — a hash, not a bare array, consistent with the other structured read responses such as `where` (ADR 0060 amendment).

The agent's MCP write surface includes the single-key `delete` and `mv` tools alongside their bulk `key_delete_prefix`/`key_mv_prefix` cousins (ADR 0060 amendment). All of these apply by default; `dry_run: true` is a uniform opt-in preview that returns a Plan without mutating (ADR 0071 — verbs are actions, dry-run is opt-in on every surface). Single-key `delete` additionally accepts an optional `if_etag` optimistic-concurrency check. The blast-radius reads (`where`/`deps`/`rdeps`) remain on MCP so an agent can look before it leaps. The promotion verbs `accept` and `reject` are also on MCP (ADR 0072): they are gated by the `author_held` capability floor, not by transport absence — a default-`agent` connection is refused, while a connection launched as a role holding `author` (`--as`/`TEXTUS_ROLE`/`.textus/role`, resolved once at launch per ADR 0040) can promote, closing the propose→accept loop over one transport. `build` is also on MCP (ADR 0076): it is caller-agnostic and self-elevating — it always runs as the manifest's `build`-capable actor regardless of the calling role, grants no authority over content (build is a pure, idempotent function of already-accepted canon, ADR 0070), and is serialized by a shared single-writer lock across all transports so a concurrent CLI or background build cannot collide with an MCP-triggered one.

`latest_seq` is the current high-water mark of the audit log; agents should use it as the starting cursor for `pulse`.

**`textus pulse` output shape:**

```json
{
  "cursor":         1845,
  "changed":        [ { "seq": 1843, "key": "knowledge.notes.x", "verb": "put", "role": "human", "ts": "..." } ],
  "stale":          [ "artifacts.marketplace" ],
  "pending_review": [ "proposals.proposal.123" ],
  "doctor":         { "ok": true, "warn": 0, "fail": 0 },
  "contract_etag":  "sha256:1f3a…",
  "next_due_at":    "2026-06-01T09:00:00Z",
  "hook_errors":    [ { "seq": 1844, "event": "after_put", "hook": "notify", "key": "knowledge.notes.x", "error_class": "Timeout::Error", "error_message": "…", "at": "..." } ]
}
```

`cursor` is the new high-water mark; pass it as `--since` on the next call. `changed` is sourced from `audit --seq-since`. `stale` is sourced from `freshness`. `pending_review` lists all keys in the queue zone. `doctor` is an `{ok, warn, fail}` count summary. `contract_etag` is the `sha256:`-prefixed composite content hash of the contract — the manifest plus hooks and schemas (ADR 0074, via ADR 0025) — for cheap change-detection. `next_due_at` is the soonest upcoming freshness deadline across entries (ISO-8601, or `null` if none). `hook_errors` lists hook failures recorded since the cursor. When `--since` is below the oldest available seq (due to audit log rotation), pulse returns `CursorExpired`.

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body.\n",
  "if_etag": "sha256:8f3c…" }
```

`if_etag` is optional on both `put` and `delete`. When provided, the write fails with `etag_mismatch` if the on-disk file's etag differs. When omitted, the write is unconditional (last-writer-wins).

**`textus freshness` output shape:**

```json
{
  "verb": "freshness",
  "rows": [
    { "key": "feeds.upstream.notes",
      "zone": "feeds",
      "last_fetched_at": "2026-05-21T13:21:17Z",
      "age_seconds": 65000,
      "ttl_seconds": 43200,
      "on_expire": "warn",
      "status": "expired",
      "next_due_at": "2026-05-22T01:21:17Z" }
  ]
}
```

Each row reports one entry's verdict (`fresh`, `expired`, or `no_policy`) plus the matched rule's `on_expire` action, against its matched `lifecycle:` rule. `textus build` consumes its own staleness signal and executes derived entries' projections under a `build`-holding role (`automation` by default); `--dry-run` prints the plan without executing.

`textus accept K --as=human` promotes a pending entry into its target zone: it copies the patch body into the target key, deletes the pending entry, and writes one audit line per side (§audit). Only a role holding the `author` capability (the trust anchor — `human` by default) may invoke `accept`.

`textus init` scaffolds a fresh `.textus/` tree (manifest, zones, schemas, audit log) under the current directory with a default manifest. Customize by editing `.textus/manifest.yaml` after init.

`textus schema show K` prints the schema for entry `K`. `textus schema init NAME` writes a stub schema. `textus schema diff NAME` compares the on-disk schema against entries that claim it and prints the deltas. `textus schema migrate NAME --rename=OLD:NEW` rewrites the `_meta` key `OLD` to `NEW` across every entry that uses the named schema, in a single transactional sweep that logs each touched file.

## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.

## 10.1 Errors carry hints

Every `Textus::Error` exposes `code`, `message`, and an optional `hint:`. The hint is a single short string suggesting the next action — the file to edit, the role to pass, the command to run. Errors in the wire envelope include the hint as a top-level `hint:` field when present. The CLI prints failures to stderr as `code: message` followed by `  → hint` (when a hint exists), in addition to the JSON envelope on stdout. Hints are advisory: implementations MAY omit or rephrase them without breaking conformance.

## 10.2 `textus doctor`

`textus doctor` returns a health-check envelope: `{ "protocol": "textus/3", "ok": bool, "issues": [...], "summary": {error, warning, info} }`. Each issue carries `code`, `level` (`error|warning|info`), `subject`, `message`, and optionally `fix`. `ok` is true iff no error-level issues are present; warnings and info do not flip the bit. Builtin checks: `protocol_version`, `manifest_files`, `schemas`, `schema_parse_error`, `templates`, `hooks`, `intake_registration`, `illegal_keys`, `sentinels`, `audit_log`, `unowned_schema_fields`, `schema_violations`, `rule_ambiguity`, `handler_allowlist`, `fetch_locks`, `proposal_targets`, `publish.tree_index_overlap`. Additional registered `:validate` hooks (§5.10) run after the builtin set. Exit code is 0 on `ok`, 1 otherwise.

## 11. Versioning

- The current wire string is `textus/3`.
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/3`.
- Breaking changes (renamed/removed envelope fields, zone semantics, key grammar) require a new wire string `textus/4`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently and speaks `textus/3`.

## 11.1 Agent integration

Agents interact with a textus store through two verbs: `boot` (once per session, for orientation) and `pulse` (per turn, for deltas). The `boot` envelope's `agent_quickstart` block gives the agent its starting cursor (`latest_seq`), its writable zones, and its propose zone. The `pulse` verb returns a delta envelope keyed on that cursor. When audit log rotation expires a cursor, `CursorExpired` signals the agent to call `boot` again.

For the full boot → pulse loop with pseudocode and cursor-expiry handling, see [`docs/how-to/agents-mcp.md`](docs/how-to/agents-mcp.md).

## 12. Conformance fixtures

A conformant implementation MUST pass these fixtures (the reference test suite ships a YAML file listing inputs and expected envelopes):

**Fixture A — Resolve and read:**
Given a manifest with `working.network.org` → `working/network/org` (nested), schema `person`, and a file `.textus/zones/working/network/org/jane.md` with valid frontmatter, `textus get working.network.org.jane --output=json` returns the canonical envelope with `etag` matching the file's sha256.

**Fixture B — Role gate on write:**
Given a manifest entry where `key: identity.self` lives in the `identity` zone (`kind: canon`, requiring the `author` capability), `textus put identity.self --stdin --as=agent` (where `agent` holds only `propose`) returns the error envelope with `code: "write_forbidden"` and exit code 1.

**Fixture C — Schema violation:**
Given the `person` schema and a `put` whose frontmatter omits `relationship`, the result is the error envelope with `code: "schema_violation"`, `details.missing: ["relationship"]`, and exit code 1.

**Fixture D — Staleness detection:**
Given a manifest entry `intake.notes` matched by a `rules: [{ match: intake.notes, lifecycle: { ttl: 1h, on_expire: warn } }]` block and an envelope on disk whose `_meta.last_fetched_at` is older than `now - ttl`, `textus freshness --output=json` includes a row for `intake.notes` with `status: "expired"`. Calling `textus freshness` does NOT trigger a refresh.

**Fixture E — Projection build:**
Given a manifest entry `derived.catalogs.skills` whose `compute: { kind: projection }` clause selects fields from `working.projects` entries, `textus build derived.catalogs.skills` materializes the derived entry on disk with frontmatter and body matching the projected shape. The output is content-addressed (no `generated_at` timestamp, ADR 0070), so rebuilding with unchanged sources reproduces it byte-for-byte and writes nothing.

**Fixture F — Mustache render:**
Given a derived entry with a `template` clause referencing a `.mustache` file and inputs drawn from other keys, `textus build` produces a body whose contents match the expected rendered output byte-for-byte (after trailing-newline normalization).

**Fixture G — Copy publish:**
Given a manifest entry with `publish: { to: [<path>] }`, a successful `textus build` for that entry leaves a plain file at `<path>` whose contents are byte-identical to the in-store artifact at `.textus/zones/<...>`, accompanied by a sentinel at `.textus/.run/sentinels/<path>.textus-managed.json` recording `source`, `target`, `sha256`, and `mode: "copy"`. Re-running `build` is idempotent.

**Fixture H — Audit log format:**
Every successful write verb (`put`, `delete`, `build`, `accept`, `schema migrate`) appends exactly one line per affected key to the audit log, in the canonical format defined in §audit (timestamp, actor role, verb, key, etag-before, etag-after). No write produces zero or multiple lines per key.

**Fixture I — Pending → accept:**
Given a proposal entry `proposals.knowledge.self.patch` proposing a change to `knowledge.identity.self`, `textus accept proposals.knowledge.self.patch --as=human` copies the patch body into the target key, deletes the proposal entry, and appends two audit lines (one for the target write, one for the proposals delete) in that order.

## 13. Why not X?

- **Why not MCP?** MCP is a transport; textus is a data model. The two compose: a 50-line MCP server can wrap `textus get/put` as tools. textus exists because the *shape* of agent-readable project memory deserves a standalone spec, separate from how it's served.

- **Why doesn't textus execute external build commands itself?** textus is a dataflow oracle, not a build runner. The moment a spec includes process execution, it inherits shell-injection surface, OS-portability concerns, and signal-handling semantics — and ends up duplicating whatever build system the consumer already runs (make, rake, just, lefthook, CI). Keeping execution external means a Python or TypeScript port of `textus/3` only has to parse YAML and emit JSON; it doesn't have to spawn processes safely. External build systems stay the executor; textus stays a data tool.

- **Why not plain Markdown vaults (Obsidian / Foam)?** No schema enforcement, no write-gating, no addressable wire format. Fine for human notes; underspecified for agents that must act on the contents deterministically.

- **Why not Notion / Coda?** Closed, hosted, lossy export. textus is local-first, plain-files, diffable in git.

- **Why not JSON Schema for the schemas?** Considered. Bespoke YAML chosen for v1: simpler implementation, lighter dependency footprint, matches the reference impl's house language. JSON Schema MAY be added as an alternate schema-language adapter in a future minor revision without breaking `textus/3`.

- **Why not a database (SQLite, kv store)?** textus's whole point is that the storage is plain files agents and humans both read. A binary store loses git-diff, grep, and editor support.

- **Why not vector embeddings?** Different problem. textus is for facts agents act on deterministically; embeddings are for fuzzy retrieval. They compose — index a textus tree into a vector store if you need both.

## 13.1 Layered architecture (internal)

Textus internals are organized into four one-way layers — **Interface** (`cli/`, `mcp/`) → **Application** (`application/` use cases) → **Domain** (`domain/` pure values) → **Infrastructure** (`infra/` adapters). Each layer imports only from the one beneath it. Plugin authors touch only the Hook DSL and the manifest YAML; the layering is internal and may evolve.

See [`docs/architecture/README.md`](docs/architecture/README.md) for an ASCII diagram and the full read-path walkthrough.

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
- [ ] Refuse writes whose resolved role lacks the capability the target zone-kind requires with `write_forbidden`.
- [ ] Return envelopes matching the shape in §8 exactly (with `_meta`, not `frontmatter`).
- [ ] Use the error codes in §8 and the exit-code table.
- [ ] Implement `textus freshness` per §5.1 and §9, walking each entry, matching it against the top-level `rules:` block, and reporting `fresh|expired|no_policy` (plus the `on_expire` action) without invoking any refresh.
- [ ] Pass the conformance fixtures A–I in §12.

A `textus/3` implementation MAY:

- Add additional CLI verbs (e.g. `move`, vendor-specific reporters) beyond the current set in §9.
- Provide alternate output formats (`--output=yaml`, `--output=table`) for human use.
- Support additional schema field types beyond §6, marked as `vendor:<name>` extensions.

## 16. Migrating from textus/2

textus does not ship a built-in textus/2 → textus/3 migrator. The historical upgrade path (via the one-shot `textus migrate` in the 0.11.x line) is recorded in `CHANGELOG.md` §0.11.0. `textus doctor` refuses a store still declaring `version: textus/2`. The textus/2 → textus/3 rename table is kept below for reference.

**Vocabulary summary** (textus/2 → textus/3 rename table, for reference):

| Category | textus/2 | textus/3 (current) |
|---|---|---|
| Actor | `ai` | `agent` |
| Actor | `script` | `automation` |
| Actor | `build` | `automation` |
| Zone | `inbox` | `intake` |
| Manifest | `writable_by:` | (removed — authority is derived from `kind:` × `can:`) |
| Manifest | `policies:` | `rules:` |
| Manifest | `handler_allowlist:` | `intake_handler_allowlist:` |
| Manifest | `promote_requires:` | `guard: { accept: [...] }` |
| Manifest | `projection:` | `compute: { kind: projection, ... }` |
| Manifest | `generator:` | `compute: { kind: external, ... }` |
| Hook event | `:intake` | `:resolve_intake` |
| Hook event | `:reduce` | `:transform_rows` |
| Hook event | `:check` | `:validate` |
| Hook event | `:put` | `:entry_put` |
| Hook event | `:deleted` | `:entry_deleted` |
| Hook event | `:refreshed` | `:entry_fetched` |
| Hook event | `:built` | `:build_completed` |
| Hook event | `:accepted` | `:proposal_accepted` |
| Hook event | `:reject` | `:proposal_rejected` |
| Hook event | `:published` | `:file_published` |
| Hook event | `:mv` | `:entry_renamed` |
| Hook event | `:loaded` | `:store_loaded` |
| Hook event | `:refresh_began` | `:fetch_started` |
| Hook event | `:refresh_detached` | `:fetch_backgrounded` |
| Hook event | `:refresh_failed` | `:fetch_failed` |
| Hook DSL | `Textus.hook(ev, name)` / sugar | `Textus.on(ev, name)` |
| Compute field | `projection.reduce:` | `compute.transform:` |
| `_meta` key | `reducer` | `transform` |
| CLI flag | `--format=json` (envelope) | `--output=json` |
| CLI verb | `refresh-stale` | `fetch all` |
| CLI verb | `policy list/explain` | `rule list/explain` |

**Hook migration.** Legacy event names / DSL methods must be renamed to the textus/3 forms above before a hook will load; see `CHANGELOG.md` §0.11.0 for the full event-rename detail.

### 16.1 Breaking changes in 0.31.0 (capability-based roles)

0.31.0 replaced declared per-zone write policies with **derived** authority and renamed the `refresh` transition to `fetch`. These keys/values are no longer accepted:

| Removed / renamed (≤ 0.30) | 0.31.0 form |
|---|---|
| `zones[*].write_policy:` | (removed) authority is derived: `role.can ⊇ { verb_for(zone.kind) }` |
| `roles[*].kind:` (`accept_authority`/`generator`/`proposer`/`runner`) | `roles[*].can:` (subset of `propose`, `author`, `fetch`, `build`) |
| Actors `runner`, `builder` | `automation` (`can: [fetch, build]`) by default |
| `rules[*].refresh:` slot | `rules[*].fetch:` slot |
| CLI `textus refresh` / `refresh stale` | `textus fetch` / `fetch all` |
| `_meta.last_refreshed_at` | `_meta.last_fetched_at` |
| Promotion predicate `:human_accept` / `:accept_authority_signed` | `:author_signed` |
| Envelope `refreshing` | `fetching` |

A manifest still declaring `write_policy:` or a role `kind:` is rejected at load. There is no compatibility alias — the breaking change requires a new wire-compatible manifest. (Wire string `textus/3` is unchanged: capabilities are a manifest concept and never appear on the wire.)

### 16.2 Breaking changes in 0.33.0 (workspace/keep + Setup-1 scaffold)

0.33.0 adds the fifth coordination primitive (`workspace` zone-kind + `keep` capability), renames the capability `accept` → `author` (and predicate `accept_signed` → `author_signed`), renames zone-kind `origin` → `canon`, and renames the default scaffold zones to the Setup-1 names. These changes affect **manifest files and tooling** only — the `textus/3` wire format is **UNCHANGED** (envelope shape, audit-log schema, key grammar, and the `version: textus/3` field are all identical to 0.32.x).

**Renames (manifest and predicate vocabulary):**

| Removed / renamed (≤ 0.32) | 0.33.0 form |
|---|---|
| Zone-kind `origin` | `canon` |
| Capability `accept` | `author` |
| Promotion predicate `accept_signed` | `author_signed` |
| Default scaffold zone `identity` | `knowledge` (identity keys live under `knowledge.identity.*`) |
| Default scaffold zone `working` | `knowledge` (merged into the same `canon` zone) |
| Default scaffold zone `intake` | `feeds` |
| Default scaffold zone `review` | `proposals` |
| Default scaffold zone `output` | `artifacts` |

**New in 0.33.0:**

| Addition | Detail |
|---|---|
| Zone-kind `workspace` | Agent's own durable lane. Required capability: `keep`. Bytes never auto-promote; climb to `canon` only via propose→accept. |
| Capability `keep` | Authorizes writes to `workspace` zones. Default scaffold: `agent` holds `[propose, keep]`. |
| Default scaffold zone `notebook` | `kind: workspace`, default owner `agent`. |
| `owner:` on a zone | OPTIONAL, INFORMATIONAL — not enforced in 0.33.0 (owner-scoped enforcement is deferred). |
| `desc:` on a zone | OPTIONAL — surfaces as the `purpose` field in `textus boot` zone rows. |

**Clarification (not a breaking change):** `accept` and `reject` are **transition verbs** (CLI commands), not capabilities. Both require the `author` capability. This has always been true; 0.33.0 makes it explicit by removing `accept` from the capability vocabulary.

A manifest declaring `kind: origin` or capability `accept` (in a `can:` list) is rejected at load.

### 16.3 Breaking changes in 0.35.0 (proposal target-canon + `author_held`)

0.35.0 constrains a proposal's target to a `canon` zone and renames the anchor-gate predicate. No `textus/3` wire change; no manifest-schema change.

**Renames (predicate vocabulary):**

| Removed / renamed (≤ 0.34) | 0.35.0 form |
|---|---|
| Promotion predicate `author_signed` | `author_held` |

**New in 0.35.0:**

| Addition | Detail |
|---|---|
| Floor predicate `target_is_canon` | On the `accept` base guard. A proposal's `target_key` MUST resolve to a `canon` zone; `accept` refuses any other target with `guard_failed` naming `target_is_canon`. Floor-only — not relaxable via `rules[].guard`. |
| `doctor` check `proposal_targets` | Warns on queued proposals whose `target_key` is non-canon (`proposal.target_not_canon`) or unresolvable (`proposal.target_unresolved`). |

A `rules[].guard` block referencing the predicate by its old name `author_signed` is rejected at load (unknown predicate).

---

**Spec word count target:** <2700 words (allowance widened to fit vocabulary axes intro + migration section).
**Reviewed against community-testing checklist (idea file §"Community-testing"):** ✅ implementable in a day in TS/Python (four concepts: manifest, schema, envelope, staleness check); ✅ conformance fixtures A–I; ✅ "Why not X?" section present (incl. why no execution); ✅ name picked.
