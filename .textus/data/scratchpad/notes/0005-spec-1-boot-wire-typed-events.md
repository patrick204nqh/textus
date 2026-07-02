---
title: 'Spec 1: Boot.wire + Typed Events'
uid: 51c10f29fafadb4a
---
# Spec 1: Boot.wire + Typed Events

**Date:** 2026-06-30  
**Status:** Approved  
**Scope:** Eliminate `Store::Container` as a class; introduce `Boot.wire`, pure handler modules, session-scoped `Event::Bus`, and typed lifecycle events.

---

## Problem

`Store::Container` is a coupling sink: it knows every handler, owns the two-phase `wire!` initialization, and must be edited whenever a handler changes or a new verb is added. Event emission from handlers (currently implicit side-effects deep in writers and middleware) is untraceable and unsubscribable from outside the pipeline.

---

## Goals

- Container disappears as a class. No callers touch it.
- Adding a handler means creating one file. No registration list to edit.
- Lifecycle events are typed `Data.define` structs emitted to a session-scoped bus.
- External observers (metrics, logging, future webhooks) subscribe to the bus with the same interface as internal ones (Cascade).
- Tests get a clean `Boot.wire`-based setup with no global state to reset.

---

## Architecture

### 1. `Ctx` — frozen boot-time dependency bundle

Replaces `Container`. Built once in `Boot.wire`, frozen, held by `Store`.

```ruby
Textus::Store::Ctx = Data.define(
  :manifest,        # Manifest
  :file_store,      # Port::Storage::FileStore
  :schemas,         # Schema::Registry
  :audit_log,       # Port::AuditLog
  :job_store,       # Port::Store
  :layout,          # Store::Layout
  :link_edge_store, # Links::LinkEdgeStore
  :workflows,       # Workflow::Registry
  :event_bus,       # Event::Bus (session-scoped)
  :pipeline,        # Dispatch::Pipeline
)
```

`Store` holds `@ctx` instead of `@container`. All existing `container.manifest`, `container.file_store` delegation patterns survive — they now delegate to `@ctx`. `Container` class is deleted. `Dispatch::Assembler` is deleted (replaced by `HandlerResolver`).

### 2. Pure handler modules

Every handler becomes a module with two constants and one class method. No `include`, no `initialize`, no instance state.

```ruby
module Textus::Handlers::Write::PutEntry
  HANDLES = Dispatch::Contracts::PutEntry
  NEEDS   = %i[manifest file_store schemas audit_log layout event_bus].freeze

  def self.call(command, call, deps)
    # command: the typed contract struct
    # call:    Value::Call (role, correlation_id, dry_run, now)
    # deps:    frozen struct sliced from Ctx by HandlerResolver at boot
    #
    # ... write logic via WriteStep::DEFAULT_PUT ...
    #
    deps.event_bus.emit(Event::EntryWritten.new(
      key:         command.key,
      role:        call.role,
      etag_before: etag_before,
      etag_after:  envelope.etag,
      occurred_at: call.now,
    ))
    Value::Result.success(envelope)
  end
end
```

Handlers never see `Ctx` directly — only the fields they declared in `NEEDS`.

### 3. `HandlerResolver`

Discovers handlers by naming convention. Called once in `Boot.wire`. Replaces `Dispatch::Assembler`.

```ruby
module Textus::Dispatch::HandlerResolver
  def self.build(ctx)
    # Walks Handlers::Read::*, Handlers::Write::*, Handlers::Maintenance::*
    # For each module defining HANDLES + NEEDS:
    #   1. Slices ctx fields matching NEEDS (raises Boot::DepNotFound if missing)
    #   2. Builds a frozen DepStruct from sliced fields
    #   3. Registers: contract_class → ->(command, call) { mod.call(command, call, deps) }
    registry = HandlerRegistry.new
    each_handler_module do |mod|
      deps = build_deps(mod::NEEDS, ctx)
      registry.register(mod::HANDLES, ->(command, call) { mod.call(command, call, deps) })
    end
    registry
  end

  def self.eager_load!
    # Requires all handler files before boot so HANDLES/NEEDS are defined
    Dir[File.expand_path("../../handlers/**/*.rb", __FILE__)].sort.each { |f| require f }
  end
end
```

`eager_load!` is called at the start of `Boot.wire`. A missing `NEEDS` field raises `Boot::DepNotFound` at boot — not at first dispatch. A conformance spec asserts that every contract in `VerbRegistry` has a registered handler (same role as the existing `assembler_spec.rb`).

### 4. `Event::Bus` — session-scoped

```ruby
class Textus::Event::Bus
  def initialize
    @subscribers = Hash.new { |h, k| h[k] = [] }
  end

  def subscribe(event_class, &block)
    @subscribers[event_class] << block
    self
  end

  def emit(event)
    @subscribers[event.class].each { |sub| sub.call(event) }
  end
end
```

One `Event::Bus` per `Boot.wire` call — one per `Store` session. `emit` is synchronous. Subscriber errors propagate to the emitting handler. Two concurrent `Store` instances have independent buses.

### 5. Typed events

```ruby
module Textus::Event
  EntryWritten     = Data.define(:key, :role, :etag_before, :etag_after, :occurred_at)
  EntryDeleted     = Data.define(:key, :role, :etag_before, :occurred_at)
  EntryMoved       = Data.define(:from_key, :to_key, :role, :etag_before, :etag_after, :occurred_at)
  ProposalOpened   = Data.define(:key, :proposal_key, :role, :occurred_at)
  ProposalAccepted = Data.define(:proposal_key, :target_key, :role, :occurred_at)
  ProposalRejected = Data.define(:proposal_key, :role, :occurred_at)
end
```

