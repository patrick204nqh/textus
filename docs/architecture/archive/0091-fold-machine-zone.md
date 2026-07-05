# ADR 0091 — One `machine` zone-kind; entry-kind is the single discriminator

**Date:** 2026-06-06
**Status:** Accepted
**Amends:** [ADR 0034](./0034-unify-lane-vocabulary.md) — its `LANES` table loses two kinds (`quarantine`, `derived`) for one (`machine`); the **bijection** that 0090 weakened to a function is **restored** (one kind ↔ one capability).
**Amends:** [ADR 0090](./0090-fold-automation-capability-and-upkeep.md) — 0090 folded the *capability* (both kinds → `reconcile`) but kept two zone-kinds and an `on:`-tagged `upkeep` union; this ADR finishes the job — it collapses the two kinds and reshapes `upkeep` from an `on:`-discriminated union to one whose grammar is **read from its keys** and validated against the entry kind at load. The `upkeep.kind_mismatch` and `lifecycle.action_invalid` doctor checks 0079/0090 introduced are **deleted** (their invariant moves to a load-time check).

> **One sentence:** the external-vs-internal distinction is carried by the **entry kind** (`intake` vs `derived`), so this ADR removes the two *redundant restatements* of it — the zone-**kind** (`quarantine`/`derived` collapse into one `machine` kind) and the `upkeep` **`on:` tag** (dropped; the grammar is read from the keys present) — and merges the two machine zones into one `artifacts/` tree.

## Context

After ADR 0090, `Schema::LANES` mapped **both** `quarantine` and `derived` to
`reconcile` — two zone-kinds, one capability, one machine pass. That left two
near-duplicate restatements of a distinction the **entry kind already carries**:

1. **The zone-kind.** A `quarantine` zone held `intake` entries (bytes pulled
   from outside); a `derived` zone held `derived` entries (bytes computed from
   repo sources). But `entry.intake?` / `entry.derived?` already say exactly
   that — more precisely than the zone, which forced a whole zone to be one or
   the other. Every site that asked `policy.derived_zone?(zone)` could ask
   `entry.derived?`.

2. **The `upkeep` `on:` tag.** `upkeep: { "on": stale, … }` vs
   `{ "on": source_change, … }` was a hand-written discriminator whose value was
   **fully determined by the entry kind**: `derived` ⟹ `source_change`,
   everything else ⟹ `stale`. A doctor check (`upkeep.kind_mismatch`) then
   *verified* the tag matched the kind, and a bare `on:` was a documented YAML
   footgun (Psych parses it as boolean `true`). All of that maintained a tag
   that carried zero information.

The recurring textus move — *"this looks like a distinction but isn't one"* —
applies to both (cf. `write_policy`/`read_policy`, the `fetch` capability, the
`build` verb). The honest shape is: **entry-kind is the discriminator; remove
every second place that restates it.**

## Decision

### (a) Fold the two zone-kinds into one `machine` kind

`Schema::LANES` drops `quarantine` and `derived`, gains `machine`:

```
canon     → author
workspace → keep
machine   → reconcile
queue     → propose
```

`LANES` is a **bijection again** — one kind ↔ one capability (0090 had two kinds
surjecting onto `reconcile`). It remains the single source of truth; `ZONE_KINDS`,
`CAPABILITIES`, `KIND_REQUIRES_VERB` all still derive from it. A manifest naming
`kind: quarantine` or `kind: derived` is rejected at load with a fold hint. The
schema enforces **at most one `machine` zone** (mirroring the ≤1 `queue` rule),
so "one tree `reconcile` owns" is structural, not convention.

### (b) Entry-kind is the only discriminator

`policy.derived_zone?(zone)` is deleted in favour of `policy.derived_entry?(key)`
(resolve the entry, return `entry.derived?`). `Entry#in_generator_zone?` is
deleted; its call sites — the reactive recursion guard, the
`format_matrix`/`inject_boot` validators, generator-staleness, boot
classification — read `entry.derived?` (and `entry.projection?`) directly. One
`machine` zone now legitimately holds both `intake` and `derived` entries, so the
per-entry test is not just simpler but *more correct* than the per-zone one.

### (c) Reshape `upkeep`: no `on:` tag, grammar read from keys, validated at load

The `upkeep` block carries **no `on:` discriminator**. The grammar is read from
the keys present:

