# ADR 0026 — Use-case construction seams (named constructors, one dispatch path, transport-side fetch helper)

**Date:** 2026-05-29
**Status:** Accepted
**Refines:** [ADR 0022](./0022-container-call-dispatcher.md), [ADR 0023](./0023-uniform-use-case-shape.md), [ADR 0025](./0025-boot-doctor-as-verbs-and-etag-via-port.md)

## Context

ADR 0023 made every application use case a plain class on `(container:, call:)`.
That settled the use-case *shape*. It left three construction-side seams where
the same wiring was re-spelled by hand — residue a senior-architect review on
2026-05-29 collected as a closed list:

1. **Identical collaborator wiring copy-pasted across write use cases.**
   `Write::{Put,Delete,Mv,RefreshWorker}` each carried a byte-identical ~15-line
   private `writer` builder (plus a `reader` builder) that reconstructed
   `Envelope::IO::Writer`/`Reader` from `Container` fields. The Writer needs
   nothing the `Container` + `Call` don't already hold, so every copy rebuilt the
   same object graph. ~60 lines of duplication and a latent hazard: a new Writer
   constructor argument means editing four files in lockstep.

2. **The transport reached past the `store.as(role).<verb>` façade into the
   intake pipeline.** Two CLI verbs — `cli/verb/put.rb` (`--fetch`) and
   `cli/verb/hook_run.rb` — hand-rolled `Timeout.timeout(N) {
   store.rpc.invoke(:resolve_intake, …, caps: nil) }` with the timeout/message
   logic inline. Identical twin leaks of pipeline mechanics into the otherwise
   pristine transport layer.

3. **The use-case invocation protocol was spelled inline in `RoleScope`.**
   `fetch(verb).new(container:, call:).call(*args, **kwargs)` — the concrete
   meaning of "the uniform shape" — lived inside `RoleScope`'s metaprogrammed
   verb loop, with no single home next to the `VERBS` table that maps the verbs.

## Decision

1. **Named constructors on the envelope IO pair.** Add
   `Envelope::IO::Writer.from(container:, call:)` and
   `Envelope::IO::Reader.from(container:)`. `Writer.from` builds its own reader
   via `Reader.from`. Each write use case's `writer` builder collapses to
   `@writer ||= Envelope::IO::Writer.from(container: @container, call: @call)`.
   The standalone `reader` builder is removed where unused; `Write::Mv` (which
   reads directly) keeps its `reader`, now sourced from `Reader.from`. The
   original `Writer.new` / `Reader.new` are untouched — `.from` is additive.

2. **A transport-side fetch kernel.** Add `Textus::Write::IntakeFetch.invoke(
   rpc:, handler:, config:, args:, label:, timeout:)` — the shared
   "invoke a `:resolve_intake` handler by name under a timeout, mapping
   `Timeout::Error` to a `UsageError`" step. `FETCH_TIMEOUT_SECONDS` (= 30) moves
   to `IntakeFetch` as its canonical home; `RefreshWorker::FETCH_TIMEOUT_SECONDS`
   becomes an alias so existing references keep resolving. Both CLI verbs call
   the helper instead of inlining the timeout dance; `hook_run` keeps its own
   outer `Textus::Error` / `StandardError` rescues around the call (the two sites
   differ only in how they wrap non-timeout errors).

3. **`Dispatcher.invoke` as the one home for the invocation protocol.** Add
   `Dispatcher.invoke(verb, container:, call:, args:, kwargs:)`, which reuses the
   existing `fetch` (so unknown verbs still raise `UsageError`) and performs the
   `new(container:, call:).call(...)` step. `RoleScope`'s verb loop keeps building
   the `Call` (request-state construction is its job) and delegates the
   instantiate-and-call to `Dispatcher.invoke`. The knowledge of how a verb is
   invoked now sits beside the table that maps the verbs.

## Consequences

**Not breaking.** Every change is additive or internal. `Writer.new`/`Reader.new`
still work; no public class is renamed or removed; use cases are not public API.
The wire format (`textus/3`) and CLI verb signatures are unchanged. Released as
the **0.29.1** patch.

**One place to change the write graph.** A new Writer dependency is a one-line
edit to `Writer.from`, not a four-file lockstep change.

**The transport façade is honest again.** No `Timeout.timeout` or
`rpc.invoke(:resolve_intake, …)` remains under `lib/textus/cli/`; the intake-fetch
mechanics live behind one named helper.

**The "uniform use-case shape" is invoked through one function.** ADR 0023
defined the shape; `Dispatcher.invoke` is now the single caller convention for it,
reachable by `RoleScope` and any future internal composer.

## Alternatives considered

**A `UseCase` base class (or mixin) providing `writer`/`reader`/`hook_context`.**
Rejected. ADR 0023 chose plain classes deliberately; a base class would
re-introduce inheritance coupling to delete ~60 lines, and not every use case
needs a writer. Named constructors remove the duplication while keeping the
classes plain.

**Kill the `hook_context` memo duplication too** (the `@hook_context ||=
Hooks::Context.for(container:, call:)` one-liner repeated in seven use cases).
Rejected for this release: it is already a single-line factory call; a shared
module to save three lines × seven buys inheritance coupling for almost nothing.
Left as a conscious non-change.

**Fold `RefreshWorker#call_intake` into `IntakeFetch` as well.** Rejected:
`call_intake` passes `caps: @container` (not `nil`), uses a per-rule timeout, and
publishes `:refresh_failed` events — it is legitimate application-layer logic, not
a transport leak. Sharing the kernel there would either widen `IntakeFetch`'s
surface or strip RefreshWorker's event semantics. Out of scope; left as-is.

**Unify `Store`'s and `RoleScope`'s verb loops.** Rejected: `Store#<verb>`
extracts the `role:` keyword and forwards to `as(role)` (role-selection);
`RoleScope#<verb>` builds the `Call` and dispatches (invocation). Different jobs.
This ADR lifts only the invocation half into `Dispatcher.invoke`; the two
metaprogrammed loops remain because their bodies are genuinely distinct.
