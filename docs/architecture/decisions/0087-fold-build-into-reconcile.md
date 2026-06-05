# ADR 0087 — Fold `build` into a single `reconcile` pass; materialization becomes system-pushed

**Date:** 2026-06-05
**Status:** Accepted
**Refines:** [ADR 0079](./0079-unify-lifecycle-policy.md) (the unified `lifecycle:` policy and its "destructiveness decides execution site" thesis stand — this ADR extends the same logic one level up: a *source change* decides the materialize site, and reshapes `tend`'s body from destructive-only sweep into a two-phase **materialize → sweep** pass), [ADR 0078](./0078-tend-composite-upkeep-pass.md) (the `tend` verb it introduced is renamed `reconcile` and regains a non-destructive phase).
**Touches:** [ADR 0076](./0076-build-gates-by-capability-actor-surface-to-mcp.md) (the `build` verb it surfaced to MCP + its `BuildLock` — `build` is removed as a verb; the lock generalizes to a shared maintenance lock), [ADR 0061](./0061-build-publish-vocabulary.md) (the `build` end-to-end verb naming — the *verb* retires; the single-pass `publish_via` walk survives as an internal service), [ADR 0070](./0070-content-addressed-build-artifacts.md) (byte-equal idempotence — reactive materialization must stay a content no-op, so it cannot stamp time), [ADR 0072](./0072-accept-reject-gate-by-capability.md) (the `build`-as-steering surface — removed), [ADR 0085](./0085-two-observability-verbs-remove-freshness.md) (`pulse`/`doctor` are where a pending/failed rebuild surfaces; `reconcile` keeps returning a health *summary*), [ADR 0062](./0062-one-get-read-through.md) (the lazy-on-read seam, reused conceptually for the reactive trigger), [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md)/[ADR 0064](./0064-derive-command-name-and-guard-dispatcher-key.md) (the `build` CLI escape hatch is deleted; the reconciliation guard enforces its absence), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (removing a verb shrinks the derived MCP catalog).

> **One sentence:** textus keeps its derived artifacts (`CLAUDE.md`, `AGENTS.md`, `.mcp.json`) fresh only when an operator remembers to run `build` by hand — a pull model that leaves canon and its projections silently out of sync between runs and forces a manual step into every ADR/runbook flow; this ADR **deletes the `build` verb** and makes materialization **system-pushed** from two triggers — a *reactive* rebuild of `rdeps(key) ∩ derived` on every canon write (governed per-entry by `materialize: { on_change: sync | async }`, `async` default) and a *full* rebuild as the first phase of the upkeep pass — and **renames `tend` → `reconcile`**, now a two-phase **materialize → destructive-sweep** under one shared lock (closing the latent build/tend race), so the only maintenance verb anyone speaks is `reconcile` and nobody ever materializes by hand again.

## Context

ADR 0079 unified the store's age-based garbage collection into one `lifecycle:` policy and drew a load-bearing line: **an action's destructiveness decides where it runs.** Non-destructive actions (`refresh`, `warn`) run lazily on `get`; destructive actions (`drop`, `archive`) run only on the `tend` sweep. It deliberately left one staleness *kind* out of that unification — **generator/build drift** (a derived artifact stale relative to its *sources*) — because it is dependency-based, not age-based, and one `ttl/on_expire` vocabulary cannot express "stale because a source changed." That exclusion was correct. But it left build's freshness story unaddressed, and the gap shows:

- **Materialization is operator-pulled.** The only path to a current `CLAUDE.md`/`.mcp.json`/`.claude-plugin/plugin.json` is an explicit `build` invocation. There is **no** trigger on canon write. The `adr` runbook literally instructs `bundle exec exe/textus build --prefix=knowledge.decisions` as a manual step — a footgun that ships stale docs the moment someone forgets it (and ADR 0081 made docs *canon*, raising the stakes).
- **`build` and `tend` race.** `build` holds `BuildLock` (ADR 0076); `tend` takes no such lock. Today a `tend` sweep can `drop`/`archive` an entry mid-`build`, between the materializer reading it and writing its projection. The two upkeep operations are unsynchronized.
- **Two maintenance verbs for one mental model.** An operator who wants "make the store right" must know both `build` (project derived) and `tend` (prune expired) — two verbs on the same maintenance surface, with opposite risk profiles and no shared trigger.

The deeper observation: `build` is a **pure projection** — `derived = f(canon)`, deterministic, idempotent (ADR 0070 made it byte-equal), non-destructive. By 0079's own axis it sits on the *opposite* side from `tend`'s destructive sweep. 0079 said *destructive work is the only thing that needs scheduling*. The corollary it did not draw: **non-destructive projection should not need an operator at all — it should be pushed by the system when its inputs change.** That is the gap this ADR closes, on the dependency basis 0079 named (not by smuggling build into the age vocabulary).

## Decision

### 1. Delete the `build` verb; materialization becomes an internal service

`build` is removed from the public surface: out of `Dispatcher::VERBS`, out of the MCP catalog and `write_verbs` (ADR 0039's reconciliation guard enforces the removal), and its hand-authored CLI escape hatch (ADR 0063/0064) is deleted. The single-pass `publish_via` walk (`Write::Build`, ADR 0061) is **not** lost — it is demoted to an internal `Maintenance::Materialize` service with no contract of its own, invoked only by the two triggers below. The build-actor resolution and `BuildLock` from ADR 0076 move onto that service (see §4).

There is **no public "rebuild-only" verb.** Freshness is guaranteed by the reactive trigger (§2) and the upkeep pass (§3); a forced full recompute without a destructive sweep is a **dev-only console/rake hatch**, not a contract verb. This is the accepted cost of collapsing the surface to one verb (see Consequences).

### 2. Reactive materialization on canon write — `materialize: { on_change: sync | async }`

On a successful mutating write to a non-`derived` entry (`put`/`accept`/`key_mv`/`key_delete`), textus computes `rdeps(key) ∩ derived` and re-materializes exactly those derived entries. This is dependency-driven, not age-driven — the basis ADR 0079 reserved for build drift.

A per-entry policy slot governs *when* the rebuild runs, mirroring 0079's `lifecycle: { on_expire: <action> }` grammar — a trigger (`on_change`) mapped to a strategy:

```yaml
materialize: { on_change: async }    # default — write returns immediately; rebuild runs after
materialize: { on_change: sync }     # opt-in — rebuild runs inside the write, under the lock; fresh on return
```

| `on_change` | the write call | freshness on return | use it for |
|---|---|---|---|
| `async` *(default)* | returns immediately; the affected derived entry is marked **rebuild-pending** | eventually fresh (bounded; surfaced in-textus via `pulse`/`doctor`) | the common case — projections that rebuild in well under a second and have no mid-write external reader |
| `sync` | blocks until the affected derived entries are materialized, under the maintenance lock | fresh the instant the call returns | an entry whose **external** file consumer cannot tolerate a stale window |

**Ship everything `async`** (YAGNI): add `sync` to a specific entry only when a real external-freshness need appears. The default is correct because the reactive rebuild is fast and the staleness window is bounded and, for in-textus readers, observable.

**Recursion guard.** Materialization writes into the `derived` zone. The reactive trigger **must skip writes whose target zone kind is `derived`**, or it loops. The guard lives at the trigger seam: only writes to non-derived entries fan out.

### 3. `tend` → `reconcile`: a two-phase materialize → sweep pass

The upkeep verb introduced by ADR 0078 and reshaped to destructive-only by ADR 0079 is **renamed `reconcile`** and regains a non-destructive phase:

```
reconcile (apply):
  acquire maintenance lock
    PHASE 1  materialize ALL derived entries   (non-destructive — the safety net)
    PHASE 2  destructive sweep                  (drop / archive / refresh-cold — exactly ADR 0079 §3)
  release lock

reconcile --dry_run:
    report would_materialize: N   (does NOT publish — materialization writes files, a real side effect)
    report would_drop / would_archive / would_refresh   (unchanged from ADR 0079)
```

Phase 1 is the belt-and-suspenders backstop to §2's reactive rebuild: anything a missed/failed reactive trigger left stale is reconciled here. The whole pass runs under **one** maintenance lock, which closes the build/tend race (§Context): a sweep can no longer mutate an entry mid-materialize.

**The name describes the machine, not the metaphor.** `reconcile` is the control-loop term for "converge actual state (derived projections + expired entries) toward desired state (canon)." It is a deliberate departure from the organic register (`pulse`, `doctor`, `freshness`-as-was) in favor of naming the convergence semantics directly — chosen with that trade-off explicit. The `tend` name (ADR 0078) is retired; 0078/0079's Status lines point forward to here.

`reconcile` keeps ADR 0085's contract: it returns a health **summary**, not the full `issues[]` (which `doctor` owns), and runs as the **caller's** role, gated per sub-operation, never self-elevating (the ADR 0078 authority stance, preserved). Phase 1's materialization runs as the manifest's build actor on the internal service (ADR 0076's actor resolution), under the caller's `reconcile` authority.

### 4. One shared maintenance lock; idempotence preserved

ADR 0076's `BuildLock` generalizes to a single maintenance lock (flock under `.textus/.run/`) taken by both the reactive trigger (for `sync`, and around each `async` rebuild) and `reconcile`. Contention resolves by **wait-with-timeout**, falling back to "`reconcile` will reconcile it" — a missed reactive rebuild is never lost, only deferred to the next pass.

Reactive materialization **must remain a content no-op when nothing changed** (ADR 0070): it stamps no time, so a rebuild whose inputs are unchanged produces byte-identical output and does not churn git or re-fire downstream. This is what makes a per-write trigger safe to run constantly.

### 5. Partial-failure isolation

A materialization failure on the reactive write path **must not fail the underlying write.** Canon is the source of truth; a stale projection is recoverable (the next write, or `reconcile`, fixes it). A failed/partial reactive rebuild marks the entry rebuild-pending and surfaces through `pulse`/`doctor` (ADR 0085) — it never raises into `put`/`accept`.

### 6. Contract & manifest surface

- **`SPEC.md`**: remove `build`; redefine `reconcile` (formerly `tend`) as the two-phase pass; add the `materialize: { on_change }` rule slot; rename the verb token everywhere it is load-bearing (CLI leaf, MCP tool id, dispatcher key, capability).
- **Manifest**: the automation role's `can: [fetch, build]` becomes `can: [fetch, reconcile]`; the `derived` kind no longer maps to a public `build` verb (it maps to the internal materialize service driven by §2/§3).
- **`runbooks/adr.md`**: delete the `exe/textus build --prefix=knowledge.decisions` step — accepting an ADR now materializes `knowledge.decisions` reactively (this very ADR's publish path is the proof).

## Consequences

- **One maintenance verb.** "Make the store right" is `reconcile`, full stop. The operator no longer reasons about two upkeep verbs with opposite risk profiles.
- **Canon and its projections cannot silently drift.** Every canon write pushes its affected projections; the upkeep pass backstops the rest. The manual build step — and the class of "forgot to rebuild, shipped stale docs" bugs — is gone.
- **The build/tend race is closed** as a side effect of the shared lock, not as a separate fix.
- **0079 is extended, not reversed.** Build drift stays dependency-based: the reactive trigger keys on `rdeps`, never on `ttl`. `reconcile`'s Phase 1 is a full safety-net pass, not a per-entry age verdict — so the "generator drift is not a lifecycle action" boundary 0079 drew is preserved.
- **The external-file caveat — the boundary `sync` exists to cross.** The stale-warning net (ADR 0085's `pulse`/`doctor`, and lazy `get`) covers only **in-textus** readers. The derived artifacts are read as **files on disk by tools outside textus** (the agent harness reading `CLAUDE.md`/`.mcp.json`). An external reader of a briefly-stale file under `async` gets **no** staleness signal. For the common case (sub-second rebuild, no mid-write external read) that is harmless; where it is not, `materialize: { on_change: sync }` is the explicit, per-entry crossing of that boundary.
- **No public force-rebuild.** Deleting `build` removes the "recompute everything now, without sweeping" affordance. The reactive trigger + `reconcile` cover the real cases; the rare forced full recompute is a dev-only hatch. This is the deliberate cost of the one-verb collapse — recorded so a future need can reopen it (e.g. a `reconcile --no-sweep` flag) rather than be surprised by it.
- **Breaking: verb surface + manifest + SPEC.** `build` is removed (CLI + MCP); `tend` is renamed `reconcile` (CLI leaf, MCP tool id, audit verb string, capability). Downstream manifests and any scripted `build`/`tend` calls break and must migrate.
- **Write-path cost.** Every non-derived canon write now does an `rdeps` lookup and (for `async`) schedules a rebuild. `rdeps` is cheap and the rebuild is scoped to affected entries only; the cost is bounded and, under `async`, off the write's critical path.

### As-shipped notes (recorded during implementation)

- **The trigger is the `:entry_put` event; the EventBus is the seam.** The reactive subscriber (`Ports::ReactiveMaterializeSubscriber`) attaches in `Store#bootstrap_hooks` alongside the audit subscriber. The bus invokes subscribers synchronously from the writer's perspective (per-subscriber thread joined before `publish` returns), which is *why* `sync` policy gets fresh-on-return for free. `async` work runs in a tracked thread joined by a one-time `at_exit` drain, so a short-lived CLI process cannot exit before an async rebuild completes; in the long-lived MCP server the threads complete on their own.
- **Source *removal/rename* is not yet reactive.** The trigger fires on `:entry_put` only. `key_delete`/`key_mv` of a canon *source* does **not** re-materialize its dependents — the published artifact stays stale until the next `reconcile`. Deferred as a follow-up (register the same handler on `:entry_deleted`/`:entry_renamed`, keyed on the rdeps of the gone/old key), not built here (YAGNI; the reactive contract is about writes).
- **`sync` rides the bus's hook timeout.** A `sync` rebuild executes inside the bus's bounded hook window (`HOOK_TIMEOUT_SECONDS`, currently 2s). A `sync` policy applied to a *large* impact set could exceed it and be killed (then swallowed by failure isolation → silently stale). Acceptable because `async` is the default and `sync` is opt-in for small/fast projections; revisit the timeout if `sync` is ever applied to heavy projections.
- **The lock and event keep their `build` names.** The maintenance lock (`Ports::BuildLock`, `.run/build.lock`), the `:build_completed` event, and the `build_in_progress` error code retain their names — they are shared infrastructure, not the removed verb. Renaming them is deferred to avoid a wider wire-contract churn; the *capability* `build` was renamed to `reconcile` (it now matches both the verb and the derived-zone kind, removing the prior orphan-capability smell).

## Alternatives considered

- **Approach A — de-surface `build` but keep it as an internal escape hatch (don't delete the verb).** Rejected in favor of the full delete: the appetite here is a genuine one-verb surface, and keeping `build` callable (even "just for debugging") re-grows exactly the surface this collapse exists to shrink. The dev-only console/rake hatch covers the rare forced-rebuild need without a contract verb.
- **Approach C — add the reactive trigger only; leave `build` and `tend` untouched.** Rejected: it fixes freshness but delivers none of the vocabulary normalization — `build` stays in the operator's face and the build/tend race persists. Half the goal.
- **Keep `build` and `tend` as separate verbs; add an external orchestrator (cron/hook) that runs both.** Rejected: it streamlines *operations* without simplifying the *contract*, and leaves the race and the two-verb mental model in place. The orchestration belongs *inside* `reconcile` (Phase 1/2), not bolted on outside.
- **Name the unified verb `tend` (keep the organic register) or `maintain`.** Rejected per the explicit choice to name the convergence machine over the metaphor: `reconcile` states the control-loop semantics; `tend` undersold the new materialize phase and `maintain` collides with the `Maintenance::` namespace.
- **Make reactive materialization lazy-on-`get` (mirror ADR 0062/0079 exactly).** Rejected: the consumers of derived artifacts are files on disk read *outside* textus, so a lazy-on-`get` rebuild never fires for the readers that matter. The trigger must be the write (push), not the read (pull). The `materialize: { on_change }` policy is the closest faithful analog of 0079's `on_expire` grammar that actually reaches external readers.
- **Fold generator drift into the `lifecycle:` age vocabulary after all.** Still rejected, for ADR 0079 §Alternatives' reason: age cannot express "stale because a source changed." The reactive `rdeps` trigger handles drift on the *dependency* basis where it belongs; `lifecycle:` stays age-only.
- **Stamp a rebuild timestamp to track staleness.** Rejected: it breaks ADR 0070's byte-equal idempotence (a rebuild would change the stamp and stop being a no-op), re-growing the churn class 0070 killed. The rebuild-pending marker is transient runtime state (`pulse`/`doctor`), not a written stamp.
