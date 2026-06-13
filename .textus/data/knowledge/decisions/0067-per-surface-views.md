# ADR 0067 — Per-surface `view`s replace `response`/`cli_response` and the arity hack

**Date:** 2026-06-03
**Status:** Accepted (ships 0.45.0)
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (introduced `cli_response`), [ADR 0065](./0065-finish-cli-response-shrink-escape-hatches.md) (grew `cli_response` to see inputs via a `Proc#arity == 2` sniff).
**Touches:** [ADR 0066](./0066-one-binder-required-is-a-surface-policy.md) (the bound `inputs` the views consume).

> **One sentence:** The contract carried two output shapers (`response` for MCP/Ruby, `cli_response` for the CLI) plus a `Proc#arity` sniff to decide whether a shaper sees the call inputs; this ADR replaces all three with one `views` map keyed by surface, every view invoked uniformly as `view.call(result, inputs)`.

## Context

ADR 0063 added `cli_response` beside `response`; ADR 0065 grew `cli_response` to optionally see the call's inputs, distinguished at runtime by `clr.arity == 2`. The result was two facets and a reflection-based branch — a shaper's *signature* silently changed its calling convention. The MCP catalog called `response`; the CLI runner called `cli_response` (falling back to `response`) through the arity sniff.

## Decision

One field, `views: { surface => shaper }`. `view { ... }` declares the default (MCP + Ruby); `view(:cli) { ... }` overrides for the CLI. `Spec#view(surface)` returns the surface's shaper or falls back to `:default`. Every view is called uniformly as `view.call(result, inputs)`; a one-parameter view simply ignores the second arg — non-lambda procs tolerate extra args, so the arity sniff disappears.

`Contract::View.render(spec, surface, result, inputs)` is the single shaping entry point. `CLI::Runner` renders `:cli`; `MCP::Catalog` renders `:default`.

Two consequences of the uniform call worth recording:
- The default identity view is `->(v, _i) { v }` (arity 2), since `View.render` always passes two args.
- `Symbol#to_proc` shapers (`response(&:to_h)`) do **not** tolerate the extra arg — `:to_h.to_proc.call(r, inputs)` becomes `r.to_h(inputs)` — so those migrated to explicit two-param blocks (`view { |v, _i| v.to_h }`).

## Consequences

- `response` and `cli_response` are removed from `Spec` and the DSL; ~25 use-cases migrate their declarations.
- The completeness guard asserts every MCP spec carries a callable `view(:default)`.
- The CLI continues to receive the `to_h_for_wire`'d result before its `:cli` view runs, so `:cli` views shape the wire hash (a verb whose default view expects the raw object declares a `:cli` view, e.g. `propose`).
