# textus/1 — Specification

**Status:** Draft v0.1 (2026-05-18)
**Protocol identifier:** `textus/1`
**Reference implementation:** Ruby gem `textus` (planned)

> *textus* — Latin for "the fabric a text is woven from," same root as *context* (from *con-texere*, "to weave together"). This spec defines a storage shape and wire protocol for that fabric.

---

## 1. What textus is

A storage convention and JSON wire protocol that lets AI agents and human collaborators read and write structured project memory **deterministically**, by addressing entries with dotted keys instead of paths, with **schema validation** and **zone-based write gates**.

The storage lives in a `.textus/` directory at the project root. Each entry is a Markdown file with YAML frontmatter. A manifest binds dotted keys to subtrees. Schemas (also YAML) define what frontmatter shape each entry must have. The CLI surface (`textus get/put/list/where/schema --format=json`) returns a versioned envelope that any agent or tool can parse without knowing Markdown.

You **shape your own memory structure** inside `.textus/`. The protocol manages how it's read, written, addressed, validated, and gated. The contents are entirely yours.

## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/1`) any language can speak.
- Deterministic read/write of structured Markdown via a CLI returning JSON.
- Schema-validated frontmatter using YAML schemas as data.
- Write gating via zones (some entries are agent-writable, some aren't).
- Optimistic concurrency via ETags.
- Plain-file backend — agents can also read raw if they prefer.

**Non-goals**
- Not a database. No queries, indexes, joins, or full-text search.
- Not a graph store. Keys are hierarchical strings; cross-links are unindexed.
- Not a sync protocol. Single-writer per file, ETag-checked.
- Not a transport. Spawn the CLI or wrap it in MCP/HTTP downstream.
- Not a UI. Filesystem + CLI. Viewers ship elsewhere.

## 3. Storage layout

The root is `.textus/` at the project working directory. A typical tree:

```
.textus/
  manifest.yaml              # key → subtree mapping + zone declarations
  schemas/                   # YAML schema files
    person.yaml
    project.yaml
    decision.yaml
  fixed/                     # zone: fixed (human-only writes)
    ...
  state/                     # zone: state (agent-writable)
    network/org/
      jane.md
      ...
    projects/
      acme/dashboard.md
      ...
  derived/                   # zone: derived (build-tool writes only)
    catalogs/
      ...
```

Zone directories are conventional but their semantics are declared in the manifest, not the directory name. The reference implementation defaults to the names above; alternative layouts are allowed if the manifest reflects them.

## 4. Manifest

The manifest declares the key-to-subtree mapping, the zone each subtree belongs to, the schema applied to entries in that subtree, and the owner string recorded in writes.

```yaml
# .textus/manifest.yaml
version: textus/1
entries:
  - key: state.network.org
    path: state/network/org
    zone: state
    schema: person
    owner: textus:network

  - key: state.projects
    path: state/projects
    zone: state
    schema: project
    owner: textus:projects
    nested: true        # any key state.projects.<anything>... resolves under path/

  - key: derived.catalogs.skills
    path: derived/catalogs/skills.md
    zone: derived
    schema: null        # generated content, no frontmatter contract
    owner: textus:build
    generator:                          # optional; required for `textus stale`
      command: "rake catalog:skills"    # how the build runner regenerates this
      sources:                          # textus keys or repo-relative paths
        - state.projects
        - state.network
```

The `generator` block (see §5.1) is optional structurally but required for any derived entry that wants to participate in staleness detection.

**Key grammar:** dotted segments matching `/^[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?$/`. Segments joined by `.`. Example: `state.projects.acme.dashboard`.

**Lookup rule:** to resolve a key, find the entry with the longest `key:` prefix that matches. If that entry has `nested: true`, the remaining segments map to subdirectories under its `path`. Otherwise the key must equal an entry exactly.

## 5. Zones

Three zones with fixed semantics:

| Zone | Writer | Agent-writable | Use |
|---|---|---|---|
| `fixed` | human | no | Identity, voice, immutable canon |
| `state` | owner (declared in manifest) | **yes** | Project state, decisions, network — the things agents update |
| `derived` | build tool | no | Generated catalogs, indexes — overwritten by the build |

Agents may only `put` into entries whose resolved zone is `state`. Writes to `fixed` or `derived` return `WRITE_FORBIDDEN`. Reads are unrestricted.

### 5.1 Derived content provenance and the `generator` contract

textus is a **dataflow oracle, not an executor**. It records what generated each derived entry and detects when an entry is stale, but it never invokes generator commands itself. External build runners (lefthook, rake, make, just, CI) execute. This keeps the spec portable across languages, free of shell-execution surface, and composable with whatever build system a consumer already has.

Two pieces of metadata make this work:

**(a) The `generator:` block in the manifest** (see §4 example) declares how a derived entry is regenerated:

| Field | Required | Meaning |
|---|---|---|
| `command` | yes | Opaque string the build runner invokes — textus does not parse or execute it |
| `sources` | yes | List of textus keys and/or repo-relative file paths whose changes invalidate this entry |

**(b) A `generated:` frontmatter block** (see §7) on each derived file records when it was last written and from what state:

```yaml
---
generated:
  by: "rake catalog:skills"
  at: "2026-05-18T10:00:00Z"
  from:
    - state.projects
    - state.network
---
```

`generated.from` SHOULD match `generator.sources` from the manifest. Build runners are expected to write this block when regenerating; textus does not synthesize it.

**Staleness rule.** A derived entry is stale when *any* item listed in its manifest `generator.sources` has a current etag/mtime newer than the entry's `generated.at` timestamp. The `textus stale` verb (§9) computes this and returns the offenders with their declared generator commands; the build runner reads that list and executes the commands.

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
org: envato
---
Short body in Markdown.
```

The frontmatter `name:` field, when present, must match the file's basename (without `.md`). Implementations may relax this for backward compat but the reference impl enforces it.

Entries in `zone: derived` SHOULD additionally carry the `generated:` block defined in §5.1. Implementations MUST treat unknown frontmatter fields as warnings, not errors, so build runners can extend the metadata without breaking conformance.

## 8. Envelope (the wire format)

Every successful CLI response (`--format=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/1",
  "key": "state.network.org.jane",
  "zone": "state",
  "owner": "textus:network",
  "path": "/absolute/path/to/.textus/state/network/org/jane.md",
  "frontmatter": { "name": "jane", "relationship": "peer", "org": "envato" },
  "body": "Short body in Markdown.\n",
  "etag": "sha256:8f3c…",
  "schema_ref": "person"
}
```

**Field rules:**
- `protocol` MUST be the exact string `textus/1`.
- `key` MUST be the canonical resolved key.
- `zone` MUST be one of `fixed`, `state`, `derived`.
- `path` MUST be an absolute filesystem path.
- `etag` MUST be `sha256:<hex>` of the raw file bytes.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/1",
  "ok": false,
  "code": "write_forbidden",
  "message": "zone 'fixed' is not agent-writable for key 'fixed.identity'",
  "details": { "key": "fixed.identity", "zone": "fixed" }
}
```

