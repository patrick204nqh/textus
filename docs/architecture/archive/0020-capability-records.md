# ADR 0020 — Replace Ports with ReadCaps, WriteCaps, HookCaps

**Date:** 2026-05-28
**Status:** Accepted
**Depends on:** [ADR 0016](./0016-application-ports-value.md), [ADR 0018](./0018-manifest-carving.md), [ADR 0019](./0019-hooks-bus-split.md)

## Context

ADR 0016 introduced `Application::Ports` to bundle collaborators and replace
the `store:` leak. This was a correct step, but it went halfway. `Ports` today
carries seven fields:

```ruby
Ports = Data.define(
  :manifest, :file_store, :schemas, :audit_log,
  :event_bus, :rpc_registry, :root
)
```

The problem: use cases don't all need all seven.

- **Read use cases** (`Reads::Get`, `Doctor::Check::*`) need `manifest`,
  `file_store`, `schemas` to read and validate. They don't need `audit_log`,
  `event_bus`, or `rpc_registry`.
- **Write use cases** (`Writes::Put`, `Writes::Delete`, `Writes::Move`) need
  the full set: `manifest`, `file_store`, `schemas`, `audit_log`, `event_bus`,
  and `rpc_registry` (for hook invocation).
- **Hook callables** registered via the RPC contract (`transform_rows`,
  `validate`, `resolve_intake`) only need `event_bus` (for publishing events)
  and `rpc_registry` (for calling other hooks).

This is a contract smell. Each use case should declare exactly what it needs,
not accept a god object and hope callers understand which fields are used.
Additionally, passing `audit_log` to a read operation or `event_bus` to a
read-only transform is misleading — it suggests these reads can trigger
side effects, which they cannot.

## Decision

Replace `Ports` with three capability records, each built once at `Store` boot
and reused:

### ReadCaps — for read-only operations

```ruby
class Application::ReadCaps
  attr_reader :manifest, :file_store, :schemas

  def initialize(manifest:, file_store:, schemas:)
    @manifest   = manifest
    @file_store = file_store
    @schemas    = schemas
  end
end
```

Used by: `Reads::Get`, `Doctor::Check::*`, `Pulse::Ledger`, read-only
transforms (`transform_rows`), and any operation that inspects state without
modifying it.

### WriteCaps — for write operations

```ruby
class Application::WriteCaps
  attr_reader :manifest, :file_store, :schemas, :audit_log, :events, :authorizer

  def initialize(manifest:, file_store:, schemas:, audit_log:, events:, authorizer:)
    @manifest    = manifest
    @file_store  = file_store
    @schemas     = schemas
    @audit_log   = audit_log
    @events      = events
    @authorizer  = authorizer
  end
end
```

Used by: `Writes::Put`, `Writes::Delete`, `Writes::Move`, `Writes::Refresh`,
and any operation that modifies state or publishes events.

Note: `authorizer` is added here because authorization checks guard writes.
`Authorizer` is an adapter that reads `manifest.policy`, so it belongs in
the write capabilities.

### HookCaps — for hook callables

```ruby
class Application::HookCaps
  attr_reader :events, :rpc

  def initialize(events:, rpc:)
    @events = events
    @rpc    = rpc
  end
end
```

Used by: hook callables registered via `Textus.hook :transform_rows do |caps:|`
or the RPC contract. Allows hooks to publish events and call other hooks.

### Construction at Store boot

```ruby
# In Store#initialize or a boot factory:
read_caps = Application::ReadCaps.new(
  manifest:   @manifest,
  file_store: @file_store,
  schemas:    @schemas
)

write_caps = Application::WriteCaps.new(
  manifest:    @manifest,
  file_store:  @file_store,
  schemas:     @schemas,
  audit_log:   @audit_log,
  events:      @events,
  authorizer:  @authorizer
)

hook_caps = Application::HookCaps.new(
  events: @events,
  rpc:    @rpc
)
```

Once built, these three objects are immutable and reused for every request.

### Use-case constructors narrow

Before (ADR 0016):

