# ADR 0093 — `source` + `retention` over one reconcile engine

**Date:** 2026-06-06
**Status:** Accepted
**Refines:** [ADR 0087](./0087-fold-build-into-reconcile.md) (its build-fold thesis stands and is *generalized* — materialization is no longer a special "build" subsystem but one **Produce** engine; the reactive trigger it introduced is reframed as "reconcile narrowed to `rdeps ∩ derived`"), [ADR 0090](./0090-fold-automation-capability-and-upkeep.md) (the `upkeep` tagged union it introduced is the thing being **split** — it conflated two orthogonal concerns), [ADR 0091](./0091-fold-machine-zone.md) (entry-kind is the single discriminator — this ADR makes `source.from` the *production* discriminator, agreeing with `kind:` rather than restating it), [ADR 0079](./0079-unify-lifecycle-policy.md) (its "destructiveness decides execution site" invariant is **preserved** — destruction never rides a write or a read; only the reconcile sweep deletes).
**Touches:** [ADR 0089](./0089-ingest-is-system-pushed.md) (`get` is a pure read — it returns a freshness verdict, never re-pulls), [ADR 0085](./0085-two-observability-verbs-remove-freshness.md) (`pulse`/`doctor` own staleness surfacing; `reconcile` returns a health summary), [ADR 0070](./0070-content-addressed-build-artifacts.md) (byte-equal idempotence — Produce stamps no time), [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md)/[ADR 0052](./0052-typed-publish-block.md) (`publish: { tree: }` nested mirroring — preserved through the Produce scope).

