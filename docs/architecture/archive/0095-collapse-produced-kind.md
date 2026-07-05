# ADR 0095 — collapse `derived`/`intake` into one `produced` kind

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0091](./0091-fold-machine-zone.md) (its "entry-kind is the single discriminator" thesis stands — but the discriminated *set* shrinks: `leaf | nested | derived | intake` becomes `leaf | nested | produced`, and the produce-method that `derived`/`intake` used to encode is read from `source.from` instead), [ADR 0094](./0094-source-data-publish-render.md) (it made `source.from` the acquire/staleness label and explicitly flagged the `kind:` ↔ `source.from` redundancy as a *scheduled follow-on* — this ADR is that follow-on; the data+publish split it shipped is unchanged).
**Touches:** [ADR 0093](./0093-source-retention-over-one-reconcile-engine.md) (its `source: { from: … }` field is now the **sole** producer discriminator — the "`from` agrees with `kind:`" agreement-check is removed, not just relaxed), [ADR 0090](./0090-fold-automation-capability-and-upkeep.md)/[ADR 0079](./0079-unify-lifecycle-policy.md) (the `upkeep`/`retention` grammar still keys off the produce-method, now obtained via the `intake?`/`derived?` predicates rather than a class check).

> **One sentence:** ADR 0094 left `kind:` and `source.from` encoding the **same fact twice** — `kind: intake ⟺ from: handler`, `kind: derived ⟺ from: project|command` — with a load-time agreement-check forcing them to match, so this ADR collapses the two producer kinds into **one `produced` kind**, reads the produce-method (intake / derived / external) entirely from `source.from`, **merges the `Entry::Derived` + `Entry::Intake` classes into one `Entry::Produced`**, repoints every `is_a?(Derived|Intake)` site to a behavioral predicate (`intake?` / `derived?` / `external?` / `projection?`), drops the agreement-check, and rejects the retired kinds at load with a fold hint — no back-compat.

## Context

ADR 0093 introduced `source: { from: … }` as a *refinement* of the entry kind:
`from: handler` rode on a `kind: intake` entry, `from: project|command` on a
`kind: derived` entry. The two were kept deliberately in agreement —
`from_raw` validated that `kind:` and `source.from` told the same story, so a
`kind: intake` entry with `from: project` was a load error.

ADR 0094 then made `source.from` the *acquire/staleness* axis (`project` →
observable → `rdeps`; `handler` → unobservable → `ttl`; `command` →
out-of-band) and moved presentation onto `publish:`. That clarified
`source.from` into the single honest label for "where do the bytes come from."
But it left a now-pure redundancy untouched and named it explicitly:

> *"The `kind:` (`derived`/`intake`) vs `source.from` taxonomy is now
> redundant (they encode the same fact … and `from_raw` must validate they
> agree); collapsing it is a scheduled follow-on ADR, deliberately deferred."*

Two facts encoding one truth is a drift surface: the agreement-check exists
only to police the redundancy it creates. Worse, the codebase had **two classes
that differed in name only** — `Entry::Derived` and `Entry::Intake` — both
holding a `source:`, both publishing through the one ADR-0094 `Publish::ToPaths`
path, distinguished at runtime by `is_a?` checks that were really asking "what
is `source.from`?" The kind was a label for the producer; the producer already
had a label.

The honest shape is **one producer kind** with the produce-method read from the
one field that already carries it.

## Decision

### 1. One `produced` kind; the produce-method is `source.from`

The entry-kind set becomes:

```
leaf | nested | produced
```

`kind: produced` means "this entry has a `source:`" — nothing more. The
**produce-method** (intake / derived / external) is read from `source.from`,
which ADR 0094 already established as the acquire/staleness label:

| `source.from` | produce-method | staleness signal |
|---|---|---|
| `project` | derived (internal projection) | `rdeps` (observable) |
| `handler` | intake (external fetch) | `ttl` (unobservable) |
| `command` | external (out-of-band artifact) | `sources:` mtime |

`kind:` still cleanly discriminates the three *structural* shapes — a `leaf`
(authored file), a `nested` (directory of files), a `produced` (made from a
`source:`). It just no longer restates *how* a produced entry is made.

