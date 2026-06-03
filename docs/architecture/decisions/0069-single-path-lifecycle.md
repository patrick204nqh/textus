# ADR 0069 — Single-path lifecycle: views self-shape, one normalizer home, validation is unconditional

**Date:** 2026-06-03
**Status:** Accepted (ships 0.45.1)
**Finishes:** [ADR 0066](./0066-one-binder-required-is-a-surface-policy.md) (one binder, one dispatch site — this retires the `validate:` fork that ADR left as a way-station), [ADR 0067](./0067-per-surface-views.md) (per-surface views — this removes the last surface that pre-shaped the result before the view saw it), [ADR 0068](./0068-declarative-facets-dissolve-escape-hatches.md) (declarative facets — this names the residual hand-authored taxonomy 0068 shrank to).
**Touches:** [ADR 0036](./0036-transports-as-pure-framings.md) (transports stay pure framings: every surface now runs the *same* lifecycle with no surface-only pre-shape or validation policy).

> **One sentence:** The 0.45.0 lifecycle (`normalize → bind → dispatch (+around) → view`) was single-path in shape but still carried four residual dual-paths — a CLI-only result pre-wire, a second normalizer inlined in MCP, a `validate:` opt-out over a `required:` arg the use-case treated as optional, and a conflated exclusion list — and this ADR removes all four so the lifecycle is single-path on every surface in fact, not just in shape.

## Context

ADRs 0066–0068 collapsed the request lifecycle onto one binder, one dispatch site, one view abstraction, and a set of declarative facets that dissolved most escape hatches. A post-0.45.0 audit found the architecture was single-path *in shape* but still carried four places where a surface diverged from the common path:

1. **The CLI runner pre-wired the result.** `CLI::Runner.dispatch` called `result.to_h_for_wire` before `View.render(:cli)`, so CLI views received a *hash* while MCP/Ruby views received the *domain object*. `propose` had to carry **two** views (a default `{uid, etag, key}` and a `view(:cli) { |wire, _i| wire }`) only because the two surfaces handed the view different input types.

2. **Two normalizers, one misplaced.** `Binder.inputs_from_ordered` (CLI/Ruby) lived in the binder; the by-wire-name normalizer (MCP JSON → by-name inputs) was inlined in `mcp/catalog.rb`. Two halves of one concept lived in two files.

3. **`validate:` was a footgun default.** `Binder.bind` took `validate: true` but `RoleScope#dispatch_bound` defaulted it to `false`, so the *default* dispatch path skipped validation — a required arg could slip through unless a surface remembered to pass `validate: true`.

4. **`validate:` forked over a lying contract.** `put.meta`/`propose.meta` were declared `required: true`, but the use-cases treat `meta` as optional (`#call(..., meta: nil)`) — its real requiredness lives in schema validation downstream. ADR 0066 reconciled this by calling `required:` "an agent-wire policy, applied via `validate:`." That was a way-station: the only reason the `validate:` fork existed was to let the lenient Ruby path tolerate a `required: true` arg the use-case did not actually require.

Plus the exclusion list itself (`HAND_AUTHORED_VERBS`) conflated two unlike categories: contract verbs with a genuine `< Runner::Base` behavioral override (`get`, `put`, `build`) and contract verbs whose CLI is a plain `< Verb` command that is not a projection at all (`fetch`, `fetch_all`, `boot`, `doctor`).

## Decision

Four targeted removals, all pre-1.0 breaking and accepted as such.

### 1. Views self-shape on every surface

Delete the `to_h_for_wire` pre-wire line in `CLI::Runner.dispatch`. Every view now receives the **raw use-case result** on every surface and shapes it itself — the pattern `get`/`zone_mv`/`migrate` already used. `propose` collapses its two views into one:

```ruby
view { |env, _i| env.to_h_for_wire }
```

This emits the full wire envelope on every surface. That is a **superset** of the old MCP/Ruby `{uid, etag, key}` — the accepted breaking change: MCP and Ruby callers of `propose` now receive the full envelope (`uid, etag, key, zone, owner, path, …`).

### 2. One normalizer home — `Binder.inputs_from_wire`

Lift MCP's inline by-wire-name normalizer into the binder, beside `inputs_from_ordered`:

