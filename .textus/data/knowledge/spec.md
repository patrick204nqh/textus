# textus/4 — Specification

**Status:** Accepted v4.0
**Protocol identifier:** `textus/4`
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
- [5. Lanes and capability-based write gates](#5-lanes-and-capability-based-write-gates)
  - [5.1 Role resolution](#51-role-resolution)
    - [5.1.1 Capabilities](#511-capabilities)
  - [5.2 Source layer (produced entries)](#52-source-layer-produced-entries)
    - [5.2.1 External source (`from: external`)](#521-external-source-from-external)
  - [5.3 Publish layer](#53-publish-layer-publish)
  - [5.4 Raw lane and ingest verb](#54-raw-lane-and-ingest-verb)
  - [5.5 Pending / accept workflow](#55-pending--accept-workflow)
  - [5.6 Audit log](#56-audit-log)
  - [5.7 Security bounds](#57-security-bounds)
  - [5.8 Schema evolution](#58-schema-evolution)
  - [5.9 Rules](#59-rules)
  - [5.10 Storage formats](#510-storage-formats)
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

---

## Conventions

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this
document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119)
and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174): with their normative
meaning **only** when they appear in uppercase. The same words in lowercase
carry their ordinary English sense and impose no requirement.

Requirements are stated against any **conforming implementation** of the
`textus/4` protocol. The Ruby gem `textus` is the reference implementation, but
the contract is the protocol defined here — not the gem. Where this document and
the implementation disagree, this document is the source of truth and the
implementation is the bug.

---

## 1. What textus is

A storage convention and JSON wire protocol for humans, agents, and automation to read and write structured project memory **deterministically**. It provides addressable dotted keys, schema validation, capability-based write gates, declarative data sources, and a list of publish targets that copy or render that data.

The storage lives in a `.textus/` directory at the project root. Each entry is a Markdown file with YAML frontmatter. A manifest binds dotted keys to subtrees, declares the capabilities each role holds, and declares each lane's kind — write authority for a lane is derived from the role's capabilities and the lane's kind. Schemas (also YAML) define what frontmatter shape each entry must have. Produced entries acquire their data via a declared `source:` (a pure projection over other entries, an external fetch, or an out-of-band workflow); that data is then optionally published to repo-relative paths — copied verbatim, or rendered through a per-target ERB template. The CLI surface (`textus get/put/list/where/schema/drain/...` `--output=json`) returns a versioned envelope any caller can parse without knowing Markdown.

You **shape your own memory structure** inside `.textus/`. The protocol manages how it's read, written, addressed, validated, gated, computed, and published. The contents are entirely yours.

### 1.1 Vocabulary axes

textus/4 names its concepts along six axes. Reviewers who internalize these can map any part of the spec to the right category:

- **Actor** — who is interacting: roles such as `human`, `agent`, `automation`, each holding a set of capabilities (`propose`, `author`, `keep`, `converge`).
- **Place** — where data lives: lanes such as `knowledge`, `notebook`, `raw`, `proposals`, `artifacts`.
- **Thing** — what is stored: entries, fields, keys.
- **Operation** — how you act on things: RPC and CLI verbs (`get`, `put`, `drain`, `serve`, `ingest`, …).
- **Event** — what gets fired after an operation: pub-sub events (`:entry_written`, `:entry_produced`, `:entry_published`, …).
- **Rule** — constraints declared in the top-level `rules:` array of the manifest.

### 1.2 The five layers

textus is organized as five composable layers. Each layer has a single responsibility; later layers build on earlier ones.

| Layer | Name | Responsibility |
|---|---|---|
| L1 | **Store** | Plain-file backend: `.textus/data/<lane>/...` with YAML frontmatter + Markdown body, addressed by dotted keys, schema-validated, etag-versioned. |
| L2 | **Sources** | Produced entries in the `artifacts` machine lane declare a `source:` block (`from: external` + a `Textus.workflow` block) that acquires their data on `drain`. textus *describes* sources; the workflow DSL acquires data and returns it to the store. |
| L3 | **Source** | An entry's `source:` *acquires* **data** — a pure in-process projection from store entries (select/pluck/sort/transform), an external fetch via a handler, or an out-of-band command. Acquire-only: rendering is not a source concern. No shell execution. |
| L4 | **Publish** | Emits a produced entry's data to repo-relative paths, declared via a **list** of `publish:` targets. A target with no `template:` copies the data verbatim (json/yaml re-serialized without `_meta`; other formats byte-copied); a target with a `template:` renders the data through it. A `{ tree: }` target mirrors a subtree (ADR 0047). Published artifacts are clean content — textus's `_meta` provenance stays in the store. A sentinel under `.textus/.run/sentinels/<target-rel-path>.textus-managed.json` (git-ignored runtime state) records the source, sha256, and `mode: "copy"`. |
| L5 | **Consumers** | Anything that reads the published files or calls the CLI — editors, LLM tools, MCP servers, CI jobs, dashboards. textus is agnostic about who consumes; the envelope is the contract. |

## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/4`) any language can speak.
- Deterministic read/write of structured Markdown via a CLI returning JSON.
- Schema-validated frontmatter using YAML schemas as data.
- Capability-based write gates (roles hold capabilities; write authority per lane is derived from the role's capabilities and the lane's kind).
- Optimistic concurrency via ETags.
- Pure declarative data sources: produced entries acquire their data via workflow DSL steps; rendering (ERB) is a separate publish concern.
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
  manifest.yaml          # internal: key → subtree mapping + role/lane declarations
  schemas/               # internal: YAML schema files
  templates/             # internal: ERB templates referenced by produced entries
  workflows/             # user: Textus.workflow DSL files for produced entry acquisition
  .run/                  # runtime (git-ignored): audit log, sentinels, locks, queue, pulse cursors
    audit.log            # append-only NDJSON log of every successful write
    sentinels/           # byte-copied publish bookkeeping (see §5.3)
  data/                  # ALL user content lives here
    knowledge/           # lane: knowledge (kind: canon — author-holders write)
    notebook/            # lane: notebook (kind: workspace — keep-holders write; agent's own durable lane)
    proposals/           # lane: proposals (kind: queue — propose-holders write)
    artifacts/           # lane: artifacts (kind: machine — converge-holders write)
    raw/                 # lane: raw (kind: raw — ingest-holders write; write-once)
```

Textus internals (`manifest.yaml`, `schemas/`, `templates/`, `workflows/`) live directly under `.textus/`; disposable runtime state (audit log, publish `sentinels/`, fetch/build locks, pulse cursors, job queue) lives under `.textus/.run/` (git-ignored, ADR 0038/0070). **All user content lives under `.textus/data/`.** Manifest `path:` fields are relative to `.textus/` — they include the `data/` prefix explicitly (e.g. `path: data/knowledge/foo.md`).

Lane directories under `data/` are conventional; their write semantics are derived from the lane's declared `kind:` (and the capabilities roles hold), not the directory name.

`.textus/audit.log` is an append-only NDJSON file written under a file lock by every successful `put`, `key_delete`, `key_mv`, and `accept`. Convergence (`drain`/`serve`) writes through these same verbs — a produced entry logs as `put`, a swept entry as `key_delete` — so there is no distinct `drain` audit verb. `.textus/role` (one line containing a role name) is optional and participates in the role-resolution order (§5).

### 3.1 Store location precedence

Implementations MUST resolve the store root in this order; the first match wins:

1. `--root <path>` flag passed to the CLI (or `root:` kwarg to `Store.discover`).
2. `TEXTUS_ROOT` environment variable.
3. Walk up from cwd looking for a `.textus/` directory containing `manifest.yaml`.

When (1) or (2) names a path that has no `manifest.yaml`, the CLI exits with `io_error` and a message naming the resolved absolute path. When (3) reaches the filesystem root without finding a store, the CLI exits with `io_error` naming the search start point.

## 4. Manifest

The manifest declares: (a) which roles exist and the capabilities each holds, (b) which lanes exist and each lane's `kind:`, (c) the key-to-subtree mapping, (d) the schema applied to entries in each subtree, and (e) the owner string recorded in writes. Write authority is **derived** — a role may write a lane iff it holds the capability the lane's kind requires (§5).

```yaml
# .textus/manifest.yaml
version: textus/4

roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose] }
  - { name: automation, can: [converge] }

lanes:
  - name: knowledge
    kind: canon
  - name: notebook
    kind: workspace
    owner: agent              # optional, informational — agent's own lane
    desc: "agent's durable working memory; bytes climb to knowledge only via propose→accept"
  - name: proposals
    kind: queue
  - name: artifacts
    kind: machine            # machine-maintained: external inputs (artifacts.feeds.*) + computed outputs (artifacts.derived.*)

entries:
  - key: knowledge.identity.self
    path: data/knowledge/identity/self.md
    lane: knowledge
    schema: identity

  - key: knowledge.network.org
    path: data/knowledge/network/org
    lane: knowledge
    schema: person
    owner: human:network
    nested: true

  - key: artifacts.catalogs.people
    path: data/artifacts/catalogs/people.md
    lane: artifacts
    schema: null
    owner: automation:converge

rules:
  - match: artifacts.feeds.**
    retention: { ttl: 6h, action: archive }

audit:
  max_size: 10485760   # bytes before rotating (default: 10 485 760 = 10 MiB)
  keep: 5              # rotated files to retain (default: 5)
```

Zone names are conventional — write authority comes from each lane's declared `kind:` crossed with the capabilities roles hold (§5); rename lanes freely.

**Key grammar:** dotted segments matching `/^[a-z0-9][a-z0-9-]*$/`. Segments are joined by `.`. A key has at most 8 segments; each segment is at most 64 characters. Segments MUST NOT contain dots, slashes, uppercase letters, or underscores. Example: `working.projects.acme.dashboard`. Enforcement points: manifest load (rejects illegal `key:` declarations and illegal nested file/directory names), `put` (rejects illegal keys before any write), `enumerate` (filters and warns on illegal filenames).

**Per-entry `format:`** an entry MAY declare `format:` to be one of `markdown` (default), `json`, `yaml`, or `text`. The `format` controls the on-disk shape and which path extension is required:

| `format`   | Path extension              | `template:`           | `schema:` |
|------------|-----------------------------|------------------------|-----------|
| `markdown` | `.md` (or appended if absent) | required for produced | optional  |
| `json`     | `.json` required            | optional (escape hatch) | optional (top-level keys) |
| `yaml`     | `.yaml` or `.yml` required  | optional (escape hatch) | optional (top-level keys) |
| `text`     | `.txt` or no extension      | required for produced | MUST be null |

For `nested: true`, the recursive glob matches the format's extension (markdown→`**/*.md`, json→`**/*.json`, yaml→`**/*.{yaml,yml}`, text→`**/*.txt`). All files under one nested entry share one format and one schema. Each matching file is enumerated as its own key, with the key segments derived from the path relative to the entry (extension stripped). A nested entry that instead mirrors a whole directory of files to a consumer path — without enumerating any of them as keys — uses a `{ tree: }` publish target (below); its files are opaque payload. (The former `index_filename:` directory-keyed enumeration was removed in 0.43.0 — ADR 0053.)

**The `publish:` list (ADR 0052, ADR 0094).** Publishing is configured by a `publish:` **list** of targets; each element is exactly one of a to-target `{ to:, template?:, inject_boot?: }` (file emit, §5.3) or a tree-target `{ tree: }` (subtree mirror, below). The legacy *map* forms (`publish: { to: [...] }`, `publish: { tree: ... }`) and the older top-level `publish_to:` / `publish_tree:` keys are rejected at load with a migration message — `publish:` is a list, and a mirror is a `{ tree: }` element of it.

**Subtree mirror (a `{ tree: }` target).** A nested manifest entry MAY include a `{ tree: "dir" }` target to mirror its entire stored subtree (`data/<lane>/**`) to a single target directory, preserving relative layout (case and extension preserved). It is **path-driven, not key-driven**: no keys are enumerated, no template variables are interpreted, and the mirrored files are opaque payload (never addressable). The entry's `ignore:` globs (§4, ADR 0042) filter the walk; each mirrored file gets its own sentinel; and on every drain the whole target directory is pruned of textus-managed files the current source no longer produces (unmanaged files are never touched). When a `{ tree: }` target directory overlaps another entry's `{ to: }` target (e.g. a derived `SKILL.md` written into the mirrored dir), the mirroring entry **must** `ignore:` that filename or prune will delete it — `doctor` flags this as `publish.tree_index_overlap`. See ADR 0047.

```yaml
- key: knowledge.skills
  path: data/knowledge/skills
  lane: knowledge
  schema: skill
  nested: true
  publish:
    - { tree: "skills" }
  ignore: ["*.tmp", ".DS_Store"]
```

**Lookup rule:** to resolve a key, find the entry with the longest `key:` prefix that matches. If that entry has `nested: true`, the remaining segments map to subdirectories under its `path`. Otherwise the key must equal an entry exactly. The resolved filesystem path is `<.textus root>/<entry.path>[/<remaining>...].md` — manifest `path:` values include the `data/` prefix (e.g. `data/knowledge/network/org`).

## 5. Lanes and capability-based write gates

Write authority is **derived**, never declared per-lane. Each lane declares a `kind:`; each lane-kind requires one capability to write to it. A role may write a lane iff its capability set (`role.can`) contains the verb that lane-kind requires. textus gates **writes, not reads**: reads are unrestricted at the protocol layer (the `.textus/` files are on disk). Per-role read-scoping, if needed, is an agent-surface projection, not a manifest field.

The kind→verb mapping is closed:

| Lane `kind` | Required capability | Meaning |
|---|---|---|
| `canon` | `author` | Authored truth — only the trust anchor writes directly. |
| `workspace` | `keep` | Agent's own durable lane — bytes never auto-promote; climb to `canon` only via propose→accept. |
| `machine` | `converge` | Machine-maintained: computed outputs produced by `drain`. |
| `queue` | `propose` | Proposals awaiting promotion. |
| `raw` | `ingest` | Write-once external source material (URL bookmarks, files, assets). |

This is a **bijection** (lane-kind ⟺ capability) (ADR 0091, extended by ADR 0116 with the `raw → ingest` pair): each lane-kind maps to exactly one capability.

`owner:` on a lane is OPTIONAL, INFORMATIONAL metadata (not enforced in 0.33.0 — owner-scoped enforcement is deferred). `desc:` on a lane is optional; the value surfaces as the `purpose` field in `textus boot` lane rows.

Default scaffold — Setup-1 (roles `human=[author, propose, ingest]`, `agent=[propose, keep, ingest]`, `automation=[converge, ingest]`):

| Lane | `kind` | Required capability | Writable by (default) | Use case |
|---|---|---|---|---|
| `knowledge` | `canon` | `author` | `human` | Authored truth: identity, voice, decisions, network. |
| `notebook` | `workspace` | `keep` | `agent` | Agent's own durable working memory. Bytes climb to `knowledge` only via propose→accept. |
| `proposals` | `queue` | `propose` | `agent`, `human` | Proposals awaiting human review via `textus accept`. |
| `artifacts` | `machine` | `converge` | `automation` | Computed outputs produced by `drain` via the workflow DSL. |
| `raw` | `raw` | `ingest` | `human`, `agent`, `automation` | Write-once external source material: URL bookmarks, files, binary assets. |

A write is gated by the caller's **role**, supplied via `--as=<role>`. If the role does not hold the capability the target lane-kind requires, the write returns `write_forbidden` with the message `writing '<key>' (lane '<lane>') needs capability '<verb>'` and a hint naming the roles that hold it (`held by: <roles>`, or `held by: no declared role` when none do).

Every lane MUST declare a `kind:` describing its role in the data-flow graph.
The vocabulary is closed: `canon` (authored truth), `workspace` (agent's own
durable lane), `machine` (machine-maintained computed outputs), `queue`
(proposals awaiting promotion), `raw` (write-once external source material). A
manifest MUST declare at most one `queue` lane and at most one `machine` lane.
Because authority is derived, a manifest is rejected at load if it declares a
lane whose required verb is held by **no** declared role (`machine` ⇒ a role with
`converge`, `queue` ⇒ `propose`, `workspace` ⇒ `keep`, `canon` ⇒ `author`,
`raw` ⇒ `ingest`). Coordination is keyed off the declared kind: a lane is
machine-maintained only if it declares `kind: machine`, and proposals route to
the declared `queue` lane — there is no name-based fallback. A manifest with a
kind-less lane is rejected at load.

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
| `automation` | `[converge]` | Scheduled or one-shot scripts: keep the `machine` lane current — pull external sources in and materialize computed outputs. |

Roles are declared in the manifest's `roles:` block (§5.1.1); the names above are the default mapping when `roles:` is omitted. Unknown role values are rejected with `invalid_role`.

Every successful write records the resolved role and a wall-clock timestamp in `.textus/audit.log`, so reviewers can later distinguish a human edit from an agent edit even though both live in the same file.

#### 5.1.1 Capabilities

Roles declare **capabilities** — verbs from a closed four-element set. A
manifest declares a `roles:` block mapping each role name to the capabilities
it holds via `can:`:

```yaml
roles:
  - { name: owner,    can: [author, propose] }
  - { name: proposer, can: [propose] }
  - { name: machine,  can: [converge] }
  - { name: keeper,   can: [keep] }
```

Capability allow-list: `propose`, `author`, `keep`, `converge`. The mapping from
lane-kind to its required capability is a **bijection** (ADR 0091, which folded
the former `quarantine` + `derived` kinds back into one `machine` kind — undoing
the two-kind split of ADR 0090): each capability authorizes exactly one
lane-kind:

| Capability | Authorizes writes to lane-kind |
|---|---|
| `author` | `canon` |
| `keep` | `workspace` |
| `propose` | `queue` |
| `converge` | `machine` |

A manifest naming a folded capability — `ingest` or `build`, or the pre-0088
spelling `fetch` — in a `can:` list is rejected at load with a hint pointing to
`converge` (ADR 0090, 0091, 0111).

`author` is the single **trust anchor**: **at most one role may hold `author`**
(a manifest declaring two or more is rejected at load). The `accept` and
`reject` transitions also require the `author` capability — `accept` is a
transition verb, not a capability. Because write authority is derived, there is
no `write_policy:` — instead, every declared lane-kind's required verb MUST be
held by at least one role, or the manifest is rejected at load.

When the `roles:` block is omitted, the default mapping applies:

| Default name | Capabilities (`can`) |
|---|---|
| `human`      | `[author, propose]` |
| `agent`      | `[propose, keep]` |
| `automation` | `[converge]` |

Wire protocol `textus/4` is unchanged — capabilities are a manifest/semantics
concept and never appear on the wire.

Every write transition is authorized by **one Guard** (ADR 0031): an ordered
list of predicates over a single evaluation context. Predicate #0 of every write
guard is `zone_writable_by` (the capability gate above); the `author_held`
predicate keys on the `author` capability and is named `author_held` (it passes
when the acting role holds `author`). See §5.11 for composing extra predicates via
`rules[].guard:`.

### 5.2 Source layer (produced entries)

Produced entries live in a `machine` lane (writable by a role holding `converge`; `automation` by default) — `artifacts` in the default scaffold. They are not authored by hand; their **data** is acquired from a declared `source:` block with `from: external`. A `source:` is **acquire-only**: it produces the data the store holds; it does **not** render. Rendering is a publish concern (§5.3). Every produced entry is `kind: produced` (ADR 0095).

#### 5.2.1 External source (`from: external`)

A produced entry that acquires its data via the `Textus.workflow` DSL declares `source: { from: external, command: "true", sources: [] }`. textus does **not** execute the command field; the workflow DSL block (in `.textus/workflows/**/*.rb`) runs on `drain` and returns the data to be stored.

```yaml
- key: artifacts.skills
  lane: artifacts
  kind: produced
  format: json
  source: { from: external, command: "true", sources: [] }
  publish: [{ to: docs/reference/skills.md, template: feeds/skills.erb }]
```

A matching `Textus.workflow` block in `.textus/workflows/`:

```ruby
Textus.workflow "agentskills" do
  match "artifacts.skills"

  step :fetch do |_, _ctx|
    # acquire data — return { "content" => { ... } }
    { "content" => { "skills" => [...], "count" => 1 } }
  end

  publish
end
```

`drain` discovers all workflow files, matches each to the produced entries via `match`, runs the steps, and writes the result back to the entry's data path. `publish:` then copies or renders it to consumer paths.

**`sources:`** lists dotted-key prefixes or repo-relative paths whose mtimes `doctor`'s `generator_drift` check compares against `_meta.generated.at`. An empty list (`sources: []`) disables drift detection for that entry.

### 5.3 Publish layer (`publish:`)

Rendering and emission are a **publish** concern, orthogonal to acquire (§5.2). `publish:` is always a **list** of targets (ADR 0094). Each element is exactly one of two shapes:

- a **to-target** — `{ to: <path>, template?: <name> }` — emit the entry's data to one repo-relative path;
- a **tree-target** — `{ tree: <dir> }` — mirror the entry's stored subtree (ADR 0047).

The legacy *map* forms — `publish: { to: [...] }` and `publish: { tree: ... }` — and the older top-level `publish_to:` / `publish_tree:` keys are **rejected at load** with a migration message: `publish:` is a list, and a mirror is a `{ tree: }` element of it.

```yaml
publish:
  - { to: CLAUDE.md, template: orientation.erb, inject_boot: true }
  - { to: AGENTS.md, template: orientation.erb }   # same data, its own render
  - { to: .mcp.json }                                    # no template → copy data verbatim
  - { tree: skills/ }                                    # subtree mirror (ADR 0047)
```

A **to-target** carries `to:` (required) and optionally `template:` / `inject_boot:`:

- **No `template:`** → publish the entry's **content**. For a structured data format (`json`/`yaml`) the content is re-serialized *without* textus's `_meta` block, so a config like `.mcp.json` stays a clean consumer file; for any other / opaque format, a literal byte-copy. (This is "publish the content," not "copy the stored envelope.")
- **`template:` present** → render the entry's data through the named ERB template under `.textus/templates/` and publish the rendered bytes. One dataset can feed differently-formatted outputs by giving each to-target its own template.
- **`inject_boot:`** (default `false`) → merge the `textus boot` payload into the render data for *this target*. It is per-target and only meaningful alongside a `template:`.

**Published artifacts are clean content.** textus's `_meta` provenance (`from`/`reduce`, §5.12) stays in the **stored** entry and is never emitted — a verbatim copy strips it on re-serialize, a rendered template surfaces provenance only if it explicitly references `_meta`. There is no entry-level / publish `provenance:` flag (rejected at load); provenance is carried in one place, the stored data's `_meta`.

The ERB template receives the entry's `content` hash as local variables via `ERB#result_with_hash`. Templates live under `.textus/templates/` as `.erb` files. If `inject_boot: true` is set on the publish target, a `boot` variable is also available with the live orientation context.

A sentinel is written for each published file at `<store_root>/.run/sentinels/<target-relative-to-repo>.textus-managed.json` (git-ignored runtime state — ADR 0070), recording `source`, `target`, the target's sha256, and `mode: "copy"`. Sentinels live under the store's runtime tree rather than beside the consumer file so target directories stay clean, and are regenerated by the next drain (via content-identical adoption) rather than committed. The sentinel exists so out-of-band edits can be detected on the next publish — textus refuses to clobber a destination that is not either missing, marked as managed, or **byte-identical to the source being published**. An identical destination is *adopted*: its sentinel is written and management proceeds (the copy is a content no-op), so an artifact tree already on disk onboards without a manual delete. An unmanaged destination whose content **differs**, or any unmanaged symlink, is still refused (ADR 0050). Legacy sibling sentinels (`<target>.textus-managed.json`) are still recognised as managed and are migrated to the new location on the next publish.

**Subtree mirror.** A nested entry MAY include a `{ tree: "dir" }` target (see §4). On every drain/serve pass, textus walks the entry's full stored subtree (`data/<lane>/**`), applies the entry's `ignore:` filter, and byte-copies each file to the target directory, preserving relative layout — one sentinel per file under `<store_root>/.run/sentinels/`. The mirror is path-driven: no keys are enumerated, no template variables are interpreted, and mirrored files are opaque payload (never addressable). On rebuild, the entire target directory is pruned of textus-managed files the current source no longer produces; unmanaged files are never touched. The convergence envelope grows a `published_leaves` array — one row per mirrored file, with `key`, `source`, and `target` — alongside the existing `produced` array, plus a `pruned` array listing any orphaned managed files removed on this pass. Targets that would resolve outside the repo root are refused. When a `{ tree: }` target overlaps another entry's `{ to: }` target (e.g. a derived `SKILL.md` written into the mirrored dir), the mirroring entry must `ignore:` that filename or prune will delete it — `doctor` flags this as `publish.tree_index_overlap` (ADR 0047).

**Publish presence is a uniform rule across all kinds.** Absent → the entry is terminal data (consumed internally via another entry's `select`, or read via `get`). Present → emit to the listed targets, every kind through one publish path. A `from: command` entry with publish targets emits the bytes the command already wrote into the store; without targets it is a staleness-only signal.

### 5.4 Raw lane and ingest verb

The `raw` lane (`kind: raw`) is a write-once intake lane for external source material that has not been reviewed. All three default roles (`human`, `agent`, `automation`) hold the `ingest` capability. (ADR 0116)

**Write-once contract** — the same key MAY NOT be written twice on the same day. A collision returns `write_forbidden`. To replace an entry, delete it and re-ingest.

**Key derivation** — the `ingest` verb derives a daily key: `raw.YYYY.MM.DD.<kind>-<slug>` where `YYYY.MM.DD` is the UTC date at ingest time.

**Three source kinds:**

| Kind | Required fields | Stored content |
|------|----------------|----------------|
| `url` | `--url` | URL reference only (`body: null`) — a bookmark, never a content fetch |
| `file` | `--path` | File body text — use only for genuinely valuable content |
| `asset` | `--path`, `--zone` | Binary copied to `assets/raw/YYYY/MM/DD/<zone>/`; inline body is null |

**`access` field** — entries MAY carry `source.access: public | private` (field is `maintained_by: human`). Set `private` for sources not safe to reproduce publicly.

**Notebook stub** — every ingest creates a `notebook.notes` stub with a backlink (`Ingested from raw.<key>`) so the agent or human can annotate the ingested material without touching the write-once record.

**Example — URL bookmark:**

```sh
textus ingest url agentskills-io-brainstorming \
  --url=https://agentskills.io/skills/brainstorming \
  --label="brainstorming skill" \
  --as=agent
```

A `get` on a raw entry is a pure read — it returns the entry as stored and never re-fetches (ADR 0089).

### 5.5 Pending / accept workflow

Proposal entries are full patches authored into the `proposals` queue lane (writable by `propose`-holders: `agent` and `human` by default) — `proposals` in the default scaffold (Setup-1) — typically by agents. The entry's frontmatter describes the patch it proposes against another lane:

```yaml
---
proposal:
  target_key: working.network.org.bob
  action: put
_meta:
  name: bob
  relationship: peer
  org: acme
---
Proposed body content.
```

`proposal.target_key` names the entry the patch would create or modify, and `proposal.action` is `put` or `delete`. The sibling `_meta` block and the body are the proposed new content — a proposal carries the same `{ _meta, body }` envelope shape it intends `accept` to write (ADR 0113). A proposal's `target_key` MUST resolve to a `canon` lane; `accept` refuses any other target (`target_is_canon`, ADR 0035).

`textus accept <proposal-key>` is a **transition** (not a capability) that requires the **`author` capability**: the resolved role must hold `author` (the single trust anchor — `human` by default). It copies the patch into the target lane, records provenance (originating proposal key, original role, original timestamp) in the audit log, and removes the proposal entry. The `reject` transition likewise requires `author`. Roles holding only `propose` (e.g. `agent`) can propose but cannot accept or reject.

### 5.6 Audit log

Every successful write appends one compact JSON object (NDJSON) to `.textus/audit.log`. The file is opened with `flock(LOCK_EX)` for the duration of each append so concurrent writers serialize cleanly.

Schema (one JSON object per line, no interior whitespace):

```json
{"seq":<integer>,"ts":"<iso8601-utc>","role":"<role>","verb":"<verb>","key":"<key>","etag_before":<etag-or-null>,"etag_after":<etag-or-null>}
```

`seq` is a monotonic integer counter, auto-incremented on each append. It is the foundation for cursor-based queries: `textus audit --seq-since=N` returns only rows with `seq > N`, and `textus pulse --since=N` builds its `changed` array from the same cursor. When an agent's cursor falls below the oldest available seq (due to log rotation), the operation raises `CursorExpired`.

`ts` is the wall-clock timestamp in UTC with second precision. `role` is the resolved role for the invocation. `verb` is the audit-log payload string identifying the operation (`put`, `key_delete`, `accept`, `compute`, `key_mv`, ...; rows written before ADR 0082 used `delete`/`mv` — readers must accept both). `key` is the affected entry key. `etag_before` and `etag_after` are the entry etags before and after the write, or JSON `null` when not applicable (e.g. create has no before-etag, delete has no after-etag).

For `key_mv`, the structural fields `from_key`, `to_key`, and `uid` appear at the top level of the JSON object. Remaining verb-specific data (e.g. `from_path`, `to_path`) is nested under an `extras` key. The `extras` key is omitted entirely when empty.

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

### 5.9 Rules

A manifest MAY declare a top-level `rules:` block — a list of rule blocks matched against entry keys by glob. Each block carries one or more slots:

```yaml
rules:
  - match: feeds.**
    retention: { ttl: 90d, action: archive }

  - match: feeds.calendar.**
    handler_permit: [ical-events]

  - match: proposals.**
    guard:
      accept: [schema_valid, author_held]
```

**Slots (all optional within a block):**

| Slot | Type | Meaning |
|---|---|---|
| `retention` | `{ ttl, action: drop\|archive }` | Age-based garbage collection (ADR 0093). `action` is `drop` (delete the entry) or `archive` (copy to `<store>/archive/<relative-path>` then delete). Age is measured from `_meta.last_fetched_at` (intake entries) when present, else the leaf file's modification time. **Destructive — applied only on the convergence sweep (the destructive phase of `drain`/`serve`), never on a write or read.** Orthogonal to production: an intake entry may declare both `source: { ..., ttl: 1h }` (re-pull cadence) and a `retention: { ttl: 90d, action: archive }` rule. `retention:` on a `derived` entry is rejected at load. |
| `handler_permit` | list of strings | Constrains which `source.handler:` names may be used by intake entries matched by this block. Enforced by `textus doctor`. |
| `guard` | `{ <transition>: [predicates] }` | Extra predicates composed (AND) onto a write transition's built-in **base** guard (ADR 0031). Keyed by transition (`put`, `key_delete`, `key_mv`, `accept`, `reject`, `converge`). Predicate names are drawn from the closed vocabulary (`zone_writable_by`, `schema_valid`, `author_held`, `target_is_canon`, `etag_match`, `fresh_within`); parameterized predicates use `{ name: param }` form, e.g. `{ fresh_within: "1h" }`. Enforced — the transition refuses (`guard_failed`) if any predicate fails; the topology refusal keeps the `write_forbidden` code. |

The `retention:` slot handles age-based GC only. Write-trigger strategy for derived entries (`on_write: sync|async`) is declared on the entry's own `source:` block (§5.2.1), not in `rules:`. Generator/build drift — a derived entry whose sources changed since its `generated.at` — is reported by the `textus doctor` `generator_drift` check rather than any rule slot.

**Match grammar.** `match:` is a single glob using `*` (single segment) and `**` (any depth). A literal segment ranks more specifically than `*`; `*` ranks more specifically than `**`.

**Resolution.** For each key textus computes a `RuleSet { intake_handler_allowlist, guard, retention }` by walking every block whose `match` matches the key, ranked by specificity. **Per slot, the most specific block wins.** Two blocks of equal specificity that match the same key and fill the same slot is a manifest error reported by `textus doctor` (`rule_ambiguity`).

**Read surface.** `textus rule list` dumps every block. `textus rule explain KEY` shows the resolved `RuleSet` for one key — lean effective `{retention, guard}` by default; `--detail` adds every matched block and the effective guard predicate names for every write transition (ADR 0059).

### 5.10 Storage formats

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

Entries in a `produced` lane SHOULD additionally carry the `generated:` block defined in §5.2. Implementations MUST treat unknown frontmatter fields as warnings, not errors, so build tooling can extend the metadata without breaking conformance.

## 8. Envelope (the wire format)

Every successful CLI response (`--output=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/4",
  "key": "knowledge.network.org.jane",
  "lane": "knowledge",
  "owner": "human:network",
  "path": "/absolute/path/to/.textus/data/knowledge/network/org/jane.md",
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
- `protocol` MUST be the exact string `textus/4`.
- `key` MUST be the canonical resolved key.
- `lane` MUST be one of the lanes declared in the manifest (`knowledge`, `notebook`, `feeds`, `proposals`, `artifacts` in the default Setup-1 scaffold).
- `path` MUST be an absolute filesystem path.
- `format` MUST be one of `markdown`, `json`, `yaml`, `text` (§5.12). Absent envelopes are treated as `markdown` for back-compat.
- `body` is the raw on-disk bytes as a UTF-8 string for every format.
- `content` is present only when `format` is `json` or `yaml`; equals the parsed object. For `json|yaml`, `_meta` mirrors the top-level `_meta` block (or `{}` if absent). For `markdown`, `_meta` holds the parsed YAML frontmatter. For `text`, `_meta` is `{}`.
- `etag` MUST be `sha256:<hex>` of the raw file bytes, computed identically for every format.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.
- `uid` is the stable Textus UID (§7) if the entry carries one, else `null`. Always present in the envelope.
- `stale` is `true` when the entry's `source.ttl` has elapsed and the entry has not yet been re-materialised; `false` otherwise. Only populated for produced entries with a declared `ttl`; always `false` for other entries.
- `stale_reason` is a short human-readable string describing why the entry is stale (e.g. `"ttl_exceeded"`, `"never_fetched"`), or `null` when `stale` is `false`.
- `fetching` is `true` when a background re-pull is in flight for this entry; `false` otherwise. Callers observing `stale: true, fetching: true` SHOULD retry after a short delay.

> **Note:** `list`/`where` envelopes do **not** include `stale`, `stale_reason`, or `fetching` — freshness annotation is only provided by `get`.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/4",
  "ok": false,
  "code": "write_forbidden",
  "message": "writing 'knowledge.identity.self' (lane 'knowledge') needs capability 'author'",
  "hint": "held by: human; pass --as=<role>",
  "details": { "key": "knowledge.identity.self", "lane": "knowledge", "verb": "author", "holders": ["human"] }
}
```

**Error codes:**

| Code | Meaning | Default exit |
|---|---|---|
| `unknown_key` | Key does not resolve | 1 |
| `bad_frontmatter` | YAML parse failed or `name:` mismatch | 1 |
| `schema_violation` | Required field missing or wrong type | 1 |
| `write_forbidden` | Resolved role lacks the capability the lane-kind requires | 1 |
| `etag_mismatch` | Concurrent write detected | 1 |
| `io_error` | Filesystem failure | 64 |
| `usage` | CLI argument error | 2 |

## 9. CLI surface

The reference binary is `textus`. Conforming implementations MAY use any binary name; the protocol is in the JSON.

All verbs accept `--output=json` and emit a canonical envelope (success or error). Write verbs require `--as=<role>`; the role must satisfy the target lane's write gate (§5). The per-entry `format:` field in the manifest is unchanged — `--output` controls only the CLI envelope rendering.

| Verb | Reads / writes | Role required |
|---|---|---|
| `list [--prefix=K] [--lane=Z]` | read | any |
| `where K` | read | any |
| `get K` | read (a pure on-disk read annotated with a freshness verdict; never refreshes — ADR 0089) | any |
| `schema show K` | read | any |
| `audit [--key=K] [--lane=Z] [--role=R] [--verb=V] [--since=X] [--correlation-id=ID] [--limit=N]` | read | any |
| `blame KEY` | read | any |
| `rule list` / `rule explain KEY` | read | any |
| `deps K` / `rdeps K` | read | any |
| `published` | read | any |
| `hook list` | read | any |
| `hook run NAME` | write | any |
| `doctor [--check=NAME[,NAME]] [--output=json]` | read | any |
| `boot [--output=json]` | read | any |
| `pulse [--since=N]` | read | any |
| `put K --stdin --as=R` | write (stores the stdin JSON; runs no handler — ADR 0089) | per lane |
| `propose K --stdin --as=R` | write | `propose`-holder (auto-prefixes propose_zone) |
| `key delete K --if-etag=E --as=R` | write | per lane |
| `drain [--prefix=K] [--lane=Z]` | write | `converge`-holder (typically `automation`) |
| `serve [--poll=SECS]` | write (long-lived daemon) | `converge`-holder (typically `automation`) |
| `jobs [--state=ready\|leased\|done\|failed] [--action=retry\|purge] [--job-id=ID]` | read | any |
| `accept K --as=human` | write | `author`-holder (typically `human`) |
| `reject K --as=human` | write | `author`-holder (typically `human`) |
| `init` | write | `human` |
| `schema {show,init,diff,migrate}` | read/write | `human` for writes |
| `key mv OLD NEW [--as=R] [--dry-run]` | write | per lane (same-lane only) |
| `key uid K` | read | any |

**`textus boot` envelope extras.** In addition to lanes, entries, hooks, write flows, and the `cli_verbs` catalog, the boot envelope includes an `agent_quickstart` block synthesized from the manifest's role capabilities:

```json
{
  "agent_quickstart": {
    "read_verbs":     ["get", "list", "pulse", "schema_show", "boot", "rule_explain", "where", "deps", "rdeps"],
    "write_verbs":    ["accept", "key_delete", "key_mv", "propose", "put", "reject"],
    "writable_lanes": ["proposals"],
    "propose_lane":   "proposals",
    "latest_seq":     1842
  }
}
```

`read_verbs` is derived from the MCP verb catalog — the verbs the agent can actually call over its transport — so it lists the read/discovery verbs (`schema_show` for an entry's field shape, `rule_explain` for its retention/guard policy, and the graph reads `where`/`deps`/`rdeps`, ADR 0060) and never the CLI-only `audit`/`doctor`, nor `freshness` (the Ruby-only internal lifecycle scan, ADR 0085) (ADR 0056). An agent learns an entry's `_meta` shape by calling the `schema_show` verb before a `put`/`propose`, not by shelling out to a CLI. The graph reads `deps`/`rdeps` return a structured `{key, deps}`/`{key, rdeps}` envelope on every surface (CLI, Ruby, MCP) — a hash, not a bare array, consistent with the other structured read responses such as `where` (ADR 0060 amendment).

The agent's MCP write surface includes the single-key `key_delete` and `key_mv` tools alongside their bulk `key_delete_prefix`/`key_mv_prefix` cousins (ADR 0060 amendment; the single-key tools were renamed from `delete`/`mv` to share the `key_` family stem in ADR 0082, which also removed the `migrate` YAML-plan orchestrator — its `zone_mv`/`key_mv_prefix`/`key_delete_prefix` ops remain individually callable). All of these apply by default; `dry_run: true` is a uniform opt-in preview that returns a Plan without mutating (ADR 0071 — verbs are actions, dry-run is opt-in on every surface). Single-key `key_delete` additionally accepts an optional `if_etag` optimistic-concurrency check. The blast-radius reads (`where`/`deps`/`rdeps`) remain on MCP so an agent can look before it leaps. The promotion verbs `accept` and `reject` are also on MCP (ADR 0072): they are gated by the `author_held` capability floor, not by transport absence — a default-`agent` connection is refused, while a connection launched as a role holding `author` (`--as`/`TEXTUS_ROLE`/`.textus/role`, resolved once at launch per ADR 0040) can promote, closing the propose→accept loop over one transport. `drain` is also on MCP (ADR 0076, ADR 0087, ADR 0110): it is caller-agnostic and its produce jobs self-elevate — materialization always runs as the manifest's `converge`-capable actor regardless of the calling role, granting no authority over content (materialization is a pure, idempotent function of already-accepted canon, ADR 0070); the destructive retention sweep runs as the caller. Each produce job self-acquires the single-writer build lock, so a concurrent CLI, reactive, or background pass cannot collide with an MCP-triggered one — a held lock is a graceful soft-miss (ADR 0110).

`latest_seq` is the current high-water mark of the audit log; agents should use it as the starting cursor for `pulse`.

**`textus pulse` output shape:**

```json
{
  "cursor":         1845,
  "changed":        [ { "seq": 1843, "key": "knowledge.notes.x", "verb": "put", "role": "human", "ts": "..." } ],
  "pending_review": [ "proposals.proposal.123" ],
  "contract_etag":  "sha256:1f3a…",
  "index_etag":     "sha256:8f3c…"
}
```

`cursor` is the new high-water mark; pass it as `--since` on the next call. `changed` is sourced from `audit --seq-since`. `pending_review` lists all keys in the `proposals` queue lane. `contract_etag` is the `sha256:`-prefixed composite content hash of the contract — the manifest plus hooks and schemas (ADR 0074, via ADR 0025) — for cheap change-detection. `index_etag` is the etag of the `artifacts.index` catalog file, or `null` when it does not exist — agents use this to detect when the catalog has been rebuilt. When `--since` is below the oldest available seq (due to audit log rotation), pulse returns `CursorExpired`.

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body.\n",
  "if_etag": "sha256:8f3c…" }
```

`if_etag` is optional on both `put` and `key_delete`. When provided, the write fails with `etag_mismatch` if the on-disk file's etag differs. When omitted, the write is unconditional (last-writer-wins).

The lifecycle scan behind `pulse.stale`/`pulse.next_due_at` reports, per entry, one verdict (`fresh`, `expired`, or `no_policy`) against each intake entry's `source.ttl`. ADR 0085 removed the standalone `freshness` verb that used to render these rows; the scan is now Ruby-only (consumed by `pulse` and the hook context), and human drill-down into a single entry's verdict is `textus get KEY` (carries `stale`/`stale_reason`) plus `textus rule_explain KEY` (the `source.ttl` and retention policy). `textus drain` enqueues the convergence jobs — produce every in-scope derived entry, re-pull every stale intake entry, and a retention sweep — then drains the queue to empty (§5.11). Convergence is async-only (ADR 0110): there is no `--dry-run`.

`textus accept K --as=human` promotes a pending entry into its target lane: it copies the patch body into the target key, deletes the pending entry, and writes one audit line per side (§audit). Only a role holding the `author` capability (the trust anchor — `human` by default) may invoke `accept`.

`textus drain [--prefix=K] [--lane=Z]` is the manual converge-and-exit pass (ADR 0093, ADR 0110). It seeds a closed allow-list of jobs into the durable file-backed queue (`Ports::Queue` under `.textus/.run/queue/`) and runs a worker until the queue is empty: a **`materialize`** job per in-scope derived / publish entry (always rebuild — pure/idempotent, unchanged sources write nothing; nested `{ tree: }` targets included), a **`re-pull`** job per intake entry past its `source.ttl`, and a single **`sweep`** job for the destructive `retention:` GC (§5.11). Authority is frozen at enqueue: `materialize`/`re-pull` self-elevate inside `Produce::Engine` to the manifest's `converge`-capable actor (`automation` by default) — materialization is a pure function of already-accepted canon and grants no authority over content — while `sweep` runs as the **caller** (gated as the caller's own `key_delete` authority), never self-elevating. Drain is single-pass and **serial**: each produce job self-acquires the non-reentrant build lock, so a held lock is a graceful soft-miss. `drain` returns `{ ok, completed, failed, health }` and exits non-zero if any job dead-lettered; per-key produce failures surface as `:produce_failed` events. There is no `--dry-run` (materialization is async-only). `textus serve` is the same worker as a long-lived daemon, whose `Scheduler` seeds TTL re-pull + sweep each tick; `textus jobs` inspects/retries/purges the queue. In day-to-day use derived entries stay fresh **reactively** — a canon write enqueues a `materialize` job for each dependent derived entry (the reactive scope is "converge narrowed to rdeps ∩ derived"), processed by a running `serve` or the next `drain` — so `drain` is the on-demand / CI catch-all, not a step in the normal write loop.

`textus init` scaffolds a fresh `.textus/` tree (manifest, lanes, schemas, audit log) under the current directory with a default manifest. Customize by editing `.textus/manifest.yaml` after init.

`textus schema show K` prints the schema for entry `K`. `textus schema init NAME` writes a stub schema. `textus schema diff NAME` compares the on-disk schema against entries that claim it and prints the deltas. `textus schema migrate NAME --rename=OLD:NEW` rewrites the `_meta` key `OLD` to `NEW` across every entry that uses the named schema, in a single transactional sweep that logs each touched file.

## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.

## 10.1 Errors carry hints

Every `Textus::Error` exposes `code`, `message`, and an optional `hint:`. The hint is a single short string suggesting the next action — the file to edit, the role to pass, the command to run. Errors in the wire envelope include the hint as a top-level `hint:` field when present. The CLI prints failures to stderr as `code: message` followed by `  → hint` (when a hint exists), in addition to the JSON envelope on stdout. Hints are advisory: implementations MAY omit or rephrase them without breaking conformance.

## 10.2 `textus doctor`

`textus doctor` returns a health-check envelope: `{ "protocol": "textus/4", "ok": bool, "issues": [...], "summary": {error, warning, info} }`. Each issue carries `code`, `level` (`error|warning|info`), `subject`, `message`, and optionally `fix`. `ok` is true iff no error-level issues are present; warnings and info do not flip the bit. Builtin checks: `protocol_version`, `manifest_files`, `schemas`, `schema_parse_error`, `templates`, `intake_registration`, `illegal_keys`, `sentinels`, `audit_log`, `unowned_schema_fields`, `schema_violations`, `rule_ambiguity`, `handler_permit`, `fetch_locks`, `proposal_targets`, `publish.tree_index_overlap`, `generator_drift`. Additional registered `:validate` hooks (§5.10) run after the builtin set. Exit code is 0 on `ok`, 1 otherwise.

## 11. Versioning

- The current wire string is `textus/4`.
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/4`.
- Breaking changes (renamed/removed envelope fields, lane semantics, key grammar) require a new wire string `textus/4`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently and speaks `textus/4`.

## 11.1 Agent integration

Agents interact with a textus store through two verbs: `boot` (once per session, for orientation) and `pulse` (per turn, for deltas). The `boot` envelope's `agent_quickstart` block gives the agent its starting cursor (`latest_seq`), its writable lanes, and its propose lane. The `pulse` verb returns a delta envelope keyed on that cursor. When audit log rotation expires a cursor, `CursorExpired` signals the agent to call `boot` again.

For the full boot → pulse loop with pseudocode and cursor-expiry handling, see [`docs/how-to/agents-mcp.md`](docs/how-to/agents-mcp.md).

## 12. Conformance fixtures

A conformant implementation MUST pass these fixtures (the reference test suite ships a YAML file listing inputs and expected envelopes):

**Fixture A — Resolve and read:**
Given a manifest with `working.network.org` → `working/network/org` (nested), schema `person`, and a file `.textus/data/working/network/org/jane.md` with valid frontmatter, `textus get working.network.org.jane --output=json` returns the canonical envelope with `etag` matching the file's sha256.

**Fixture B — Role gate on write:**
Given a manifest entry where `key: identity.self` lives in the `identity` lane (`kind: canon`, requiring the `author` capability), `textus put identity.self --stdin --as=agent` (where `agent` holds only `propose`) returns the error envelope with `code: "write_forbidden"` and exit code 1.

**Fixture C — Schema violation:**
Given the `person` schema and a `put` whose frontmatter omits `relationship`, the result is the error envelope with `code: "schema_violation"`, `details.missing: ["relationship"]`, and exit code 1.

**Fixture D — Staleness detection:**
Given a manifest entry `artifacts.feeds` with `kind: produced` and a `retention: { ttl: 1h }` rule, and an envelope on disk whose `_meta.last_fetched_at` is older than `now - ttl`, `textus pulse --output=json` lists `artifacts.feeds` in its `stale` array (the lifecycle scan classifies it `expired`). The scan is pure: producing this verdict does NOT trigger a re-materialise.

**Fixture E — Workflow produce:**
Given a manifest entry `artifacts.skills` with `kind: produced` and `source: { from: external, command: "true", sources: [] }` and a matching `Textus.workflow` block, `textus drain --prefix=artifacts.skills` produces the entry's **data** on disk (serialized per `format:`) matching the workflow's returned content. The output is content-addressed (no `generated_at` timestamp, ADR 0070), so re-running with unchanged sources reproduces it byte-for-byte and writes nothing.

**Fixture F — ERB render at publish:**
Given a produced entry with a to-target `{ to:, template: <name> }`, `textus drain` renders the entry's stored data through the named ERB template (under `.textus/templates/`) and emits a file whose contents match the expected rendered output byte-for-byte (after trailing-newline normalization). Two to-targets with different templates produce different bytes from the one entry.

**Fixture G — Copy publish:**
Given a manifest entry with a templateless to-target `publish: [{ to: <path> }]`, a successful `textus drain` for that entry leaves a plain file at `<path>` whose contents are the entry's content re-serialized without `_meta` (byte-identical to a clean consumer config), accompanied by a sentinel at `.textus/.run/sentinels/<path>.textus-managed.json` recording `source`, `target`, `sha256`, and `mode: "copy"`. Re-running `drain` is idempotent.

**Fixture H — Audit log format:**
Every successful write verb (`put`, `key_delete`, `key_mv`, `accept`, `schema migrate`) appends exactly one line per affected key to the audit log, in the canonical format defined in §audit (timestamp, actor role, verb, key, etag-before, etag-after). Convergence (`drain`/`serve`) writes through these same verbs (`put` for a produced entry, `key_delete` for a swept one), so it appends per the underlying write, not under a distinct `drain` verb. No write produces zero or multiple lines per key.

**Fixture I — Pending → accept:**
Given a proposal entry `proposals.knowledge.self.patch` proposing a change to `knowledge.identity.self`, `textus accept proposals.knowledge.self.patch --as=human` copies the patch body into the target key, deletes the proposal entry, and appends two audit lines (one for the target write, one for the proposals delete) in that order.

## 13. Why not X?

- **Why not MCP?** MCP is a transport; textus is a data model. The two compose: a 50-line MCP server can wrap `textus get/put` as tools. textus exists because the *shape* of agent-readable project memory deserves a standalone spec, separate from how it's served.

- **Why doesn't textus execute external build commands itself?** textus is a dataflow oracle, not a build runner. The moment a spec includes process execution, it inherits shell-injection surface, OS-portability concerns, and signal-handling semantics — and ends up duplicating whatever build system the consumer already runs (make, rake, just, lefthook, CI). Keeping execution external means a Python or TypeScript port of `textus/4` only has to parse YAML and emit JSON; it doesn't have to spawn processes safely. External build systems stay the executor; textus stays a data tool.

- **Why not plain Markdown vaults (Obsidian / Foam)?** No schema enforcement, no write-gating, no addressable wire format. Fine for human notes; underspecified for agents that must act on the contents deterministically.

- **Why not Notion / Coda?** Closed, hosted, lossy export. textus is local-first, plain-files, diffable in git.

- **Why not JSON Schema for the schemas?** Considered. Bespoke YAML chosen for v1: simpler implementation, lighter dependency footprint, matches the reference impl's house language. JSON Schema MAY be added as an alternate schema-language adapter in a future minor revision without breaking `textus/4`.

- **Why not a database (SQLite, kv store)?** textus's whole point is that the storage is plain files agents and humans both read. A binary store loses git-diff, grep, and editor support.

- **Why not vector embeddings?** Different problem. textus is for facts agents act on deterministically; embeddings are for fuzzy retrieval. They compose — index a textus tree into a vector store if you need both.

## 13.1 Layered architecture (internal)

Textus internals are organized as one-way layers — **Surfaces** (`surfaces/cli/`, `surfaces/mcp/`) → **Contract** (`contract/`) → **Dispatch** (`dispatch/`) → **Manifest + Core + Ports + Step** (domain and adapters). Each layer imports only from layers to its right. Plugin authors touch only the Step DSL and the manifest YAML; the layering is internal and may evolve.

See [`docs/architecture/README.md`](docs/architecture/README.md) for an ASCII diagram and the full read-path walkthrough.


