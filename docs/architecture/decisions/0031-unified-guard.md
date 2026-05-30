# ADR 0031 — The unified Guard: one explainable authorization path for every transition

**Date:** 2026-05-30
**Status:** Accepted — shipped in 0.32.0 (ADR 0028 moves 2 & 3); **sequenced after [ADR 0030](./0030-capability-based-roles.md)** (capability roles, 0.31.0).
**Refines:** [ADR 0028](./0028-coordination-planes.md), [ADR 0030](./0030-capability-based-roles.md), [ADR 0011](./0011-authorize-bang-in-context.md), [ADR 0027](./0027-hook-signature-and-mcp-policy.md)

## Relationship to ADR 0030 (capability roles)

ADR 0030 and this ADR are the two halves of ADR 0028's three-plane model:

- **ADR 0030 cleans Plane 1 (topology).** Write authority is derived: a role may write a
  zone ⟺ `role.can` includes the verb that zone's kind requires (`role.can ⊇
  {verb_for(zone.kind)}`). `role-kind` and `write_policy` are retired.
- **This ADR cleans Planes 2 & 3 (transitions + policy).** It funnels every transition
  through one `Guard`. The capability gate ADR 0030 built *is* this ADR's `zone_writable_by`
  predicate — they compose, not collide.

ADR 0030 deliberately leaves two accept-checks standing (a rewritten `write/authority_gate.rb`
**and** the `accept_signed` predicate) plus `rules[].promotion.requires`. This ADR removes
exactly that remaining duplication. Names below use ADR 0030's vocabulary: capability verb
`accept` (not `role-kind :accept_authority`), the `accept_signed` predicate (renamed from
`accept_authority_signed`), and the `fetch` transition (renamed from `refresh`).

## Context

ADR 0028 named the coordination model as three planes — **topology** (closed data),
**transitions** (closed verbs), **policy** (open, composable predicates) — and ratified
the invariant that flexibility lives only in the predicate vocabulary. It also recorded,
as direction not yet built, two moves:

- **Move 2** — generalize `rules[].promotion.requires:` from role-kind names to predicate
  references, so a guard can read `requires: [accept_authority_signed, schema_valid,
  fresh_within: 1h]`.
- **Move 3** — unify the guard so *every* transition, not only `accept`, evaluates one
  `Guard` abstraction sourced from `rules:`. "One thing to learn, one thing `policy
  explain` reports."

A code survey found the policy plane is answered by **three unrelated mechanisms** — and
ADR 0030 (capability roles) leaves all three standing. The same question — *may this byte
cross into this zone?* — is asked three different ways:

| Mechanism | File | Consulted by |
|---|---|---|
| `Authorizer.authorize_write!` (capability × zone-kind, post-0.31.0) | `domain/authorizer.rb` | `put`, `delete`, `mv`, `fetch` |
| `AuthorityGate#assert_accept_authority!` (`accept ∈ role.can`, post-0.31.0) | `write/authority_gate.rb` | `accept`, `reject` |
| `Promotion.from_names(requires).evaluate(...)` (composable predicates) | `domain/policy/promotion.rb` | **only** `accept` |

The fragmentation has produced four concrete smells:

1. **Two predicate allowlists kept in hand-sync** — `Promote::KNOWN` (manifest layer) and
   `Promotion::REGISTRY` (domain layer).
2. **No uniform predicate signature.** `Promotion#invoke` special-cases `accept_signed`
   by name to pass different keyword arguments. There is no evaluation-context value object.