```ruby
class Application::Writes::Put
  def initialize(ctx:, ports:, envelope_io:, authorizer:, hook_context:)
    @manifest  = ports.manifest
    @file_store = ports.file_store
    @audit_log = ports.audit_log
    @event_bus = ports.event_bus
  end
end

class Application::Reads::Get
  def initialize(ctx:, ports:, envelope_io:)
    @manifest  = ports.manifest
    @file_store = ports.file_store
  end
end
```

After (this ADR):

```ruby
class Application::Writes::Put
  def initialize(ctx:, caps:, envelope_io:, hook_context:)
    @manifest  = caps.manifest
    @file_store = caps.file_store
    @audit_log = caps.audit_log
    @events    = caps.events
  end
end

class Application::Reads::Get
  def initialize(ctx:, caps:, envelope_io:)
    @manifest  = caps.manifest
    @file_store = caps.file_store
  end
end
```

The constructor signature now declares the operation's power level — `ReadCaps`
vs. `WriteCaps` — at a glance.

### Operations / Session plumbing

The current `Operations.for(store, role:)` wiring method simplifies:

Before:

```ruby
def self.for(store, role: Role::DEFAULT, correlation_id: nil, dry_run: false)
  ports = Application::Ports.from_store(store)
  ctx   = Application::Context.build(role: role, correlation_id: correlation_id, dry_run: dry_run)
  new(ctx: ctx, ports: ports)
end
```

After (ADR 0021 also renames `Operations` to `Session`):

```ruby
def self.session(role: Role::DEFAULT, correlation_id: nil, dry_run: false)
  ctx = Application::Context.build(role: role, correlation_id: correlation_id, dry_run: dry_run)
  new(ctx: ctx, read_caps: @read_caps, write_caps: @write_caps, hook_caps: @hook_caps)
end
```

Each use-case factory method in `Session` passes the appropriate capability:

```ruby
def put(key:, rows:, dry_run: false)
  Application::Writes::Put.new(
    ctx: @ctx,
    caps: @write_caps,
    envelope_io: envelope_io,
    hook_context: hook_context
  ).call(key: key, rows: rows, dry_run: dry_run)
end

def get(key:)
  Application::Reads::Get.new(
    ctx: @ctx,
    caps: @read_caps,
    envelope_io: envelope_io
  ).call(key: key)
end
```

## Consequences

**Positive**

- Every use-case constructor declares its power level. Readers always get
  `ReadCaps`; writers always get `WriteCaps`. There is no ambiguity.
- Hook callables are freed from `audit_log`, `file_store`, `schemas` they
  don't need. The contract is minimal.
- Tests can construct narrow capability objects for unit testing. A test of
  `Reads::Get` no longer needs to mock an `audit_log` or `authorizer`.
- Alternative backends (e.g., a memory store or external API) can implement
  the three interfaces and plug in. No single wide `Ports` gate-keeps access.
- Collapses all `Operations` factory method plumbing. Instead of six separate
  methods (`put`, `delete`, `move`, etc.), each with hand-wired capability
  passing, the generation is systematic (ADR 0021).

**Negative**

- Every use-case constructor signature changes. A single find-and-replace
  won't work; each class needs deliberate audit.
- Tests that mock or spy on `Ports` must update to mock `ReadCaps` /
  `WriteCaps` / `HookCaps` respectively.
- The three classes must be constructed and held by `Store` / `Session`.
  One more composition concern.

**Neutral**

- No wire-format change. Protocol remains `textus/3`.
- Gem version bumps; landing in 0.26.0.

## Alternatives considered

**Keep Ports, add private `#read_slice` / `#write_slice` methods.** Doesn't
express the intent in the type. A constructor that accepts `ports:` and calls
`ports.read_slice` is no clearer than today.

**Use role-based access control within Ports.** `ports.manifest(role:
:read)` — too clever. The three records are simpler and align with how the
rest of the codebase carves responsibilities.

**Build capabilities per-request instead of once at boot.** Adds allocation
pressure and makes caching harder. These are immutable values that don't
change for the lifetime of the store.
