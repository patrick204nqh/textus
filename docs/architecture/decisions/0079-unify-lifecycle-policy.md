# ADR 0079 — Unify staleness + retention into one `lifecycle` policy; collapse the upkeep verbs; lazy by default

**Date:** 2026-06-04
**Status:** Proposed
**Refines:** [ADR 0048](./0048-fetch-subsystem-three-concerns.md) (the `fetch:` rule slot and its intake invocation / deadline / events split — this ADR keeps those *mechanisms* but folds the `fetch:` slot's freshness budget into the unified `lifecycle:` slot), the retention policy (`rules[*].retention:`, SPEC §5.11).
**Touches:** [ADR 0062](./0062-one-get-read-through.md) (`get` is read-through — this ADR makes that read-through path the *default* execution site for non-destructive lifecycle actions), [ADR 0078](./0078-tend-composite-upkeep-pass.md) (`tend` survives but is reshaped: from a composite of `fetch_all`+`retain`+`doctor` into the **destructive-only sweep** — see its status note), [ADR 0058](./0058-one-verb-name-across-surfaces.md) (the verb-naming discipline this collapse continues), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (removing verbs shrinks the derived catalog; the reconciliation guards enforce it), [ADR 0008](./0008-freshness-and-resolution-types.md) (the `Freshness` value object the unified read verb returns).

> **One sentence:** textus runs two age-based garbage-collection systems with different vocabularies — `fetch: {ttl, on_stale}` (refresh stale intake) and `retention: {expire_after, archive_after}` (prune aged leaves) — each with its own preview verb (`stale`/`retainable`), its own apply verb(s) (`fetch`/`fetch_all` vs `retain`), and only one of which (intake) self-heals on read; this ADR collapses both into **one `lifecycle: {ttl, on_expire}` policy** with a single action vocabulary (`refresh | warn | drop | archive`), makes the action's *destructiveness* decide its *execution site* (non-destructive `refresh`/`warn` run lazily on `get`/`list`; destructive `drop`/`archive` run only on the `tend` sweep), and removes the now-redundant public verbs (`stale`, `retainable`, `fetch`, `fetch_all`, `retain`) — a breaking manifest + verb-surface redesign that supersedes the composite framing of ADR 0078.

## Context

A store's "keep things tidy" surface has grown into two parallel subsystems that are structurally identical and only superficially different:

```
 rule slot today                              age basis           action on expiry
 ──────────────                               ─────────           ────────────────
 fetch:     {ttl, on_stale: warn|sync|        _meta.              re-pull from handler
            timed_sync, sync_budget_ms}        last_fetched_at
 retention: {expire_after, archive_after}     file mtime          delete / archive
```

Both say *"an entry has a maximum age; when it's exceeded, do something."* Yet they diverge gratuitously:

- **Two vocabularies** for one idea (`ttl`/`on_stale` vs `expire_after`/`archive_after`).
- **Two preview verbs** — `stale` (what intake is past TTL) and `retainable` (what retention would expire/archive) — plus `freshness` for per-entry intake status. Three read verbs reporting "what's aged out."
- **Two apply paths** — `fetch`/`fetch_all` (refresh) and `retain` (prune) — papered over by `tend` (ADR 0078), which exists *only because* the two paths were separate.
- **Asymmetric execution.** Intake already self-heals on read: `get` is read-through and refreshes on a stale verdict (ADR 0062, `on_stale: sync`). Retention has **no** lazy path — an aged leaf is pruned only when someone runs `retain`/`tend`. So one system is lazy and the other is sweep-only, for no principled reason.

This asymmetry is the smell. It forced ADR 0078 to invent a composite verb, and it forced the operator to reason about two TTL concepts, three read verbs, and three apply verbs to answer one question: *is this entry too old, and what happens then?*

A third kind of staleness exists — **generator/build staleness** (`Domain::Staleness::GeneratorCheck`: is a derived artifact stale relative to its *sources*?). That one is **deliberately out of scope**: it is dependency-based, not age-based. Folding it in would merge two genuinely different concepts and yield a worse abstraction. It stays on the `build`/`External` path (ADR 0076).

## Decision

### 1. One slot: `lifecycle: { ttl, on_expire }`

Replace the `fetch:` and `retention:` rule slots with a single `lifecycle:` slot:

```yaml
rules:
  - match: "feeds.*"
    lifecycle: { ttl: 1h,  on_expire: refresh }   # intake: re-pull from handler
  - match: "review.*"
    lifecycle: { ttl: 30d, on_expire: drop }       # stored: delete when aged
  - match: "audit.*"
    lifecycle: { ttl: 90d, on_expire: archive }     # stored: copy to archive/, then remove
```

`ttl` is a duration string (`30s`/`90m`/`12h`/`30d`/bare seconds). The intake-invocation *mechanism* from ADR 0048 (handler resolution, deadline, lifecycle events) is unchanged; only its freshness **budget** moves into `lifecycle:`. The `refresh` action carries the optional budget knobs (`budget_ms:` replaces `on_stale: timed_sync` + `sync_budget_ms`).

### 2. One action vocabulary, validated against entry kind at load

`on_expire` is one of four actions, and which actions are legal depends on the entry — a constraint `doctor` enforces at manifest load (the two old slots could never validate each other):

| `on_expire` | does | valid for | destructive |
|---|---|---|---|
| `refresh` | re-run the intake handler | **intake entries only** (must declare a handler) | no |
| `warn` | mark the entry stale on read; mutate nothing | any | no |
| `drop` | delete the entry (audited) | stored leaf/nested — **not** intake (it would just re-fetch) | yes |
| `archive` | copy to `<store>/archive/<relative-path>`, then remove from the zone | stored leaf/nested | yes |

`refresh` on a non-intake entry, or `drop`/`archive` on an intake entry, is a `doctor` `lifecycle_action_invalid` error — not a silent no-op.

### 3. Destructiveness decides the execution site — lazy is the default

This is the load-bearing simplification: **an action's destructiveness determines where it runs**, dissolving the "lazy vs scheduled" question into the policy itself.

```
 non-destructive  (refresh, warn)  ──► run LAZILY on get / list
 destructive      (drop, archive)  ──► run ONLY on the tend sweep
                                        — never as a side effect of a read
```

- `get`/`list` apply `refresh` (re-pull) and `warn` (flag) inline for the entries they touch — generalizing ADR 0062's read-through from intake-only to all non-destructive lifecycle actions. A read **never** deletes.
- `tend` becomes the **destructive-only sweep**: it applies `drop`/`archive` for aged entries, and `refresh`es *cold* entries (those no read has touched). It is the exception, run on a schedule (host-owned, per ADR 0078); the common case is handled lazily on access.

The age basis unifies too: age is measured from `_meta.lifecycle_at` (set on every write and every refresh), falling back to file mtime — so `refresh` and `drop`/`archive` measure age identically instead of `last_fetched_at` vs mtime.

### 4. Collapse the verb surface (8 → 3 + `doctor`)

| Removed (public) | Replaced by |
|---|---|
| `stale`, `retainable`, `freshness` | one read verb `freshness` — reports every matched entry's verdict (`fresh`/`expired`) **and** the `on_expire` action that applies |
| `fetch`, `fetch_all` | lazy `refresh` on `get`/`list`; cold-entry refresh on `tend` |
| `retain` | `tend` (the destructive sweep) |

Final lifecycle surface: **`freshness`** (read/preview), **`get`** (lazy apply on read), **`tend`** (destructive sweep), **`doctor`** (validate policy legality). The removed names become internal use-cases that `get`/`tend` call; the MCP-catalog and CLI-registry reconciliation guards (ADR 0039) enforce the removals.

### 5. Drop the two-window archive→delete progression

`archive_after` < `expire_after` (archive at T1, hard-delete at T2) collapses to a single `ttl` per `lifecycle` policy. `on_expire: archive` copies to `archive/` and removes from the zone in one step. If archived copies themselves need pruning, that is a `lifecycle:` rule matching `archive/` — recursion, not a special case. (SPEC already hedges on the two-window semantics; this removes the ambiguity.)

## Consequences

- **One mental model, one rule block, one age concept.** "Is this entry too old, and what happens then?" is answered by reading a single `lifecycle:` block. The intake/retention asymmetry is gone.
- **The lazy/scheduled debate is dissolved, not decided.** You no longer choose lazy vs sweep globally (the A/B framing that preceded this ADR): each policy's *action* picks. Destructive work is the only thing that needs scheduling, which is the only thing that ever did.
- **`tend` gets simpler, not deleted.** ADR 0078's verb survives with its authority stance intact (runs as caller, never self-elevates), but its body stops being "compose three sub-verbs" and becomes "apply destructive policies + refresh cold entries." 0078 is marked *partially superseded* accordingly.
- **Breaking: manifest schema + verb surface.** `fetch:`/`retention:` slots and the `stale`/`retainable`/`fetch`/`fetch_all`/`retain` verbs are removed. Mitigated by: a `migrate` rewrite (`fetch:`+`retention:` → `lifecycle:`) and a `doctor` check that detects the legacy slots and prints the rewrite. This is precisely what `migrate` exists for.
- **`SPEC.md` changes materially** — the rules table (§5.11), the freshness/read-through semantics, and the verb list. Unlike ADR 0078, this decision *does* move the normative contract, so SPEC is updated when it ships.
- **Cold entries still rely on the sweep for destructive actions** — an aged leaf nobody reads is dropped only when `tend` runs. That is correct and intentional: a read must never delete, so destructive GC for untouched entries is inherently a scheduled concern. Non-destructive freshness, by contrast, now needs no schedule at all.

## Alternatives considered

- **Keep both slots; just add `tend` (status quo, ADR 0078).** Rejected as the thing being simplified: it preserves two vocabularies, three read verbs, and the lazy/sweep asymmetry, and needs a composite verb to hide the seam.
- **Unify the policy but keep all verbs as thin aliases (no surface break).** Rejected for this ADR: it delivers the single mental model but leaves five redundant public verbs projecting the same model, so the surface never actually shrinks — the documentation and catalog stay large. Given the explicit appetite for a breaking redesign, the full collapse is the point.
- **Lazy-only: evaluate everything on read, delete the sweep entirely.** Rejected: `drop`/`archive` on a `get` would make reads destructive (a `list` that deletes rows is a footgun), and cold entries would never be collected at all. Lazy is right for non-destructive actions; destructive actions need an explicit, schedulable trigger.
- **Sweep-only: no lazy path, everything via `tend`.** Rejected: it throws away ADR 0062's proven read-through refresh and makes every freshness guarantee depend on a schedule running — the asymmetry inverted, not removed.
- **Also fold generator/build staleness into `lifecycle`.** Rejected: build staleness is dependency-based (output vs sources), not age-based. One `ttl/on_expire` vocabulary cannot express "stale because a source changed." Merging them would produce a leaky abstraction; it stays on the `build` path.