3. **A redundant gate.** The `accept_signed` predicate "trivially passes" because
   `AuthorityGate` already checked the same `accept` capability — the topology gate and a
   predicate duplicate one check. (ADR 0030 §Consequences notes the predicate is "reframed
   against the `accept` capability" but does not collapse the duplication — that is this ADR.)
4. **`policy explain` can only tell the truth about `accept`.** For `put`, `delete`, `mv`,
   `fetch`, "what must be true to cross" is hard-coded Ruby, not data, so it cannot be
   reported before the attempt. The legible refusal — the product — is only legible for
   one verb.

This ADR builds moves 2 & 3. It does **not** open Plane 2: the verb set stays closed
(ADR 0028 §4). It gives the closed set one engine instead of three hand-rolled gates.

## Decision

### 1. One `Guard`, evaluated by every transition

A `Guard` is an **ordered list of pure predicates** over a single immutable evaluation
context. Every write transition (`put`, `delete`, `mv`, `accept`, `reject`, `fetch`)
builds its guard and calls `Guard#check!` exactly once, before it persists bytes.

```ruby
Evaluation = Data.define(:actor, :transition, :origin, :target, :envelope, :snapshot)

class Guard
  def check!(eval)
    failed = @predicates.reject { |p| p.call(eval) }
    raise GuardFailed.new(failed.map { |p| [p.name, p.reason] }) unless failed.empty?
  end

  def explain(eval) = @predicates.map { |p| [p.name, p.call(eval), p.reason] }
end
```

### 2. The topology check becomes predicate #0

`Authorizer.authorize_write!` is reframed as the `zone_writable_by` predicate — the first
entry in every write transition's base guard. There is then **one** evaluation per
transition and **one** failure path (`GuardFailed`) whether the unmet condition is
topology, schema, freshness, or accept-authority. `zone_writable_by` checks the capability
matrix directly (`policy.permission_for(z).allows_write?`); `Domain::Authorizer` is then
**deleted entirely** ([ADR 0032](./0032-drop-read-policy.md)) — its write check moved here,
its read check (`authorize_read!`) had no callers.

### 3. Uniform predicate protocol — closed signature, open vocabulary

Every predicate answers `#call(Evaluation) -> true | false`, exposes `#name`, and sets
`#reason` on failure. No predicate is invoked through a name-special-cased dispatch. The
**predicate vocabulary is the single growth surface** (ADR 0028 §2): adding a capability
is a new pure predicate in `domain/policy/predicates/` plus a `rules:` reference — never a
new verb, never a new gate. There is **one** registry (`Predicates::REGISTRY`); the
`Promote::KNOWN` duplicate list is deleted.

### 4. Base guard (code, closed) + composed guard (rules, open)

Each transition declares a minimal **base** predicate list in code — the conditions
without which the verb is meaningless (`put → [zone_writable_by]`;
`accept → [accept_signed]`). The manifest's `rules[].guard:`
block contributes **additional** predicates, matched most-specific-glob like every other
rule slot. The effective guard is `base + composed`. This keeps the floor safe (you cannot
delete `zone_writable_by` from `put` via config) while making the ceiling open.

### 5. `rules[].promotion.requires:` → `rules[].guard:` (move 2)

The promotion block is generalized to a transition-scoped guard map with parameterizable
predicates:

```yaml
rules:
  - match: "working.**"
    guard:
      accept: [accept_signed, schema_valid, { fresh_within: "1h" }]
```

This is a **breaking manifest-schema change**. `promotion: { requires: [...] }` is removed,
not aliased — per the "no external users to migrate" stance carried since 0.30.0.

### 6. `policy explain` reports the full guard, for every verb

`Read::PolicyExplain` reports, per matching key, the effective ordered predicate list for
each transition and (when given an envelope) each predicate's pass/fail with reason — the
same data `Guard#explain` returns. The truthful-refusal property now holds uniformly.

## Consequences

- **Three mechanisms collapse to one.** `AuthorityGate` (mixin) and the `Promote` /
  `Promotion` dual-allowlist are deleted. `Domain::Authorizer` is deleted too
  ([ADR 0032](./0032-drop-read-policy.md)): its write check becomes `zone_writable_by`, its
  read check had no callers.
- **Error reshape (breaking).** Promotion failures and accept-authority failures unify
  under `GuardFailed`, which carries `[[predicate_name, reason], …]`. The `write_forbidden`
  code and its `pass --as=<role>` hint are **preserved** for the `zone_writable_by`
  predicate so the topology refusal stays exactly as legible; other predicate failures
  surface under a new `guard_failed` code naming the unmet predicate(s). CLI/MCP error
  JSON shape changes.
- **Uniform predicate signature (breaking).** Any vendored or custom predicate must move
  to `#call(Evaluation)`.
- **Predicates are the only growth surface.** Adding `fresh_within`, `owner_is`,
  `quorum(n)` is additive — a class under `predicates/` and a registry row.
- **`textus/3` wire format unchanged.** This touches the manifest schema and error
  envelopes, not the entry/envelope wire contract. The CHANGELOG marks the manifest and
  error changes **BREAKING**.

## Alternatives considered

**Leave the three gates, only do move 2.** Generalize `promotion.requires` but keep
`authorize_write!` and `AuthorityGate` separate. Rejected — it leaves `policy explain`
lying for four of six verbs and keeps the dual allowlist. Move 2 without move 3 is half a
fix; the chosen scope (recorded in the planning session) is the unified engine.

**Open Plane 2 — let transitions be guard objects users define.** Rejected, restating
ADR 0028 §4: a turing-complete transition DSL destroys the legible refusal. The verb set
and the base-guard floor stay closed; only the predicate vocabulary and the composed layer
are open.

**Make schema/etag checks base predicates by pulling them out of `Envelope::IO::Writer`.**
Rejected — it would validate schema twice on every direct write. Schema enforcement stays
**solely** in `Writer` (the authoritative serialize → validate → write → audit step, ADR
0017). `schema_valid` and `etag_match` remain in the registry as **composable-only**
predicates: an operator declares them under `rules[].guard:` when they want a legible
pre-flight refusal (e.g. `accept` should reject an ill-shaped proposal *as a promotion
guard failure*, not let it fail deep inside the downstream `put`), and `policy explain`
can report them. They are never in a base guard, so no transition double-validates.

## Open questions

- **Predicate vocabulary for v1.** Beyond `zone_writable_by`, `schema_valid`,
  `accept_signed`, `etag_match`: ship `fresh_within` now (fetch/promotion reuse), defer
  `owner_is` / `quorum(n)`? (Inherited from ADR 0028.)
- **Composition operators.** Base+composed is `AND` only. Is `OR` ever needed, or does a
  named composite predicate cover it? Defer until a real case appears.
- **Fetch freshness as a predicate.** `Domain::Freshness` is a separate evaluator. Fold
  its verdict into a `fresh_within` predicate so `fetch`'s guard is data too, or leave
  freshness as the read-time annotator it is? (Sequenced after this ADR.)
- **Per-zone isolation predicate.** ADR 0030 defers per-zone write isolation (e.g. "only
  `notion-bot` writes `intake.notion`") to "a predicate on the zone." That predicate lands
  in *this* ADR's vocabulary (`owner_is` / a zone-scoped capability check) — the two ADRs'
  open questions converge here.
