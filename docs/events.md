# Events — writing hooks

> **How-to** · for hook authors · **read when** you want to extend textus with Ruby hooks
> **SSoT for** the hook-authoring guide (normative event table lives in SPEC §5.10) · **reviewed** 2026-05 (v0.30)

How to extend textus with Ruby hooks: when each event fires, what arguments it receives, how to define one, and how to test it.

This is the hook-author's guide. For the normative event table see [`../SPEC.md` §5.10](../SPEC.md). For configuring zones and entries see [`./zones.md`](./zones.md).

**New to hooks?** Read §1 — the RPC-vs-pub-sub model is the whole mental model in ~20 lines. The rest is reference you can skim on demand.

## Table of contents

1. [The one mental model — RPC vs pub-sub](#1-the-one-mental-model--rpc-vs-pub-sub)
2. [The events in plain English](#2-the-events-in-plain-english)
3. [Lifecycle timelines per verb](#3-lifecycle-timelines-per-verb)
4. [The definition surface](#4-the-definition-surface)
5. [The `ctx:` handle — what you can and can't do](#5-the-ctx-handle)
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
   :validate       → doctor checks          :entry_fetched      → after fetch
                                            :build_completed    → after derived materialization
                                            :proposal_accepted  → after pending → target promotion
                                            :file_published     → after each file written to a repo path
                                            :entry_renamed      → after rename
                                            :proposal_rejected  → after proposal discard
                                            :store_loaded       → once per Store.new
                                            :fetch_started      → before intake handler runs
                                            :fetch_failed       → intake handler raised
                                            :fetch_backgrounded → timed_sync budget exceeded
```

**RPC events steer the verb's data. Pub-sub events observe the verb's outcome.** That's the whole model.

---

## 2. The events in plain English

textus has 15 events: 3 RPC and 12 pub-sub. The 3 `:fetch_*` lifecycle events are listed separately in §2.1.

| Event | Mode | What it's for |
|-------|------|---------------|
| `:resolve_intake` | rpc | Pull bytes into an `intake` entry. Invoked by `textus fetch` or `textus fetch stale`. |
| `:transform_rows` | rpc | Reshape projection rows for a `derived` entry. Invoked by `textus build`. |
| `:validate` | rpc | Contribute a custom rule to `textus doctor`. Returns an array of issues. |
| `:entry_put` | pubsub | Something just got written. Fires for every successful write (including fetch-driven). Payload: `{ ctx:, key:, envelope: }`. |
| `:entry_deleted` | pubsub | An entry was just unlinked. Payload: `{ ctx:, key: }`. |
| `:entry_fetched` | pubsub | Like `:entry_put` but specific to fetch-driven writes. Both fire — `:entry_put` first, then `:entry_fetched`. Payload: `{ ctx:, key:, envelope:, change: }`. |
| `:build_completed` | pubsub | One derived entry just finished materializing. Fires once per derived entry per build. Payload: `{ ctx:, key:, envelope:, sources: }`. |
| `:proposal_accepted` | pubsub | A pending proposal was promoted into its target zone. Payload: `{ ctx:, key:, target_key: }`. |
| `:file_published` | pubsub | A derived file was written to a repo path. Fires once per file for both `publish_to:` and `publish_each:`. Payload: `{ ctx:, key:, envelope:, source:, target: }`. |
| `:entry_renamed` | pubsub | A key was renamed in place. Both `:entry_put` and `:entry_deleted` are suppressed — `:entry_renamed` is the sole signal. Payload: `{ ctx:, key:, from_key:, to_key:, envelope: }`. `key:` equals `to_key:` — it's the entry's post-move home, present so `keys:` glob filters route correctly. |
| `:proposal_rejected` | pubsub | A pending proposal was explicitly discarded (via `textus reject` or `ops.reject(key)`). Counterpart to `:proposal_accepted`. Payload: `{ ctx:, key:, target_key: }`. |
| `:store_loaded` | pubsub | Fires exactly once after `Store#initialize` finishes — hooks are registered, ports are wired. Use for cache warmups or external watcher registration. Payload: `{ ctx: }`. |

### 2.1 Fetch lifecycle events

Three additional pub-sub events observe the progress of in-process and background intake fetches.

| Event | Mode | What it's for |
|-------|------|---------------|
| `:fetch_started` | pubsub | Fires immediately before an intake handler is invoked. `mode:` is `"sync"` or `"timed_sync"`. Payload: `{ ctx:, key:, mode: }`. |
| `:fetch_failed` | pubsub | Fires when an intake handler raises. Payload: `{ ctx:, key:, error_class:, error_message: }`. The failing fetch is already aborted; this is observational only. |
| `:fetch_backgrounded` | pubsub | Fires when a `timed_sync` fetch exceeds its `sync_budget_ms` deadline and is handed off to a background thread. Payload: `{ ctx:, key:, started_at:, budget_ms: }`. Callers can use this to log latency outliers. |

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

### `textus build`

```
  ┃ for each entry in a build-writable zone:
  ┃   ┃ load source rows
  ┃   ┃ if compute.transform: ───────────► :transform_rows  (RPC)
  ┃   ┃                                      returns Array<row> or Hash
  ┃   ┃ sort/limit (skipped if reduce returned Hash)
  ┃   ┃ merge `boot` if inject_boot:
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
  ┃ run 9 builtin Doctor::Check::* classes
  ┃ for each registered :validate hook:
  ┃   ───────────────────────────────────► :validate  (RPC per hook)
  ┃                                          returns Array<issue>
  ┃ aggregate, emit report
  ✔ exit 0 / 1
```

---

## 4. The definition surface

Hook files wrap a single `Textus.hook { |reg| ... }` block. The block receives the store's registry and registers handlers on it.

```ruby
# RPC and pub-sub register the same way — through reg.on.
Textus.hook do |reg|
  reg.on(:resolve_intake, :local_file) do |caps:, config:, args:|
    { _meta: {}, body: File.read(config["path"]) }
  end

  reg.on(:entry_put, :audit, keys: ["working.*"]) { |ctx:, key:, envelope:, **| ... }
  reg.on(:file_published, :git_add, keys: ["derived.*"]) { |ctx:, key:, target:, **| `git add #{target.shellescape}` }
end
```

Multiple `reg.on` calls can share one `Textus.hook` block, or you can split them across blocks — the store-scoped loader drains every queued block and invokes each with its own registry. There is no thread-local and no global state.

**Signature rule** — every hook accepts kwargs. Either list the ones you need explicitly, or accept `**` to absorb the rest. Missing a required kwarg with no `**` raises `UsageError` at registration time.

---

## 5. The `ctx:` handle

Every pubsub event receives `ctx:` (a `Textus::Hooks::Context`) instead of the raw store. Use it to read entries (`ctx.get(key)`, `ctx.list(...)`, `ctx.deps(key)`), write entries (`ctx.put(key, body: ...)`, `ctx.delete(key)`), append custom audit rows (`ctx.audit("my_verb", key: key, etag_before: nil, etag_after: nil)`), or fan out follow-up events (`ctx.publish_followup(:entry_put, key: key, envelope: env)`). The `ctx.role` and `ctx.correlation_id` accessors expose the originating request context.

All writes via `ctx` route through the use-case dispatch (`store.as(role)` → `RoleScope` → `Dispatcher`) so authorization, schema validation, and audit logging always fire — there are no bypass paths.

RPC events (`:resolve_intake`, `:transform_rows`, `:validate`) are gem-internal and receive `caps:` instead of `ctx:` — a `Textus::Container` record (the wired ports + manifest). Legacy `store:` is rejected by the registry.

If you don't need `ctx:`, absorb it with `**`:

```ruby
Textus.hook do |reg|
  reg.on(:transform_rows, :claude_root) do |rows:, **|   # ctx: absorbed by **
    ...
  end
end
```

---

## 6. Failure modes and timeouts

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

## 7. Fan-out and `keys:` globs

Pub-sub handlers can scope themselves with a `keys:` filter. Globs use `File.fnmatch?` with `FNM_PATHNAME`, meaning `*` does **not** cross `.` separators:

```ruby
Textus.hook do |reg|
  reg.on(:entry_put, :audit_working, keys: ["working.*"])      { ... }  # working.x ✓, working.y.z ✗
  reg.on(:entry_put, :audit_working_deep, keys: ["working.**"]) { ... } # any depth ✓
  reg.on(:entry_put, :audit_identity, keys: ["identity.*", "identity.**"]) { ... }
  reg.on(:entry_put, :audit_all) { ... }                                # no filter → every key
end
```

One `:entry_put` fans out to **every matching handler**, sequentially, each under its own 2-second timeout. Order is registration order (alphabetical by hook file path).

---

## 7a. `:resolve_intake` args

The third kwarg `args:` carries leaf-key context populated by `FetchWorker`:

| Key | Type | Meaning |
|-----|------|---------|
| `trigger_key` | String | The full key being fetched (e.g. `"intake.vendor.affaan-m.agent-eval"`). |
| `leaf_segments` | Array&lt;String&gt; | The segments **past** the parent `intake` entry (`["affaan-m", "agent-eval"]` in the example above). Empty array when the key matches the entry exactly. |

Handlers that ignore `args:` keep working unchanged. Handlers over a `nested: true` intake should scope to the requested leaf using `args[:leaf_segments]` — re-processing the full parent `intake_config` for every leaf fetch is the path of pain (and the reason Bug 2 existed pre-0.15.0).

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

---

## 9. Testing hooks

Hooks register against a per-store `Hooks::Registry`. In tests, instantiate a registry and call `reg.on` directly — no thread-local, no global state:

```ruby
RSpec.describe "my notion hook" do
  let(:reg) { Textus::Hooks::Registry.new }

  it "registers under :notion" do
    reg.on(:resolve_intake, :notion) { |caps:, config:, args:| { _meta: {}, body: "stub" } }
    expect(reg.rpc_names(:resolve_intake)).to include(:notion)
  end

  it "returns the expected shape" do
    reg.on(:resolve_intake, :notion) do |caps:, config:, args:|
      { _meta: { "fetched_at" => "now" }, body: "hello" }
    end
    handler = reg.rpc_callable(:resolve_intake, :notion)
    result  = handler.call(caps: nil, config: {}, args: {})
    expect(result[:body]).to eq("hello")
  end
end
```

For pub-sub handlers, drive the dispatcher directly:

```ruby
captured = []
reg.on(:entry_put, :listener, keys: ["working.*"]) { |ctx:, key:, envelope:, **| captured << key }

reg.listeners(:entry_put, key: "working.x").first[:callable].call(
  ctx: nil, key: "working.x", envelope: {}
)
expect(captured).to eq(["working.x"])
```

To exercise the loader end-to-end (drains `Textus.hook` blocks against your registry), point `Hooks::Loader.new(registry: reg).load_dir(path)` at a fixture directory whose files declare `Textus.hook { |reg| reg.on(...) { ... } }`.

See `spec/hooks/registry_spec.rb` for the canonical patterns.

---

## 10. Common patterns

### Connector — paired `:resolve_intake` + `:transform_rows`

```ruby
Textus.hook do |reg|
  reg.on(:resolve_intake, :linear) do |caps:, config:, args:|
    bytes = LinearClient.fetch(config["team_id"])
    { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: bytes }
  end

  reg.on(:transform_rows, :linear) do |rows:, **|
    rows.map { |r| r.slice("id", "title", "state", "updated_at") }
        .sort_by { |r| r["updated_at"] }
        .reverse
  end
end
```

Manifest references the same name on both sides:

```yaml
- key: intake.linear.issues
  zone: intake
  intake: { handler: linear, config: { team_id: "ENG" } }

- key: output.linear.dashboard
  zone: output
  compute: { kind: projection, select: [intake.linear.issues], transform: linear }

rules:
  - match: intake.linear.**
    fetch: { ttl: 1h, on_stale: warn }
```

### Audit listener — every write to a sensitive zone

```ruby
Textus.hook do |reg|
  reg.on(:entry_put, :identity_audit, keys: ["identity.**"]) do |ctx:, key:, envelope:, **|
    Syslog.log(Syslog::LOG_INFO, "identity-write key=#{key} etag=#{envelope['etag']} role=#{ctx.role}")
  end
end
```

### Build notifier — desktop ping when derived files rebuild

```ruby
Textus.hook do |reg|
  reg.on(:build_completed, :notify) do |ctx:, key:, sources:, **|
    system("terminal-notifier", "-message", "Built #{key} from #{sources.size} sources")
  end
end
```

### Custom doctor check — enforce a project rule

```ruby
Textus.hook do |reg|
  reg.on(:validate, :no_drafts_in_identity) do |caps:|
    call = Textus::Call.new(role: "doctor")
    Textus::Read::List.new(container: caps, call: call).call(zone: "identity")
      .select { |e| e["frontmatter"]["status"] == "draft" }
      .map    { |e| { "code" => "draft_in_identity", "key" => e["key"] } }
  end
end
```

A non-empty return array surfaces as a doctor failure with each issue listed.

`caps:` is a `Textus::Container` bundling `manifest`, `file_store`, `schemas`, `audit_log`, `events`, `rpc`, `authorizer`, and the store `root`. Pull the slice you need into a local; never reach for the raw Store.

---

## Where to go from here

- [`./zones.md`](./zones.md) — the manifest side: declaring which entries trigger which hooks
- [`../SPEC.md` §5.4, §5.10](../SPEC.md) — the normative `:resolve_intake` and event contracts
- [`architecture/README.md`](architecture/README.md) — how `Hooks::Registry` and `Hooks::Dispatcher` are implemented
- [`../examples/claude-plugin/.textus/hooks/`](../examples/claude-plugin/.textus/hooks/) — six worked hooks across four event types
