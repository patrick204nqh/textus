# ADR 0099 — one `Freshness` evaluator

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0093](./0093-source-retention-over-one-reconcile-engine.md) (its `source: { from: … }` discriminator established the two staleness signals — `ttl` for intake, `rdeps` for derived/external — but left the *age comparison* logic scattered across three independent sites; this ADR collapses those three sites into the one evaluator that 0093's model implied).
**Touches:** [ADR 0079](./0079-unify-lifecycle-policy.md) (the "destructiveness decides execution site" invariant is unchanged; the evaluator only answers currency questions, never triggers GC), [ADR 0085](./0085-two-observability-verbs-remove-freshness.md) (`pulse`/`doctor` own staleness surfacing — their intake path now goes through the evaluator rather than a private age comparison), [ADR 0089](./0089-ingest-is-system-pushed.md) (`get` is a pure read that annotates the envelope with a freshness verdict — that annotation now delegates to the evaluator).

> **One sentence:** the "is this entry stale?" age comparison is written three times — `Domain::IntakeStaleness#due?`, `Read::Freshness#row_for`, and `Read::Get#annotated_envelope` — with subtly divergent edge-case handling and two name collisions sitting alongside it (`Domain::Freshness` the wire value vs `Read::Freshness` the use-case; `Domain::Retention` the reporter vs `Domain::Policy::Retention` the policy), so this ADR collapses the three age-comparison sites into **one `Domain::Freshness::Evaluator`**, renames the wire value object to `Domain::Freshness::Verdict`, renames the retention reporter to `Domain::Retention::Sweep`, and deletes the now-dead `Domain::IntakeStaleness` and `Domain::Staleness` wrapper — no change to the manifest grammar, the wire `freshness` field name, or the CLI/MCP verb surface.

## Context

ADR 0093 established that there are exactly two staleness signals:

- **`ttl` (intake)** — the upstream is unobservable; staleness is a time proxy
  (`now - last_fetched_at > source.ttl`).
- **`rdeps` (derived/external)** — the upstream is observable; staleness is
  detected by comparing a dependency's modification time against
  `_meta.generated_at`.

Both signals were correctly identified and kept conceptually separate. But the
codebase implemented them piecemeal:

**(a) The age comparison lives in three places.** `Domain::IntakeStaleness#due?`
answers "is this intake entry past its `source.ttl`?" for the reconcile Phase 1
scope. `Read::Freshness#row_for` answers the same question for `pulse`. And
`Read::Get#annotated_envelope` answers it a third time when annotating the
envelope returned to a caller. Three independent implementations of one formula
mean three independent opportunities for the edge-case handling to drift.

The drift is already present. A `produced` intake entry with no `source.ttl` is
treated differently depending on which path the question reaches: `reconcile`
re-pulls it on every pass (the `IntakeStaleness` "no ttl → always stale"
reading), while `pulse` reports it `:no_policy` (the `Read::Freshness` "no ttl
→ no opinion" reading). Neither is wrong for its context, but the divergence is
accidental — the two callers did not *decide* to differ, they just wrote the
formula independently. A fourth caller would face the same coin flip.

**(b) `Domain::Staleness` is a dead wrapper.** Its outer `#call` method is
unreferenced; only its nested `Domain::Staleness::GeneratorCheck` (the `rdeps`
drift detector) is used. The wrapper class exists only as a namespace that happens
to contain the one live class — a latent confusion between a concept
("staleness") and a use-case service.

**(c) Two name collisions.** `Domain::Freshness` is a wire value object (the
struct serialized into the `freshness:` envelope field). `Read::Freshness` is a
use-case that runs the pulse currency query. A name that means both "a value on
the wire" and "a service that computes currency" is a module boundary smell.
Separately, `Domain::Retention` is the GC reporter fed into the reconcile sweep.
`Domain::Policy::Retention` is the policy object that evaluates retention rules.
Two `Retention` names in adjacent namespaces — one a reporter, one a policy —
collide in reader attention even though they do not collide in Ruby constant
resolution.

The honest shape is one evaluator that owns the age-comparison formula and
exposes both the age signal (for intake) and the drift rows (for derived/external)
behind a single entry point.

IMPORTANT: `Read::Get` only annotates entries that already exist on disk. Because
a file that does not exist is never annotated, `get` and `pulse` already agree on
every value that `get` can observe. There is no user-facing bug — the motivation
is **DRY / one definition / removing a latent-drift hazard** before a fourth
caller inherits it.

## Decision

### 1. Two orthogonal currency questions

Currency and retention remain orthogonal concerns (ADR 0093 §1):

- **Currency** — "is the stored data stale relative to its source?" Answered by
  the `Domain::Freshness::Evaluator`.
- **Retention** — "is the entry old enough to retire?" Already clean from ADR
  0093; `Domain::Retention::Sweep` (renamed below) handles it.

This ADR touches only Currency. The retention model and the reconcile two-phase
shape are unchanged.

### 2. One `Domain::Freshness::Evaluator` for all produce-methods

`Domain::Freshness::Evaluator.call(entry, now:)` is the single age-comparison
entry point. It chooses its signal from `entry.source.from` (the ADR 0093 /
0095 discriminator):

| `source.from` | signal | basis |
|---|---|---|
| `handler` (intake) | **AGE** — `now - last_fetched_at > source.ttl` | `_meta.last_fetched_at`; falls back to file mtime when the meta field is absent |
| `project` / `command` (derived / external) | **DRIFT** — a source entry's mtime is newer than `_meta.generated_at` | the `sources:` list, matched via `Domain::Staleness::GeneratorCheck` logic (moved into the evaluator) |

The evaluator exposes two outputs behind one call:

- **`verdict`** — a `Domain::Freshness::Verdict` (see §3): `fresh`, `stale`,
  `no_policy`, or `unknown` with a reason string.
- **`drift_rows`** — the list of changed-source rows behind a `:stale / :drift`
  verdict, used by `Doctor::Check::GeneratorDrift` to show which dependencies
  changed.

**Canonical rule: a never-recorded entry is stale.** An intake entry with no
`last_fetched_at` and no file on disk has no age data; the evaluator returns
`:stale` (not `:no_policy`, not `:unknown`). This matches the existing `get`
behavior for files that exist on disk (where `last_fetched_at` would be
present) and makes the reconcile and pulse readings agree by construction:
"no record → pull it."

The "no `source.ttl`" edge case is decided once, here: a `source.ttl`-less
intake entry returns `:no_policy` from the evaluator. Both reconcile's scope
filter (`stale_intake_keys`) and pulse treat `:no_policy` as "skip" — removing
the current divergence.

### 3. `Domain::Freshness` becomes a namespace; wire value renamed `Domain::Freshness::Verdict`

`Domain::Freshness` (the wire value object) is renamed to
`Domain::Freshness::Verdict`. The outer `Domain::Freshness` becomes a plain
namespace module holding `Evaluator` and `Verdict`.

The wire `freshness:` field name in the `get` / `pulse` envelope is **unchanged**
— this is a rename of a Ruby constant, not of a serialized key.

### 4. Delete `Domain::IntakeStaleness` and `Domain::Staleness`

`Domain::IntakeStaleness` (the three-line age comparison used by reconcile scope)
is **deleted** — its logic is subsumed by the evaluator's AGE signal.

`Domain::Staleness` (the dead outer wrapper) is **deleted** — its `#call` was
never called. `Domain::Staleness::GeneratorCheck` (the one live class it
contained) is **moved into the evaluator** as the implementation of the DRIFT
signal; the public name `GeneratorCheck` is retired.

### 5. Rename `Domain::Retention` → `Domain::Retention::Sweep`

`Domain::Retention` (the GC reporter that feeds reconcile Phase 2) is renamed
`Domain::Retention::Sweep`. This resolves the reader-attention collision with
`Domain::Policy::Retention` (the policy object, **unchanged**) by placing the
reporter as an explicit sub-concept of its own namespace:

```
Domain::Retention::Sweep     # the Phase-2 GC reporter (was Domain::Retention)
Domain::Policy::Retention    # the rule evaluator (unchanged)
```

### 6. Callers repointed

All call sites are updated to route through the evaluator:

- **`Read::Get`** — `annotated_envelope` delegates the freshness annotation to
  `Domain::Freshness::Evaluator.call(entry).verdict` instead of its inline age
  comparison.
- **`Read::Freshness` / pulse** — intake currency rows call the evaluator;
  GC rows use `Domain::Retention::Sweep` (renamed).
- **`Maintenance::Reconcile`** — the stale-intake key scope (`stale_intake_keys`)
  calls the evaluator and filters for `verdict.stale?` — replaces the
  `Domain::IntakeStaleness#due?` predicate.
- **`Doctor::Check::GeneratorDrift`** — calls
  `Domain::Freshness::Evaluator.call(entry).drift_rows` instead of calling
  `Domain::Staleness::GeneratorCheck` directly.

No change to the manifest grammar, the reconcile two-phase shape, or the
CLI/MCP verb surface.

## Consequences

- **One definition of "stale".** The age-comparison formula exists in exactly one
  place; a future caller inherits the canonical edge-case handling automatically.
- **The `ttl`-less intake edge case is decided once.** Reconcile scope and pulse
  now agree by construction: `:no_policy` → skip. The current accidental divergence
  (`reconcile` re-pulls, `pulse` reports `:no_policy`) is gone.
- **Two name collisions resolved.** `Domain::Freshness` is now unambiguously a
  namespace (not a wire value); `Domain::Retention::Sweep` is unambiguously the GC
  reporter (not the policy).
- **Dead code deleted.** `Domain::Staleness#call` (the unreferenced outer wrapper)
  is gone; `Domain::IntakeStaleness` is gone. The live `GeneratorCheck` logic
  survives as the evaluator's DRIFT signal implementation.
- **No manifest grammar change.** `source:`, `retention:`, `publish:`, and the
  wire `freshness:` envelope field are all unchanged. No migration hint is needed.
- **No CLI/MCP verb surface change.** The verb interface is unchanged — this is a
  pure internal refactor behind the existing read and reconcile verbs.

## Alternatives considered

- **Leave the three sites and add a shared helper module.** Rejected: a helper
  module with the formula still requires each caller to import and call it; the
  "one entry point with canonical edge-case handling" guarantee requires an
  evaluator object, not a mixin. A mixin also does not resolve the name collisions.
- **Move the formula into `Entry::Produced`.** Rejected: currency is a *query
  against the store state* (`last_fetched_at`, file mtime) — it is not a property
  of the entry struct in isolation, and placing it there would re-couple the domain
  model to I/O. The evaluator keeps the query separate from the data object.
- **Rename only; keep three sites.** Rejected: the name collisions are a symptom;
  the three-site duplication is the disease. Renaming without collapsing removes
  the symptom while leaving the latent-drift hazard.
- **Unify into `Read::Freshness` (the use-case), not a `Domain::` evaluator.**
  Rejected: `Read::Freshness` is a use-case (pulse query); `Maintenance::Reconcile`
  is a maintenance verb. Both need the formula, but neither should own it for the
  other. Domain layer ownership is the right level.
