# Events — writing hooks

How to extend textus with Ruby hooks: when each event fires, what arguments it receives, how to define one, and how to test it.

This is the hook-author's guide. For the normative event table see [`../SPEC.md` §5.10](../SPEC.md). For configuring zones and entries see [`./zones.md`](./zones.md).

## Table of contents

1. [The one mental model — RPC vs pub-sub](#1-the-one-mental-model--rpc-vs-pub-sub)
2. [The 8 events in plain English](#2-the-8-events-in-plain-english)
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

   :fetch  → input to the store     :put     → after any write
   :reduce → projection shaping     :delete  → after delete
   :check  → doctor checks          :refresh → after refresh
                                    :build   → after derived materialization
                                    :accept  → after pending → target promotion
```

**RPC events steer the verb's data. Pub-sub events observe the verb's outcome.** That's the whole model.

---

## 2. The 8 events in plain English

| Event | Mode | What it's for |
|-------|------|---------------|
| `:fetch` | rpc | Pull bytes into an `intake` entry. Invoked by `textus refresh`. |
| `:reduce` | rpc | Reshape projection rows for a `derived` entry. Invoked by `textus build`. |
| `:check` | rpc | Contribute a custom rule to `textus doctor`. Returns an array of issues. |
| `:put` | pubsub | Something just got written. Fires for every successful write (including refresh-driven). |
| `:delete` | pubsub | An entry was just unlinked. |
| `:refresh` | pubsub | Like `:put` but specific to refresh-driven writes. Both fire — `:put` first, then `:refresh`. |
| `:build` | pubsub | One derived entry just finished materializing. Fires once per derived entry per build. |
| `:accept` | pubsub | A pending proposal was promoted into its target zone. |

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
  ┃ ─────────────────────────────────────► :put  (pubsub)
  ✔ emit envelope to stdout
```

### `textus delete KEY --as=<role>`

```
  ┃ role gate                              ── ABORT if no
  ┃ unlink file
  ┃ append audit row {verb:"delete"}
  ┃ ─────────────────────────────────────► :delete  (pubsub)
  ✔ done
```

### `textus refresh KEY --as=script`

```
  ┃ require entry.source.fetch             ── ABORT if missing
  ┃ ─────────────────────────────────────► :fetch  (RPC)
  ┃                                          returns { _meta:, body: } | { content: } | { body: }
  ┃ normalize result by entry.format
  ┃ role gate, etag check, write           (same path as put)
  ┃ append audit row {verb:"refresh"}
  ┃ ─────────────────────────────────────► :put      (pubsub) — every write fires :put
  ┃ ─────────────────────────────────────► :refresh  (pubsub) — plus the refresh-specific event
  ✔ done
```

### `textus build`

```
  ┃ for each entry in a build-writable zone:
  ┃   ┃ load source rows
  ┃   ┃ if projection.reduce: ───────────► :reduce  (RPC)
  ┃   ┃                                      returns Array<row> or Hash
  ┃   ┃ sort/limit (skipped if reduce returned Hash)
  ┃   ┃ merge `intro` if inject_intro:
  ┃   ┃ render via format + template
  ┃   ┃ write derived path, byte-copy publish_to: targets
  ┃   ┃ append audit row {verb:"compute"}
  ┃   ┃ ───────────────────────────────► :build  (pubsub) — per entry
  ✔ done
```

### `textus accept PENDING_KEY --as=human`

```
  ┃ role gate: must be "human"             ── ABORT if no
  ┃ read pending entry frontmatter
  ┃ apply proposal.action to proposal.target_key
  ┃   └─► triggers :put or :delete pubsub for the target
  ┃ delete pending entry
  ┃   └─► triggers :delete pubsub for pending
  ┃ append audit row {verb:"accept"}
  ┃ ─────────────────────────────────────► :accept  (pubsub)
  ✔ done
```

### `textus doctor`

```
  ┃ run 9 builtin Doctor::Check::* classes
  ┃ for each registered :check hook:
  ┃   ───────────────────────────────────► :check  (RPC per hook)
  ┃                                          returns Array<issue>
  ┃ aggregate, emit report
  ✔ exit 0 / 1
```

---

## 4. The two definition surfaces

Both register against the same registry. Pick whichever reads best.

```ruby
# 1. Primitive — authoritative entry point
Textus.hook(:fetch, :local_file) do |store:, config:, args:|
  { _meta: {}, body: File.read(config["path"]) }
end

# 2. Per-event sugar (0.8.2+) — one event, one callback
Textus.fetch(:local_file)        { |config:, args:, **| ... }
Textus.reduce(:rank_by_recency)  { |rows:, **|          ... }
Textus.put(:audit, keys: ["working.*"]) { |key:, envelope:, **| ... }
```

**When to use which:**
- Per-event sugar (`Textus.fetch`, `Textus.reduce`, …) — preferred for simple cases
- `Textus.hook` — authoritative entry point; use when you want the most explicit form

**Signature rule** — every hook accepts kwargs. Either list the ones you need explicitly, or accept `**` to absorb the rest. Missing a required kwarg with no `**` raises `UsageError` at registration time.

---

## 5. The `store:` proxy

Every hook receives `store:` as its first kwarg. It's a **read-only proxy** — calling `store.get(key)`, `store.list(...)`, `store.where(key)` works; calling `store.put(...)` raises `UsageError`.

Why: hooks fire inside a verb's control flow. Letting hooks write would create reentrancy, audit-log chaos, and surprise infinite loops. If you genuinely need to write from a hook, do it out of band — enqueue a job, write a sentinel file, or run a follow-up CLI command.

For sugar forms that don't name `store:`, use `**` to discard it:

```ruby
Textus.reduce(:claude_root) do |rows:, **|   # store: absorbed by **
  ...
end
```

---

## 6. Failure modes and timeouts

| Hook event | Failure mode | What gets written |
|------------|--------------|-------------------|
| `:fetch` raises | refresh aborts | nothing |
| `:reduce` raises | build aborts (this entry only) | nothing |
| `:check` raises | doctor aborts | nothing |
| `:put` raises | verb still succeeds | `event_error` row in `audit.log` |
| `:delete` raises | verb still succeeds | `event_error` row |
| `:refresh` raises | verb still succeeds | `event_error` row |
| `:build` raises | verb still succeeds | `event_error` row |
| `:accept` raises | verb still succeeds | `event_error` row |

Every handler runs under `Timeout.timeout(2)`. A timeout is treated as a raised error: RPC handlers abort the verb, pub-sub handlers log `event_error` and the verb continues.

The pub-sub guarantee — "your write will not fail because of a flaky listener" — is intentional. It means you can wire diagnostic listeners freely without worrying about breaking the request path.

---

## 7. Fan-out and `keys:` globs

Pub-sub handlers can scope themselves with a `keys:` filter. Globs use `File.fnmatch?` with `FNM_PATHNAME`, meaning `*` does **not** cross `.` separators:

```ruby
Textus.put(:audit_working, keys: ["working.*"])    { ... }     # working.x ✓, working.y.z ✗
Textus.put(:audit_working_deep, keys: ["working.**"]) { ... }  # any depth ✓
Textus.put(:audit_canon,   keys: ["canon.*", "canon.**"]) { ... }
Textus.put(:audit_all)                              { ... }     # no filter → every key
```

One `put` fans out to **every matching handler**, sequentially, each under its own 2-second timeout. Order is registration order (alphabetical by hook file path).

---

## 8. Built-in fetch parsers

Five `:fetch` hooks ship pre-registered:

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
Textus.fetch(:remote_rss) do |store:, config:, args:|
  bytes = Net::HTTP.get(URI(config["url"]))
  store.invoke_rpc(:fetch, :rss, config: { "bytes" => bytes }, args: args)
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
    Textus.fetch(:notion) { |config:, **| { _meta: {}, body: "stub" } }
    expect(reg.rpc_names(:fetch)).to include(:notion)
  end

  it "returns the expected shape" do
    Textus.fetch(:notion) do |config:, args:, **|
      { _meta: { "fetched_at" => "now" }, body: "hello" }
    end
    handler = reg.rpc(:fetch, :notion)
    result  = handler.call(store: nil, config: {}, args: {})
    expect(result[:body]).to eq("hello")
  end
end
```

For pub-sub handlers, drive the dispatcher directly:

```ruby
captured = []
Textus.put(:listener, keys: ["working.*"]) { |key:, **| captured << key }

reg.listeners(:put, key: "working.x").first[:callable].call(
  store: nil, key: "working.x", envelope: {}
)
expect(captured).to eq(["working.x"])
```

See `spec/hooks/sugar_spec.rb` for the canonical patterns.

---

## 10. Common patterns

### Connector — paired `:fetch` + `:reduce`

```ruby
Textus.fetch(:linear) do |config:, args:, **|
  bytes = LinearClient.fetch(config["team_id"])
  { _meta: { "fetched_at" => Time.now.utc.iso8601 }, body: bytes }
end

Textus.reduce(:linear) do |rows:, **|
  rows.map { |r| r.slice("id", "title", "state", "updated_at") }
      .sort_by { |r| r["updated_at"] }
      .reverse
end
```

Manifest references the same name on both sides:

```yaml
- key: intake.linear.issues
  source: { fetch: linear, config: { team_id: "ENG" } }

- key: derived.linear.dashboard
  projection: { select: [intake.linear.issues], reduce: linear }
```

### Audit listener — every write to a sensitive zone

```ruby
Textus.put(:canon_audit, keys: ["canon.**"]) do |key:, envelope:, **|
  Syslog.log(Syslog::LOG_INFO, "canon-write key=#{key} etag=#{envelope['etag']}")
end
```

### Build notifier — desktop ping when derived files rebuild

```ruby
Textus.build(:notify) do |key:, sources:, **|
  system("terminal-notifier", "-message", "Built #{key} from #{sources.size} sources")
end
```

### Custom doctor check — enforce a project rule

```ruby
Textus.check(:no_drafts_in_canon) do |store:|
  store.list(zone: "canon")
       .select { |e| e["frontmatter"]["status"] == "draft" }
       .map    { |e| { "code" => "draft_in_canon", "key" => e["key"] } }
end
```

A non-empty return array surfaces as a doctor failure with each issue listed.

---

## Where to go from here

- [`./zones.md`](./zones.md) — the manifest side: declaring which entries trigger which hooks
- [`../SPEC.md` §5.4, §5.10](../SPEC.md) — the normative `:fetch` and event contracts
- [`./architecture.md`](./architecture.md) — how `Hooks::Registry` and `Hooks::Dispatcher` are implemented
- [`../examples/claude-plugin/.textus/hooks/`](../examples/claude-plugin/.textus/hooks/) — six worked hooks across four event types
