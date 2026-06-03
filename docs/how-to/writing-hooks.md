# Writing hooks

> **How-to** · for hook authors · **read when** you want to define, wire, and test Ruby hooks
> **SSoT for** the hook-authoring procedure (definition surface, fan-out, testing, common patterns) · **reviewed** 2026-06 (v0.39)

How to extend textus with Ruby hooks: the definition surface, the `ctx:` handle, fan-out with `keys:` globs, testing, and common patterns.

For the event catalog, per-verb lifecycle timelines, and `ctx:` payload fields, see [`../reference/events.md`](../reference/events.md). For the normative event table, see [`../../SPEC.md` §5.10](../../SPEC.md#510-hooks).

## Table of contents

1. [The definition surface](#the-definition-surface)
2. [The `ctx:` handle](#the-ctx-handle)
3. [Fan-out and `keys:` globs](#fan-out-and-keys-globs)
4. [Testing hooks](#testing-hooks)
5. [Common patterns](#common-patterns)

---

## The definition surface

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

## The `ctx:` handle

Every pubsub event receives `ctx:` (a `Textus::Hooks::Context`) instead of the raw store. Use it to read entries (`ctx.get(key)`, `ctx.list(...)`, `ctx.deps(key)`), write entries (`ctx.put(key, body: ...)`, `ctx.delete(key)`), append custom audit rows (`ctx.audit("my_verb", key: key, etag_before: nil, etag_after: nil)`), or fan out follow-up events (`ctx.publish_followup(:entry_put, key: key, envelope: env)`). The `ctx.role` and `ctx.correlation_id` accessors expose the originating request context.

All writes via `ctx` route through the use-case dispatch (`store.as(role)` → `RoleScope` → `Dispatcher`) so authorization, schema validation, and audit logging always fire — there are no bypass paths.

RPC events (`:resolve_intake`, `:transform_rows`, `:validate`) are gem-internal and receive `caps:` instead of `ctx:` — a `Textus::Container` record (the wired ports + manifest). A block that declares legacy `store:` but not `caps:` is rejected at registration time: the required `caps:` kwarg comes back missing from the signature check.

If you don't need `ctx:`, absorb it with `**`:

```ruby
Textus.hook do |reg|
  reg.on(:transform_rows, :claude_root) do |rows:, **|   # ctx: absorbed by **
    ...
  end
end
```

---

## Fan-out and `keys:` globs

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

## Testing hooks

Hooks register against two per-store objects: a `Hooks::EventBus` (pub-sub) and a `Hooks::RpcRegistry` (RPC). In tests, instantiate whichever you need and register directly — no thread-local, no global state.

For an RPC hook, register on an `RpcRegistry` and call `invoke` (which injects `caps:` only if the block declares it):

```ruby
RSpec.describe "my notion hook" do
  let(:rpc) { Textus::Hooks::RpcRegistry.new }

  it "registers under :notion" do
    rpc.register(:resolve_intake, :notion) { |args:, **| { _meta: {}, body: "stub" } }
    expect(rpc.names(:resolve_intake)).to include(:notion)
  end

  it "returns the expected shape" do
    rpc.register(:resolve_intake, :notion) do |args:, **|
      { _meta: { "fetched_at" => "now" }, body: "hello" }
    end
    result = rpc.invoke(:resolve_intake, :notion, caps: nil, config: {}, args: {})
    expect(result[:body]).to eq("hello")
  end
end
```

For a pub-sub hook, register on an `EventBus` and `publish`:

```ruby
let(:bus) { Textus::Hooks::EventBus.new }

it "fires only on a matching key" do
  fired = []
  bus.on(:entry_put, :listener, keys: ["working.*"]) { |key:, **| fired << key }

  bus.publish(:entry_put, ctx: nil, key: "working.x", envelope: {})
  bus.publish(:entry_put, ctx: nil, key: "other.y",   envelope: {})

  expect(fired).to eq(["working.x"])
end
```

`publish` returns a `FireReport` listing the `fired` / `errored` / `timed_out` handler names. To exercise the loader end-to-end (drains `Textus.hook` blocks against your bus + rpc), point `Hooks::Loader.new(events: bus, rpc: rpc).load_dir(path)` at a fixture directory whose files declare `Textus.hook { |reg| reg.on(...) { ... } }`.

See `spec/hooks/event_bus_spec.rb` and `spec/hooks/rpc_registry_spec.rb` for the canonical patterns.

---

## Common patterns

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

### Connection marker — log each MCP session as it opens

`:session_opened` fires once per MCP connection at `initialize`, carrying the connection's resolved `role:` and boot `cursor:` (ADR 0075). Unlike `:store_loaded` (once per process, default role), it observes a client attaching.

```ruby
Textus.hook do |reg|
  # fires once per MCP connection at initialize, with the resolved role
  reg.on(:session_opened, :log_connection) do |role:, cursor:, **|
    # e.g. append a connection marker to a workspace log
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

- [`../reference/events.md`](../reference/events.md) — the event catalog, lifecycle timelines, and `ctx:` fields
- [`./configuring-zones.md`](configuring-zones.md) — the manifest side: declaring which entries trigger which hooks
- [`../../SPEC.md` §5.4, §5.10](../../SPEC.md#510-hooks) — the normative `:resolve_intake` and event contracts
- [`../architecture/README.md`](../architecture/README.md) — how `Hooks::EventBus` and `Hooks::RpcRegistry` are implemented
- [`../../examples/project/.textus/hooks/`](../../examples/project/.textus/hooks/) — a worked `:transform_rows` hook that reshapes projection rows for a template
