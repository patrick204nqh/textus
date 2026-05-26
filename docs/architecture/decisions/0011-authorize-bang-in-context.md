# ADR 0011 — Authorize-bang in Context

**Date:** 2026-05-27
**Status:** Accepted
**Depends on:** [ADR 0010](./0010-flat-operations-api.md)

## Context

Every write use case under `lib/textus/application/writes/` carried
the same two-line authorization preamble:

```ruby
unless @ctx.can_write?(mentry.zone)
  raise WriteForbidden.new(mentry.key, mentry.zone, writers: ...)
end
```

Seven use cases, seven copies: `Put`, `Delete`, `Mv`, `Accept`,
`Reject`, `Build`, `Publish`. Each constructed the `WriteForbidden`
error with the same details — key, zone, the writers list pulled
from `@ctx.store.manifest.zone_writers(mentry.zone)`. The only place
the pattern diverged was `Mv`, which authorized the *source* zone
but not the *destination* — a real bug the duplicated shape made
easy to miss.

Two further details accreted around the same boundary:

1. Use cases reached for the event bus via `@ctx.store.bus`. Every
   construction site for `Hooks::Dispatcher.new(...)` was wired
   correctly, but six layers of code piercing through `store.bus`
   to publish meant the `Context` was effectively a half-built
   composition object — the things it knew about were "store, role,
   correlation, clock", but it stopped one accessor short.
2. Every write use case took an explicit `bus:` constructor kwarg
   threaded by `Operations`. That double-wiring (bus from
   `Operations`, store from `Context`) meant two construction sites
   could disagree about which bus a use case talked to. Nothing
   guarded that invariant.

## Decision

Add `Application::Context#authorize_write!(mentry)` and
`#authorize_read!(mentry)`. Both resolve the zone's writers/readers
via `store.manifest` and raise the matching `*Forbidden` error when
the bound role lacks permission. They return `nil` on success.

```ruby
class Application::Context
  def authorize_write!(mentry)
    return if can_write?(mentry.zone)
    raise WriteForbidden.new(
      mentry.key, mentry.zone, writers: store.manifest.zone_writers(mentry.zone)
    )
  end

  def authorize_read!(mentry)
    return if can_read?(mentry.zone)
    raise ReadForbidden.new(
      mentry.key, mentry.zone, readers: store.manifest.zone_readers(mentry.zone)
    )
  end

  def bus = store.bus
end
```

`ReadForbidden` is added to `lib/textus/errors.rb`, mirroring
`WriteForbidden` (code `read_forbidden`, exit 1, details: `key`,
`zone`, `readers`).

`#bus` returns `store.bus` — the same object, no proxy. Use cases
that publish events do so through `@ctx.bus`, never
`@ctx.store.bus`. The `bus:` constructor kwarg is removed from every
write use case; they pull the bus from `@ctx.bus` directly.

The predicate API (`#can_write?`, `#can_read?`) is retained for
non-raising callers (`textus doctor` policy checks, the
`policy_explain` use case). The bang variants are the recommended
path for write/read paths where forbidden access is a verb-aborting
condition.

`Application::Writes::Mv` now calls `ctx.authorize_write!` on the
source zone *and* the destination zone — the bug the duplication
was hiding is fixed by virtue of moving authorization into a single
helper that the use case calls twice.

## Consequences

- **Single source of forbidden errors.** Adding a new write use case
  is one line (`@ctx.authorize_write!(mentry)`) instead of six. The
  error shape (code, exit, details) is owned by `Context`.
- **`Mv` correctness.** Source and destination both authorized; the
  prior partial check is gone.
- **`ReadForbidden` parity.** Reads can now raise a typed error
  symmetric with writes. Currently exercised by `policy_explain`
  and a small number of read paths that opt into the bang
  variant; predicate calls still work where preferred.
- **`bus:` kwarg removed from write use case constructors.** A
  one-line drop in `Operations` (use cases construct with just
  `ctx:`). External code that constructed an `Application::Writes::*`
  directly must drop `bus:`.
- **Test ergonomics.** A `Context` test double need only stub
  `authorize_write!` / `authorize_read!` / `bus` — three small
  seams instead of six (`store`, `store.manifest`, `store.bus`,
  `can_write?`, `role`, `correlation_id`).

## Out of scope

- Moving lifecycle audit-row writing (`verb: "put"` / `"delete"` /
  `"rename"`) out of `Store::Writer` and `Writes::Mv`. That's
  deferred to 0.18 port extraction; see ADR 0009 for the
  `AuditSubscriber` shape it will use.
- Granular per-field permissions. Authorization stays zone-scoped.

## Alternatives considered

- **Authorization decorator around use cases.** A `with_auth { ... }`
  wrapper at the `Operations` layer. Rejected: pushes the policy
  decision away from the use case that needs the error message
  details. The bang on `Context` keeps the call site adjacent to
  the `mentry` resolution that feeds it.
- **Add `WriteForbidden.for(ctx, mentry)` factory.** Trims the call
  site but keeps the `unless` block. Rejected: still seven copies
  of the conditional.
- **Make `can_write?` itself raise.** Rejected: `policy_explain` and
  doctor checks legitimately want a predicate. Splitting predicate
  and bang variants is the standard Ruby idiom.
