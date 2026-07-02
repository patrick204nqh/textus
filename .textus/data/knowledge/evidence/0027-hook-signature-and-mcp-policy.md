# ADR 0027 — Hook-registry convergence and MCP transport de-leak

**Date:** 2026-05-29
**Status:** Accepted
**Refines:** [ADR 0019](./0019-hooks-bus-split.md), [ADR 0024](./0024-domain-purity-ports.md), [ADR 0026](./0026-use-case-construction-seams.md)

## Context

A senior-architect review on 2026-05-29 followed the 0.29.1 construction-seams work
(ADR 0026) and found the next tier of the same issue families one layer over —
this time in the hook registries and the MCP transport. Four problems were collected
as a closed list:

**A. Callable keyword-introspection written ~3½ times.**
After ADR 0019 split `Hooks::Bus` into `EventBus` (0..N pub-sub) and `RpcRegistry`
(single-handler RPC), both classes independently implemented callable keyword
introspection. `EventBus#shape_check!` and `RpcRegistry#shape_check!` were
byte-identical. The downstream derivations (`EventBus#filter_kwargs` and
`RpcRegistry#invoke`'s hand-rolled keyword filtering) re-derived the same facts from
the same parameter query — one concept written across three-and-a-half distinct
sites.

**B. `RpcRegistry`'s `store:` shim contradicted its own comment.**
A `store:`→`caps:` compatibility shim let a handler declaring `store:` register
successfully, then fail only at invoke time — after the handler had been loaded and
stored. A comment in that branch stated "reject if handler declares `store:`", but
the code did the opposite. The failure message at invoke time also referenced the
wrong kwarg name. A handler using `store:` appeared valid at registration and
surfaced the error only when the RPC was first exercised.

**C. `MCP::Server#handle_initialize` computed zone selection inline.**
The method iterated `manifest.data.zones` to find a proposer-writable zone whose
name matched `*review*` — embedding both the zone-selection policy and a magic-string
convention directly in the JSON-RPC transport handler. This is the same leak shape
caught in ADR 0026 (the CLI `--fetch` case): pipeline mechanics surfacing in the
otherwise-clean transport layer.

**D. `MCP::Session` was hand-rolled while every other value object uses `Data.define`.**
The session held `:role`, `:cursor`, `:propose_zone`, `:manifest_etag` in a custom
immutable class. Nineteen other value objects in the codebase use `Data.define`; the
session was the sole exception with no documented reason.

## Decision

**A → Extract `Hooks::Signature`.**
Add `Textus::Hooks::Signature` — a value object wrapping a callable's `.parameters`
and exposing four queries: `accepts_keyrest?`, `declared_keys`, `missing(required)`,
and `filter(kwargs)`. Both `EventBus` and `RpcRegistry` delegate to it. The
observation that drives this: once the `store:` shim is removed (see B), the two
registries' `shape_check!` methods become identical — extracting `Signature` deletes
both copies at once rather than reconciling two survivors.

A one-line comment is added to `EventBus`'s bounded `Thread#kill`-on-timeout marking
it a conscious tradeoff (see Alternatives).

**B → Remove the `store:` shim entirely.**
Reject any RPC handler that declares `store:` at registration time, not at invoke
time. The registration-time error message names the correct kwarg (`caps:`). As
fallout, stale in-repo RPC hook fixtures (`spec/boot_spec.rb`,
`spec/doctor_spec.rb`, `spec/doctor/check/intake_registration_spec.rb`,
`spec/read/get_spec.rb`, `spec/read/get_or_refresh_spec.rb`) and the user-facing
scaffold DSL example in `lib/textus/init.rb` are migrated from the legacy `store:`
kwarg to `caps:`.

**C → Add `Manifest::Policy#propose_zone_for(role)`.**
The "first writable zone whose name contains `review`" logic moves to
`Manifest::Policy`. `MCP::Server#handle_initialize` calls
`policy.propose_zone_for(proposer)` and receives the zone name (or `nil`) — no
zones scan remains in the transport handler. The convention now has a single,
named home next to the authority logic it depends on.

**D → Convert `MCP::Session` to `Data.define`.**
Replace the hand-rolled immutable class with
`Data.define(:role, :cursor, :propose_zone, :manifest_etag)`, adding
`advance_cursor(c) = with(cursor: c)` as the one mutating-style accessor the
session needs. Behaviour-preserving; matches the house convention.

## Consequences

**Not breaking overall.** No wire change (`textus/3` unchanged), no manifest-schema
change, no public class renamed or removed.

**Finding B is not breaking in practice.** A handler declaring `store:` already
failed at first invocation with a confusing message. The change moves that failure
to registration time and makes the message honest. In-repo fixtures and the `init.rb`
scaffold example are migrated to `caps:` as part of this work, so no shipped example
remains on the old kwarg.

**One home for callable introspection.** Adding a new introspection query (e.g.
positional-argument awareness) is a one-line change to `Signature`; both registries
gain it automatically.

**The MCP transport is honest again.** No `manifest.data.zones` scan remains in
`MCP::Server`. The review-zone convention lives beside the authority logic that
determines zone writability — not in the JSON-RPC handler.

**Session aligns with the house convention.** `Data.define`-based value objects get
`with(...)`, `==`, `to_h`, and `freeze` for free; the hand-rolled equivalents are
deleted.

## Alternatives considered

**Merge `EventBus` and `RpcRegistry` into one registry.**
Rejected. The two registries have genuinely different dispatch models: pub-sub fires
0..N handlers in per-hook threads with timeout; RPC resolves exactly one handler
synchronously. Only the *introspection* step is shared. A unified registry would
conflate different dispatch semantics; extracting `Signature` shares only what is
actually common.

**Fix the `Thread#kill`-on-timeout in `EventBus`.**
Rejected. `Thread#kill` is unsafe in the general case (it can leave mutexes locked),
but the usage here is bounded: the hook runs post-commit in an isolated thread, only
the user's own hook is affected on timeout, and the framework itself is not in a
critical section at that point. The tradeoff is explicitly marked with a comment
rather than silently left. Replacing it with a safe interrupt mechanism (e.g.
`Thread#raise` + a rescue in the hook wrapper) is out of scope for this patch.
