# Zones — shaping your context

> **Reference** · for integrators · **read when** you're designing your zone layout
> **SSoT for** zone semantics, roles, entries, and data flow · **reviewed** 2026-05 (v0.31)

How to define the **shape of your context** in textus: zones, the roles that write to them, the entries that live in them, and how data flows from input adapters out to published files.

This is the user-configuration guide. For the wire protocol, see [`../SPEC.md`](../SPEC.md). For implementation internals, see [`architecture/README.md`](architecture/README.md).

## Table of contents

1. [The mental model](#1-the-mental-model)
2. [Roles and capabilities — who is allowed to write](#2-roles-and-capabilities--who-is-allowed-to-write)
3. [The five default zones](#3-the-five-default-zones) — `identity`, `working`, `intake`, `review`, `output`
4. [Defining your own zones](#4-defining-your-own-zones)
5. [Defining entries](#5-defining-entries)
6. [Wiring data in — intake and `:resolve_intake` hooks](#6-wiring-data-in--intake-and-resolve_intake-hooks)
7. [Wiring data out — derived entries and publishing](#7-wiring-data-out--derived-entries-and-publishing)
8. [Worked example](#8-worked-example)
9. [Enforcement — what `textus doctor` checks](#9-enforcement--what-textus-doctor-checks)

---

## 1. The mental model

A textus store is a small **data-flow graph**. Information enters from outside, gets curated by humans and AI, and gets compiled into files you ship.

```mermaid
flowchart LR
    ext["external world<br/>APIs · files · feeds"] -->|:resolve_intake hook| intake["intake<br/>(quarantine)"]
    automation(["automation"]) -->|fetch| intake
    human(["human"]) -->|accept| identity["identity<br/>(origin)"]
    human -->|accept| working["working<br/>(origin)"]
    agent(["agent"]) -->|propose| review["review<br/>(queue)"]
    review -->|human accept| identity
    review -->|human accept| working
    automation -->|build| output["output<br/>(derived)"]
    intake -.->|projection source| output
    working -.->|projection source| output
    output -->|publish| files["shipped files"]
```

*Flow at a glance:* automation pulls external bytes into `intake` (the `fetch` capability); humans write `identity`/`working` directly (the `accept` capability); agents `propose` into `review` and a human `accept` promotes to `working`/`identity`; automation `build`s `output` from `working`/`intake` and publishes shipped files.

Two ideas do all the work:

- **A zone is a write-authority partition.** Each zone declares its `kind:`; the kind decides which capability a writer must hold. Directory names are convention; the manifest is the source of truth.
- **A role is a bundle of capabilities.** A role holds verbs from a closed four-element set — `propose`, `accept`, `fetch`, `build` — and may write a zone iff it holds the verb that zone's kind requires. Every `textus put` carries `--as=<role>`, and the writer is refused if that role lacks the required capability.

Everything else — projections, publishing, hooks, schemas — is layered on top of those two ideas.

---

## 2. Roles and capabilities — who is allowed to write

A role is a name in the manifest that holds a set of **capabilities** — verbs from a closed four-element set. Write authority is *derived*: a role may write a zone iff it holds the capability the zone's kind requires (see [§3](#3-the-five-default-zones)). The default mapping, applied when the manifest omits a `roles:` block:

| Role | Capabilities (`can`) | What it represents |
|------|----------------------|--------------------|
| `human` | `[accept, propose]` | A person at a terminal; the single trust anchor. |
| `agent` | `[propose]` | An autonomous agent staging changes into the queue. |
| `automation` | `[fetch, build]` | Scheduled or one-shot scripts: pull external sources in, materialize derived outputs. |

The four capabilities:

| Capability | Authorizes writes to zone-kind | What it represents |
|------------|--------------------------------|--------------------|
| `accept` | `origin` | Authoring authored truth — the **single trust anchor** (at most one role holds it). |
| `propose` | `queue` | Staging a proposal awaiting promotion. |
| `fetch` | `quarantine` | Pulling external bytes in. |
| `build` | `derived` | Computing outputs from other zones. |

Declare roles in the manifest with a `roles:` block; each names the capabilities it holds via `can:`:

```yaml
roles:
  - { name: human,      can: [accept, propose] }
  - { name: agent,      can: [propose] }
  - { name: automation, can: [fetch, build] }
```

Two analogies that usually click for `automation`:

- **`fetch` is the grocery shopper** — goes outside, brings raw ingredients home (into `intake`).
- **`build` is the chef** — takes ingredients already in the kitchen and cooks the meal (into `output`).

You can also invent your own role names (`reviewer`, `import-bot`, `compiler`) and hand them whichever capabilities fit — see [§4](#4-defining-your-own-zones). Only one constraint is absolute: **at most one role may hold `accept`** (the trust anchor).

---

## 3. The five default zones

`textus init` scaffolds this manifest:

```yaml
roles:
  - { name: human,      can: [accept, propose] }
  - { name: agent,      can: [propose] }
  - { name: automation, can: [fetch, build] }

zones:
  - { name: identity, kind: origin }
  - { name: working,  kind: origin }
  - { name: intake,   kind: quarantine }
  - { name: review,   kind: queue }
  - { name: output,   kind: derived }
```

Write authority is **derived** — there is no `write_policy:`. Each zone declares only its `kind:`; the kind decides the required capability, and any role holding that capability may write. The kind→verb mapping is closed:

| Zone `kind` | Required capability | Meaning |
|-------------|---------------------|---------|
| `origin` | `accept` | Authored truth — only the trust anchor writes directly. |
| `quarantine` | `fetch` | External bytes pending validation. |
| `queue` | `propose` | Proposals awaiting promotion. |
| `derived` | `build` | Computed from other zones. |

Crossing that table with the default role mapping gives the default writers:

| Zone | `kind` | Required capability | Writable by (default) | Purpose / lifetime |
|------|--------|---------------------|-----------------------|--------------------|
| `identity` | `origin` | `accept` | `human` | Slow-changing identity. Voice, mission, brand, project facts. (Years.) |
| `working` | `origin` | `accept` | `human` | Active project state: notes, decisions, network. (Days to weeks.) |
| `intake` | `quarantine` | `fetch` | `automation` | Declared external inputs, fetched via `textus fetch KEY --as=automation`; never edited by hand. (Fetched on demand.) |
| `review` | `queue` | `propose` | `agent`, `human` | AI proposals awaiting human review. (Until `accept` or rejection.) |
| `output` | `derived` | `build` | `automation` | Build-computed outputs. Materialized from projections; never hand-edited. (Recomputed every build.) |

These five are a **starter template**, not a closed set. Rename them, add to them, remove the ones you don't need.

---

## 4. Defining your own zones

Edit `.textus/manifest.yaml` and add entries under `zones:`. A zone declares only its `kind:` — write authority is derived from the kind, never listed per-zone:

```yaml
zones:
  - { name: <zone-name>, kind: <origin|quarantine|queue|derived> }
```

### Declaring a zone's kind

Every zone declares its data-flow role with `kind:` — one of `origin`,
`quarantine`, `queue`, `derived`:

```yaml
zones:
  - { name: working, kind: origin }
  - { name: intake,  kind: quarantine }
  - { name: review,  kind: queue }
  - { name: output,  kind: derived }
```

`kind:` is required — a manifest with a kind-less zone is rejected at load. The
kind is authoritative: a zone is "derived" only if it says `kind: derived`, and
`textus put` routes proposals to the zone declaring `kind: queue` (no
name-based guessing). The kind also fixes the capability a writer must hold —
`origin`⇒`accept`, `quarantine`⇒`fetch`, `queue`⇒`propose`, `derived`⇒`build`.
Rules: at most one `queue` zone, and (since `accept` is the single trust
anchor) at most one role may hold it.

### Renaming defaults

`identity`, `working`, etc. have no privileged status in the code. Rename freely — a zone carries only its `kind:`, and an optional `read_policy:` (default `[all]`):

```yaml
zones:
  - { name: self,    kind: origin }                      # was identity
  - { name: notes,   kind: origin }                      # was working
  - { name: feeds,   kind: quarantine, read_policy: [all] } # was intake
  - { name: outputs, kind: derived }                     # was output
```

### Adding new zones

A consulting-engagement layout might want a sharper split than the defaults. Each new zone needs only a `kind:`; which roles can write it follows from the kind crossed with the role mapping:

```yaml
zones:
  - { name: identity,    kind: origin }     # accept-holders (human) author
  - { name: research,    kind: origin }     # AI-assisted research notes — still accept-gated
  - { name: deliverable, kind: origin }     # human-only client-facing copy
  - { name: archive,     kind: origin }     # read-mostly historical record
  - { name: feeds,       kind: quarantine } # external signals — fetch-holders write
  - { name: built,       kind: derived }    # rendered outputs — build-holders write
```

### Custom roles

Role names are arbitrary strings; what matters is the capabilities they hold. Invent roles and hand them whichever verbs fit:

```yaml
roles:
  - { name: owner,    can: [accept, propose] }   # trust anchor
  - { name: reviewer, can: [propose] }
  - { name: importer, can: [fetch] }
  - { name: compiler, can: [build] }
```

Custom roles work everywhere conventional ones do (`--as=reviewer`, audit log, doctor checks). What makes a zone derived, a queue, or a quarantine is its declared `kind:`, not any role name — and a role can write a given zone only if it holds the verb that zone's kind requires.

### Rules to keep in mind

- **Zone names must be unique.** Duplicates are caught by `textus doctor`.
- **Every entry must declare a zone that exists.** An entry pointing at an undeclared zone raises `UsageError` at load time.
- **A zone-kind with no capability holder is read-only at runtime** — if no declared role holds the verb a zone's kind requires, you can still publish into it via `build` (for `derived`), but `put --as=anything` will be refused with `write_forbidden`.
- **There is no implicit role hierarchy.** `human` is not a superuser; if no role but `compiler` holds `build`, even a human running `put --as=human` against the `derived` zone is refused.
- **At most one role may hold `accept`.** The trust anchor is singular; a manifest declaring two `accept`-holders is rejected at load.

---

## 5. Defining entries

Each entry is a key, a path under `zones/<zone>/`, and metadata:

```yaml
entries:
  - key: identity.self
    path: identity/self.md
    zone: identity
    schema: identity        # references .textus/schemas/identity.yaml
    owner: human:self
```

### Fields

| Field | Required | Meaning |
|-------|----------|---------|
| `key` | yes | Dotted identifier (`identity.self`, `working.notes.daily`). |
| `path` | yes | Relative path under `.textus/zones/`. |
| `zone` | yes | Must match a declared zone. |
| `schema` | no | YAML schema name. `null` means free-form. |
| `owner` | yes | `<role>:<actor>` — for audit and convention; not enforced. |
| `nested` | no | If `true`, the key prefix-matches subdirectories. `working.notes.daily.2026-05-21` resolves under `working/notes/`. |
| `format` | no | `markdown` \| `json` \| `yaml` \| `text`. Inferred from extension if omitted. |
| `intake:` | no | Declares this is an intake entry. See [§6](#6-wiring-data-in--intake-and-intake-hooks). |
| `compute:` | no | Declares this is a derived entry (`kind: projection` computes from store entries; `kind: external` tracks an outside build tool). See [§7](#7-wiring-data-out--derived-entries-and-publishing). |
| `template:` | no | Mustache template name under `.textus/templates/`. Required for markdown/text derived entries; optional for JSON/YAML. |
| `inject_boot:` | no | When `true` on a derived entry, the `textus boot` payload is merged into the projection data so templates can reference it. |
| `publish_to:` | no | List of external paths to byte-copy the built file to. |
| `publish_each:` | no | For `nested:` entries — pattern like `"skills/{basename}/SKILL.md"` that publishes each child file to its own external path. |
| `events:` | no | Per-entry pub-sub bindings (e.g. run a shell command after this entry's `:build` event). |

The full schema lives in [`SPEC.md §4`](../SPEC.md).

### Nested entries

A single entry can host an unbounded subtree:

```yaml
- key: working.notes
  path: working/notes
  zone: working
  nested: true
```

That declaration covers `working.notes.daily.2026-05-21`, `working.notes.meetings.kickoff`, etc. — textus resolves the suffix as `/`-joined subdirectories under `working/notes/`.

---

## 6. Wiring data in — intake and `:resolve_intake` hooks

`intake` zones are populated by `:resolve_intake` hooks. An intake entry declares its handler; `textus fetch KEY --as=automation` (or `ops.fetch(key)` in Ruby) invokes the handler and writes the result. Freshness budgets live in a top-level `rules:` block, matched by glob.

```yaml
entries:
  - key: intake.upstream.notes
    path: intake/upstream/notes.md
    zone: intake
    intake:
      handler: pull_notes
      config: { url: "https://example.com/notes" }

rules:
  - match: intake.upstream.**
    fetch:
      ttl: 1h
```

#### `on_stale:` options

| Value | Behaviour |
|---|---|
| `warn` (default) | Return stale data immediately with `stale: true` in the envelope. No blocking. |
| `sync` | Block the `get` call and fetch in-process before returning. |
| `timed_sync` | Try to fetch within `sync_budget_ms` (default 500 ms). Return stale data with `fetching: true` if the budget is exceeded; the fetch continues in the background. |

### Built-in `:resolve_intake` handlers

Out of the box, textus ships **parsers** for common shapes — `json`, `csv`, `markdown-links`, `ical-events`, `rss`. These are not full fetchers: each expects raw bytes in `config["bytes"]` and produces structured `_meta`/body. The caller (typically an outer hook you write) is responsible for the actual I/O. This keeps textus itself free of implicit network calls (SPEC §5.4).

If you want bytes to come from disk or a URL, you write the handler.

### Custom `:resolve_intake` hooks

Drop a Ruby file in `.textus/hooks/`. The return shape must be one of three:

- `{ _meta:, body: }` — markdown-friendly; `_meta` becomes the entry's parsed metadata hash
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content
- `{ body: }` — raw bytes; the store re-parses per `format:`

```ruby
# .textus/hooks/notion.rb
Textus.hook do |reg|
  reg.on(:resolve_intake, :notion) do |caps:, config:, args:|
    page_id = config.fetch("page_id")
    body = NotionClient.new.fetch_markdown(page_id)
    { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: body }
  end
end
```

Then point an entry at it:

```yaml
entries:
  - key: intake.notion.roadmap
    path: intake/notion/roadmap.md
    zone: intake
    intake:
      handler: notion            # matches the hook name
      config: { page_id: "abc123" }

rules:
  - match: intake.notion.**
    fetch: { ttl: 6h, on_stale: warn }
```

`textus fetch intake.notion.roadmap --as=automation` invokes the handler, normalizes the result by the entry's declared format, and writes it through the capability gate just like any other write.

The third kwarg, `args:`, carries leaf-key context: `args[:trigger_key]` is the full key being fetched and `args[:leaf_segments]` holds the segments past the parent `intake` entry (for `nested: true` intakes). Handlers over fan-out intakes should scope work to the requested leaf rather than re-running the parent config for every leaf. See [events.md §7a](events.md#7a-resolve_intake-args).

### Aging entries out — `retention`

Queue and quarantine zones accumulate; `retention` lets them self-prune. Declare
it in a `rules:` block, matched by glob:

```yaml
rules:
  - match: review.**
    retention: { expire_after: 30d }   # delete accepted/abandoned proposals
  - match: intake.**
    retention: { archive_after: 90d }  # move stale external bytes aside
```

Then `textus retain --as=ROLE` performs the sweep (the role must be allowed to
write the matched zone). `expire_after` deletes the leaf; `archive_after` moves
it to `.textus/archive/` and then deletes the original. If a rule sets both,
`expire_after` is checked first, so a leaf wins deletion once it passes that
window. Age is measured from the
leaf's file modification time. Narrow a sweep with `--prefix` or `--zone`, and
inspect what a key is subject to with `textus rule explain KEY` — retention
appears in the effective output.

---

## 7. Wiring data out — derived entries and publishing

A derived entry says **"compute me from these sources, render me with this template, copy me to these external paths."**

```yaml
- key: output.claude-root
  path: output/CLAUDE.md
  zone: output
  format: markdown
  owner: build:auto
  compute:
    kind: projection                           # projection | external
    select: [identity.self, working.notes]     # source keys
    pluck: "*"                                 # which fields
    transform: identity                        # optional :transform_rows hook
  template: claude-root.mustache               # in .textus/templates/
  publish_to: [CLAUDE.md]                      # external target(s)
```

### Registering hooks

Hooks live in Ruby files under `.textus/hooks/`. See [`events.md`](events.md) — the hook-author's guide — for the registration surface, handler signatures, and worked examples. The manifest side (which entries trigger which hooks) is covered by [§6](#6-wiring-data-in--intake-and-resolve_intake-hooks) and [§7](#7-wiring-data-out--derived-entries-and-publishing) above.

### What `textus build` does

For every entry in a build-writable zone:

1. **Load sources** — gather the named keys
2. **Project** — pluck fields, run the reducer if any
3. **Render** — pass the projected data to the format renderer (markdown/text/json/yaml), using a template if declared
4. **Write** — save the bytes to the derived path
5. **Publish** — for each `publish_to:` target (or per-leaf `publish_each:` match), byte-copy to the repo path, write a sentinel under `.textus/sentinels/`, and fire the `:publish` pub-sub event. Listeners can subscribe to `:publish` to react per-file — e.g. run `git add`, notify on writes, or compute checksums.

### The sentinel guard

`Textus::Ports::Publisher` refuses to overwrite any external file textus didn't write itself. The sentinel records which external paths are textus-managed; a missing sentinel means the file is yours, and build will refuse rather than clobber it.

---

## 8. Worked example

A Claude plugin repo that publishes `CLAUDE.md` from a slow-changing identity file plus a feed of working notes.

`.textus/manifest.yaml`:

```yaml
version: textus/3

roles:
  - { name: human,      can: [accept, propose] }
  - { name: agent,      can: [propose] }
  - { name: automation, can: [fetch, build] }

zones:
  - { name: identity, kind: origin }
  - { name: working,  kind: origin }
  - { name: output,   kind: derived }

entries:
  - key: identity.self
    path: identity/self.md
    zone: identity
    schema: identity
    owner: human:self

  - key: working.notes
    path: working/notes
    zone: working
    nested: true
    owner: human:self

  - key: output.claude-root
    path: output/claude-root.md
    zone: output
    owner: automation:build
    compute:
      kind: projection
      select: [identity.self, working.notes]
      pluck: "*"
      transform: claude_root         # name of a :transform_rows hook in .textus/hooks/
    template: claude-root.mustache   # under .textus/templates/
    inject_boot: true                 # merge `textus boot` payload into template data
    publish_to: [CLAUDE.md]
```

Day-to-day flow:

```
$ textus put identity.self --as=human    < new-identity.md   # edit identity
$ textus put working.notes.kickoff --as=human < kickoff.md   # add a note
$ textus build                                               # rebuild CLAUDE.md
$ git diff CLAUDE.md                                         # review and commit
```

To layer AI proposals in, add a zone with `kind: queue` (e.g. `name: review`) and let agents write into it with `--as=agent`, then `textus accept review.suggestion.<id> --as=human` promotes the proposal into `identity` or `working`. Proposals route to whichever zone declares `kind: queue` — the name doesn't matter.

To layer external feeds in, add a zone with `kind: quarantine` (writable by a role holding `fetch`, e.g. `automation`) and an entry whose `intake: handler:` points at a `:resolve_intake` hook, plus a `rules:` block matching the entry. `textus fetch KEY --as=automation` (one-shot) or `textus fetch stale` (sweep TTL-expired entries) keeps it current.

---

## 9. Enforcement — what `textus doctor` checks

The manifest is declarative. `textus doctor` is the runtime check that the store still matches what it declares:

- Every entry's `zone:` references a declared zone
- Every entry file actually exists at its computed path
- Frontmatter `name:` matches the file basename
- Schemas exist for entries that reference one
- Hooks named by intake entries are registered
- Derived entries aren't stale relative to their sources
- No files exist under `.textus/zones/` that aren't declared

If doctor passes, your declared shape and your on-disk reality agree. If it fails, the error message names the entry and the rule that broke.

---

## Where to go from here

- [`../SPEC.md`](../SPEC.md) — the normative wire-protocol spec
- [`architecture/README.md`](architecture/README.md) — how the Ruby implementation is laid out
- [`./conventions.md`](./conventions.md) — store location, transport wrappers, multi-store patterns
- [`../examples/claude-plugin/`](../examples/claude-plugin/) — a complete worked example