**Error codes:**

| Code | Meaning | Default exit |
|---|---|---|
| `unknown_key` | Key does not resolve | 1 |
| `bad_frontmatter` | YAML parse failed or `name:` mismatch | 1 |
| `schema_violation` | Required field missing or wrong type | 1 |
| `write_forbidden` | Zone is not agent-writable | 1 |
| `etag_mismatch` | Concurrent write detected | 1 |
| `io_error` | Filesystem failure | 64 |
| `usage` | CLI argument error | 2 |

## 9. CLI surface

The reference binary is `textus`. Conforming implementations MAY use any binary name; the protocol is in the JSON.

| Verb | Purpose | Reads / writes |
|---|---|---|
| `textus list [--prefix=<key>] --format=json` | Enumerate all keys under an optional prefix | read |
| `textus where <key> --format=json` | Resolve a key to its file path without reading | read |
| `textus get <key> --format=json` | Return the full envelope for a key | read |
| `textus put <key> --stdin --format=json` | Write/update an entry, body and frontmatter on stdin as JSON `{frontmatter, body, if_etag?}` | write |
| `textus schema <key> --format=json` | Return the resolved schema definition for a key | read |
| `textus stale [--prefix=<key>] --format=json` | List derived entries whose `generator.sources` have changed since `generated.at` | read |

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "frontmatter": { "name": "jane", "relationship": "peer", "org": "envato" },
  "body": "Short body.\n",
  "if_etag": "sha256:8f3c…" }
