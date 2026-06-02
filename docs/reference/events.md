# Events — reference

> **Reference** · for hook authors · **read when** you need the event catalog, lifecycle timelines, or `ctx:` fields
> **SSoT for** the friendly event catalog and per-verb lifecycle timelines (the *normative* event table is SPEC §5.10) · **reviewed** 2026-06 (v0.43)

The event catalog in plain English, the per-verb lifecycle timelines, and the facts hook authors look up: failure modes, intake `args:`, and built-in parsers.

This is the catalog and timeline reference. The *normative* event table lives in [`../../SPEC.md` §5.10](../../SPEC.md#510-hooks) — this doc does not restate it. For how to define, wire, and test hooks, see [`../how-to/writing-hooks.md`](../how-to/writing-hooks.md).

> New here? Start with [Concepts](../explanation/concepts.md).

## Table of contents

1. [The events in plain English](#the-events-in-plain-english)
2. [Fetch lifecycle events](#fetch-lifecycle-events)
3. [Lifecycle timelines per verb](#lifecycle-timelines-per-verb)
4. [Failure modes and timeouts](#failure-modes-and-timeouts)
5. [`:resolve_intake` args](#resolve_intake-args)
6. [Built-in fetch parsers](#built-in-fetch-parsers)

---

## The events in plain English

textus has 15 events: 3 RPC and 12 pub-sub. The 3 `:fetch_*` lifecycle events are listed separately in [Fetch lifecycle events](#fetch-lifecycle-events).

| Event | Mode | What it's for |
|-------|------|---------------|
| `:resolve_intake` | rpc | Pull bytes into an `intake` entry. Invoked by `textus fetch` or `textus fetch all`. |
| `:transform_rows` | rpc | Reshape projection rows for a `derived` entry. Invoked by `textus publish`. |
| `:validate` | rpc | Contribute a custom rule to `textus doctor`. Returns an array of issues. |
| `:entry_put` | pubsub | Something just got written. Fires for every successful write (including fetch-driven). Payload: `{ ctx:, key:, envelope: }`. |
| `:entry_deleted` | pubsub | An entry was just unlinked. Payload: `{ ctx:, key: }`. |
| `:entry_fetched` | pubsub | Like `:entry_put` but specific to fetch-driven writes. Both fire — `:entry_put` first, then `:entry_fetched`. Payload: `{ ctx:, key:, envelope:, change: }`. |
| `:build_completed` | pubsub | One derived entry just finished materializing. Fires once per derived entry per build. Payload: `{ ctx:, key:, envelope:, sources: }`. |
| `:proposal_accepted` | pubsub | A pending proposal was promoted into its target zone. Payload: `{ ctx:, key:, target_key: }`. |
| `:file_published` | pubsub | A derived file was written to a repo path. Fires once per file for both `publish: { to: }` and `publish: { tree: }`. Payload: `{ ctx:, key:, envelope:, source:, target: }`. |
| `:entry_renamed` | pubsub | A key was renamed in place. Both `:entry_put` and `:entry_deleted` are suppressed — `:entry_renamed` is the sole signal. Payload: `{ ctx:, key:, from_key:, to_key:, envelope: }`. `key:` equals `to_key:` — it's the entry's post-move home, present so `keys:` glob filters route correctly. |
| `:proposal_rejected` | pubsub | A pending proposal was explicitly discarded (via `textus reject` or `ops.reject(key)`). Counterpart to `:proposal_accepted`. Payload: `{ ctx:, key:, target_key: }`. |
| `:store_loaded` | pubsub | Fires exactly once after `Store#initialize` finishes — hooks are registered, ports are wired. Use for cache warmups or external watcher registration. Payload: `{ ctx: }`. |

### Fetch lifecycle events

Three additional pub-sub events observe the progress of in-process and background intake fetches.

| Event | Mode | What it's for |
|-------|------|---------------|
| `:fetch_started` | pubsub | Fires immediately before an intake handler is invoked. `mode:` is `"sync"` or `"timed_sync"`. Payload: `{ ctx:, key:, mode: }`. |
| `:fetch_failed` | pubsub | Fires when an intake handler raises. Payload: `{ ctx:, key:, error_class:, error_message: }`. The failing fetch is already aborted; this is observational only. |
| `:fetch_backgrounded` | pubsub | Fires when a `timed_sync` fetch exceeds its `sync_budget_ms` deadline and is handed off to a background thread. Payload: `{ ctx:, key:, started_at:, budget_ms: }`. Callers can use this to log latency outliers. |

---

## Lifecycle timelines per verb

Each timeline reads top-to-bottom. `┃` is the verb's control flow; `─►` is a hook callout.

### `textus put KEY --as=<role>`

```
  ┃ resolve KEY → manifest entry
  ┃ role gate                              ── ABORT if no
  ┃ etag check (--if-etag)                 ── ABORT if mismatch
  ┃ serialize, write file
  ┃ append audit row {verb:"put"}
  ┃ ─────────────────────────────────────► :entry_put  (pubsub)
  ✔ emit envelope to stdout
```

### `textus key delete KEY --as=<role>`

```
  ┃ role gate                              ── ABORT if no
  ┃ unlink file
  ┃ append audit row {verb:"delete"}
  ┃ ─────────────────────────────────────► :entry_deleted  (pubsub)
  ✔ done
```

### `textus fetch KEY --as=script`

```
  ┃ require entry.intake.handler           ── ABORT if missing
  ┃ ─────────────────────────────────────► :fetch_started  (pubsub, mode: "sync"|"timed_sync")
  ┃ ─────────────────────────────────────► :resolve_intake  (RPC)
  ┃                                          returns { _meta:, body: } | { content: } | { body: }
  ┃   if handler raises:
  ┃ ─────────────────────────────────────► :fetch_failed  (pubsub)
  ┃   if timed_sync and budget exceeded:
  ┃ ─────────────────────────────────────► :fetch_backgrounded  (pubsub) — then continues in bg
  ┃ normalize result by entry.format
  ┃ role gate, etag check, write           (same path as put)
  ┃ append audit row {verb:"fetch"}
  ┃ ─────────────────────────────────────► :entry_put         (pubsub) — every write fires :entry_put
  ┃ ─────────────────────────────────────► :entry_fetched     (pubsub) — plus the fetch-specific event
  ✔ done
```

### `textus mv OLD_KEY NEW_KEY --as=<role>`

```
  ┃ resolve OLD_KEY → manifest entry
  ┃ role gate                              ── ABORT if no
  ┃ resolve NEW_KEY, refuse if exists      ── ABORT if collision
  ┃ mint uid in place if absent (suppressed :entry_put)
  ┃ FileUtils.mv source → target
  ┃ rewrite name frontmatter
  ┃ append audit row {verb:"mv"}
  ┃ ─────────────────────────────────────► :entry_renamed  (pubsub) — single signal; no :entry_put/:entry_deleted
  ✔ done
```

### `textus reject PENDING_KEY --as=human`

```
  ┃ guard: actor must hold `author` (author_held)        ── ABORT if no
  ┃ require zone == pending                ── ABORT if no
  ┃ require _meta.proposal block           ── ABORT if no
  ┃ delete the pending file
  ┃ append audit row {verb:"delete"}
  ┃ ─────────────────────────────────────► :entry_deleted     (pubsub) — generic delete observers still fire
  ┃ ─────────────────────────────────────► :proposal_rejected (pubsub) — proposal-specific signal
  ✔ done
```

### `Textus::Store.new(root)` (one-shot)

```
  ┃ load manifest
  ┃ build schemas, file_store, audit_log
  ┃ build dispatcher + registry
  ┃ load all hooks under .textus/hooks/**.rb
  ┃ ─────────────────────────────────────► :store_loaded (pubsub) — fires exactly once per process per store
  ✔ store ready for use
```

### `textus publish`

```
  ┃ for each entry in a build-writable zone:
  ┃   ┃ load source rows
  ┃   ┃ if compute.transform: ───────────► :transform_rows  (RPC)
  ┃   ┃                                      returns Array<row> or Hash
  ┃   ┃ sort/limit (skipped if reduce returned Hash)
  ┃   ┃ merge `boot` if inject_boot:
  ┃   ┃ render via format + template
  ┃   ┃ write derived path
  ┃   ┃ for each publish.to / publish.tree target:
  ┃   ┃   byte-copy file to repo path
  ┃   ┃   ─────────────────────────────► :file_published   (pubsub) — per file written
  ┃   ┃ append audit row {verb:"compute"}
  ┃   ┃ ───────────────────────────────► :build_completed  (pubsub) — per entry
  ✔ done
```

### `textus accept PENDING_KEY --as=human`

```
  ┃ guard: actor must hold `author` (author_held)        ── ABORT if no
  ┃ read pending entry frontmatter
  ┃ guard: target_key must resolve to a canon zone (target_is_canon) ── ABORT if no
  ┃ apply proposal.action to proposal.target_key
  ┃   └─► triggers :entry_put or :entry_deleted pubsub for the target
  ┃ delete pending entry
  ┃   └─► triggers :entry_deleted pubsub for pending
  ┃ append audit row {verb:"accept"}
  ┃ ─────────────────────────────────────► :proposal_accepted  (pubsub)
  ✔ done
```

### `textus doctor`

```
  ┃ run builtin Doctor::Check::* classes
  ┃ for each registered :validate hook:
  ┃   ───────────────────────────────────► :validate  (RPC per hook)
  ┃                                          returns Array<issue>
  ┃ aggregate, emit report
  ✔ exit 0 / 1
```

---

## Failure modes and timeouts

| Hook event | Failure mode | What gets written |
|------------|--------------|-------------------|
| `:resolve_intake` raises | fetch aborts | nothing |
| `:transform_rows` raises | build aborts (this entry only) | nothing |
| `:validate` raises | doctor aborts | nothing |
| `:entry_put` raises | verb still succeeds | `event_error` row in `audit.log` |
| `:entry_deleted` raises | verb still succeeds | `event_error` row |
| `:entry_fetched` raises | verb still succeeds | `event_error` row |
| `:build_completed` raises | verb still succeeds | `event_error` row |
| `:proposal_accepted` raises | verb still succeeds | `event_error` row |
| `:file_published` raises | verb still succeeds | `event_error` row |
| `:entry_renamed` raises | verb still succeeds | `event_error` row |
| `:proposal_rejected` raises | verb still succeeds | `event_error` row |
| `:store_loaded` raises | store still ready | `event_error` row |
| `:fetch_started` raises | verb still succeeds | `event_error` row |
| `:fetch_failed` raises | verb still succeeds | `event_error` row |
| `:fetch_backgrounded` raises | verb still succeeds | `event_error` row |

Every handler runs under `Timeout.timeout(2)`. A timeout is treated as a raised error: RPC handlers abort the verb, pub-sub handlers log `event_error` and the verb continues.

The pub-sub guarantee — "your write will not fail because of a flaky listener" — is intentional. It means you can wire diagnostic listeners freely without worrying about breaking the request path.

---

## `:resolve_intake` args

The third kwarg `args:` carries leaf-key context populated by `FetchWorker`:

| Key | Type | Meaning |
|-----|------|---------|
| `trigger_key` | String | The full key being fetched (e.g. `"intake.vendor.affaan-m.agent-eval"`). |
| `leaf_segments` | Array&lt;String&gt; | The segments **past** the parent `intake` entry (`["affaan-m", "agent-eval"]` in the example above). Empty array when the key matches the entry exactly. |

Handlers that ignore `args:` keep working unchanged. Handlers over a `nested: true` intake should scope to the requested leaf using `args[:leaf_segments]` — re-processing the full parent `intake_config` for every leaf fetch is the path of pain (and the reason Bug 2 existed pre-0.15.0).

---

## Built-in fetch parsers

Five `:resolve_intake` hooks ship pre-registered:

| Name | Expects in `config["bytes"]` | Returns |
|------|------------------------------|---------|
| `json` | JSON text | YAML-serialized parsed object as `body:` |
| `csv` | CSV with header row | YAML-serialized array of row hashes |
| `markdown-links` | Markdown text | YAML-serialized list of `{text, href}` |
| `ical-events` | iCal text | YAML-serialized list of VEVENTs |
| `rss` | RSS/Atom XML | YAML-serialized list of `{title, link, pubDate}` |

**They do not perform I/O.** The bytes must arrive in `config["bytes"]`, supplied by the caller — usually a custom outer hook that fetches the URL and delegates parsing. This keeps textus itself free of implicit network calls (SPEC §5.4).

Wrapping pattern:

```ruby
Textus.hook do |reg|
  reg.on(:resolve_intake, :remote_rss) do |caps:, config:, args:|
    bytes = Net::HTTP.get(URI(config["url"]))
    # Parse the bytes inline — the built-in :rss handler is also available
    # but invoking it from a sibling hook requires plumbing the RpcRegistry
    # through; for a single-format wrapper, parse directly here.
    rows = MyRssParser.parse(bytes)
    { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: rows.to_json }
  end
end
```

For how to define, wire, and test these handlers, see [`../how-to/writing-hooks.md`](../how-to/writing-hooks.md).
