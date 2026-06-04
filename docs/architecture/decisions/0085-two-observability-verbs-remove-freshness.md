# ADR 0085 — Two observability verbs on orthogonal axes; remove the public `freshness` verb

**Date:** 2026-06-04
**Status:** Accepted
**Refines:** [ADR 0079](./0079-unify-lifecycle-policy.md) (§4 kept `freshness` as the unified age-verdict read verb — this ADR removes its *public surface*, folding its agent-facing output into `pulse`, and corrects the SPEC drift where generator/external staleness was still attributed to `freshness` instead of `doctor`).
**Touches:** [ADR 0078](./0078-tend-composite-upkeep-pass.md) (`tend`'s output shape — the heartbeat-not-detail principle applies to it), [ADR 0073](./0073-surfaces-declare-external-projections.md) (an empty `surfaces` is the honest home for a Ruby-only internal verb — `freshness` becomes its first real instance), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the catalog/dispatcher reconciliation guards that keep the de-surfacing honest), [ADR 0008](./0008-freshness-and-resolution-types.md) (the `Freshness` value object on `get` envelopes — unrelated and unchanged).

> **One sentence:** textus has three observability reads — `pulse` (delta heartbeat), `doctor` (structural health), `freshness` (per-entry lifecycle) — but reading the implementation shows `pulse` already *consumes* `freshness` and projects it to a `stale` list + `next_due_at`, exactly as it consumes `doctor` and projects an `{ok,warn,fail}` summary; this ADR names the real structure — **two report tiers** (one aggregate heartbeat `pulse`, over detail-owners `doctor` + the lifecycle scan), establishes that the two *axes* are orthogonal (`doctor` = structural correctness, `pulse` = transient/temporal state), and on that basis **removes the public `freshness` verb**, keeping its scan as a Ruby-only internal (ADR 0073's empty-`surfaces` home) that `pulse` and the hook context consume — because the per-entry detail is reconstructable from `get` (`last_fetched_at`/`stale`) + `rule_explain` (the `lifecycle:` ttl/`on_expire`).

## Context

ADR 0079 collapsed the upkeep surface to "`freshness` (age verdict) + `get` (lazy apply) + `tend` (destructive sweep) + `doctor` (policy legality)," and §4 *kept* `freshness` as the read verb that reports each entry's `fresh|expired|no_policy` verdict. That was the right call at the time, but it left three observability reads whose relationship was never named — and the implementation tells a sharper story than "three peer verbs":

- **`pulse` consumes `freshness`.** `Read::Pulse#call` instantiates `Read::Freshness` directly, then projects it: `stale` = the keys of rows whose status is `:expired`; `next_due_at` = the soonest row deadline. It discards the per-entry `ttl_seconds`/`age_seconds`/`on_expire`/`reason` and the `:fresh`/`:no_policy` rows.
- **`pulse` consumes `doctor` the same way.** `pulse.doctor` is the `{ok, warn, fail}` *summary*, not doctor's full `issues[]`.

So the architecture is already a two-tier hierarchy; it was just described as three peers:

```
 TIER 1 — aggregate heartbeat (agent-facing, MCP)
   pulse : changed (audit Δ) + stale + next_due (from the scan)
           + health summary (from doctor) + pending_review
                 │ projects ▼            │ projects ▼
 TIER 2 — detail owners (human-facing, CLI)
   doctor (full issues[], structural correctness)   freshness (per-entry lifecycle rows)
```

Two further facts settle the question:

- **The surface split already exists.** `freshness` and `doctor` are `surfaces :cli` (never MCP); `pulse` is `:cli, :mcp`. Agents already get only the heartbeat; the detail verbs are human/CLI. (The `boot` agent-quickstart even hardcodes that `freshness`/`doctor` are excluded from `read_verbs`.)
- **The two axes are orthogonal, and conflating them is a trap.** `doctor` answers "is the store well-formed?" (a defect needs a human). The lifecycle scan answers "what is stale?" (a transient state that self-heals via `on_expire: refresh`). A stale-but-refreshable entry is the system *working as designed*, not ill health — folding staleness into `doctor` would make `doctor.ok: false` fire for normal operation and train operators to ignore it.

Given that, a standalone `freshness` *verb* earns its surface only if humans need the per-entry table often enough to justify it. They do not: this store runs **zero** lifecycle policies today (every scan row is `:no_policy`), the agent never had access (CLI-only), and the per-entry detail is reconstructable — `textus get KEY` carries `stale`/`stale_reason`, `textus rule_explain KEY` carries the `lifecycle:` ttl + `on_expire`. The verb is reporting surface that `pulse` (for the common loop) and `get`+`rule_explain` (for drill-down) already cover.

## Decision

### 1. Two observability verbs, two orthogonal axes

```
 doctor → STRUCTURAL    "is the store well-formed?"   defect — needs a human
 pulse  → TEMPORAL/Δ    "what changed / is stale?"    transient — self-heals
```

`doctor` owns structural correctness and is the sole owner of the full `issues[]` detail. `pulse` owns the transient/temporal axis — including staleness (`stale`, `next_due_at`) — as an aggregate heartbeat. Staleness is **not** a `doctor` concern; it stays in the heartbeat where self-healing, time-based state belongs.

### 2. Remove the public `freshness` verb; keep the scan internal

`Read::Freshness` loses its `:cli` surface, its `cli` leaf, and its `view(:cli)`. With an empty `surfaces`, it is a **Ruby-only internal verb** — ADR 0073's reserved "honest home," now used for the first time. It is no longer generated as a CLI command nor listed in the operator catalog. It remains a `Dispatcher::VERBS` entry so it stays dispatchable for:

- **`pulse`**, which instantiates it directly to compute `stale`/`next_due_at`; and
- **the hook `Context`** (`ctx.freshness`), a pure-observation read for pub-sub hooks (SPEC §5.10).

### 3. Per-entry detail is reconstructable, not lost

The capability is unbundled, not deleted. A human who needs one entry's lifecycle verdict reads:

```
 freshness(KEY)  ≈  get(KEY).stale / .last_fetched_at      (the "when" + verdict)
                  + rule_explain(KEY).lifecycle            (the ttl / on_expire action)
```

### 4. ACT verbs carry a health *heartbeat*, not detail (applies to `tend`)

The same tier discipline trims `tend`: a sweep returns *what it did* plus the `{ok,warn,fail}` health summary — matching `pulse` — and does **not** re-expose `doctor`'s full `issues[]`. (In practice a no-op `tend` was echoing an unrelated schema advisory and looking like it had "found" something.) `doctor` stays the single owner of detailed health output, so the two surfaces cannot drift.

### 5. Correct the generator-drift attribution in SPEC

ADR 0079 §4 moved generator/build drift to `doctor`'s `generator_drift` check and excluded it from the lifecycle/`freshness` path — but SPEC §5.2.2 still said external-compute staleness is "reported by `textus freshness`." This ADR fixes that prose: generator drift is reported by `doctor`'s `generator_drift` check (dependency-based, not age-based), never by the lifecycle scan.

## Consequences

- **A genuinely smaller public surface with no capability loss.** One fewer verb in the CLI, the catalog, and the docs; `pulse` + `get` + `rule_explain` cover every use the verb served.
- **`freshness` becomes ADR 0073's first real Ruby-only internal verb** — validating that the empty-`surfaces` home actually works (the CLI runner skips it, the MCP catalog excludes it, the dispatcher still registers it). The reconciliation guards (ADR 0039) keep it in the `MCP_CATALOG_INTENTIONALLY_OMITTED` set with a stated reason.
- **`doctor` stays clean.** Staleness never pollutes structural health; `doctor.ok` means "well-formed," not "nothing aged," so it stays a trustworthy alarm.
- **SPEC and docs change.** The `freshness` verb row (§9), its output-shape block, the Fixture-D staleness check, and the impl checklist are re-pointed at `pulse`/`get`+`rule_explain`; the generator-drift prose moves to `doctor`. The `get`-envelope freshness annotation (the `Freshness` value object, ADR 0008) is unrelated and unchanged.
- **No agent-visible change.** Agents never had `freshness` (CLI-only); they keep reading `pulse`. The MCP catalog and `read_verbs` are byte-identical.
- **A reversible bet.** If a future store runs many feeds with divergent TTLs and operators genuinely need the per-entry table back, the scan still exists internally — re-surfacing it (or adding a `pulse --detail`) is a small, additive change.

## Alternatives considered

- **Keep all three verbs (status quo after ADR 0079).** Rejected: it leaves `freshness` as CLI-only reporting surface that `pulse` already projects for the common loop and `get`+`rule_explain` cover for drill-down — reporting nothing today (zero live policies) at the cost of a verb in every catalog and doc.
- **Fold the lifecycle scan into `doctor` (one detail verb).** Rejected, and it is the trap to avoid: a stale-but-refreshable entry is normal operation, not a defect. Putting it in `doctor` makes `doctor.ok: false` fire for healthy stores and erodes the verb's signal. The axes are orthogonal on purpose.
- **Delete `Read::Freshness` entirely; inline the scan into `pulse`.** Rejected for this pass: the hook `Context#freshness` is a documented pub-sub read (SPEC §5.10), and `pulse` already news-up the class cleanly. Removing the *public verb* achieves the goal; deleting the *class* would also drop a hook-authoring capability that is out of this ADR's scope. Keeping it as the internal scan is the minimal, honest removal.
- **Remove `freshness` but leave `tend` reporting full `issues[]`.** Rejected: the `tend` over-report is the same tier violation in a different verb. Fixing both under one rule — "ACT verbs carry the heartbeat summary; `doctor` solely owns detail" — is what makes the surface coherent rather than spot-patched.