```

`if_etag` is optional. When provided, the write fails with `etag_mismatch` if the on-disk file's etag differs. When omitted, the write is unconditional (last-writer-wins).

**`textus stale` output shape:**

```json
[
  { "key": "derived.catalogs.skills",
    "path": "/abs/.textus/derived/catalogs/skills.md",
    "generator": { "command": "rake catalog:skills",
                   "sources": ["state.projects", "state.network"] },
    "reason": "source 'state.projects' modified after generated.at" }
]
```

Build runners consume this list and execute `generator.command` themselves. textus never invokes the command.

## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.

## 11. Versioning

- The wire string `textus/1` is the protocol version.
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/1`.
- Breaking changes (renamed/removed fields, zone semantics, key grammar) require a new wire string `textus/2`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently. Gem 1.x speaks `textus/1`.

## 12. Conformance fixtures

A conformant implementation MUST pass these three fixtures (the reference test suite will ship a YAML file listing inputs and expected envelopes):

**Fixture A — Resolve and read:**
Given a manifest with `state.network.org` → `state/network/org` (nested), schema `person`, and a file `state/network/org/jane.md` with valid frontmatter, `textus get state.network.org.jane --format=json` returns the canonical envelope above with `etag` matching the file's sha256.

**Fixture B — Zone gate on write:**
Given a manifest entry where `key: fixed.identity` has `zone: fixed`, `textus put fixed.identity --stdin` (with any valid input) returns the error envelope with `code: "write_forbidden"` and exit code 1.

**Fixture C — Schema validation:**
Given the `person` schema above and a `put` whose frontmatter omits `relationship`, the result is the error envelope with `code: "schema_violation"`, `details.missing: ["relationship"]`, and exit code 1.

**Fixture D — Staleness detection:**
Given a manifest entry `derived.catalogs.skills` with `generator.sources: [state.projects]`, and a state entry under `state.projects` whose file mtime is newer than the derived entry's `generated.at` frontmatter timestamp, `textus stale --format=json` includes the derived entry with its declared `generator.command` and a `reason` field naming the stale source. Calling textus does NOT execute the command.

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
- [ ] Refuse writes to non-state zones with `write_forbidden`.
- [ ] Return envelopes matching the shape in §8 exactly.
- [ ] Use the error codes in §8 and the exit-code table.
- [ ] Implement `textus stale` per §5.1 and §9, comparing each derived entry's `generator.sources` against its `generated.at` timestamp without invoking any commands.
- [ ] Pass the four conformance fixtures in §12.

A v1 implementation MAY:

- Add additional CLI verbs (delete, move, validate-all) that are not part of the spec.
- Provide alternate output formats (`--format=yaml`, `--format=table`) for human use.
- Support additional schema field types beyond §6, marked as `vendor:<name>` extensions.

---

**Spec word count target:** <2500 words (allowance widened from 2000 to fit Level-A/B derived provenance + staleness in v1).
**Reviewed against community-testing checklist (idea file §"Community-testing"):** ✅ <2500 words; ✅ implementable in a day in TS/Python (four concepts: manifest, schema, envelope, staleness check); ✅ four conformance fixtures; ✅ "Why not X?" section present (incl. why no execution); ✅ name picked.
