# ADR 0090 — Automation is one capability + one `upkeep` policy

**Date:** 2026-06-05
**Status:** Accepted
**Supersedes:** [ADR 0088](./0088-rename-quarantine-capability-fetch-to-ingest.md) (it renamed the quarantine capability `fetch` → `ingest`; that capability is now **deleted**, folded into `reconcile`, so the rename it performed no longer has a subject).
**Amends:** [ADR 0034](./0034-unify-lane-vocabulary.md) (its `LANES` "total bijection" guarantee weakens to a **function** `zone-kind → capability` — two kinds may now share one capability; the one-table/derived-constants anti-drift guarantee is preserved).
**Refines:** [ADR 0079](./0079-unify-lifecycle-policy.md) (the unified `lifecycle:` age policy) and [ADR 0087](./0087-fold-build-into-reconcile.md) (the reactive `materialize:` dependency policy) — the *framing* that these are two separate top-level rule fields is superseded; their *substance* (two grammars, two bases, `ttl` never touches the dependency branch) is preserved verbatim inside the new `upkeep` tagged union.

> **One sentence:** automation does one job — keep the machine-maintained lanes current — so this ADR collapses its two near-duplicate expressions of that job into one each: the quarantine **capability** (`ingest`) folds into `reconcile` (the `LANES` function now maps both `quarantine` and `derived` → `reconcile`), and the two **rule fields** that drive machine upkeep (`lifecycle`, age-based; `materialize`, dependency-based) merge into one `upkeep` tagged union discriminated by `on:`.

## Context

After the reconcile-era sweep (ADRs 0087–0089) the `automation` role and its rule
surface carried two pairs of things that *looked* like distinctions but no longer
were:

**(a) Two machine-write capabilities.** `Schema::LANES` (ADR 0034) was a total
bijection zone-kind ⇄ capability: `quarantine ⇄ ingest`, `derived ⇄ reconcile`.
But ADR 0089 made **ingest system-pushed** — quarantine bytes are pulled only by
the `reconcile` sweep and `hook run`, the exact two triggers that drive *derived*
materialization (ADR 0087). The two lanes are now maintained by the **same
machine pass on the same triggers**; the only thing keeping `ingest` and
`reconcile` apart was a one-cell entry in the lane table. The recurring question
"is the quarantine capability redundant — doesn't `reconcile` do it all?" (named
and *deferred* in ADR 0088) became answerable: yes, now that ingest is
system-pushed.

**(b) Two machine-upkeep rule fields.** A rule block could carry `lifecycle:`
(age-based freshness/retention, ADR 0079: `ttl` + `on_expire` + `budget_ms`) and
`materialize:` (dependency-based reactive rebuild, ADR 0087: `on_change`). Both
answer the same operator question — *"how does the system keep this entry
current?"* — and both fire on the same `reconcile` pass. They are genuinely
different *grammars* (age vs dependency) over different *bases* (file mtime /
`last_fetched_at` vs source `rdeps`), but presenting them as two unrelated
top-level fields hid that they are two cases of one concern.

## Decision

### (a) Fold the quarantine capability into `reconcile`

`Schema::LANES` maps **both** `quarantine` and `derived` to `reconcile`:

```
canon       → author
workspace   → keep
quarantine  → reconcile
queue       → propose
derived     → reconcile
```

`LANES` is now a **function (zone-kind → capability)**, not a bijection — two
kinds legitimately share one capability because they are maintained by one pass.
It remains the **single source of truth**: `ZONE_KINDS` (`LANES.keys`),
`CAPABILITIES` (`LANES.values.uniq` — now **four**: `author, keep, propose,
reconcile`), and `KIND_REQUIRES_VERB` (`LANES` itself) all derive from it, so the
anti-drift guarantee ADR 0034 bought is intact.

The default role map becomes `automation → [reconcile]`. A manifest still naming
the deleted quarantine capability — `ingest`, or its pre-0088 spelling `fetch` —
is rejected at load with a pointed hint:

> `unknown capability 'ingest' for role '…' (known: author, keep, propose, reconcile) — the quarantine capability folded into 'reconcile' (ADR 0090)`

The `:ingest` guard transition (base guard `zone_writable_by`) is renamed to
`:reconcile`, and the `automation` agent recipe follows. There is no shim
(textus is pre-1.0); the load-time hint makes the migration mechanical.

### (b) Merge `lifecycle` + `materialize` into the `upkeep` tagged union

The two top-level rule fields become one — `upkeep:` — a **tagged union
discriminated by `on:`**:

