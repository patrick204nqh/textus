# Zones — shaping your context

How to define the **shape of your context** in textus: zones, the roles that write to them, the entries that live in them, and how data flows from input adapters out to published files.

This is the user-configuration guide. For the wire protocol, see [`../SPEC.md`](../SPEC.md). For implementation internals, see [`./architecture.md`](./architecture.md).

## Table of contents

1. [The mental model](#1-the-mental-model)
2. [Roles — who is allowed to write](#2-roles--who-is-allowed-to-write)
3. [The five default zones](#3-the-five-default-zones)
4. [Defining your own zones](#4-defining-your-own-zones)
5. [Defining entries](#5-defining-entries)
6. [Wiring data in — intake and `:fetch` hooks](#6-wiring-data-in--intake-and-fetch-hooks)
7. [Wiring data out — derived entries and publishing](#7-wiring-data-out--derived-entries-and-publishing)
8. [Worked example](#8-worked-example)
9. [Enforcement — what `textus doctor` checks](#9-enforcement--what-textus-doctor-checks)

---

## 1. The mental model

A textus store is a small **data-flow graph**. Information enters from outside, gets curated by humans and AI, and gets compiled into files you ship.

```
            EXTERNAL WORLD                          INSIDE .textus/zones/
         (network, files, APIs)                  (already-captured context)
                  │                                       │
                  │  :fetch hook                          │  projection sources
                  ▼                                       ▼
            ┌──────────┐                            ┌──────────┐
   script ─►│  intake  │                    build ─►│ derived  │─► publish
            └──────────┘                            └──────────┘
            "pull bytes IN"                         "compute bytes OUT"

                          ┌────────┐     ┌─────────┐
                  human ─►│ canon  │  ai ►│ pending │─► accept ─► canon/working
                          └────────┘     └─────────┘
                          ┌─────────┐
            human, ai ───►│ working │◄─── script
                          └─────────┘
```

Two ideas do all the work:

- **A zone is a write-authority partition.** Each zone declares which roles may write to it. Directory names are convention; the manifest is the source of truth.
- **A role is a write intent.** `human`, `ai`, `script`, `build` are the four conventional roles. Every `textus put` carries `--as=<role>`, and the writer is refused if that role isn't listed for the target zone.

Everything else — projections, publishing, hooks, schemas — is layered on top of those two ideas.

---

## 2. Roles — who is allowed to write

Roles are just strings declared in the manifest. The four conventional ones:

| Role | What it represents | Typical verb |
|------|--------------------|--------------|
| `human` | A person editing files directly | `put`, `accept`, `mv` |
| `ai` | An autonomous agent proposing changes | `put` (usually into `pending`) |
| `script` | Automation pulling external data in | `refresh` |
| `build` | The compiler that materializes derived entries | `build` |

Two analogies that usually click:

- **`script` is the grocery shopper** — goes outside, brings raw ingredients home.
- **`build` is the chef** — takes ingredients already in the kitchen and cooks the meal.

You can also invent your own roles (`reviewer`, `import-bot`, `scheduler`) — see [§4](#4-defining-your-own-zones). The `build` role has one piece of special meaning: any zone whose writers include `"build"` is treated as a derived zone by the build pipeline.

---

## 3. The five default zones

`textus init` scaffolds this manifest:

```yaml
zones:
  - { name: canon,   writable_by: [human] }
  - { name: working, writable_by: [human, ai, script] }
  - { name: intake,  writable_by: [script] }
  - { name: pending, writable_by: [ai, human] }
  - { name: derived, writable_by: [build] }
```

| Zone | Purpose | Lifetime | Writers |
|------|---------|----------|---------|
| `canon` | Slow-changing identity. Voice, mission, brand, project facts. | Years | `human` only |
| `working` | Active project state. Day-to-day notes that humans and agents both touch. | Days to weeks | `human`, `ai`, `script` |
| `intake` | Declared external inputs. Refreshed by `:fetch` hooks, never edited by hand. | Refreshed on demand | `script` |
| `pending` | AI proposals awaiting human review. | Until `accept` or rejection | `ai`, `human` |
| `derived` | Build-computed outputs. Materialized from projections. Never hand-edited. | Recomputed every build | `build` |

These five are a **starter template**, not a closed set. Rename them, add to them, remove the ones you don't need.

---

## 4. Defining your own zones

Edit `.textus/manifest.yaml` and add entries under `zones:`. The schema is dead simple:

```yaml
zones:
  - { name: <zone-name>, writable_by: [<role>, <role>, ...] }
```

### Renaming defaults

`canon`, `working`, etc. have no privileged status in the code — only `build` does. Rename freely:

```yaml
zones:
  - { name: identity,  writable_by: [human] }       # was canon
  - { name: notes,     writable_by: [human, ai] }   # was working
  - { name: feeds,     writable_by: [importer] }    # was intake (custom role too)
  - { name: outputs,   writable_by: [build] }       # was derived
```

### Adding new zones

A consulting-engagement layout might want a sharper split than the defaults:

```yaml
zones:
  - { name: canon,       writable_by: [human] }
  - { name: research,    writable_by: [human, ai] }     # AI-assisted research notes
  - { name: deliverable, writable_by: [human] }         # human-only client-facing copy
  - { name: archive,     writable_by: [human] }         # read-mostly historical record
  - { name: feeds,       writable_by: [script] }        # external signals
  - { name: built,       writable_by: [build] }         # rendered outputs
```

### Custom roles

Roles are just strings — invent them as you need:

```yaml
zones:
  - { name: reviews, writable_by: [reviewer] }
  - { name: imports, writable_by: [shopify-importer, stripe-importer] }
```

Custom roles work everywhere conventional ones do (`--as=reviewer`, audit log, doctor checks). The only role with code-level meaning is `build`: it marks a zone as derived. Everything else is convention.

### Rules to keep in mind

- **Zone names must be unique.** Duplicates are caught by `textus doctor`.
- **Every entry must declare a zone that exists.** An entry pointing at an undeclared zone raises `UsageError` at load time.
- **An empty `writable_by:` list makes a zone read-only at runtime** — you can still publish into it via `build`, but `put --as=anything` will be refused.
- **There is no implicit role hierarchy.** `human` is not a superuser; if a zone's writers are `[ai]`, even a human running `put --as=human` is refused.

---

## 5. Defining entries

Each entry is a key, a path under `zones/<zone>/`, and metadata:

```yaml
entries:
  - key: canon.identity
    path: canon/identity.md
    zone: canon
    schema: identity        # references .textus/schemas/identity.yaml
    owner: human:self
```

### Fields

| Field | Required | Meaning |
|-------|----------|---------|
| `key` | yes | Dotted identifier (`canon.identity`, `working.notes.daily`). |
| `path` | yes | Relative path under `.textus/zones/`. |
| `zone` | yes | Must match a declared zone. |
| `schema` | no | YAML schema name. `null` means free-form. |
| `owner` | yes | `<role>:<actor>` — for audit and convention; not enforced. |
| `nested` | no | If `true`, the key prefix-matches subdirectories. `working.notes.daily.2026-05-21` resolves under `working/notes/`. |
| `format` | no | `markdown` \| `json` \| `yaml` \| `text`. Inferred from extension if omitted. |
| `source:` | no | Declares this is an intake entry. See [§6](#6-wiring-data-in--intake-and-fetch-hooks). |
| `projection:` | no | Declares this is a derived entry. See [§7](#7-wiring-data-out--derived-entries-and-publishing). |
| `template:` | no | Mustache template name under `.textus/templates/`. Required for markdown/text derived entries; optional for JSON/YAML. |
| `inject_intro:` | no | When `true` on a derived entry, the `textus intro` payload is merged into the projection data so templates can reference it. |
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

## 6. Wiring data in — intake and `:fetch` hooks

`intake` zones are populated by `:fetch` hooks. An intake entry declares its source; `textus refresh KEY --as=script` invokes the hook and writes the result.

```yaml
- key: intake.upstream.notes
  path: intake/upstream/notes.md
  zone: intake
  owner: script:local
  source:
    fetch: local-file                                  # name of the :fetch hook
    config: { path: .textus/zones/canon/voice-tools.md }
    ttl: 12h
```

### Built-in `:fetch` hooks

Out of the box, textus ships **parsers** for common shapes — `json`, `csv`, `markdown-links`, `ical-events`, `rss`. These are not full fetchers: each expects raw bytes in `config["bytes"]` and produces structured `_meta`/body. The caller (typically an outer hook you write) is responsible for the actual I/O. This keeps textus itself free of implicit network calls (SPEC §5.4).

If you want bytes to come from disk or a URL, you write the fetcher.

### Custom `:fetch` hooks

Drop a Ruby file in `.textus/hooks/`. The return shape must be one of three:

- `{ _meta:, body: }` — markdown-friendly; `_meta` becomes the entry's parsed metadata hash
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content
- `{ body: }` — raw bytes; the store re-parses per `format:`

```ruby
# .textus/hooks/notion.rb — 0.8.2+ sugar form
Textus.fetch(:notion) do |config:, args:, **|
  page_id = config.fetch("page_id")
  body = NotionClient.new.fetch_markdown(page_id)
  { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: body }
end

# Equivalent primitive form
Textus.hook(:fetch, :notion) do |store:, config:, args:|
  ...
end
```

Then point an entry at it:

```yaml
- key: intake.notion.roadmap
  path: intake/notion/roadmap.md
  zone: intake
  source:
    fetch: notion              # matches the hook name
    config: { page_id: "abc123" }
    ttl: 6h
```

`textus refresh intake.notion.roadmap --as=script` invokes the hook, normalizes the result by the entry's declared format, and writes it through the role gate just like any other write.

---

## 7. Wiring data out — derived entries and publishing

A derived entry says **"compute me from these sources, render me with this template, copy me to these external paths."**

```yaml
- key: derived.claude-root
  path: derived/CLAUDE.md
  zone: derived
  format: markdown
  owner: build:auto
  projection:
    select: [canon.identity, working.notes]    # source keys
    pluck: "*"                                 # which fields
    reduce: identity                           # optional reducer
  template: claude-root.mustache               # in .textus/templates/
  publish_to: [CLAUDE.md]                      # external target(s)
```

### Two ways to define a hook

Both surfaces are equivalent — they all register against the same registry. Pick whichever reads best.

```ruby
# 1. Primitive — the authoritative entry point
Textus.hook(:fetch, :local_file) do |store:, config:, args:|
  { _meta: {}, body: File.read(config["path"]) }
end

# 2. Per-event sugar (0.8.2+) — one event, one callback
Textus.fetch(:local_file)       { |config:, args:, **| ... }
Textus.reduce(:rank_by_recency) { |rows:, **|          ... }
Textus.put(:audit, keys: ["working.*"]) { |key:, envelope:, **| ... }
```

To register multiple events under the same name (e.g. a `:fetch` + `:reduce` connector), simply call the sugar methods separately with the same name:

```ruby
Textus.fetch(:notion)  { |config:, args:, **| ... }
Textus.reduce(:notion) { |rows:, **| ... }
```

Both reference the same name from the manifest:

```yaml
source:     { fetch: notion, config: { ... } }
projection: { reduce: notion }
```

### What `textus build` does

For every entry in a build-writable zone:

1. **Load sources** — gather the named keys
2. **Project** — pluck fields, run the reducer if any
3. **Render** — pass the projected data to the format renderer (markdown/text/json/yaml), using a template if declared
4. **Write** — save the bytes to the derived path
5. **Publish** — for each `publish_to:` target, byte-copy and write a sentinel under `.textus/sentinels/`

### The sentinel guard

`Publisher` refuses to overwrite any external file textus didn't write itself. The sentinel records which external paths are textus-managed; a missing sentinel means the file is yours, and build will refuse rather than clobber it.

---

## 8. Worked example

A Claude plugin repo that publishes `CLAUDE.md` from a slow-changing identity file plus a feed of working notes.

`.textus/manifest.yaml`:

```yaml
version: textus/2

zones:
  - { name: canon,   writable_by: [human] }
  - { name: working, writable_by: [human, ai] }
  - { name: derived, writable_by: [build] }

entries:
  - key: canon.identity
    path: canon/identity.md
    zone: canon
    schema: identity
    owner: human:self

  - key: working.notes
    path: working/notes
    zone: working
    nested: true
    owner: human:self

  - key: derived.claude-root
    path: derived/claude-root.md
    zone: derived
    owner: build:auto
    projection:
      select: [canon.identity, working.notes]
      pluck: "*"
      reduce: claude_root            # name of a :reduce hook in .textus/hooks/
    template: claude-root.mustache   # under .textus/templates/
    inject_intro: true               # merge `textus intro` payload into template data
    publish_to: [CLAUDE.md]
```

Day-to-day flow:

```
$ textus put canon.identity --as=human   < new-identity.md   # edit identity
$ textus put working.notes.kickoff --as=human < kickoff.md   # add a note
$ textus build                                               # rebuild CLAUDE.md
$ git diff CLAUDE.md                                         # review and commit
```

To layer AI proposals in, add a `pending` zone and let agents write `pending.suggestion.*` with `--as=ai`, then `textus accept pending.suggestion.<id> --as=human` promotes the proposal into `canon` or `working`.

To layer external feeds in, add an `intake` zone with `writable_by: [script]` and an entry whose `source: fetch:` points at a `:fetch` hook. `textus refresh` keeps it current.

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
- [`./architecture.md`](./architecture.md) — how the Ruby implementation is laid out
- [`./conventions.md`](./conventions.md) — store location, transport wrappers, multi-store patterns
- [`../examples/claude-plugin/`](../examples/claude-plugin/) — a complete worked example