Write handlers emit exactly one event. Read handlers emit nothing. `occurred_at` comes from `Value::Call#now` — observers never call `Time.now` themselves.

### 6. `Boot.wire`

Flat, linear, no two-phase dance. Replaces `Store#build_container`.

```ruby
module Textus::Boot
  def self.wire(root)
    HandlerResolver.eager_load!

    manifest        = Manifest.load(root)
    layout          = Store::Layout.new(root)
    file_store      = Port::Storage::FileStore.new
    schemas         = Schema::Registry.new(layout.schemas_dir)
    audit_log       = Port::AuditLog.new(layout:, **manifest.data.audit_config)
    job_store       = Port::Store.new(root:).setup!
    link_edge_store = Links::LinkEdgeStore.new
    workflows       = Workflow::Loader.load_all(root)
    event_bus       = Event::Bus.new

    # Wire cascade subscriber
    cascade = Produce::CascadeSubscriber.new(manifest:, workflows:, job_store:, file_store:)
    event_bus.subscribe(Event::EntryWritten,     &cascade.method(:on_entry_written))
    event_bus.subscribe(Event::EntryDeleted,     &cascade.method(:on_entry_deleted))
    event_bus.subscribe(Event::EntryMoved,       &cascade.method(:on_entry_moved))
    event_bus.subscribe(Event::ProposalAccepted, &cascade.method(:on_proposal_accepted))

    ctx_seed = Store::Ctx.new(
      manifest:, file_store:, schemas:, audit_log:, job_store:,
      layout:, link_edge_store:, workflows:, event_bus:, pipeline: nil
    )

    registry   = HandlerResolver.build(ctx_seed)
    middleware = [
      Dispatch::Middleware::Binder.new,
      Dispatch::Middleware::Auth.new,
      Dispatch::Middleware::AuditIndex.new(job_store: ctx_seed.job_store, audit_log: ctx_seed.audit_log),
    ]
    pipeline   = Dispatch::Pipeline.new(registry:, container: ctx_seed, middleware:)

    ctx_seed.with(pipeline:).freeze
  end
end
```

`ctx_seed.with(pipeline:).freeze` produces the final `Ctx` in one step. The `wire!` two-phase dance is gone.

### 7. Cascade middleware → `CascadeSubscriber`

The trigger logic from `Dispatch::Middleware::Cascade` moves to `Produce::CascadeSubscriber` — a plain object subscribing to specific event classes. `Cascade` middleware is deleted. `CascadeSubscriber` receives events and enqueues materialize/sweep jobs on the job store.

---

## Data Flow

```
store.entry(:put, key:, body:)
  → Store#_dispatch_in_domain
    → pipeline.dispatch(contract, call)
      → Binder → Auth → AuditIndex → handler dispatch
        → Handlers::Write::PutEntry.call(command, call, deps)
          → WriteStep::DEFAULT_PUT.reduce(ctx)
          → deps.event_bus.emit(Event::EntryWritten.new(...))
          → Value::Result.success(envelope)
      ← result returned up through middleware
    ← result extracted by Store
  ← envelope returned to caller

(async, same thread)
  Produce::CascadeSubscriber#on_entry_written
    → enqueues materialize jobs for dependents on job_store
```

---

## Files

### New
- `lib/textus/store/ctx.rb` — `Store::Ctx = Data.define(...)`
- `lib/textus/event.rb` — typed event structs
- `lib/textus/event/bus.rb` — `Event::Bus`
- `lib/textus/dispatch/handler_resolver.rb` — replaces Assembler
- `lib/textus/produce/cascade_subscriber.rb` — extracted from Cascade middleware

### Modified
- `lib/textus/store.rb` — `build_container` → `Boot.wire`; `@container` → `@ctx`
- `lib/textus/boot.rb` — `Boot.wire` added (file exists, new method)

### Deleted
- `lib/textus/store/container.rb`
- `lib/textus/dispatch/assembler.rb`
- `lib/textus/dispatch/middleware/cascade.rb`

### Converted (29 handler files)
- `lib/textus/handlers/**/*.rb` — all converted to pure modules with HANDLES/NEEDS

### Tests
- `spec/unit/store/ctx_spec.rb`
- `spec/unit/event/bus_spec.rb`
- `spec/unit/dispatch/handler_resolver_spec.rb` (completeness + NEEDS satisfaction)
- `spec/unit/produce/cascade_subscriber_spec.rb`
- `spec/integration/boot_spec.rb` — `Boot.wire` builds a valid frozen Ctx

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| `NEEDS` field missing from Ctx at boot | `Boot::DepNotFound` raised in `HandlerResolver.build` — fails before first request |
| No handler for a contract | `Dispatch::UnknownHandler` raised at dispatch time (unchanged) |
| Subscriber error during `emit` | Propagates to the emitting handler — callers wrap in rescue if fire-and-forget needed |
| `HandlerResolver.eager_load!` missing a file | Conformance spec catches it — missing handler → missing contract registration |

---

## Testing Strategy

- `Boot.wire` is the integration boundary: one spec with a minimal fixture manifest; asserts `Ctx` is fully populated and pipeline responds to every registered contract.
- Each handler module tested with a synthetic `command` + `call` + minimal `deps` — no Store, no Boot.
- `Event::Bus`: subscribe, emit, multiple subscribers, two independent bus instances don't cross-contaminate.
- `CascadeSubscriber`: fake `job_store` — event → job enqueue, no full pipeline needed.
- Conformance spec: every contract in `VerbRegistry::VERB_TO_CONTRACT` has a handler registered by `HandlerResolver`.