```yaml
rules:
  # age-based — the former lifecycle grammar
  - match: feeds.calendar.**
    upkeep: { "on": stale, ttl: 30m, action: refresh, budget_ms: 800 }

  # dependency-based — the former materialize grammar
  - match: artifacts.**
    upkeep: { "on": source_change, strategy: async }
```

- **`on: stale`** carries the ADR 0079 lifecycle grammar: `ttl`, `action` (the
  field formerly named `on_expire` — `refresh | warn | drop | archive`), and an
  optional `budget_ms`.
- **`on: source_change`** carries the ADR 0087 materialize grammar: `strategy`
  (the field formerly named `on_change` — `sync | async`, default `async`).

The two grammars and their bases stay **distinct** — `ttl` never appears on the
`source_change` branch, `strategy` never on the `stale` branch (each branch
rejects the other's keys at parse). Internally `Upkeep` routes to the unchanged
`Lifecycle` / `Materialize` policies and exposes them as `.lifecycle` /
`.materialize` sub-views, so every reconcile/reactive call site reads through
unchanged. ADR 0079's and 0087's substance is preserved; only the field framing
changed.

> **YAML note:** the discriminator MUST be quoted — `"on": stale`. A bare `on:`
> is parsed as the YAML 1.1 boolean `true` by Psych and breaks the union. Every
> example here and in the docs quotes it.

#### One-tag-per-kind invariant + doctor enforcement

The union is lossless only if each entry kind takes at most one tag. A new
doctor check, **`upkeep.kind_mismatch`**, enforces the invariant:

- `on: source_change` is dependency-based and is valid **only for a `derived`
  entry** (a non-derived entry has no `rdeps`-driven rebuild).
- `on: stale` with a **destructive** action (`drop`/`archive`) is age-retention,
  which is **never** valid for a `derived` entry — it is a byte-equal
  regenerable projection, so dropping it on age is meaningless.

The existing `lifecycle.action_invalid` check (refresh-only-on-intake,
drop/archive-only-on-stored) still applies within the `on: stale` branch.

### Breaking — no shim

A manifest declaring the old top-level `lifecycle:` or `materialize:` rule field
is rejected at load with an `upkeep` hint, e.g.:

> `` `lifecycle:` was merged into `upkeep` at '…' (ADR 0090) — use `upkeep: { on: stale, … }`. ``
> `` `materialize:` was merged into `upkeep` at '…' (ADR 0090) — use `upkeep: { on: source_change, … }`. ``

The rule-field renames are breaking too: `on_expire` → `action`, `on_change` →
`strategy`. The migration is mechanical and the hints name the target shape.

## Consequences

- The capability vocabulary is **four** clean lane-authorizations — `author`,
  `keep`, `propose`, `reconcile` — none of which is a former verb or a
  same-pass duplicate. `automation` defaults to `[reconcile]`.
- `LANES` is documented as a **function, not a bijection**; the surjection onto
  `reconcile` is the visible record that quarantine + derived are one machine
  pass. The single-table anti-drift guarantee is unchanged.
- The rule surface presents machine upkeep as **one** field with two tags, so the
  operator question "how is this kept current?" has one answer slot. The two
  grammars remain typed and mutually exclusive; `doctor` (`upkeep.kind_mismatch`)
  rejects a tag on the wrong kind.
- The byte-pulling **mechanism** (`FetchWorker`/`IntakeFetch`, ADR 0048) is
  unchanged — it is still the executor the `reconcile` sweep drives for intake;
  only the *capability* that authorizes those writes was folded.
- Breaking: every `can: [ingest]` (or legacy `[fetch]`) role, and every
  top-level `lifecycle:`/`materialize:` rule field, must update. Load-time hints
  make both migrations self-explaining.

## Alternatives considered

- **Keep `ingest` as a distinct capability.** Rejected: once ingest is
  system-pushed (ADR 0089) it is authorized by the same pass and triggers as
  derived materialization; a separate capability is a distinction without a
  difference and re-invites the "is it redundant" question 0088 deferred.
- **Keep `lifecycle` + `materialize` as two fields, document the overlap only.**
  Rejected: two top-level fields for one concern is the same "looks like a
  distinction, isn't one" redundancy this codebase removes at ADR cadence
  (`write_policy`, `read_policy`, the `fetch` capability). One field with a tag
  is the honest shape.
- **One flat `upkeep` field merging both grammars (e.g. allow `ttl` and
  `strategy` together).** Rejected: the grammars are genuinely different (age vs
  dependency) and conflating them loses the type safety ADR 0079/0087 bought. The
  tagged union keeps the substance distinct while unifying the framing.
- **A migration shim accepting the old field names as aliases.** Rejected:
  pre-1.0, breaking is cheaper than a permanent alias, and the load-time hints
  already make the break mechanical.
