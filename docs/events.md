# Events — writing hooks

How to extend textus with Ruby hooks: when each event fires, what arguments it receives, how to define one, and how to test it.

This is the hook-author's guide. For the normative event table see [`../SPEC.md` §5.10](../SPEC.md). For configuring zones and entries see [`./zones.md`](./zones.md).

## Table of contents

1. [The one mental model — RPC vs pub-sub](#1-the-one-mental-model--rpc-vs-pub-sub)
2. [The events in plain English](#2-the-events-in-plain-english)
3. [Lifecycle timelines per verb](#3-lifecycle-timelines-per-verb)
4. [The three definition surfaces](#4-the-three-definition-surfaces)
5. [The `store:` proxy — what you can and can't do](#5-the-store-proxy)
6. [Failure modes and timeouts](#6-failure-modes-and-timeouts)
7. [Fan-out and `keys:` globs](#7-fan-out-and-keys-globs)
8. [Built-in fetch parsers](#8-built-in-fetch-parsers)
9. [Testing hooks](#9-testing-hooks)
10. [Common patterns](#10-common-patterns)

---

## 1. The one mental model — RPC vs pub-sub

Every event is one of two kinds.

```
   RPC                              PUB-SUB
   ───                              ───────
   • exactly 1 handler              • 0..N handlers
   • return value is USED           • return value is DISCARDED
   • raised error ABORTS the verb   • raised error LOGGED, verb continues
   • named explicitly by manifest   • triggered by lifecycle, filtered by keys:

   :resolve_intake → input to the store     :entry_put          → after any write
   :transform_rows → projection shaping     :entry_deleted      → after delete
   :validate       → doctor checks          :entry_refreshed    → after refresh
                                            :build_completed    → after derived materialization
                                            :proposal_accepted  → after pending → target promotion
                                            :file_published     → after each file written to a repo path
                                            :entry_renamed      → after rename
                                            :proposal_rejected  → after proposal discard
                                            :store_loaded       → once per Store.new
                                            :refresh_started    → before intake handler runs
                                            :refresh_failed     → intake handler raised
                                            :refresh_backgrounded → timed_sync budget exceeded
```

**RPC events steer the verb's data. Pub-sub events observe the verb's outcome.** That's the whole model.

---

## 2. The events in plain English

textus has 15 events: 3 RPC and 12 pub-sub. The 3 `:refresh_*` lifecycle events are listed separately in §2.1.

| Event | Mode | What it's for |
|-------|------|---------------|
| `:resolve_intake` | rpc | Pull bytes into an `intake` entry. Invoked by `textus refresh` or `textus refresh-stale`. |
| `:transform_rows` | rpc | Reshape projection rows for a `derived` entry. Invoked by `textus build`. |
| `:validate` | rpc | Contribute a custom rule to `textus doctor`. Returns an array of issues. |
| `:entry_put` | pubsub | Something just got written. Fires for every successful write (including refresh-driven). Payload: `{ store:, key:, envelope: }`. |
| `:entry_deleted` | pubsub | An entry was just unlinked. Payload: `{ store:, key: }`. |
| `:entry_refreshed` | pubsub | Like `:entry_put` but specific to refresh-driven writes. Both fire — `:entry_put` first, then `:entry_refreshed`. Payload: `{ store:, key:, envelope:, change: }`. |
| `:build_completed` | pubsub | One derived entry just finished materializing. Fires once per derived entry per build. Payload: `{ store:, key:, envelope:, sources: }`. |
| `:proposal_accepted` | pubsub | A pending proposal was promoted into its target zone. Payload: `{ store:, key:, target_key: }`. |
| `:file_published` | pubsub | A derived file was written to a repo path. Fires once per file for both `publish_to:` and `publish_each:`. Payload: `{ store:, key:, envelope:, source:, target: }`. |
| `:entry_renamed` | pubsub | A key was renamed in place. Both `:entry_put` and `:entry_deleted` are suppressed — `:entry_renamed` is the sole signal. Payload: `{ store:, key:, from_key:, to_key:, envelope: }`. `key:` equals `to_key:` — it's the entry's post-move home, present so `keys:` glob filters route correctly. |
| `:proposal_rejected` | pubsub | A pending proposal was explicitly discarded (via `textus reject` or `Operations.writes.reject.call(key)`). Counterpart to `:proposal_accepted`. Payload: `{ store:, key:, target_key: }`. |
| `:store_loaded` | pubsub | Fires exactly once after `Store#initialize` finishes — hooks are registered, reader/writer are ready. Use for cache warmups or external watcher registration. Payload: `{ store: }`. |

### 2.1 Refresh lifecycle events

Three additional pub-sub events observe the progress of in-process and background intake refreshes.

| Event | Mode | What it's for |
|-------|------|---------------|
| `:refresh_started` | pubsub | Fires immediately before an intake handler is invoked. `mode:` is `"sync"` or `"timed_sync"`. Payload: `{ store:, key:, mode: }`. |
| `:refresh_failed` | pubsub | Fires when an intake handler raises. Payload: `{ store:, key:, error_class:, error_message: }`. The failing refresh is already aborted; this is observational only. |
| `:refresh_backgrounded` | pubsub | Fires when a `timed_sync` refresh exceeds its `sync_budget_ms` deadline and is handed off to a background thread. Payload: `{ store:, key:, started_at:, budget_ms: }`. Callers can use this to log latency outliers. |

---

## 3. Lifecycle timelines per verb

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

### `textus delete KEY --as=<role>`

```
  ┃ role gate                              ── ABORT if no
  ┃ unlink file
  ┃ append audit row {verb:"delete"}
  ┃ ─────────────────────────────────────► :entry_deleted  (pubsub)
  ✔ done
```

### `textus refresh KEY --as=script`

```
  ┃ require entry.intake.handler           ── ABORT if missing
  ┃ ─────────────────────────────────────► :refresh_started  (pubsub, mode: "sync"|"timed_sync")
  ┃ ─────────────────────────────────────► :resolve_intake  (RPC)
  ┃                                          returns { _meta:, body: } | { content: } | { body: }
  ┃   if handler raises:
  ┃ ─────────────────────────────────────► :refresh_failed  (pubsub)
  ┃   if timed_sync and budget exceeded:
  ┃ ─────────────────────────────────────► :refresh_backgrounded  (pubsub) — then continues in bg
  ┃ normalize result by entry.format
  ┃ role gate, etag check, write           (same path as put)
  ┃ append audit row {verb:"refresh"}
  ┃ ─────────────────────────────────────► :entry_put         (pubsub) — every write fires :entry_put
  ┃ ─────────────────────────────────────► :entry_refreshed   (pubsub) — plus the refresh-specific event
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
  ┃ build dispatcher + registry
  ┃ load all hooks under .textus/hooks/**.rb
  ┃ build reader + writer
  ┃ ─────────────────────────────────────► :store_loaded (pubsub) — fires exactly once per process per store
  ✔ store ready for use
```

### `textus build`

```
  ┃ for each entry in a build-writable zone:
  ┃   ┃ load source rows
  ┃   ┃ if projection.reduce: ───────────► :transform_rows  (RPC)
  ┃   ┃                                      returns Array<row> or Hash
  ┃   ┃ sort/limit (skipped if reduce returned Hash)
  ┃   ┃ merge `intro` if inject_intro:
  ┃   ┃ render via format + template
  ┃   ┃ write derived path
  ┃   ┃ for each publish_to: / publish_each: target:
  ┃   ┃   byte-copy file to repo path
  ┃   ┃   ─────────────────────────────► :file_published   (pubsub) — per file written
  ┃   ┃ append audit row {verb:"compute"}
  ┃   ┃ ───────────────────────────────► :build_completed  (pubsub) — per entry
  ✔ done
```

### `textus accept PENDING_KEY --as=human`

```
  ┃ role gate: must be "human"             ── ABORT if no
  ┃ read pending entry frontmatter
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
  ┃ run 9 builtin Doctor::Check::* classes
  ┃ for each registered :validate hook:
  ┃   ───────────────────────────────────► :validate  (RPC per hook)
  ┃                                          returns Array<issue>
  ┃ aggregate, emit report
  ✔ exit 0 / 1
```

---

## 4. The two definition surfaces

Both register against the same registry. Pick whichever reads best.

```ruby
# 1. Primitive — the only registration form
Textus.on(:resolve_intake, :local_file) do |store:, config:, args:|
  { _meta: {}, body: File.read(config["path"]) }
end

# 2. Same API for pub-sub events
Textus.on(:entry_put, :audit, keys: ["working.*"]) { |store:, key:, envelope:, **| ... }
Textus.on(:file_published, :git_add, keys: ["derived.*"]) { |store:, key:, target:, **| `git add #{target.shellescape}` }
```

**Signature rule** — every hook accepts kwargs. Either list the ones you need explicitly, or accept `**` to absorb the rest. Missing a required kwarg with no `**` raises `UsageError` at registration time.

---

## 5. The `store:` proxy

Every hook receives `store:` as its first kwarg. It's an `Application::Context` bound to the active role — use it to drive read use cases (`Textus::Application::Reads::Get.new(ctx: store).call(key)`, `Textus::Application::Reads::List.new(ctx: store).call(...)`, etc.). Writes from inside a hook are unsupported and will raise.

Why: hooks fire inside a verb's control flow. Letting hooks write would create reentrancy, audit-log chaos, and surprise infinite loops. If you genuinely need to write from a hook, do it out of band — enqueue a job, write a sentinel file, or run a follow-up CLI command.

If you don't need `store:`, absorb it with `**`:

```ruby
Textus.on(:transform_rows, :claude_root) do |rows:, **|   # store: absorbed by **
  ...
end
```

---

## 6. Failure modes and timeouts

| Hook event | Failure mode | What gets written |
|------------|--------------|-------------------|
| `:resolve_intake` raises | refresh aborts | nothing |
| `:transform_rows` raises | build aborts (this entry only) | nothing |
| `:validate` raises | doctor aborts | nothing |
| `:entry_put` raises | verb still succeeds | `event_error` row in `audit.log` |
| `:entry_deleted` raises | verb still succeeds | `event_error` row |
| `:entry_refreshed` raises | verb still succeeds | `event_error` row |
| `:build_completed` raises | verb still succeeds | `event_error` row |
| `:proposal_accepted` raises | verb still succeeds | `event_error` row |
| `:file_published` raises | verb still succeeds | `event_error` row |
| `:entry_renamed` raises | verb still succeeds | `event_error` row |
| `:proposal_rejected` raises | verb still succeeds | `event_error` row |
| `:store_loaded` raises | store still ready | `event_error` row |
| `:refresh_started` raises | verb still succeeds | `event_error` row |
| `:refresh_failed` raises | verb still succeeds | `event_error` row |
| `:refresh_backgrounded` raises | verb still succeeds | `event_error` row |

Every handler runs under `Timeout.timeout(2)`. A timeout is treated as a raised error: RPC handlers abort the verb, pub-sub handlers log `event_error` and the verb continues.

The pub-sub guarantee — "your write will not fail because of a flaky listener" — is intentional. It means you can wire diagnostic listeners freely without worrying about breaking the request path.

---

## 7. Fan-out and `keys:` globs

Pub-sub handlers can scope themselves with a `keys:` filter. Globs use `File.fnmatch?` with `FNM_PATHNAME`, meaning `*` does **not** cross `.` separators:

```ruby
Textus.on(:entry_put, :audit_working, keys: ["working.*"])      { ... }  # working.x ✓, working.y.z ✗
Textus.on(:entry_put, :audit_working_deep, keys: ["working.**"]) { ... } # any depth ✓
Textus.on(:entry_put, :audit_identity, keys: ["identity.*", "identity.**"]) { ... }
Textus.on(:entry_put, :audit_all) { ... }                                # no filter → every key
```

One `:entry_put` fans out to **every matching handler**, sequentially, each under its own 2-second timeout. Order is registration order (alphabetical by hook file path).

---

## 8. Built-in fetch parsers

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
Textus.on(:resolve_intake, :remote_rss) do |store:, config:, args:|
  bytes = Net::HTTP.get(URI(config["url"]))
  store.invoke_rpc(:resolve_intake, :rss, config: { "bytes" => bytes }, args: args)
end
```

---

## 9. Testing hooks

Hooks register into the active registry. In tests, scope a registry per example with `Textus.with_registry`:

```ruby
RSpec.describe "my notion hook" do
  let(:reg) { Textus::Hooks::Registry.new }
  around { |ex| Textus.with_registry(reg) { ex.run } }

  it "registers under :notion" do
    Textus.on(:resolve_intake, :notion) { |store:, config:, args:| { _meta: {}, body: "stub" } }
    expect(reg.rpc_names(:resolve_intake)).to include(:notion)
  end

  it "returns the expected shape" do
    Textus.on(:resolve_intake, :notion) do |store:, config:, args:|
      { _meta: { "fetched_at" => "now" }, body: "hello" }
    end
    handler = reg.rpc_callable(:resolve_intake, :notion)
    result  = handler.call(store: nil, config: {}, args: {})
    expect(result[:body]).to eq("hello")
  end
end
```

For pub-sub handlers, drive the dispatcher directly:

```ruby
captured = []
Textus.on(:entry_put, :listener, keys: ["working.*"]) { |store:, key:, envelope:, **| captured << key }

reg.listeners(:entry_put, key: "working.x").first[:callable].call(
  store: nil, key: "working.x", envelope: {}
)
expect(captured).to eq(["working.x"])
```

See `spec/hooks/registry_spec.rb` for the canonical patterns.

---

## 10. Common patterns

### Connector — paired `:resolve_intake` + `:transform_rows`

```ruby
Textus.on(:resolve_intake, :linear) do |store:, config:, args:|
  bytes = LinearClient.fetch(config["team_id"])
  { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: bytes }
end

Textus.on(:transform_rows, :linear) do |store:, rows:, **|
  rows.map { |r| r.slice("id", "title", "state", "updated_at") }
      .sort_by { |r| r["updated_at"] }
      .reverse
end
```

Manifest references the same name on both sides:

```yaml
- key: intake.linear.issues
  zone: intake
  intake: { handler: linear, config: { team_id: "ENG" } }

- key: output.linear.dashboard
  zone: output
  projection: { select: [intake.linear.issues], reduce: linear }

rules:
  - match: intake.linear.**
    refresh: { ttl: 1h, on_stale: warn }
```

### Audit listener — every write to a sensitive zone

```ruby
Textus.on(:entry_put, :identity_audit, keys: ["identity.**"]) do |store:, key:, envelope:, **|
  Syslog.log(Syslog::LOG_INFO, "identity-write key=#{key} etag=#{envelope['etag']}")
end
```

### Build notifier — desktop ping when derived files rebuild

```ruby
Textus.on(:build_completed, :notify) do |store:, key:, sources:, **|
  system("terminal-notifier", "-message", "Built #{key} from #{sources.size} sources")
end
```

### Custom doctor check — enforce a project rule

```ruby
Textus.on(:validate, :no_drafts_in_identity) do |store:|
  Textus::Application::Reads::List.new(ctx: store).call(zone: "identity")
    .select { |e| e["frontmatter"]["status"] == "draft" }
    .map    { |e| { "code" => "draft_in_identity", "key" => e["key"] } }
end
```

A non-empty return array surfaces as a doctor failure with each issue listed.

---

## Where to go from here

- [`./zones.md`](./zones.md) — the manifest side: declaring which entries trigger which hooks
- [`../SPEC.md` §5.4, §5.10](../SPEC.md) — the normative `:resolve_intake` and event contracts
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — how `Hooks::Registry` and `Hooks::Dispatcher` are implemented
- [`../examples/claude-plugin/.textus/hooks/`](../examples/claude-plugin/.textus/hooks/) — six worked hooks across four event types
