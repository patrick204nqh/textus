# ADR 0023 — Uniform use-case shape

**Date:** 2026-05-29
**Status:** Accepted
**Refines:** [ADR 0022](./0022-container-call-dispatcher.md)

## Context

[ADR 0022](./0022-container-call-dispatcher.md) (0.27.0) collapsed the application
layer into `Container` + `Call` + `Dispatcher` + plain use-case classes. It
landed the big moves but left four seams behind:

1. **The `Context → Call` rename was half-done.** `Application::Context`
   became `Textus::Call` and use cases stored `@call`, but five files still
   spoke the old name: `AuthorityGate` read `@ctx.role` (forcing `Accept` and
   `Reject` to carry a redundant `@ctx = call # AuthorityGate uses @ctx.role`
   alias), and `Envelope::IO::Writer` / `RefreshOrchestrator` took a `ctx:`
   constructor kwarg that actually received a `Call`.

2. **The "uniform `(container:, call:)`" shape was faked.** 18 use cases took
   a third `hook_context:` kwarg; ~17 of them declared it and never used it,
   carrying `# rubocop:disable Lint/UnusedMethodArgument` to silence the
   linter. `RoleScope` — and `Doctor::Check` — then used runtime reflection
   (`klass.instance_method(:initialize).parameters`) to decide whether to
   inject it. So the shape was neither uniform nor minimal: constructors
   declared params they ignored, and the dispatcher branched on them.

3. **`ARCHITECTURE.md` lied.** It advertised a uniform `(container:, call:)`
   use-case shape — which the `hook_context:` third kwarg contradicted.

4. **Two behavioural methods carried `Metrics/ParameterLists` disables.**
   `Read::Audit#call` (8 keyword filters) and `Builder::Pipeline.run`
   (8 collaborators) had ballooned into parameter bags.

The smell is the usual one: a large rename shipped at the structural level but
left a trail of stragglers, dead params, and compensating reflection.

## Decision

1. **Finish the rename.** `@ctx` / `ctx:` → `@call` / `call:` everywhere it
   carries a `Call`. The only surviving `ctx:` is the **event-payload key** on
   `events.publish(:event, ctx: <Hooks::Context>, ...)` — that is the
   `EventBus` API and names a `Hooks::Context`, not a `Call`.

2. **Derive `hook_context` from `(container, call)`.** A `Hooks::Context` only
   needs a `RoleScope`, and a `RoleScope` is fully determined by
   `(container, call.role, call.correlation_id, call.dry_run)`. A new factory
   `Textus::Hooks::Context.for(container:, call:)` centralises that
   construction; use cases that emit events build their context lazily through
   it. The `hook_context:` constructor kwarg is removed from every use case.

3. **Make dispatch unconditional.** With no use case declaring `hook_context:`,
   the reflection in `RoleScope` and `Doctor::Check` is dead. Both now do a
   plain `klass.new(container:, call:).call(...)`. The constructor shape is
   genuinely uniform — and `ARCHITECTURE.md` is now true.

   `RefreshOrchestrator` is the one exception: it is a *collaborator*, not a
   `Dispatcher` verb, so it is constructed directly by `RefreshWorker` /
   `GetOrRefresh`, which pass their derived `hook_context` in. It keeps an
   explicit `hook_context:` kwarg, with a comment explaining the asymmetry.

4. **Refactor the two parameter-bag methods to value objects.**
   `Read::Audit#call(**filters)` builds a `Read::Audit::Query` value object
   (which also owns the manifest-independent row predicate `#matches?`);
   `Builder::Pipeline.run(mentry:, deps:)` takes a `Builder::Pipeline::Deps`
   record. Both behavioural methods drop their `Metrics/ParameterLists`
   disable.

5. **Keep `Metrics/ParameterLists: Max 6` as the documented honest ceiling.**
   Value-object constructors/factories (`Envelope.build`, `Manifest::Entry`,
   `Error`, `Freshness.build`, `Audit::Query.build`), the structured
   `AuditLog#append` row, and the public
   `put(key, meta:, body:, content:, if_etag:)` API legitimately reach up to
   six. Lowering to 4 surfaced 17 offenses, ~14 of which would need narrow
   `rubocop:disable` exemptions — enforcement theatre. `Max 6` documents the
   real ceiling; the only methods that *exceeded* it (`Audit`, `Pipeline`)
   were refactored.

## Consequences

**Breaking — Ruby API only.** Use-case constructors no longer accept
`hook_context:`. `Envelope::IO::Writer` and `RefreshOrchestrator` take `call:`,
not `ctx:`. `Read::Audit#call` takes filters and builds a `Query` internally
(keyword callers unchanged). `Builder::Pipeline.run` takes a `Deps` record.
The `CLI::VERBS` const-missing shim and the `Manifest::Entry::PUBLISH_EACH_*`
re-exports (≥0.26 back-compat) are removed.

**Wire format unchanged.** Protocol stays `textus/3`. CLI verb signatures
unchanged. Hook callable surfaces unchanged — pub-sub hooks still receive
`ctx: <Hooks::Context>`, RPC hooks still receive `caps: <Container>`.

**Net cleanup.** The `hook_context:` param is gone from ~28 constructors; the
reflection block is gone from two dispatch sites; `Lint/UnusedMethodArgument`
disables drop from 27 to 20; two `Metrics/ParameterLists` (and two complexity)
disables are removed by the value-object refactors.

## Alternatives considered

**Per-class `scope`/`hook_context` helper duplicated across 11 use cases.**
Rejected: 11 copies of the same two-method helper is worse than one
`Hooks::Context.for` factory.

**Always inject `hook_context` (truly uniform, even for non-emitters).**
Rejected: it is derivable, so injecting it is dead weight for the use cases
that never emit.

**`Metrics/ParameterLists: Max 4` with narrow disables.** Rejected: it
flags 17 methods, ~14 of which are legitimate value-object / port / public-API
signatures. Setting a limit and then exempting everyone is worse than an
honest `Max 6`.
