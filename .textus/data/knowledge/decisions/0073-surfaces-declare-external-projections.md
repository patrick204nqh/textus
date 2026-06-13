# ADR 0073 — `surfaces` declares external projections; Ruby is the implicit base

**Date:** 2026-06-03
**Status:** Accepted
**Refines:** [ADR 0036](./0036-transports-as-pure-framings.md) (three transports — CLI, Ruby, MCP — are pure framings of one contract; this ADR sharpens *how* the framings are declared: the two operator/agent projections are named, the in-process base is not), [ADR 0066](./0066-one-binder-required-is-a-surface-policy.md) (collapsed three bind paths into one `RoleScope#dispatch_bound`; this removes the last asymmetry it left — a surface token with no site), [ADR 0069](./0069-single-path-lifecycle.md) (made validation unconditional and dropped the `validate:` fork — the one place `:ruby` ever carried behavioral weight, so after 0069 the token is inert).
**Touches:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (`mcp?`/catalog derivation unchanged), [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (`cli?`/runner filter unchanged), [ADR 0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) (boot derives from the catalog — unaffected). Surfaced by the #161 integration review while reading `surfaces :cli, :ruby, :mcp`.

> **One sentence:** `:ruby` appears in **100%** of `surfaces` declarations, has **no predicate** (`spec.ruby?` does not exist), and after ADR 0069 made validation unconditional it gates **nothing** — it is a constant carrying zero bits; this ADR drops it from the vocabulary so `surfaces` declares only the *external projections* (`:cli`, `:mcp`) while the Ruby API stays the always-present in-process base, and an empty `surfaces` becomes the honest home for a Ruby-only internal verb.

## Context

textus exposes one contract over three transports (ADR 0036). Each verb declares its transports with `surfaces`:

```ruby
surfaces :cli, :ruby, :mcp   # 21 verbs
surfaces :cli, :ruby         # 14 verbs
```

Reading every declaration in `lib/` (35 verbs) reveals the defect: **the three tokens are modeled inconsistently at every level.**

```
                         surfaces :cli, :ruby, :mcp
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
      :cli                        :ruby                       :mcp
        │                           │                           │
   spec.cli?                   ── none ──            spec.mcp? + Catalog.mcp_surfaced?(klass)
        │                           │                           │
   ┌────┴────┐                 ┌────┴─────┐              ┌──────┴──────┐
   │ inline  │                 │ NOTHING  │              │  TWO        │
   │ filter  │                 │ wires    │              │  predicates │
   │ in      │                 │ ALL      │              │  TWO layers │
   │ Runner  │                 │ verbs    │              │             │
   └─────────┘                 └──────────┘              └─────────────┘
   gates ✅                     gates ❌                   gates ✅
   present 100%                present 100%               present ~60%
                              (constant = 0 bits)
```

Three concrete findings:

1. **`:ruby` is a constant.** It appears in every one of the 35 declarations — never absent, never alone, never `:cli, :mcp` without it. A token whose value never varies carries no information.

2. **`:ruby` has no predicate and gates nothing.** `Contract::Spec` defines `cli?` and `mcp?` (`lib/textus/contract.rb:37-38`) but **no `ruby?`**. Nothing *filters* on it. `RoleScope` auto-wires *every* verb in `Dispatcher::VERBS` as a callable method (`lib/textus/role_scope.rb:65-76`) regardless of what `surfaces` lists — so a verb is Ruby-callable whether or not `:ruby` is declared. No CLI/MCP/dispatch behavior turns on the token.

3. **The one behavior `:ruby` once implied is gone.** ADR 0066 distinguished a lenient Ruby bind (`validate: false`) from strict agent binds. ADR 0069 then made validation **unconditional** on every surface (`lib/textus/contract/binder.rb:36` — *"Validation is unconditional… a contract violation on every surface"*) and dropped `validate:` from the contract path. So the policy hook that gave `:ruby` meaning no longer exists; the token outlived its semantics.

**One consumer reads the token — and it is the reason this is not a pure deletion.** The *only* reader of `spec.surfaces` in the codebase is `Read::Capabilities#project` (`lib/textus/read/capabilities.rb:43`), which projects the list verbatim into the machine-readable contract surface that integrators assert against in CI (the #161 F4 anti-drift contract). So `"ruby"` is observable on the `capabilities` wire even though it gates nothing. A naïve deletion would silently change that integrator-facing payload (and break `capabilities_spec.rb:23`). This ADR therefore does not merely delete the token — it **relocates the truth it carried**: every verb is Ruby-reachable because `RoleScope` wires them all, so `capabilities` should *derive* `"ruby"` from that structural fact rather than read a copy-pasted token. The payload is preserved; its source moves from 32 hand-written tokens to one computed base.

The result is an asymmetry a reader cannot derive from the code: **MCP** is queried via `Catalog.mcp_surfaced?(klass)` *and* `spec.mcp?` (two predicates, two layers); **CLI** via an inline `spec.cli?` filter in the runner; **Ruby** via *nothing* — yet `capabilities` reports all three as peers. The vocabulary presents three equals; the implementation has two gated projections over one ungated base, and the introspection payload papers over the difference with a constant token.

## Decision

**`surfaces` declares the external projections only. The Ruby API is the implicit, always-present base.**

```
                    surfaces :cli, :mcp          ← external projections only
                          │
              ┌───────────┴───────────┐
            :cli                     :mcp
              │                       │
         spec.cli?                spec.mcp?
              │                       │
          CLI::Runner             MCP::Catalog
              │                       │
              └───────────┬───────────┘
                          │
              ╔═══════════▼═══════════╗
              ║   RUBY API (base)     ║   ← always present, never declared
              ║   RoleScope wires     ║      surfaces []  = Ruby-only internal verb
              ║   every verb          ║
              ╚═══════════════════════╝
```

1. **Drop `:ruby` from the `surfaces` vocabulary.** Every declaration loses the token:
   - `surfaces :cli, :ruby, :mcp` → `surfaces :cli, :mcp`
   - `surfaces :cli, :ruby` → `surfaces :cli`

2. **Ruby is the base API — never declared.** `RoleScope` already exposes every verb in-process; that is the contract, stated rather than tokenized. The Ruby surface needs no predicate because it has no filter: it is the substrate the other two project from.

3. **`Read::Capabilities` derives the Ruby base instead of reading the token.** `Capabilities#project` (`lib/textus/read/capabilities.rb:43`) currently emits `spec.surfaces.map(&:to_s)`. Change it to append `"ruby"` unconditionally — `spec.surfaces.map(&:to_s) + ["ruby"]` — because every verb `capabilities` enumerates lives in `Dispatcher::VERBS` and is therefore Ruby-reachable by construction. The integrator-facing payload (#161 F4) is **unchanged** — `where` still reports `["cli","mcp","ruby"]` — but its source moves from a copy-pasted token to a computed fact. A future empty-`surfaces` internal verb then correctly reports just `["ruby"]`, which is *more* informative than today.

4. **Empty `surfaces` = Ruby-only internal verb.** With `:ruby` gone, `surfaces []` (or no declaration — `@__surfaces ||= []`) becomes the honest, usable state for an internal operation reachable from code but absent from both operator and agent wires. Today no verb uses it; the model now *has a name* for it.

5. **No regression guard — deliberately.** An earlier draft added a build-time raise rejecting `:ruby` in `surfaces`. We dropped it: it serves no consumer, and a re-introduced `:ruby` is *inert* (it gates nothing — the very property that motivated this ADR). Enforcing the absence of a token that does nothing is machinery without a job. The retirement is carried by the ADR and by the token's absence from every declaration, not by a tripwire. (Known residual: because `capabilities` appends `"ruby"` unconditionally, a re-added `:ruby` would produce a duplicate in that one payload — accepted as a low-severity, easily-spotted risk rather than paid down with a guard or a `.uniq`.) `cli?`/`mcp?` and all catalog/runner derivation are **unchanged** — this is a pure vocabulary subtraction.

This is the minimal, honest move. Two larger redesigns were considered and deferred (see Alternatives): unifying the query mechanism behind one `Surface` registry, and modeling each surface as a framing value object that owns its own ingest/view. Both *subsume* this ADR; neither is justified yet.

## Consequences

- **Zero change to observable output.** No verb gains or loses a transport. `cli?`/`mcp?` predicates, the CLI runner filter, the MCP catalog derivation, and boot's catalog-derived advertisements are all untouched. The one observable surface — the `capabilities` introspection payload — is held byte-identical by deriving `"ruby"` in `project` (Decision §3). This is *not* a pure no-op deletion: it is a token-for-derivation swap that leaves every wire identical. (An earlier draft of this ADR claimed "zero runtime change" on the strength of "no `ruby?` reader exists" — that was wrong: `capabilities` reads the whole `surfaces` list, not a predicate. The execution caught it; the fix is §3.)

- **The model becomes statable in one sentence:** *"`surfaces` lists the external projections; Ruby is the base."* The reader who tripped on `:ruby` in the #161 review gets an answer that matches the code instead of contradicting it.

- **~35 contract files shrink by one token each.** Mechanical, reviewable as a single diff. The `surfaces` DSL signature in `lib/textus/contract.rb` is unchanged (still `*list`); only the accepted token set narrows.

- **A new capability is named, not added:** `surfaces []` for internal Ruby-only verbs. Nothing uses it yet — but the next internal operation has a correct home instead of a misleading `:ruby`-only declaration.

- **DSL vocabulary change.** Anyone authoring a contract learns two tokens instead of three, and learns that Ruby is implicit. This is the cost: a one-time mental-model update. There is no guard against typing the retired `:ruby` (see Decision §5) — a stray token is inert, and the absence of any in-tree example is the guidance.

## Alternatives considered

- **Keep `:ruby`, document it (status quo + comment).** Rejected. A comment explaining why a token is inert is a confession, not a fix — the asymmetry remains and the next reader re-discovers it. Subtraction is cheaper to maintain than a standing footnote.

- **Make `:ruby` real — add a `ruby?` predicate and have `RoleScope` refuse undeclared verbs.** Rejected. This restores symmetry by *adding* machinery and a capability ("hide a verb from Ruby callers") that nobody has asked for, with blast radius across every internal call site. It optimizes for a hypothetical; the empty-`surfaces` state already covers "not on a wire" without gating the base.

- **Unify the query mechanism behind one `Surface` registry (Proposal B).** Deferred, not rejected. A single `Surface.verbs(:cli|:mcp)` / `Surface.surfaced?(klass, s)` would also kill the `mcp_surfaced?`-vs-`mcp?` near-homonym (the two-predicate/two-layer wrinkle above). Worth doing the moment any surface-aware logic is added — but it is a refactor with its own ADR, and this subtraction should land first so the model it cleans up is already defined.

- **Model each surface as a framing value object that owns ingest + view (Proposal C).** Deferred. The literal realization of ADR 0036 — `Surface::CLI/MCP/RUBY` each carrying `(ingest, view, base?)`, collapsing `CLI::Runner` and `Catalog#call` into one `Surface#invoke`, making a fourth transport (HTTP/WebSocket/gRPC) a new row rather than new dispatch code. Elegant, but speculative: the framings being implemented divergently is currently *inelegant*, not *painful*. Pay this cost when a new transport forces it; until then it is a bet on extensibility with no caller. Recorded here so the rationale survives.