```ruby
def inputs_from_wire(spec, raw)
  raw ||= {}
  spec.args.each_with_object({}) do |a, h|
    h[a.name] = raw[a.wire.to_s] if raw.key?(a.wire.to_s)
  end
end
```

The binder now owns **both** normalizers; `mcp/catalog.rb` calls `Binder.inputs_from_wire(spec, args)`.

### 3. Validation is unconditional; `required:` is an honest invariant

Drop the `validate:` parameter from `Binder.bind` and `RoleScope#dispatch_bound` entirely (and from the lone direct caller, `Maintenance::Migrate#invoke_op`). Bind always validates. There is no opt-out, so the footgun (finding #3) cannot exist.

Reconcile the contracts to make this honest: `put.meta` and `propose.meta` become `required: false`. `required:` is now a genuine contract invariant — "this arg must be present on every surface" — **not** a surface policy. `meta`'s real requiredness lives where it always belonged: schema validation in the write pipeline. The consequence is the second accepted breaking change: an MCP `put`/`propose` with a missing `_meta` no longer returns a pre-dispatch `missing _meta` error — it binds with `meta` absent and flows downstream, where a *valid* (or absent-and-schema-permitted) `_meta` succeeds and an *invalid* `_meta` fails schema validation.

This **retires the `validate:` fork ADR 0066 introduced.** That ADR's finding ("`required:` is an agent-wire policy") was the correct read of a transitional state; the right end state is to make `required:` true to its name and let schema validation own what it already owned.

### 4. Name the hand-authored taxonomy

Split `HAND_AUTHORED_VERBS` into two named, guarded categories with a derived union:

```ruby
BEHAVIORAL_HATCHES = %i[get put build].freeze        # genuine < Runner::Base overrides
NON_PROJECTED_CLI  = %i[fetch fetch_all boot doctor].freeze  # plain < Verb commands, not projections
HAND_AUTHORED_VERBS = (BEHAVIORAL_HATCHES + NON_PROJECTED_CLI).freeze
```

A guard spec (`spec/cli_hand_authored_taxonomy_spec.rb`) asserts each member's CLI class matches its declared category — a `BEHAVIORAL_HATCHES` verb resolves to a `< Runner::Base` subclass; a `NON_PROJECTED_CLI` verb to a plain `< Verb` — so the taxonomy can no longer drift silently. (`get`'s own `to_h_for_wire` duplication is recorded here as inherent to its behavioral-hatch hand-class, which emits directly; it is not separately removed.)

## Consequences

- The lifecycle is single-path **in fact**: `normalize → bind (always validate) → dispatch (+around) → view (self-shaping)`, identical on CLI, MCP, and Ruby. No surface pre-shapes a result; no surface opts out of validation; both normalizers and the validation rule have exactly one home.
- `propose` carries one view, not two. The class of "verb needs a second view only because surfaces disagree on the view's input type" is gone — it was an artifact of the pre-wire, now removed.
- Three accepted pre-1.0 breaks: (a) `Binder.bind`/`RoleScope#dispatch_bound` drop the `validate:` keyword; (b) MCP/Ruby `propose` now returns the full wire envelope; (c) a missing `_meta` yields a schema-validation outcome rather than a `missing _meta` pre-dispatch error.
- `required:` means one thing everywhere. A reader of any contract can now trust that a `required:` arg is genuinely required on every surface, and that an arg the use-case treats as optional is declared `required: false` — the declaration no longer lies for the benefit of a surface fork.

## Alternatives considered

- **Keep `validate:`, just fix its default.** Flipping `dispatch_bound`'s default to `true` would close finding #3 but leave finding #4 — a `required: true` arg the use-case treats as optional — needing the fork to exist at all. Removing the parameter and fixing the contract is strictly simpler: no parameter, no lying declaration.
- **Give `propose` a `to_h_for_wire`-shaped default view but keep the CLI pre-wire for other verbs.** Rejected — the pre-wire is exactly the surface divergence; keeping it for "other verbs" preserves the dual input-type the audit flagged. Every generated CLI view already self-shapes via `to_h`/`to_h_for_wire`, so removing the pre-wire is a no-op for them and a simplification for `propose`.
- **Leave `HAND_AUTHORED_VERBS` as one list with a longer comment.** Rejected — a comment cannot fail CI. The split lets a spec enforce the distinction so the two categories cannot quietly merge again.
