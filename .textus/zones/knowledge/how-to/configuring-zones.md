# Configuring zones

> **How-to** · for integrators · **read when** you're defining zones, wiring intake, or setting up derived entries
> **SSoT for** the zone-setup procedures (declare/rename zones, intake wiring, derived + publishing, worked example) · **reviewed** 2026-06 (v0.43)

How to shape your context: define your own zones, wire external data in through intake hooks, wire derived data out through projections and publishing, and a full worked example.

For the exact zone, role, and entry semantics this guide builds on, see [`../reference/zones.md`](../reference/zones.md). For the wire protocol, see [`../../SPEC.md`](../../SPEC.md).

## Table of contents

1. [Defining your own zones](#defining-your-own-zones)
2. [Wiring data in — intake and `:resolve_intake` hooks](#wiring-data-in--intake-and-resolve_intake-hooks)
3. [Wiring data out — derived entries and publishing](#wiring-data-out--derived-entries-and-publishing)
4. [Worked example](#worked-example)

---

## Defining your own zones

Edit `.textus/manifest.yaml` and add entries under `zones:`. A zone declares only its `kind:` — write authority is derived from the kind, never listed per-zone:

```yaml
zones:
  - { name: <zone-name>, kind: <canon|workspace|quarantine|queue|derived> }
```

### Declaring a zone's kind

Every zone declares its data-flow role with `kind:` — one of `canon`,
`workspace`, `quarantine`, `queue`, `derived`:

```yaml
zones:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace }
  - { name: feeds,      kind: quarantine }
  - { name: proposals,  kind: queue }
  - { name: artifacts,  kind: derived }
```

`kind:` is required — a manifest with a kind-less zone is rejected at load. The
kind is authoritative: a zone is "derived" only if it says `kind: derived`, and
`textus put` routes proposals to the zone declaring `kind: queue` (no
name-based guessing). The kind also fixes the capability a writer must hold —
`canon`⇒`author`, `workspace`⇒`keep`, `quarantine`⇒`reconcile`, `queue`⇒`propose`, `derived`⇒`reconcile`. (This is a function, not a bijection — `quarantine` and `derived` share `reconcile`; ADR 0090.)
Rules: at most one `queue` zone, and (since `author` is the single trust
anchor) at most one role may hold it.

### Renaming defaults

`knowledge`, `notebook`, etc. have no privileged status in the code. Rename freely — a zone carries only its `kind:`, and an optional `read_policy:` (default `[all]`):

```yaml
zones:
  - { name: self,     kind: canon }                       # was knowledge
  - { name: scratch,  kind: workspace }                   # was notebook
  - { name: extern,   kind: quarantine, read_policy: [all] } # was feeds
  - { name: compiled, kind: derived }                     # was artifacts
```

### Adding new zones

A consulting-engagement layout might want a sharper split than the defaults. Each new zone needs only a `kind:`; which roles can write it follows from the kind crossed with the role mapping:

```yaml
zones:
  - { name: knowledge,   kind: canon }      # author-holders (human) write
  - { name: research,    kind: canon }      # AI-assisted research notes — still author-gated
  - { name: deliverable, kind: canon }      # human-only client-facing copy
  - { name: archive,     kind: canon }      # read-mostly historical record
  - { name: feeds,       kind: quarantine } # external signals — reconcile-holders write
  - { name: built,       kind: derived }    # rendered outputs — reconcile-holders write
```

### Tuning role capabilities

Role **names** are a closed set — `human`, `agent`, `automation` — but each role's **capabilities** are yours to tune. You assign any subset of the closed four-verb set (`author`, `propose`, `keep`, `reconcile`), subject to the one rule that at most one role may hold `author`:

```yaml
roles:
  - { name: human,      can: [author, propose] }   # the trust anchor
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [reconcile] }           # the one machine-maintenance capability
```

A manifest need not declare all three — declare the subset you use. Declaring a role whose name is not one of the three is rejected at load. To attribute work to individual people or bots, use the `owner:` field (`owner: human:patrick`, `owner: automation:ci`) — attribution, not authority.

### Rules to keep in mind

- **Zone names must be unique.** Duplicates are caught by `textus doctor`.
- **Every entry must declare a zone that exists.** An entry pointing at an undeclared zone raises `UsageError` at load time.
- **A zone-kind with no capability holder is read-only at runtime** — if no declared role holds the verb a zone's kind requires, you can still publish into it via `publish` (for `derived`), but `put --as=anything` will be refused with `write_forbidden`.
- **There is no implicit role hierarchy.** `human` is not a superuser; if only `automation` holds `reconcile`, even a human running `put --as=human` against the `derived` zone is refused.
- **At most one role may hold `author`.** The trust anchor is singular; a manifest declaring two `author`-holders is rejected at load.

---

## Wiring data in — intake and `:resolve_intake` hooks

`intake` zones are populated by `:resolve_intake` hooks. An intake entry declares its handler; on a stale entry whose rule says `action: refresh`, `textus reconcile --as=automation` (the scheduled sweep) or a `hook run` event invokes the handler and writes the result. A `get` never invokes the handler — it is a pure read (ADR 0089). Upkeep budgets live in a top-level `rules:` block, matched by glob.

```yaml
entries:
  - key: feeds.upstream.notes
    path: feeds/upstream/notes.md
    zone: feeds
    intake:
      handler: pull_notes
      config: { url: "https://example.com/notes" }

rules:
  - match: feeds.upstream.**
    upkeep:
      "on": stale          # MUST quote "on" — a bare on: is YAML boolean true
      ttl: 1h
      action: refresh
```

The `upkeep:` field is a **tagged union** discriminated by `on:` (ADR 0090): `"on": stale` carries the age-based grammar (`ttl`, `action`, optional `budget_ms`); `"on": source_change` carries the dependency-based grammar (`strategy`) — covered under [derived entries](#wiring-data-out--derived-entries-and-publishing) below. **The `"on":` key must be quoted in YAML** — a bare `on:` is parsed as the boolean `true` (YAML 1.1 / Psych) and breaks the union.

#### `action:` options (intake — `"on": stale`)

For intake entries, `action:` may be `refresh` or `warn` (`drop`/`archive` apply only to stored entries; `doctor` rejects the mismatch via `lifecycle.action_invalid`). A `"on": source_change` tag on a non-derived entry is rejected by `doctor`'s `upkeep.kind_mismatch` check.

| Value | Behaviour |
|---|---|
| `warn` (default) | A read returns stale data immediately with `stale: true` in the envelope; the entry is left untouched. |
| `refresh` | On the next `reconcile` sweep (or a `hook run` event), re-pull the entry from its declared intake handler, bounded by `budget_ms` (default 500). A `get` never refreshes — it reads the entry back stale until reconcile runs (ADR 0089). |

### Built-in `:resolve_intake` handlers

Out of the box, textus ships **parsers** for common shapes — `json`, `csv`, `markdown-links`, `ical-events`, `rss`. These are not full fetchers: each expects raw bytes in `config["bytes"]` and produces structured `_meta`/body. The caller (typically an outer hook you write) is responsible for the actual I/O. This keeps textus itself free of implicit network calls (SPEC §5.4).

If you want bytes to come from disk or a URL, you write the handler.

> Copy-paste starting points for common sources (HTTP JSON, RSS, iCal, local
> file, Notion) live in [`../cookbook/intake-recipes.md`](../cookbook/intake-recipes.md).

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
  - key: feeds.notion.roadmap
    path: feeds/notion/roadmap.md
    zone: feeds
    intake:
      handler: notion            # matches the hook name
      config: { page_id: "abc123" }

rules:
  - match: feeds.notion.**
    upkeep: { "on": stale, ttl: 6h, action: refresh }
```

On a stale entry, `textus reconcile --as=automation` (or a `hook run` event) invokes the handler, normalizes the result by the entry's declared format, and writes it through the capability gate just like any other write.

The third kwarg, `args:`, carries leaf-key context: `args[:trigger_key]` is the full key being fetched and `args[:leaf_segments]` holds the segments past the parent `intake` entry (for `nested: true` intakes). Handlers over fan-out intakes should scope work to the requested leaf rather than re-running the parent config for every leaf. See [`../reference/events.md` (`:resolve_intake` args)](../reference/events.md#resolve_intake-args).

### Machine snapshot (scaffolded)

`textus init` drops a `machine_intake.rb` `:resolve_intake` hook and a **nested**
`feeds.machines` entry (`tracked: false`) with one machine configured — `local`.
`textus reconcile --as=automation` (when the entry is stale and its rule says
`action: refresh`) pulls a snapshot of this host into the `feeds` zone:

- **git** — short HEAD, branch, dirty flag, repo root (the *control* host's repo; only meaningful for `local`)
- **platform** — os, arch, ruby version, and `runtimes` (node/python/go versions, `null` when not installed)
- **packages** — counts per manager (`brew`, `apt`); never the package list
- `captured_at`, `textus_version`, `protocol`

It is **retrievable via the protocol** (`textus get feeds.machines.local`) but
**gitignored and never published**, because machine info can be sensitive or
noisy — the entry's `tracked: false` flag drives the generated `.gitignore`
(the whole `zones/feeds/machines/` subtree). The scan runs **only on a
`reconcile` refresh** (never a `get`/`boot`/`pulse` read), and a
`feeds.machines.**` upkeep rule (`upkeep: { "on": stale, ttl: 1h, action: refresh }`) amortizes the
cost (a `brew list` count is ~1–3 s) on a long-running server. The hook is a deliberate **allowlist** — versions and counts, no raw
`env`, no secrets.

Because it's **nested**, it grows to a fleet without renaming: add
`feeds.machines.<host>` leaves pulled over SSH (the *Environment scan across
machines* cookbook recipe shows the fan-out). Don't want it? Delete the entry +
hook to opt out.

### Aging entries out — `upkeep: { "on": stale }` with a destructive action

Queue and quarantine zones accumulate; an `upkeep: { "on": stale, … }` rule with a
destructive `action` lets them self-prune. Declare it in a `rules:` block, matched
by glob:

```yaml
rules:
  - match: proposals.**
    upkeep: { "on": stale, ttl: 30d, action: drop }      # delete accepted/abandoned proposals
  - match: feeds.**
    upkeep: { "on": stale, ttl: 90d, action: archive }   # move stale external bytes aside
```

Then `textus reconcile --as=ROLE` performs the destructive sweep (the role must be
allowed to write the matched zone). `action: drop` deletes the leaf;
`action: archive` moves it to `.textus/archive/` and then deletes the
original. `drop`/`archive` apply only to stored entries — `doctor` rejects a
`refresh` action on a stored entry (and a `drop`/`archive` on an intake entry)
via `lifecycle.action_invalid`, and a destructive `"on": stale` on a `derived`
entry via `upkeep.kind_mismatch` (a derived entry regenerates — dropping it on age
is meaningless). Age is measured from the leaf's file
modification time. Preview with `--dry-run`, narrow a sweep with `--prefix` or
`--zone`, and inspect what a key is subject to with `textus rule explain KEY` —
the resolved `upkeep` appears in the effective output.

---

## Wiring data out — derived entries and publishing

A derived entry says **"compute me from these sources, render me with this template, copy me to these external paths."**

```yaml
- key: artifacts.claude-root
  path: artifacts/CLAUDE.md
  zone: artifacts
  format: markdown
  owner: automation:build
  compute:
    kind: projection                                    # projection | external
    select: [knowledge.identity.self, knowledge.notes]  # source keys
    pluck: "*"                                          # which fields
    transform: identity                                 # optional :transform_rows hook
  template: claude-root.mustache                        # in .textus/templates/
  publish:
    to: [CLAUDE.md]                                     # external target(s)
```

### Registering hooks

Hooks live in Ruby files under `.textus/hooks/`. See [`../how-to/writing-hooks.md`](writing-hooks.md) — the hook-author's guide — for the registration surface, handler signatures, and worked examples. The manifest side (which entries trigger which hooks) is covered by [intake wiring](#wiring-data-in--intake-and-resolve_intake-hooks) and [derived entries](#wiring-data-out--derived-entries-and-publishing) above.

### What `textus reconcile` does (Phase 1 — materialize)

For every entry in a reconcile-writable zone:

1. **Load sources** — gather the named keys
2. **Project** — pluck fields, run the reducer if any
3. **Render** — pass the projected data to the format renderer (markdown/text/json/yaml), using a template if declared
4. **Write** — save the bytes to the derived path
5. **Publish** — for each `publish: { to: }` target (or each file under a `publish: { tree: }` mirror), byte-copy to the repo path, write a sentinel under `.textus/sentinels/`, and fire the `:file_published` pub-sub event. Listeners can subscribe to `:file_published` to react per-file — e.g. run `git add`, notify on writes, or compute checksums.

Phase 2 sweeps the destructive `upkeep: { "on": stale, action: drop|archive }` actions on aged entries. Both phases run under one shared maintenance lock; `--dry-run` prints the plan without executing.

Derived entries also stay fresh **reactively** between full passes: a canon write re-materializes the derived entries that depend on it, governed by the `source_change` tag of `upkeep`:

```yaml
rules:
  - match: artifacts.**
    upkeep: { "on": source_change, strategy: async }   # sync | async (default async)
```

`"on": source_change` is the dependency-based grammar (ADR 0090, the former `materialize` field): `strategy: sync` re-materializes inline under the maintenance lock (the artifact is fresh by the time the write returns); `strategy: async` defers to a background runner. It is valid **only on `derived` entries** — `doctor`'s `upkeep.kind_mismatch` check rejects it elsewhere. The `ttl`/`action` (`"on": stale`) grammar and the `strategy` (`"on": source_change`) grammar are mutually exclusive: a block carries one tag, and each tag rejects the other's keys.

### The sentinel guard

`Textus::Ports::Publisher` refuses to overwrite any external file textus didn't write itself. The sentinel records which external paths are textus-managed; a missing sentinel means the file is yours, and `reconcile` will refuse rather than clobber it.

---

## Worked example

A Claude plugin repo that publishes `CLAUDE.md` from a slow-changing identity file plus a feed of working notes.

`.textus/manifest.yaml`:

```yaml
version: textus/3

roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [reconcile] }

zones:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace, owner: agent }
  - { name: artifacts,  kind: derived }

entries:
  - key: knowledge.identity.self
    path: knowledge/identity/self.md
    zone: knowledge
    schema: identity
    owner: human:self

  - key: knowledge.notes
    path: knowledge/notes
    zone: knowledge
    nested: true
    owner: human:self

  - key: artifacts.claude-root
    path: artifacts/claude-root.md
    zone: artifacts
    owner: automation:build
    compute:
      kind: projection
      select: [knowledge.identity.self, knowledge.notes]
      pluck: "*"
      transform: claude_root         # name of a :transform_rows hook in .textus/hooks/
    template: claude-root.mustache   # under .textus/templates/
    inject_boot: true                # merge `textus boot` payload into template data
    publish:
      to: [CLAUDE.md]
```

Day-to-day flow:

```
$ textus put knowledge.identity.self --as=human  < new-identity.md   # edit identity
$ textus put knowledge.notes.kickoff --as=human  < kickoff.md         # add a note
$ textus reconcile                                                     # materialize CLAUDE.md
$ git diff CLAUDE.md                                                   # review and commit
```

To layer AI proposals in, add a zone with `kind: queue` (e.g. `name: proposals`) and let agents write into it with `--as=agent`, then `textus accept proposals.suggestion.<id> --as=human` promotes the proposal into `knowledge`. Proposals route to whichever zone declares `kind: queue` — the name doesn't matter.

To layer external feeds in, add a zone with `kind: quarantine` (writable by a role holding `reconcile`, e.g. `automation`) and an entry whose `intake: handler:` points at a `:resolve_intake` hook, plus a `rules:` block with an `upkeep: { "on": stale, ttl, action: refresh }` matching the entry. `textus reconcile --as=automation` (on a schedule) then re-pulls any stale entry and keeps it current; a `get` reads it but never refreshes (ADR 0089).

For agent workspace memory, add a zone with `kind: workspace` (e.g. `name: notebook`) writable by a role holding `keep` (e.g. `agent`). Bytes in `notebook` never auto-promote; to persist changes into `knowledge`, the agent proposes and a human accepts.

---

## Where to go from here

- [`../reference/zones.md`](../reference/zones.md) — the exact zone, role, and entry semantics
- [`../../SPEC.md`](../../SPEC.md) — the normative wire-protocol spec
- [`../how-to/writing-hooks.md`](writing-hooks.md) — the hook-author's guide
- [`../../examples/project/`](../../examples/project/) — a complete worked example