> **One sentence:** the overloaded `upkeep` rule slot conflated two orthogonal concerns — *production* (how an entry's bytes are made from upstream) and *retention* (when an aged entry is retired) — so this ADR splits them into an entry-level **`source:`** (one "produce from upstream" concept, discriminated by `from: handler | template | command`, unifying the former intake + materialize blocks) and a glob-matched **`retention:`** rule (`ttl` + `drop | archive`), drives both through **one `Produce` engine** that `reconcile` runs at two scopes (a write-narrowed reactive rebuild + a full pass), removes the `warn`/`refresh` actions, and deletes the legacy materialize/upkeep machinery outright with no back-compat.

## Context

By the end of the reconcile-era sweep (ADRs 0087–0091) two things had quietly
accreted:

**(a) One `upkeep` slot holding two grammars.** ADR 0090 merged `lifecycle:`
(age) and `materialize:` (dependency) into `upkeep`, and ADR 0091 dropped its
`on:` tag so the grammar was read from the keys present. But the slot still
spoke two languages: an *age* grammar (`stale` → `ttl`/`action`) and a
*dependency* grammar (`source_change` → `strategy`). And the age grammar's
`action` itself bundled two unlike things under "age": **reconverge** (`refresh`
— re-pull an intake source) and **retire** (`drop`/`archive` — garbage-collect
an aged entry). One slot was carrying production *and* retention.

**(b) Three convergence code paths.** Materialization existed in three places:
`Ports::ReactiveMaterializeSubscriber` (the per-write push, ADR 0087 §2),
`Maintenance::Materialize` (the internal "build" service, ADR 0087 §1), and the
Lifecycle sweep (the destructive `drop`/`archive`, ADR 0079). The first two are
the *same operation* — render a derived entry, publish it — fired from two
triggers.

The smell is the one this codebase removes at ADR cadence: `upkeep` presented
**production** and **retention** as *alternatives* (one slot, pick a grammar)
when they are **orthogonal**. An intake entry legitimately wants **both** an
hourly re-pull **and** a 90-day archive — production cadence and retention
cadence are different axes — and the union could not express the conjunction.
The honest shape is two fields and one engine.

## Decision

### 1. Two orthogonal concerns: `source:` (production) + `retention:` (GC)

Production and retention **compose** — they are not a choice. So they are two
declarations, not one tagged union:

- **`source:`** is an entry field (§5.2): *how this entry's bytes are produced
  from upstream.*
- **`retention:`** is a rule slot (§5.11): *when an aged entry is retired.*

Forcing them back into one field recreates exactly the overloading this ADR
removes (see Alternatives). An intake entry may carry `source: { …, ttl: 1h }`
(re-pull cadence) **and** match a `retention: { ttl: 90d, action: archive }`
rule, independently.

### 2. One "produce from upstream" concept — `source: { from: … }`

`source: { from: handler | template | command }` unifies what were the `intake:`
block and the derived `compute:`/`template:` blocks into one concept. Intake and
materialize are not two mechanisms — they differ only in their **staleness
signal**:

- an **intake** source's upstream is **unobservable** (a remote feed); its
  staleness is a **`ttl` proxy** — re-pull on a cadence;
- a **template/projection** source's upstream is **observable** (repo entries);
  its staleness is **`rdeps`** — rebuild when a dependency changes.

`from` **agrees with the entry `kind:`** (the ADR 0091 lineage — `from: handler`
on `intake`, `from: template`/`command` on `derived`), so it is a production
*refinement* of the kind, not a second discriminator. A **templateless
projection** (`project:` without `template:`) is allowed — textus serializes the
projection directly via the `format:` strategy (e.g. structured `json`/`yaml`
output).

### 3. One `Produce` engine, two scopes

`Maintenance::Produce.call(keys:)` is the single materialization engine:
it renders + publishes derived entries, re-pulls intake entries, and skips
external (`from: command`) entries (textus never runs the command — ADR 0079
§2). It replaces **both** `ReactiveMaterializeSubscriber` and
`Maintenance::Materialize` — there is no separate "materialize" subsystem.

- The **per-write reactive rebuild** is Produce narrowed to `rdeps(key) ∩
  derived`, governed per-entry by `source.on_write: sync | async` (async
  default).
- **`reconcile`** runs Produce over the full in-scope set.

The reactive rebuild *is* reconcile narrowed to a write's blast radius — one
engine, two scopes, not two subsystems.

### 4. `reconcile` = two-phase produce → retention sweep

```
reconcile (apply):
  drain in-flight async produce-on-write threads
  acquire maintenance lock
    PHASE 1  produce ALL in-scope derived + intake past source.ttl + nested publish_tree   (non-destructive)
    PHASE 2  retention sweep: drop / archive entries past retention.ttl                     (destructive)
  release lock
```

- **Phase 1 (non-destructive)** self-elevates to the manifest's
  `reconcile`-capable build actor (`automation` by default). Pure
  materialization is a function of already-accepted canon and **grants no
  authority over content** — so it may run as the system actor.
- **Phase 2 (destructive)** runs as the **caller**, gated as its own
  `key_delete`, and **never self-elevates** — a deliberate authority decision.
  An `automation` reconcile can sweep machine entries but **not** canon; canon GC
  requires an authorized caller. This preserves ADR 0079's "destruction never
  rides a write or a read" and ADR 0078's "the sweep never self-elevates."

### 5. Remove `warn` and `refresh`

The age `action` set loses both non-GC actions:

- **`refresh` is implicit** — reconcile re-pulls every intake entry past
  `source.ttl` in Phase 1; there is no reason to spell a "refresh" action.
- **`warn` never fired** after ADR 0089 made `get` a pure read (the lazy-on-read
  path that would have surfaced it is gone).

Staleness is surfaced by `pulse`/`doctor` and the `get` freshness verdict
(ADR 0085, 0089) — not by a rule action. `retention.action` is therefore exactly
`drop | archive`.

### 6. No back-compat — delete outright

The legacy machinery is **deleted**, not shimmed (pre-1.0; a load hint makes the
migration mechanical):

- `Maintenance::Materialize`, `Ports::ReactiveMaterializeSubscriber`,
  `Policy::Upkeep` / `Policy::Lifecycle` / `Policy::Materialize`, and the
  `Domain::Lifecycle` reporter are removed.
- A manifest using `upkeep:` / `compute:` / `intake:` is **rejected at load**
  with a fold hint pointing at `source:` / `retention:`.

## Consequences

- **One mental model for production.** "How is this entry made?" has one answer
  slot (`source:`) and one engine (`Produce`); intake vs materialize is a
  staleness-signal refinement, not two subsystems.
- **Retention is independently expressible** — `retention:` composes freely with
  `source:`, so "re-pull hourly *and* archive at 90 days" is now sayable. This is
  **strictly more powerful** than the union it replaces.
- **Canon ↔ projection cannot silently drift.** The reactive push survives
  (reframed as narrowed Produce), so a canon write still re-materializes its
  dependents inline (ADR 0087's guarantee is kept, not weakened).
- **One maintenance verb, one engine.** `reconcile` over `Produce`; no second
  materialize path to keep in sync.
- **The authority boundary on canon GC is explicit.** Phase 1 self-elevates
  (pure), Phase 2 runs as the caller (destructive) — automation can converge but
  cannot silently garbage-collect canon.
- **Breaking** — manifest schema (`upkeep:`/`compute:`/`intake:` →
  `source:`/`retention:`) and verb result keys (`materialized` → `produced`,
  dropped `refreshed` and `warn`). Load hints make the manifest migration
  mechanical.

### As-shipped notes

- **Templateless projection escape hatch.** `from: template` accepts `template:`
  **or** `project:` alone — a `project:` with no `template:` renders structured
  output directly (`json`/`yaml`) via the `format:` strategy, so a derived index
  need not carry a Mustache template just to emit data.
- **Produce scope includes nested `publish: tree:` entries**, not only
  `derived?` ones. This was a narrowing bug caught during the suite migration:
  scoping Produce to `entry.derived?` silently dropped the path-driven subtree
  mirror, on which this repo's `docs/` publish depends. The engine produces an
  entry when `entry.derived? || !entry.publish_tree.nil?`.
- **`Read::Freshness` / `get`.** A never-recorded intake entry (no
  `last_fetched_at`, no file on disk) reads back as `:expired`. An intake entry
  past `source.ttl` reads back **stale** via the `get` freshness verdict but is
  **never re-pulled on read** (ADR 0089) — only Phase 1 of `reconcile` (or a
  `hook run`) re-pulls it.
- **Reconcile drains before it locks.** `reconcile` first drains in-flight async
  produce-on-write threads (`Produce::AsyncRunner.drain`), *then* acquires the
  (non-blocking) maintenance lock. This realizes ADR 0087's "wait-with-timeout,
  reconcile will reconcile it" as **drain-then-acquire**, and closes an in-process
  produce/reconcile lock race (the shared lock is non-blocking, so a still-running
  async produce thread had to be joined explicitly).
- **The shared maintenance lock keeps its `BuildLock` name** and the engine keeps
  the `:build_completed` / `:materialize_failed` event names — they are shared
  infrastructure, not the removed verb (consistent with ADR 0087's as-shipped
  note that the lock and events retain their `build` names through the rename).

## Alternatives considered

- **One literal unified field (`upkeep`/`source`) for everything.** Rejected:
  production and retention are orthogonal axes that compose; a union forces a
  choice between them and recreates exactly the overloading this ADR removes
  (the intake "re-pull *and* archive" case is unsayable in a union).
- **Collapse only the engine; keep the `upkeep` rule surface.** Rejected: it
  unifies the three code paths but leaves the conceptual smell (one slot, two
  concerns) on the operator's surface — half the goal.
- **Keep reactive materialize as a separate subsystem.** Rejected: it is
  *exactly* `reconcile` narrowed to a write's blast radius (`rdeps ∩ derived`); a
  second subsystem is duplication of the Produce engine, not a distinct concern.
- **Pure-pull, `reconcile`-only (no per-write push).** Rejected: published
  on-disk files are read by external tools (the agent harness reading
  `CLAUDE.md`/`.mcp.json`), which would silently go stale between writes — exactly
  the ADR 0087 footgun, reopened.
- **Self-elevate the destructive sweep to `author` so automation can GC canon.**
  Rejected: it silently expands automation's authority over canon. Canon GC stays
  an authorized-caller action (Phase 2 runs as the caller); only pure
  materialization (Phase 1) self-elevates.
