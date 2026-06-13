# ADR 0066 — One argument binder; `required:` is a surface policy, not a contract invariant

**Date:** 2026-06-03
**Status:** Accepted (ships 0.45.0)
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (CLI as a contract projection), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (MCP catalog derive-or-guard).
**Touches:** [ADR 0036](./0036-transports-as-pure-framings.md) (transports stay pure framings around one core).

> **One sentence:** Three surfaces (MCP, CLI, Ruby) each re-implemented the same map-args-and-default algorithm; this ADR collapses them into one `Contract::Binder.bind`, routes every surface through a single bind+invoke site (`RoleScope#dispatch_bound`), and names the finding the collapse exposed — `required:` is an *agent-wire* policy the binder applies via `validate:`, not a contract-wide invariant.

## Context

`MCP::Catalog.map_args`, `CLI::Runner.call_args`, and `RoleScope`'s per-verb default-injection loop were three copies of one algorithm: take the surface's raw input, fill defaults/session-defaults, and split into the use-case's `(positional, keyword)` shape. Each copy could drift; the MCP copy validated required args, the RoleScope copy silently did not — a difference that was accidental, not designed.

## Decision

One `Contract::Binder` owns the shared algorithm. Its currency is a uniform by-name `inputs` hash (`{arg_name => value}`); each surface normalizes its own transport shape into it (`inputs_from_ordered` for ordered argv/Ruby args, a wire-name map for MCP JSON). `bind` validates (optionally), fills session/literal defaults, and splits into `[positional, keyword]`.

Every surface dispatches through one site, `RoleScope#dispatch_bound(verb, inputs, session:, validate:)`, so bind fires exactly once per request and there is a single hook for `around:` (ADR 0068). MCP and CLI build `inputs` and call it directly; the per-verb Ruby methods normalize their args into `inputs` and delegate.

**Finding — `required:` is a surface policy.** The agent surfaces (MCP, CLI) pass `validate: true` so an agent gets a crisp "missing X" error instead of a downstream failure. The Ruby API binds leniently (`validate: false`) and trusts the use-case's own keyword defaults — e.g. `put`'s `meta:` is `required: true` on the wire yet defaults to `nil` in `#call`. The unified binder makes this explicit (`validate:`) rather than an accident of which code path ran.

## Consequences

- `map_args`/`call_args` are deleted; the double-bind (surface binds, then `RoleScope#<verb>` re-binds) is gone.
- The reconciliation specs (`contract_signature_reconciliation`, `cli_contract_reconciliation`, `mcp_catalog_dispatcher_reconciliation`) remain the safety belt; a green suite means the projection is faithful.
- `dispatch_bound` is the chokepoint ADRs 0067 (views) and 0068 (acquisition, `around:`) build on.
