# Configuring zones

> **How-to** · for integrators · **read when** you're defining zones, wiring intake, or setting up derived entries
> **SSoT for** the zone-setup procedures (declare/rename zones, intake wiring, derived + publishing, worked example) · **reviewed** 2026-06 (v0.43)

How to shape your context: define your own zones, wire external data in through intake hooks, wire derived data out through projections and publishing, and a full worked example.

For the exact zone, role, and entry semantics this guide builds on, see [`../reference/zones.md`](../reference/zones.md). For the wire protocol, see [`../../SPEC.md`](../../SPEC.md).

## Table of contents

1. [Defining your own zones](#defining-your-own-zones)
2. [Wiring data in — intake and `:resolve_handler` hooks](#wiring-data-in--intake-and-resolve_handler-hooks)
3. [Wiring data out — derived entries and publishing](#wiring-data-out--derived-entries-and-publishing)
4. [Worked example](#worked-example)

---

## Defining your own zones

Edit `.textus/manifest.yaml` and add entries under `zones:`. A zone declares only its `kind:` — write authority is derived from the kind, never listed per-zone:

```yaml
zones:
  - { name: <zone-name>, kind: <canon|workspace|machine|queue> }
```

### Declaring a zone's kind

Every zone declares its data-flow role with `kind:` — one of `canon`,
`workspace`, `machine`, `queue`:

```yaml
zones:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace }
  - { name: artifacts,  kind: machine }
  - { name: proposals,  kind: queue }
```

`kind:` is required — a manifest with a kind-less zone is rejected at load. The
kind is authoritative: `textus put` routes proposals to the zone declaring
`kind: queue` (no name-based guessing). The kind also fixes the capability a
writer must hold — `canon`⇒`author`, `workspace`⇒`keep`, `machine`⇒`reconcile`, `queue`⇒`propose`. This is a **bijection** — one kind maps to exactly one capability (ADR 0091).
Rules: at most one `queue` zone, at most one `machine` zone, and (since `author`
is the single trust anchor) at most one role may hold it.

### Renaming defaults

`knowledge`, `notebook`, etc. have no privileged status in the code. Rename freely — a zone carries only its `kind:`, and an optional `read_policy:` (default `[all]`):

```yaml
zones:
  - { name: self,     kind: canon }                       # was knowledge
  - { name: scratch,  kind: workspace }                   # was notebook
  - { name: outputs,  kind: machine, read_policy: [all] } # was artifacts
  - { name: review,   kind: queue }                       # was proposals
```

### Adding new zones

A consulting-engagement layout might want a sharper split than the defaults. Each new zone needs only a `kind:`; which roles can write it follows from the kind crossed with the role mapping:

```yaml
zones:
  - { name: knowledge,   kind: canon }      # author-holders (human) write
  - { name: research,    kind: canon }      # AI-assisted research notes — still author-gated
  - { name: deliverable, kind: canon }      # human-only client-facing copy
  - { name: archive,     kind: canon }      # read-mostly historical record
  - { name: artifacts,   kind: machine }    # machine zone: intake feeds + derived outputs — reconcile-holders write
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
- **A zone-kind with no capability holder is read-only at runtime** — if no declared role holds the verb a zone's kind requires, you can still publish into it via `publish` (for `machine` derived entries), but `put --as=anything` will be refused with `write_forbidden`.
- **There is no implicit role hierarchy.** `human` is not a superuser; if only `automation` holds `reconcile`, even a human running `put --as=human` against the `derived` zone is refused.
- **At most one role may hold `author`.** The trust anchor is singular; a manifest declaring two `author`-holders is rejected at load.

---

## Wiring data in — intake and `:resolve_handler` hooks

`intake` entries are populated by `:resolve_handler` hooks. An intake entry declares its handler and re-pull cadence via `source: { from: handler, handler:, ttl: }`; on an entry past its `source.ttl`, `textus reconcile --as=automation` (the scheduled sweep) or a `hook run` event invokes the handler and writes the result. A `get` never invokes the handler — it is a pure read (ADR 0089).

```yaml
entries:
  - key: artifacts.feeds.notes
    path: artifacts/feeds/notes.md
    zone: artifacts
    kind: produced               # produce-method (intake) read from source.from: handler
    source:
      from: handler
      handler: pull_notes
      ttl: 1h                    # re-pull cadence; reconcile re-pulls when past ttl
      config: { url: "https://example.com/notes" }
```

The re-pull cadence is the entry's own `source.ttl` (ADR 0093). Age-based garbage collection is the orthogonal `retention:` rule slot — they compose, so an intake entry can re-pull hourly *and* be archived at 90 days:

```yaml
rules:
  - match: artifacts.feeds.**
    retention: { ttl: 90d, action: archive }   # drop | archive — destructive, reconcile-sweep only
```

A `get` annotates a past-ttl entry with `stale: true` but never re-pulls it; re-pull is `reconcile`'s job (the scheduled sweep) or a `hook run` event. `retention:` is `{ ttl, action: drop | archive }` and applies only on the destructive Phase 2 of the reconcile sweep, never on a write or read (ADR 0079/0093).

### Built-in `:resolve_handler` handlers

Out of the box, textus ships **parsers** for common shapes — `json`, `csv`, `markdown-links`, `ical-events`, `rss`. These are not full fetchers: each expects raw bytes in `config["bytes"]` and produces structured `_meta`/body. The caller (typically an outer hook you write) is responsible for the actual I/O. This keeps textus itself free of implicit network calls (SPEC §5.4).

If you want bytes to come from disk or a URL, you write the handler.

> Copy-paste starting points for common sources (HTTP JSON, RSS, iCal, local
> file, Notion) live in [`../cookbook/intake-recipes.md`](../cookbook/intake-recipes.md).

### Custom `:resolve_handler` hooks

Drop a Ruby file in `.textus/hooks/`. The return shape must be one of three:

- `{ _meta:, body: }` — markdown-friendly; `_meta` becomes the entry's parsed metadata hash
- `{ content: }` — for `format: json|yaml` entries; the parsed object becomes the entry's content
- `{ body: }` — raw bytes; the store re-parses per `format:`

```ruby
# .textus/hooks/notion.rb
Textus.hook do |reg|
  reg.on(:resolve_handler, :notion) do |caps:, config:, args:|
    page_id = config.fetch("page_id")
    body = NotionClient.new.fetch_markdown(page_id)
    { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: body }
  end
end
```

Then point an entry at it:

```yaml
entries:
  - key: artifacts.feeds.notion.roadmap
    path: artifacts/feeds/notion/roadmap.md
    zone: artifacts
    kind: produced              # produce-method (intake) read from source.from: handler
    source:
      from: handler
      handler: notion           # matches the hook name
      ttl: 6h
      config: { page_id: "abc123" }
```

On an entry past its `source.ttl`, `textus reconcile --as=automation` (or a `hook run` event) invokes the handler, normalizes the result by the entry's declared format, and writes it through the capability gate just like any other write.

The third kwarg, `args:`, carries leaf-key context: `args[:trigger_key]` is the full key being fetched and `args[:leaf_segments]` holds the segments past the parent `intake` entry (for `nested: true` intakes). Handlers over fan-out intakes should scope work to the requested leaf rather than re-running the parent config for every leaf. See [`../reference/events.md` (`:resolve_handler` args)](../reference/events.md#resolve_handler-args).

### Machine snapshot (scaffolded)

`textus init` drops a `machine_intake.rb` `:resolve_handler` hook and a **nested**
`artifacts.feeds.machines` entry (`tracked: false`) with one machine configured — `local`.
`textus reconcile --as=automation` (when the entry is past its `source.ttl`)
pulls a snapshot of this host into the `artifacts` machine zone:

- **git** — short HEAD, branch, dirty flag, repo root (the *control* host's repo; only meaningful for `local`)
- **platform** — os, arch, ruby version, and `runtimes` (node/python/go versions, `null` when not installed)
- **packages** — counts per manager (`brew`, `apt`); never the package list
- `captured_at`, `textus_version`, `protocol`

It is **retrievable via the protocol** (`textus get artifacts.feeds.machines.local`) but
**gitignored and never published**, because machine info can be sensitive or
noisy — the entry's `tracked: false` flag drives the generated `.gitignore`
(the whole `zones/artifacts/feeds/machines/` subtree). The scan runs **only on a
`reconcile` re-pull** (never a `get`/`boot`/`pulse` read), and the entry's own
`source.ttl: 1h` amortizes the cost (a `brew list` count is ~1–3 s) on a long-running server. The hook is a deliberate **allowlist** — versions and counts, no raw
`env`, no secrets.

Because it's **nested**, it grows to a fleet without renaming: add
`feeds.machines.<host>` leaves pulled over SSH (the *Environment scan across
machines* cookbook recipe shows the fan-out). Don't want it? Delete the entry +
hook to opt out.

### Aging entries out — a destructive `retention:` rule

Queue and machine zones accumulate; a `retention:` rule lets them self-prune. It is
the orthogonal age-based GC slot (ADR 0093) — independent of an intake entry's
`source.ttl` re-pull cadence. Declare it in a `rules:` block, matched by glob:

```yaml
rules:
  - match: proposals.**
    retention: { ttl: 30d, action: drop }      # delete accepted/abandoned proposals
  - match: artifacts.feeds.**
    retention: { ttl: 90d, action: archive }   # move stale external bytes aside
```

Then `textus reconcile --as=ROLE` performs the destructive sweep (Phase 2; the role
must be allowed to write the matched zone). `action: drop` deletes the leaf;
`action: archive` moves it to `.textus/archive/` and then deletes the original.
`retention:` applies to stored (leaf/nested/intake) entries; a `retention:` rule on a
`derived` entry is rejected at load (derived entries regenerate — aging them out is
meaningless). Age is measured from `_meta.last_fetched_at` (intake entries) when
present, else the leaf's file modification time. Destruction runs **only** on the
reconcile sweep, never on a write or read (ADR 0079/0093). Preview with `--dry-run`,
narrow a sweep with `--prefix` or `--zone`, and inspect what a key is subject to with
`textus rule explain KEY` — the resolved `retention` appears in the effective output.

---

## Wiring data out — derived entries and publishing

A derived entry says **"acquire my data from these sources, then publish me — copy verbatim, or render through a template — to these external paths."** Acquire (`source:`) and presentation (`publish:`) are two orthogonal axes (ADR 0094): `source:` produces data; rendering lives on a publish target.

```yaml
- key: artifacts.derived.claude-root
  path: artifacts/derived/claude-root.md
  zone: artifacts
  owner: automation:reconcile
  source:
    from: project                                      # project | command (handler = intake)
    select: [knowledge.identity.self, knowledge.notes] # source keys
    pluck: "*"                                          # which fields
    transform: identity                                # optional :transform_rows hook (shapes data)
    format: json                                        # the stored form is data
  publish:
    - { to: CLAUDE.md, template: claude-root.mustache } # render the data through a template
```

One dataset can feed differently-formatted outputs — add a second to-target with its own `template:` (e.g. `{ to: AGENTS.md, template: agents.mustache }`). A to-target with **no** `template:` copies the data verbatim (json/yaml re-serialized without `_meta`).

### Registering hooks

Hooks live in Ruby files under `.textus/hooks/`. See [`../how-to/writing-hooks.md`](writing-hooks.md) — the hook-author's guide — for the registration surface, handler signatures, and worked examples. The manifest side (which entries trigger which hooks) is covered by [intake wiring](#wiring-data-in--intake-and-resolve_handler-hooks) and [derived entries](#wiring-data-out--derived-entries-and-publishing) above.

### What `textus reconcile` does (Phase 1 — produce)

For every entry in a reconcile-writable zone:

1. **Acquire** — gather the data per `source.from` (`project`: select the named keys; `handler`: fetch; `command`: already on disk)
2. **Shape** — pluck fields, run the `:transform_rows` reducer if any (it shapes the data, not its presentation)
3. **Write data** — save the data bytes (per `format:`) to the derived path, and fire `:entry_produced`
4. **Publish** — for each publish target (one shared path), render the data through `template:` (`+ boot` if `inject_boot:`) or copy it verbatim, write the file to the repo path, write a sentinel under `.textus/.run/sentinels/`, and fire the `:entry_published` pub-sub event. Listeners can subscribe to `:entry_published` to react per-file — e.g. run `git add`, notify on writes, or compute checksums.

Phase 2 sweeps the destructive `retention:` actions (`action: drop|archive`) on aged entries. Both phases run under one shared maintenance lock; `--dry-run` prints the plan without executing.

Derived entries also stay fresh **reactively** between full passes: a canon write enqueues a `materialize` job for each derived entry that depends on it, which a worker converges. Materialization is **async-only** — the write returns immediately and the job is processed by `drain` (the batch/CI pass) or `serve` (the daemon). There is no per-entry write-trigger knob; freshness is re-homed to the drain at the commit/CI gate and to the running daemon. The per-write rebuild is still "reconcile narrowed to `rdeps ∩ derived`" (ADR 0093).

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
  - { name: artifacts,  kind: machine }

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

  - key: artifacts.derived.claude-root
    path: artifacts/derived/claude-root.md
    zone: artifacts
    owner: automation:reconcile
    source:
      from: project
      select: [knowledge.identity.self, knowledge.notes]
      pluck: "*"
      transform: claude_root           # name of a :transform_rows hook in .textus/hooks/
      format: json                     # the stored form is data
    publish:
      - { to: CLAUDE.md, template: claude-root.mustache, inject_boot: true }  # render + merge `textus boot`
```

Day-to-day flow:

```
$ textus put knowledge.identity.self --as=human  < new-identity.md   # edit identity
$ textus put knowledge.notes.kickoff --as=human  < kickoff.md         # add a note
$ textus reconcile                                                     # produce data + publish CLAUDE.md
$ git diff CLAUDE.md                                                   # review and commit
```

To layer AI proposals in, add a zone with `kind: queue` (e.g. `name: proposals`) and let agents write into it with `--as=agent`, then `textus accept proposals.suggestion.<id> --as=human` promotes the proposal into `knowledge`. Proposals route to whichever zone declares `kind: queue` — the name doesn't matter.

To layer external feeds in, declare intake entries under `artifacts.feeds.*` in the `machine` zone, each with a `source: { from: handler, handler:, ttl: }` pointing at a `:resolve_handler` hook (add an orthogonal `retention:` rule for GC). `textus reconcile --as=automation` (on a schedule) then re-pulls any entry past its `source.ttl` and keeps it current; a `get` reads it but never refreshes (ADR 0089).

For agent workspace memory, add a zone with `kind: workspace` (e.g. `name: notebook`) writable by a role holding `keep` (e.g. `agent`). Bytes in `notebook` never auto-promote; to persist changes into `knowledge`, the agent proposes and a human accepts.

---

## Where to go from here

- [`../reference/zones.md`](../reference/zones.md) — the exact zone, role, and entry semantics
- [`../../SPEC.md`](../../SPEC.md) — the normative wire-protocol spec
- [`../how-to/writing-hooks.md`](writing-hooks.md) — the hook-author's guide
- [`../../examples/project/`](../../examples/project/) — a complete worked example
