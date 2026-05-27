# ADR 0014 — Explicit Dependencies

**Date:** 2026-05-27
**Status:** Accepted
**Depends on:** ADR 0011 (authorize-bang-in-context), ADR 0013 (port extraction)

## Context

ADR 0013 extracted the I/O port (`Infra::Storage::FileStore`) and lifted the
write pipeline into `Application::Writes::EnvelopeIO`. What remained was a
service-locator-shaped `Application::Context` that every use case received,
exposing `store`, `manifest`, `schemas`, `file_store`, `audit_log`, `bus`,
plus authorization methods. Each use case could reach for anything; their
constructors did not declare their real dependencies.

Three problems followed:

1. **Layering names did not tell the full truth.** Use cases ostensibly
   took "a Context"; in practice they took "the whole store."
2. **Operations was bound to Store.** Embedders who wanted to use the
   library against a non-file backend had no constructor that took ports
   directly.
3. **Side seams.** `Mv` reached past `EnvelopeIO` and used `Put` with a
   `suppress_events:` flag as a UID-injection helper. `Builder::Pipeline`
   re-entered `Operations.for(store)` from inside a use case. CLI verbs
   constructed `Application::Context.new(store:, role:)` directly. Each
   was the same root cause: dependencies were not explicit.

## Decision

A Context is a request value (`role`, `correlation_id`, `now`, `dry_run`)
and nothing else. Use cases declare their real ports in their
constructor. `Operations.new(...)` takes those ports directly;
`Operations.for(store, role:)` remains as a convenience that pulls them
off `Store`.

`Domain::Authorizer` becomes the single home for the authorization rule.
`EnvelopeIO` gains a `#move(...)` method so `Mv` no longer bypasses it.
`Builder::Pipeline` takes reader/lister callables from the caller; the
re-entry into `Operations.for(store)` from `Writes::Build` is gone.
Policy predicates that read live envelopes move to `Application::Policy`.

Hooks/intakes/transforms receive the actual `Store` (composition root)
as `store:`, not a Context wrapper. Event payloads carry `role:`
directly so hook authors can observe the actor without reaching for
`store.role`.

## Consequences

**Public Ruby API breaks** for embedders that:

- Constructed `Application::Context.new(store:, role:)` — replace with
  `Operations.for(store, role:)` (the common case) or
  `Application::Context.build(role:)` (when testing pure call state).
- Reached through `ctx.store.manifest` etc. — go directly to the
  relevant port or use `Operations`.
- Used `Put#call`'s `suppress_events:` kwarg — removed; the only
  internal caller (`Mv`) now uses `EnvelopeIO#move` directly.
- Read `store.role` inside a hook — `store:` is now a `Textus::Store`,
  which has no `.role`. Hooks should read `role:` from the event
  payload instead (all write/refresh events now carry it).

**CLI behavior is unchanged.** Wire format `textus/3` is unchanged.
Audit-log NDJSON shape is unchanged. Stores written by 0.18.x
round-trip through 0.19.0 byte-for-byte.

**Non-file storage backends are now practical.** `Operations.new(...)`
accepts an arbitrary `FileStore`-compatible port; no `Store` handle is
strictly required (a Store-like object that exposes the read surface
suffices for hook payloads).

**Layer purity.** `Domain::*` is value-and-rule vocabulary. `Application::*`
is request coordination (now includes Policy::Evaluator). `Infra::*` is
I/O. `Store` is a composition root. Each box owns what its name implies.

## Out of scope

- **Non-file backends.** Enabled by this ADR; no concrete backend ships
  in 0.19.0.
- **`Operations` registry pattern.** Considered and rejected — inline
  factories are clearer than a `USE_CASES` dispatch table at this size.
- **Sub-typing `Envelope#meta`.** ADR 0007 typed the envelope; further
  refinement waits for a real need.
- **CLI verbs reaching into `store.manifest`/`store.registry` for
  introspection.** Two CLI verbs (`hook run`, `put --fetch`) still
  invoke `store.registry.rpc_callable(...)` directly. A future task
  introduces `Operations#run_intake` and similar projections so CLI
  verbs stop touching ports.

## Alternatives considered

- **Pass `Context` everywhere, expand its interface.** Rejected: that
  is the service-locator shape we are leaving.
- **Eliminate `Context` entirely; pass `role` as a bare argument.**
  Rejected: `correlation_id`, `now`, and `dry_run?` cluster around the
  request and want to travel together.
- **Keep `Operations.for(store, ...)` as the only constructor.**
  Rejected: ADR 0013 explicitly named non-file backends as the next
  motivation. `Operations.new(...)` delivers on that.
- **Per-use-case registry via `define_method`.** Rejected as too clever
  for the savings. Inline factories make the wiring legible at the
  point of dispatch.
