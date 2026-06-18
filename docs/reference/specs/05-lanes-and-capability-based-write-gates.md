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
- key: artifacts.feeds.skills
  lane: artifacts
  kind: produced
  format: json
  source: { from: external, command: "true", sources: [] }
  publish: [{ to: docs/reference/skills.md, template: feeds/skills.erb }]
```

A matching `Textus.workflow` block in `.textus/workflows/`:

```ruby
Textus.workflow "agentskills" do
  match "artifacts.feeds.skills"

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