### 2. `Entry::Derived` + `Entry::Intake` → one `Entry::Produced`

The two producer classes merge into a single `Entry::Produced < Base` keyed at
`KIND = :produced`. It holds the `source:` and exposes the produce-method as
**behavioral predicates** off `source`:

```ruby
def intake?     = @source.kind == :intake     # from: handler
def derived?    = @source.kind == :derived     # from: project | command
def external?   = @source.external?            # from: command
def projection? = @source.projection?          # from: project
```

A `produced` entry publishes through the **one** ADR-0094 `Publish::ToPaths`
path: a `projection?` entry builds its data first (`Write::DataBuilder`) then
delegates emit; intake bytes arrive from `FetchWorker`, command bytes from the
out-of-band runner — all three publish their stored bytes through the same mode.
This is unchanged from 0094; only the class topology collapses.

### 3. `is_a?` → behavioral predicates

Every site that branched on `is_a?(Entry::Derived)` / `is_a?(Entry::Intake)`
now asks the behavioral question directly — `entry.derived?`, `entry.intake?`,
`entry.external?`, `entry.projection?`. This is the ADR-0091 lineage applied one
level deeper: 0091 deleted `policy.derived_zone?` in favor of `entry.derived?`;
this ADR removes the *class identity* that `derived?`/`intake?` were standing in
for, so the predicate is now the only handle. Repointed sites span `boot`,
`Builder::Pipeline`, the json/yaml renderers, the `handler_allowlist` /
`intake_registration` doctor checks, `Domain::Staleness::GeneratorCheck`,
`Read::Deps`/`Read::Rdeps`, and `Write::FetchWorker`.

### 4. No agreement-check

The `from_raw` validation that `kind:` and `source.from` agree is **deleted** —
there is nothing left to agree, since `kind:` no longer encodes the
produce-method. One field, one source of truth.

### 5. No back-compat — old kinds fail loudly with a fold hint

`kind: derived` and `kind: intake` are **rejected at load** (pre-1.0; a load
hint makes the migration mechanical):

```
entry 'feeds.x': kind: derived was collapsed into `kind: produced` (ADR 0095) —
the produce method is `source.from` (project|command)
```

There is no shim. A manifest using a retired kind raises `BadManifest`,
pointing the author at `kind: produced` and the `source.from` value that now
carries the produce-method.

## Consequences

- **One fact, one field.** "How is this entry produced?" has exactly one
  answer slot (`source.from`); the kind no longer restates it, and the
  agreement-check that policed the restatement is gone.
- **One producer class.** `Entry::Produced` replaces the name-only-different
  `Derived` + `Intake` pair; the `is_a?` checks that were really `source.from`
  questions become honest predicates.
- **The kind set is smaller and orthogonal.** `leaf | nested | produced` are
  three *structural* shapes; produce-method, staleness, and presentation are all
  read off `source:`/`publish:`, not off the kind.
- **The ADR-0094 data+publish model is untouched.** This is a pure taxonomy
  collapse on top of it — one publish path, `_meta` in the store, `publish:` as a
  list all stand.
- **Breaking** — manifest schema: `kind: derived` / `kind: intake` are rejected
  at load with a fold hint. Load hints make the migration mechanical; no
  back-compat shim.

## Alternatives considered

- **Keep two producer kinds (`derived`/`intake`), drop only the
  agreement-check.** Rejected: it leaves two classes that differ in name only and
  two fields encoding one fact — the redundancy survives, just unpoliced, which is
  strictly worse than policed redundancy.
- **Infer `produced` from the presence of `source:` and drop `kind:` for
  produced entries entirely.** Rejected: `kind:` still cleanly discriminates the
  three *structural* shapes (`leaf` / `nested` / `produced`), and dropping it only
  for produced entries makes `kind:` an optional/conditional field ("present
  unless there's a `source:`") — a messier grammar than a single always-present
  discriminator. The win is removing the *producer-method* redundancy, not the
  kind field.
- **Collapse the classes but keep both kind *tokens* as aliases.** Rejected:
  pre-1.0, no back-compat; two spellings of one kind is the redundancy in a
  different costume. One token, a fold hint on the old ones.
