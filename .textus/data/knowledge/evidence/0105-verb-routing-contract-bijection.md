# ADR 0105 — the verb token has one home: route ⟺ contract

**Date:** 2026-06-08
**Status:** Accepted
**Refines:** [ADR 0022](./0022-container-call-dispatcher.md) (established `Dispatcher::VERBS` as the canonical verb→use-case map and the `Dispatcher.invoke(verb, container:, call:)` protocol — a static frozen map, replacing the load-order-populated use-case registry; this ADR closes the gap that nothing checked that map against the `Contract` DSL's own `verb :foo` declaration).
**Touches:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) / [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (CLI/MCP/boot/`capabilities` all project from the `Contract` DSL — this ADR makes the *routing* layer agree with that same source rather than restating it), [ADR 0085](./0085-two-observability-verbs-remove-freshness.md) / [ADR 0073](./0073-surfaces-declare-external-projections.md) (the empty-`surfaces` Ruby-only-verb convention — `validate_all` is folded into it here so the bijection is total).

> **One sentence:** a verb token is declared twice — once as a `Dispatcher::VERBS` routing key, once as `verb :foo` in the use case's `Contract` DSL — with nothing coupling the two, so a use case could be routed under a key that disagrees with its contract or (the real footgun) declare a verb it is never routed under; this ADR couples them with a **build-time bijection** (a conformance spec, not a per-store `doctor` check, because the relation is gem-internal — a user's store cannot change `Dispatcher::VERBS`), and folds the lone drift the check surfaced (`Read::ValidateAll`, routed but contract-less) into the existing empty-`surfaces` Ruby-only convention so the routing↔contract relation is **total**.

## Context

`Dispatcher::VERBS` is the canonical verb→use-case map (ADR 0023):

```ruby
VERBS = { get: Read::Get, put: Write::Put, validate_all: Read::ValidateAll, ... }.freeze
```

Independently, each use case declares its own verb token through the `Contract`
DSL, co-located with its summary, arg schema, and surfaces (ADR 0039/0063):

```ruby
class Read::Get
  extend Contract::DSL
  verb :get
  surfaces :cli, :mcp
  # ...
end
```

The CLI, the MCP catalog, `boot`, and `capabilities` all *project* from the
contract — they read `klass.contract` and never restate the verb token. But the
**routing layer does restate it**: the `:get` in `VERBS` and the `verb :get` in
the class are two strings that happen to agree, with nothing asserting they must.
The same fact lives in two places, so it can drift two ways:

1. **Mis-routing.** A typo or copy-paste in `VERBS` routes `:foo` to a class
   whose contract says `verb :bar`. The verb dispatches to the wrong use case,
   or the wrong contract is projected for it.
2. **Declare-but-unrouted** (the real footgun). A new use case declares
   `verb :foo` and wires up its whole contract, but the author forgets to add the
   `foo:` line to `VERBS`. The verb is fully *described* — it shows up nowhere on
   any surface, because the dispatcher never learned to route it. Nothing fails;
   the verb is simply dead.

Neither failure is loud. The first surfaces only if someone exercises the exact
mis-routed verb; the second never surfaces at all.

### What the check found

Encoding the bijection as a spec immediately caught a real instance of the gap.
`Read::ValidateAll` was registered in `VERBS` under `:validate_all` but declared
**no contract at all** — not even a `verb`. It is an internal, Ruby-only
validation pass (the public `validate-all` CLI verb was removed in v0.5;
`doctor`'s `schema_violations` check dispatches it; it is also exposed as a Ruby
store method). Its *category* is identical to `Read::Freshness`, which is also a
Ruby-only internal verb — but `Freshness` follows the established convention
(ADR 0085/0073): it declares a contract (`verb :freshness`, a summary) and simply
**omits `surfaces`**, so it round-trips through every contract projection while
getting no CLI/MCP surface. `ValidateAll` had never been brought into that
convention; it was the one routed verb the dispatcher knew about that the
contract layer did not.

## Decision

**1. The verb token's single home is the `Contract` DSL; `Dispatcher::VERBS` must
agree with it as a total bijection.** A conformance spec asserts, over the live
`VERBS` map and the eager-loaded set of contract-declaring classes:

- **forward** — every `VERBS[sym]` resolves to a class that declares a contract,
  and that class's `contract.verb == sym`;
- **reverse** — every contract-declaring use case (`klass.contract?`) appears in
  `VERBS.values` (no declare-but-unrouted);
- **injection** — no class is routed under more than one verb;
- **round-trip** — `VERBS.keys.sort == VERBS.values.map { _1.contract.verb }.sort`.

**2. The enforcement is a build-time spec, not a `doctor` check.** The
routing<->contract relation is a property of *textus's own source*, invariant
across every store — a user's manifest cannot change `Dispatcher::VERBS`. A
per-store `doctor` check would re-run this on every invocation against data that
cannot affect the outcome; it can only fail if the gem itself ships broken, which
is precisely what a CI spec catches at build time. This is the same reasoning
textus applies elsewhere (e.g. ADR 0104's "ceremony for no SSoT gain"): the
*guard* belongs where the thing it guards can actually vary.

**3. `Read::ValidateAll` is folded into the empty-`surfaces` Ruby-only
convention.** It now declares `verb :validate_all` with a summary and no
`surfaces` — exactly mirroring `Read::Freshness`. Behavior is unchanged (no
surface gains a `validate_all`, since empty surfaces project to neither CLI nor
MCP), but it now round-trips through `capabilities` and the produced `verbs.md`
like every other Ruby-surface verb, and the bijection is total with no
allowlisted exception.

## Consequences

- A new verb that is declared-but-unrouted (or routed-but-undeclared, or
  mis-keyed) fails CI with a message naming the offending class and the
  disagreement — the footgun becomes a build failure.
- The "Ruby-only internal verb" pattern (`Freshness`, now `ValidateAll`) is the
  *only* sanctioned way to have a routed-but-unsurfaced verb: declare the
  contract, omit `surfaces`. There is no second category of "routed without a
  contract." Adding one would fail the reverse/forward check.
- `validate_all` appears in `capabilities` output and the produced
  `docs/reference/verbs.md` (`surfaces: [ruby]`), regenerated by `reconcile` —
  consistent with how `freshness` is already documented.
- The static, frozen `VERBS` map is **kept** — its greppability (the deliberate
  win of ADR 0022's static map, replacing the load-order-populated registry) is
  preserved. The bijection couples the two declarations without making either
  dynamic.

## Alternatives considered

- **A per-store `doctor` check.** Rejected per Decision §2: the invariant is
  gem-internal and cannot vary per store, so a runtime check is wasted work that
  only restates a build-time property. (The original review framed this as a
  "doctor/CI check"; the CI/spec half is the correct one.)
- **Derive `VERBS` from the contracts** (enumerate contract classes at load,
  build the map by reflection). Rejected: this is exactly the load-order-side-
  effect registration ADR 0022 deleted in favor of an explicit frozen map.
  Greppable routing is worth more than the saved duplication; the spec gives the
  safety without the dynamism.
- **Allowlist `validate_all` as a named routed-but-contract-less exception.**
  Rejected in favor of folding it into the existing empty-`surfaces` convention
  (Decision §3): one sanctioned pattern for Ruby-only verbs beats a permanent
  carve-out, and the fold is a behavior-preserving few lines.

No `SPEC.md` change — the wire contract and verb surfaces are unchanged; this is
an internal-invariant guard plus a Ruby-only-verb normalization.
