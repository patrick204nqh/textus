# ADR 0075 — `session_opened`: a connect-time hook event carrying the resolved role

**Date:** 2026-06-03
**Status:** Accepted
**Refines:** [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (role bound at `initialize`), [ADR 0012](./0012-explicit-hook-registration.md) (hooks load once at `Store#initialize`)
**Touches:** [ADR 0036](./0036-transports-as-pure-framings.md) (one session value across transports)

## Context

Hooks load once at `Store#initialize` and the only lifecycle event near
"startup" is `:store_loaded`, which fires inside `Store.new` under the **default
role** (`human`) — before any MCP `initialize`, before the connection's real
role is known (ADR 0040 binds it at the handshake). So there is no seam for
connect-time behavior keyed to *who* connected: session logging, per-agent
context priming, a connection audit marker. `boot` is pull-only and carries no
hook.

## Decision

Add a pubsub event `:session_opened` with args `ctx:, role:, cursor:`, fired in
`MCP::Server#handle_initialize` immediately after the `Session` is built, with
the **resolved connection role** and the boot cursor. Like every pubsub event it
is fire-and-forget (return discarded, failures logged, 2s timeout) — it observes
the connection opening; it does not gate it. This keeps ADR 0040's two-channel
model intact: a `session_opened` hook cannot carry authority any more than
`store_loaded` can.

`:session_opened` is distinct from `:store_loaded`: the latter fires once per
**process** at construction under the default role; the former fires once per
**MCP connection** with that connection's role. CLI and Ruby embedder sessions do
not fire it (no `initialize` handshake); embedders that want the seam call
`store.events.publish(:session_opened, …)` themselves.

## Consequences

- Stores gain a connect-time hook keyed to the resolved role — session logging,
  per-agent priming, connection audit markers become possible without touching
  the protocol.
- New public pubsub event → SPEC §5.10 table, `init.rb` doc list, and
  `canonical_events_spec` updated.
- `boot` remains the orientation channel; `session_opened` is an observation
  seam, not a second orientation payload.

## Alternatives considered

- **Document the boundary, add no event.** Rejected here (was the conservative
  option): a real need for role-keyed connect behavior exists, and a
  fire-and-forget pubsub event is the lowest-risk way to meet it without
  reopening ADR 0040's authority surface.
- **Reuse `:store_loaded` with a role arg.** Rejected: it fires at process
  construction before the connection role exists, and changing its arity breaks
  every existing `store_loaded` hook.
- **A live "session context" MCP tool.** Rejected: that is `boot`'s job; a tool
  is pull, this is the push seam hooks need.
