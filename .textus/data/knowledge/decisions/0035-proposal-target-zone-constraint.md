# ADR 0035 — Constrain a proposal's target zone; keep the accept/reject anchor-gate explicit

**Date:** 2026-05-31
**Status:** Accepted — ships 0.35.0
**Refines:** [ADR 0028](./0028-coordination-planes.md) (trust flows uphill through guarded transitions), [ADR 0030](./0030-capability-based-roles.md) (single trust anchor), [ADR 0031](./0031-unified-guard.md) (the unified Guard floor), [ADR 0033](./0033-complete-primitives-and-vocabulary.md) (`accept` is a transition; `author` is the capability). Builds on the in-flight [ADR 0034](./0034-unify-lane-vocabulary.md) (Lane vocabulary).

## Context

A post-0.33 audit asked whether the `author_signed` predicate (the closed-floor guard on the
`accept`/`reject` transitions, [ADR 0031](./0031-unified-guard.md) §4) is a redundant special
case of `zone_writable_by` and could be folded into it. Tracing the actual code refuted the
premise and surfaced a real, distinct gap.

**Two facts from the use-cases:**

```
write/accept.rb:18   guard.for(:accept, target).check!(Evaluation target: target …)   # target = the CANON key
write/reject.rb:13   guard.for(:reject, pending_key).check!(Evaluation target: pending_key)   # the QUEUE key
domain/policy/base_guards.rb   accept → [author_signed] ;  reject → [author_signed]
predicates/author_signed.rb    actor ∈ roles_with_capability("author")     # a GLOBAL anchor check; ignores the key
predicates/zone_writable_by.rb actor ∈ writers(resolve(eval.target).zone)  # depends entirely on which key is passed
```

`author_signed` asks *"are you the single trust anchor?"* — independent of any zone.
`zone_writable_by` asks *"can you write the zone this key lives in?"*. They return the same
answer in exactly one case and diverge everywhere else:

| transition | `eval.target` zone | `author_signed` needs | `zone_writable_by(eval.target)` needs | same? |
|---|---|---|---|---|
| `accept`, target ∈ **canon** | canon | `author` | `author` (canon→author) | ✅ coincides |
| `accept`, target ∈ workspace/derived/… | that kind | `author` | `keep`/`build`/… | ❌ |
| `reject` (always) | **queue** | `author` | `propose` (queue→propose) | ❌ |

For `reject` they *never* coincide: folding would let **any proposer reject any proposal**
(an agent could discard the human's queue). So `author_signed` is a deliberate anchor-gate
([ADR 0030](./0030-capability-based-roles.md) §6 / [ADR 0033](./0033-complete-primitives-and-vocabulary.md) §2),
not a degenerate `zone_writable_by`. **The fold is rejected.**

**The real gap.** Nothing constrains `proposal.target_key` to a canon zone. A proposer may
write `target_key: scratchpad.x` (workspace) or `artifacts.x` (derived). `accept` then passes
that key to its guard and to a nested `put`/`delete` whose own `zone_writable_by` gate decides
by the target's kind — producing incoherent outcomes:

- target ∈ derived → the nested `put` fails on `build` (a confusing downstream error, not an
  accept-level refusal);
- target ∈ workspace → the nested `put` *succeeds* if the anchor happens to hold `keep`,
  "accepting" a proposal into a workspace that never needed the proposal path at all.

Proposing into a non-canon zone is meaningless by construction: `workspace` is written directly
(`keep`), `derived` is build-computed, `quarantine` is fetch-populated, and there is at most one
`queue`. The queue→canon promotion is *the* trust-elevation gesture; canon is the only coherent
target.

## Decision (proposed)

1. **A proposal's `target_key` MUST resolve to a `canon` zone.** Enforce it as a closed-floor
   guard predicate `target_is_canon` in the `accept` base guard, so a non-canon-targeting
   proposal is refused at accept-time with a single clear reason rather than a downstream
   `put`/`delete` failure. (`reject` only discards the pending entry, so it does not need the
   target constraint; a `doctor` check is the right place to flag a dangling/invalid proposal.)
2. **Keep `author_signed` as the explicit anchor-gate** for both `accept` and `reject`. Do not
   fold it into `zone_writable_by`. With `target_is_canon` in force the nested `put` *also*
   requires `author` (canon→author), so the anchor requirement is defended twice on the happy
   path — but `reject` (which never runs `put`) still needs the explicit gate, so the predicate
   stays.
3. **Rename `author_signed` → `author_held`** to name what it checks (possession of the `author`
   capability), not a "signing" gesture. (Optional, bundled here because it touches the same
   file; defer if it widens the blast radius.)
4. **Document the key asymmetry:** `accept` guards on the resolved canon `target`; `reject`
   guards on the queue `pending_key`. This is load-bearing and currently invisible.

## Consequences

- A proposal targeting a non-canon zone fails early at `accept` with `target_is_canon` instead
  of a confusing nested-write error or an incoherent success. Clearer product behavior.
- **No `textus/3` wire change; no manifest-schema change.** The proposal `_meta` shape
  (`proposal.target_key` / `action`) is unchanged.
- The single-trust-anchor invariant ([ADR 0030](./0030-capability-based-roles.md) §6) stays
  explicit rather than emergent.
- The closed predicate floor grows by one (`target_is_canon`) — operator-invisible; it is a
  base guard, not a new `rules[].guard` option (though it could later be exposed as one).

## Alternatives considered

- **Fold `author_signed` into `zone_writable_by` (the original proposal).** Rejected: they are
  different invariants; `reject` diverges (would grant rejection to any proposer), and
  `accept`-into-non-canon would silently change behavior.
- **Leave the target unconstrained (status quo).** Rejected: incoherent accept outcomes are a
  latent correctness/clarity bug; "propose into a workspace/derived" has no meaning.
- **Enforce only at propose-time** (reject the `put` into the queue when `target_key` isn't
  canon). Viable as *additional* UX, but the authoritative gate belongs at the consuming
  transition (`accept`); propose-time validation also couples the generic `put` to proposal
  semantics and can't account for later manifest edits. Keep accept-time as the floor;
  propose-time/doctor are optional niceties.

## Resolutions (accepted)

- **Q1 — workspace self-promote: NO.** `target_is_canon` permits only `:canon`; a proposal
  targeting a workspace (even the actor's own) is refused. Workspace is `keep`-direct.
- **Q2 — doctor check: YES.** `doctor` gains `Check::ProposalTargets`, flagging queued
  proposals whose `target_key` is non-canon (`proposal.target_not_canon`, warning) or
  unresolvable (`proposal.target_unresolved`, warning).
- **Q3 — relaxable: NO.** `target_is_canon` is floor-only (`BaseGuards::BASE[:accept]`); there
  is no `rules[].guard` path to remove a floor predicate (ADR 0031).
- **Rename: YES.** `author_signed` → `author_held` (names capability possession, not a gesture).
