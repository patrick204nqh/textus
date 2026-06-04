# ADR 0065 — Finish the `cli_response` projection: shrink the output-only escape hatches

**Date:** 2026-06-03
**Status:** Accepted (ships 0.44.1)
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (introduced the `cli_response` facet and the generated/escape-hatch split; `runner.rb` itself flags this as "stay hand-authored until the contract grows a CLI-specific response facet (ADR 0063 follow-up)" — this is that follow-up).
**Touches:** [ADR 0036](./0036-transports-as-pure-framings.md) (keeps CLI imperative machinery out of the transport-agnostic contract — the reason this is `cli_response`, not a strategy-object hook), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the signature-reconciliation guard is what makes the Tier-2 positional alignment safe).

> **One sentence:** Some CLI verbs are hand-authored `Runner::Base` subclasses *only* because their operator envelope differs from their Ruby/agent return (`uid` → `{key, uid}`, `blame` → `{verb, key, rows}`) — exactly what `cli_response` exists for — so this ADR grows `cli_response` to also see the call's inputs and aligns a couple of CLI-positional args, moving ~1–3 verbs from the escape-hatch population into the generated one with no new concept and no operator-visible change.

## Context

ADR 0063 split the CLI into generated verbs (pure projection) and escape hatches (`class X < Runner::Base` overriding `#invoke`). Earlier analysis (the rejection of "Option D") established that most escape hatches are hand-authored for *genuine* reasons — stdin (`put`/`propose`), file reads (`migrate`/`rule_lint`), stateful resources (`build`/BuildLock, `pulse`/CursorStore), one-command-two-verbs multi-dispatch (`key delete`/`key mv`), or domain behavior (`get`'s `UnknownKey` + suggestions). Those should stay hand-authored; collapsing them behind a strategy hook would only rename the bodies while dragging imperative CLI code into the contract (against ADR 0036).

But a minority escape **only because their output envelope differs from `response`**:

| verb | Ruby/agent `response` | CLI envelope (hand-authored) | why it can't generate today |
|---|---|---|---|
| `uid` | the bare uid string | `{ "key" => key, "uid" => uid }` | the envelope needs the **input key**, which `cli_response ->(result)` never sees |
| `blame` | rows array | `{ "verb" => "blame", "key" => key, "rows" => rows }` | needs the input key **and** `arg :key` is declared non-positional while the CLI takes it positionally |
| `zone_mv` | `&:to_h` (a Plan) | `plan.to_h` (identical shape) | output already matches; blocked only by `from`/`to` being declared non-positional while the CLI takes them positionally |
| `audit` | rows array | `{ "verb" => "audit", "rows" => rows }` | needs a `since` String→Time coercion **and** uses `#call(**filters)` (keyrest), which the signature guard already exempts |

`runner.rb`'s `HAND_AUTHORED_VERBS` comment names this group explicitly and defers it. This ADR scopes the finish.

## Decision

Three independent levers, in increasing cost. **Shipped in 0.44.1: Lever A + `uid` (Tier 1) + `blame` (Tier 2). Excluded: `zone_mv` (dry_run asymmetry) and `audit` (Tier 3).**

### Lever A — grow `cli_response` to see the call's inputs (Tier 1: `uid`)

Change the `cli_response` calling convention in `CLI::Runner.dispatch` from `shaper.call(result)` to pass a second argument — a hash of the resolved inputs keyed by contract arg name — **only when the lambda's arity is 2**, so existing one-arg `cli_response` lambdas (`list`, `freshness`, `rule_list`, `rule_explain`) are untouched:

```ruby
# in Runner.dispatch, after computing (pos, kw):
inputs = spec.args.select(&:positional).map(&:name).zip(pos).to_h.merge(kw)
shaped =
  if (clr = spec.cli_response)
    clr.arity == 2 ? clr.call(result, inputs) : clr.call(result)
  else
    spec.response.call(result)
  end
verb_instance.emit(shaped)
```

Then `Read::Uid` declares its CLI envelope in the contract and drops the hand-class:

```ruby
# lib/textus/read/uid.rb
cli_response { |uid, inputs| { "key" => inputs[:key], "uid" => uid } }
```

`uid` comes off `HAND_AUTHORED_VERBS`; `lib/textus/cli/verb/uid.rb` is deleted; the reconciliation specs prove the generated command sits at `key uid` and dispatches `:uid`. **`uid` is the clean win — Lever A alone, one new contract line, one deleted file.**

### Lever B — align CLI-positional args (Tier 2: `blame`, `zone_mv`)

`blame` and `zone_mv` take positional CLI arguments (`blame KEY`, `zone mv FROM TO`) but declare those args non-positional in the contract, so the generic `call_args` would map them to `--key`/`--from` flags — a CLI change. To generate them without changing the operator surface, mark the args `positional: true` and change the use-case `#call` from keyword to positional params (`call(key, limit: nil)`, `call(from, to, dry_run: true)`). The signature-reconciliation guard (ADR 0039) verifies positional contract args are positional in `#call`, so this stays honest. `blame` needs Lever A as well, for its `{verb, key, rows}` envelope.

`zone_mv` was evaluated and **excluded**: its CLI applies by default (`dry_run || false`) while its Ruby/MCP default plans (`dry_run: true`, ADR 0060). The generic runner has one default per arg, so generating it would flip the CLI to plan-by-default — an operator-visible change. It stays hand-authored. **Tier 2 therefore shipped `blame` only.**

**Cost:** this is a pre-1.0 **Ruby API** signature change for direct callers (`store.as(role).blame(key:)` → `.blame(key)`); `RoleScope` and `MCP::Catalog.map_args` already build `(pos, kw)` from the contract, and the MCP JSON wire (keyed by arg name) is unchanged, so only hand-written Ruby callers and specs are affected.

### Lever C — `since` coercion + keyrest (Tier 3: `audit` — recommend leaving hand-authored)

`audit` would additionally need a per-arg coercion hook (e.g. an `arg ..., coerce: ->(s) { Read::Audit.parse_since(s, now: Time.now) }`, since `parse_since` handles relatives like `2h` that a generic `:time` type cannot) and works around `#call(**filters)`. The payoff is one verb; the cost is a new contract primitive (`coerce:`) used exactly once. **Recommendation: leave `audit` hand-authored** unless a second verb ever needs the same coercion.

### Explicitly dropped from the original sketch — `Plan#to_h_for_wire`

The proposal floated adding `Plan#to_h_for_wire`. It is **unnecessary**: `zone_mv` already declares `response(&:to_h)`, and the generic dispatch falls through to `spec.response` when the result doesn't respond to `to_h_for_wire`, producing `plan.to_h` — the exact CLI shape. The blocker is the positional-arg alignment (Lever B), not the wire method.

## Consequences

- Behavioral escape-hatch classes (`< Runner::Base` overriding `#invoke`) shrink **13 → 11** as shipped (removed `uid`, `blame`). The verbs that remain are hand-authored for *real* reasons (I/O, state, multi-dispatch, domain behavior, surface-divergent safety defaults) — the population becomes "behavioral escape hatches only," which is the honest end state. (Note: `HAND_AUTHORED_VERBS`, a broader exclusion list that also names the `fetch` family, the `*_prefix` cousins, and `boot`/`doctor`, is a different and larger count — 19 → 17.)
- No operator-visible change at any tier: identical commands, flags, and JSON output (the reconciliation specs are the proof).
- `cli_response` becomes able to express any envelope derivable from `(result, inputs)`, closing the gap 0063 named — without putting imperative CLI code in the contract (the line Option D would have crossed).
- The contract gains no new concept (only a wider lambda arity). The two excluded verbs each remain because folding them would require a **single-use** contract primitive, which is a net loss in DSL surface area for one caller — and for `zone_mv` would additionally *hide* a safety-relevant default divergence (ADR 0060) that the hand class currently makes legible.

### Revisit when — the second-caller trigger

This ADR is the deliberate floor, not a way-station. Do **not** re-open it to convert `zone_mv`/`audit` for their own sake — the reconciliation guards (ADR 0063/0064) already make the remaining hand classes incapable of drifting, so the only benefit of folding is a smaller count. Revisit only when a *second* verb independently needs the same primitive, at which point the excluded verb folds in for free:

- A second verb needs a **surface-divergent default** (CLI default ≠ agent default) → introduce `cli_default:` → `zone_mv` converts (also align `from`/`to` to positional, opportunistically, whenever it is next touched).
- A second verb needs **String→Time/duration coercion** (relatives like `1h`/`30m` that a generic `:time` type can't express) → introduce `coerce:` → `audit` converts (its `#call(**filters)` keyrest already survives generic dispatch; the `since` coercion is the sole blocker).

## Alternatives considered

- **Option D (strategy-object hook, `cli_invoke with:`).** Rejected previously: it renames the 13 bodies rather than removing them (no reuse/swap payoff at a flat 1:1 hierarchy) and couples the transport-agnostic contract to CLI machinery (stdin, locks, cursors). `cli_response` achieves the *output*-only subset — the part that genuinely is a projection — without that coupling.
- **Pass the whole `Call`/spec to `cli_response` instead of an `inputs` hash.** Rejected — `inputs` keyed by arg name is the minimal thing the envelopes need; passing the spec invites lambdas to reach into transport internals.
- **Do nothing.** Entirely defensible. This is polish: the hand-classes are small, correct, and guarded by reconciliation. Pursue only if the output-only duplication starts to bother, or when a verb is being touched anyway.
