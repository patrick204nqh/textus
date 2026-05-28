# ADR 0016 — Application Ports value object

**Date:** 2026-05-28
**Status:** Proposed
**Depends on:** [ADR 0010](./0010-flat-operations-api.md), [ADR 0013](./0013-port-extraction-store-as-root.md), [ADR 0014](./0014-explicit-dependencies.md)

## Context

ADR 0013 reshaped `Store` into a composition root and ADR 0014 made
use-case dependencies explicit constructor kwargs. Both were the
right move, but the cleanup stopped one step short: **`Operations`
and several application use-cases still take a `store:` kwarg.**

Concretely (post-0.25.0):

- `Operations.for(store, …)` accepts a whole `Store` and immediately
  destructures six fields off it (`manifest`, `file_store`,
  `schemas`, `audit_log`, `bus`, `root`) plus retains `store:` itself
  to forward into a handful of downstream callers.
- `Application::Refresh::Worker`, `Application::Refresh::All`,
  `Application::Writes::Publish`, and all of
  `Application::Restructure::*` declare `store:` as a constructor
  kwarg.
- The hook RPC contract (`projection.rb`, `validate`) passes
  `store:` as a keyword to user-supplied callables — the public name
  on the wire is `store`.

This is a leak. The application layer is supposed to depend on a
narrow set of ports, not on the composition root itself. Three
concrete costs today:

1. **Construction noise.** Every use-case repeats the same six-kwarg
   block. `Operations` has one wiring method per use case purely to
   re-assemble the same struct of dependencies (operations.rb:55–95).
2. **Ambiguous contract.** `store:` could be any subset of the store.
   Reading the constructor tells the caller nothing; reading the body
   is required to know that, e.g., `Refresh::Worker` only ever uses
   `@store` to forward into a hook callable, not to do work itself.
3. **Backend swap is still gated.** ADR 0013 narrowed the I/O port
   to `FileStore`, but the rest of the layer is still coupled to
   `Store`, the file-system composition root. A SQLite or S3 store
   that wanted to skip `Manifest.load` and synthesise its own
   `manifest_data` cannot, because every use case demands the whole
   `Store` shape.

## Decision

Introduce a single **`Textus::Application::Ports`** value object that
bundles every collaborator a use case can need. `Store` builds one at
boot; `Operations` carries it and forwards it into use cases.
Use-case constructors take `ports:` and pull the slice they need.

```ruby
module Textus
  module Application
    Ports = Data.define(
      :manifest, :file_store, :schemas, :audit_log,
      :event_bus, :rpc_registry, :root
    ) do
      def self.from_store(store)
        new(
          manifest:     store.manifest,
          file_store:   store.file_store,
          schemas:      store.schemas,
          audit_log:    store.audit_log,
          event_bus:    store.bus,
          rpc_registry: store.bus,   # same object until ADR 0019 splits it
          root:         store.root,
        )
      end
    end
  end
end
```

### Use-case shape

Before:

```ruby
class Application::Writes::Put
  def initialize(ctx:, manifest:, envelope_io:, bus:, authorizer:, hook_context:)
    …
  end
end
```

After:

```ruby
class Application::Writes::Put
  def initialize(ctx:, ports:, envelope_io:, authorizer:, hook_context:)
    @ctx          = ctx
    @manifest     = ports.manifest
    @bus          = ports.event_bus
    @envelope_io  = envelope_io
    @authorizer   = authorizer
    @hook_context = hook_context
  end
end
```

`envelope_io`, `authorizer`, and `hook_context` remain explicit
parameters because they are **derived** collaborators
(`EnvelopeIO` composes `file_store + manifest + schemas + audit_log`;
`Authorizer` composes `manifest`); construction belongs to
`Operations`, not to `Ports`.

### Hook RPC contract

The current public kwarg name in hook callables is `store:`. ADR 0016
renames it to `ports:` and ships a one-cycle bridge:

```ruby
# 0.25.1 — both names accepted
callable.call(store: ports, ports: ports, rows: rows, …)
```

…with a deprecation warning when `store:` is consumed but not
`ports:`. The bridge is removed in 0.26.0. The protocol wire string
does not change (`textus/3`); hooks are gem-internal contracts.

### `Operations.for` becomes one line of wiring

```ruby
def self.for(store, role: Role::DEFAULT, correlation_id: nil, dry_run: false)
  ports = Application::Ports.from_store(store)
  ctx   = Application::Context.build(role: role, correlation_id: correlation_id, dry_run: dry_run)
  new(ctx: ctx, ports: ports)
end
```

…and per-use-case factory methods read like:

```ruby
def put(...)
  Application::Writes::Put.new(
    ctx: @ctx, ports: @ports, envelope_io: envelope_io,
    authorizer: authorizer, hook_context: hook_context
  ).call(...)
end
```

## Consequences

**Positive**

- Use cases declare *which slice* of the store they depend on by
  reading `ports.X` in the body — no more `store:` smuggling.
- `Operations` shrinks: one wiring helper, not six. Adding a new
  use case becomes "new file + one factory method".
- Alternative backends become drop-in: anything that can synthesise
  a `Ports` value can run the application layer. `Store` is no
  longer the only legal root.
- Sets up ADR 0017 (EnvelopeIO split) and ADR 0018 (Manifest carving)
  — both introduce new ports that get added to the struct without
  touching every use case constructor.

**Negative**

- Hook contract churn. `store:` → `ports:` is a public kwarg rename
  for the hook DSL (`Textus.hook :validate do |store:|`). One-cycle
  bridge keeps existing user hooks working; cleanup is in 0.26.0.
- Tests that constructed application classes directly with `store:
  fake_store` need to pass `ports: Ports.new(...)` instead.

**Neutral**

- No wire-format change. Gem version bumps to `0.25.1`. Protocol
  remains `textus/3`.

## Alternatives considered

**Pass individual collaborators** — what we have today. Honest, but
expands every constructor every time a new collaborator appears
(see ADR 0018, which adds two).

**Resurrect a `Store#methods_missing`-style facade** — gives use
cases `store.manifest` access. Rejected: blurs the boundary ADR
0013 just sharpened.

**Service locator (`Textus.current_store`)** — global state. Rejected
on sight; ADR 0014 went the opposite direction.