```yaml
rules:
  # age-based — intake or stored entry
  - match: artifacts.feeds.calendar.**
    upkeep: { ttl: 30m, action: refresh }

  # dependency-based — derived entry
  - match: artifacts.derived.**
    upkeep: { strategy: async }
```

`{ ttl, action, budget_ms }` ⇒ the age grammar (`Lifecycle`); `{ strategy }` ⇒
the dependency grammar (`Materialize`). Mixing the two key-sets, or an empty
block, is a parse error. Because rules are parsed independently of entries,
*which* grammar (and *which* action) is legal for *which* entry kind is enforced
once, at load, by **`Schema.validate_upkeep_kinds!`**, which pairs each entry with
its resolved `upkeep`:

- `strategy` (dependency) only on a `derived` entry;
- `action: refresh|warn` only on an `intake` entry; `action: drop|archive` only
  on a stored (leaf/nested) entry; a `derived` entry takes no age grammar at all.

This is the union of the two **deleted** doctor checks (`upkeep.kind_mismatch`,
`lifecycle.action_invalid`), now an **eager load error** — illegal combinations
cannot load, rather than surfacing as advisory `doctor` findings. The inner
`Lifecycle` / `Materialize` policies are unchanged in substance (0079/0087
preserved); `Upkeep` still exposes `.lifecycle` / `.materialize` so reconcile and
the reactive path read through unchanged.

### Keys and layout

Under the single `machine` zone (`artifacts/`), intake keys nest as
`artifacts.feeds.*` and derived keys as `artifacts.derived.*` — a symmetric
namespace where the second segment names the producer. The `init` scaffold and
the canonical `examples/project` manifest both adopt this shape.

### Breaking — no shim

Pre-1.0; breaking is cheaper than aliases, and load-time hints make migration
mechanical:

- `kind: quarantine`/`kind: derived` → `kind: machine` (load hint).
- A second `machine` zone is rejected.
- `upkeep: { "on": … }` — the `on:` key is now unknown (rejected by the generic
  sub-key walk); use the keyed form.
- Self-host keys moved: the repo's `artifacts.{orientation,mcp-config,claude-plugin}`
  → `artifacts.derived.*`.

## Consequences

- The zone-kind vocabulary is **four** kinds, each mapping 1:1 to a capability —
  the `LANES` bijection is restored and the surjection 0090 introduced is gone.
- Net deletion: one zone-kind, one `Policy` predicate (`derived_zone?`), one
  `Entry` predicate (`in_generator_zone?`), the `upkeep` `on:` discriminator, the
  `reject_unquoted_on!` schema guard and its YAML footgun, and **two doctor
  checks** — replaced by one load-time validation. No new abstractions.
- The operator question *"how is this kept current?"* has one answer slot
  (`upkeep:`) whose grammar follows from the entry kind; the two grammars stay
  typed and mutually exclusive.
- `intake` (handler-pulled, age-stale) and `derived/external` (out-of-band
  runner, dependency-stale) remain distinct — `external` stays a `derived`
  source variant; the two staleness models 0079/0087 separated are untouched.

## Alternatives considered

- **Keep two zone-kinds (0090's state).** Rejected: two kinds sharing one
  capability is the same "distinction that isn't one"; the entry kind already
  carries it, and the zone-kind only forced whole-zone homogeneity.
- **One `machine` kind but allow N machine zones.** Rejected: the operational
  goal is one tree `reconcile` owns; ≤1 makes it structural (and mirrors `queue`).
- **Keep the `on:` tag (drop only the zone-kind).** Rejected: `on:` is fully
  derivable from `entry.derived?` — keeping it keeps a zero-information tag, its
  verifying doctor check, and the YAML quoting footgun.
- **Discriminate the grammar by keys but keep the doctor checks.** Rejected:
  the kind-consistency is a hard invariant (a wrong-kind upkeep is a manifest
  error, not a lint), so a load-time failure is the honest enforcement; a doctor
  check would let an illegal manifest load.
- **Flat keys under the machine zone (`artifacts.machines`, `artifacts.index`).**
  Rejected: with both producers in one zone, the `artifacts.feeds.*` /
  `artifacts.derived.*` split keeps the namespace self-describing.
- **A migration shim accepting the old kinds / `on:` tag.** Rejected: pre-1.0;
  load-time hints make the break mechanical.
