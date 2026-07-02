# ADR 0009 — AuditSubscriber split from Hooks::Dispatcher

**Date:** 2026-05-26
**Status:** Partially superseded by [ADR 0022](./0022-container-call-dispatcher.md) (`Infra::AuditSubscriber` is now `Ports::AuditSubscriber`; `Application::Writes::Mv` is now `Write::Mv`). The subscriber-split decision stands.
**Depends on:** [ADR 0008](./0008-freshness-and-resolution-types.md)

## Context

`Hooks::Dispatcher` carried a single piece of coupling to the audit
log: when a user-supplied hook subscriber raised, the dispatcher's
`rescue` branch wrote a `verb: "event_error"` row directly via
`@audit_log.append(...)`. Construction required `audit_log:` as a
kwarg.

That coupling blocked two things:

1. The intended hexagonal direction (started by ADRs 0004 and 0005) of
   making the dispatcher a pure pub/sub primitive. With `audit_log:`
   on its constructor, the dispatcher could not be reused outside the
   `Store` composition root without dragging an audit dependency
   along.
2. Tests of dispatcher behavior had to either pass a real
   `Store::AuditLog` (touching the filesystem) or a hand-rolled stub.
   There was no clean seam for "publish events to a bus, and
   separately observe failures."

`Infra::EventBus` already existed as a parallel pub/sub primitive
(used for the registry-backed event surface). It was already pure
pub/sub with no audit coupling. No change to it was needed.

## Decision

Drop the `audit_log:` kwarg from `Hooks::Dispatcher.new`. Extend the
dispatcher with an `on_error(&block)` callback hook. When a user hook
raises and the dispatcher rescues, it invokes registered `on_error`
callbacks with `event:`, `hook:`, `key:`, `kwargs:`, `error:` — enough
information to reconstruct the prior audit row.

Move the audit-row-writing behavior into a new
`Textus::Infra::AuditSubscriber`:

```ruby
module Textus
  module Infra
    class AuditSubscriber
      def initialize(audit_log)
        @audit_log = audit_log
      end

      def attach(bus)
        bus.on_error { |event:, hook:, key:, kwargs:, error:| record_error(...) }
        self
      end

      # ...
    end
  end
end
```

`Store#initialize` constructs the dispatcher without `audit_log:`, then
attaches an `AuditSubscriber` at boot:

```ruby
@bus = Hooks::Dispatcher.new
Textus::Infra::AuditSubscriber.new(audit_log).attach(@bus)
```

The audit NDJSON line written by the subscriber is byte-identical (in
key order, field set, value formatting) to the row the dispatcher used
to write. A spec pins the canonical key ordering and the JSON shape.

## Consequences

- **Public Ruby API breaks.** External code that constructed
  `Hooks::Dispatcher.new(audit_log: x)` directly must drop the kwarg.
  In-tree, only `Store#initialize` did this.
- **Audit NDJSON unchanged.** Byte-identical row written by the
  subscriber. No migration needed for consumers reading `audit.log`.
- **Dispatcher is now reusable** in contexts without an audit log
  (tests, future per-process buses, embedded scenarios).
- **`on_error` is dispatcher-internal**, not a generic event. Hook
  errors do not traverse the key-glob/subscriber routing machinery
  that user-level events use. Errors are not user-routable.

## Out of scope (deferred)

The plan's broader vision was that `AuditSubscriber` would also write
the lifecycle audit rows currently emitted directly by
`Store::Writer` (`verb: "put"` / `"delete"`) and
`Application::Writes::Mv` (`verb: "rename"`). That move requires
event payloads (`:entry_put`, `:entry_deleted`, `:entry_renamed`) to
carry `etag_before` / `etag_after` — which they presently don't —
and touches every write path. It is deferred to the **0.18
port-extraction** phase, where the broader `Store::Writer` decomposition
naturally lifts that data through the new write pipeline. The
`AuditSubscriber` class is shaped to receive additional `attach(bus)`
subscriptions when that work lands.

## Alternatives considered

- **Synthetic `:hook_error` event on the bus.** Rejected: hook errors
  are infrastructure concerns, not domain events. Routing them
  through the key-glob/subscriber-name plumbing meant for `:entry_put`
  et al. invites surprising configuration (a wildcard subscriber
  accidentally catching error events).
- **Keep `audit_log:` as an optional kwarg.** Rejected: optionality
  on a constructor that effectively *must* be wired for production
  use is worse than an explicit, separate attachment step.
