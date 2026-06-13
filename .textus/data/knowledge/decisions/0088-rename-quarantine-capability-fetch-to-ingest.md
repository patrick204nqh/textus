# ADR 0088 — Rename the quarantine capability `fetch` → `ingest`; name the verb/capability split

**Date:** 2026-06-05
**Status:** Accepted
**Refines:** [ADR 0034](./0034-unify-lane-vocabulary.md) (the `LANES` bijection it established — this ADR changes one cell, `quarantine`'s capability, and leaves the table the single source of truth), [ADR 0030](./0030-capability-based-roles.md)/[ADR 0033](./0033-complete-primitives-and-vocabulary.md) (the capability-based role model and its closed five — one member is renamed).
**Touches:** [ADR 0079](./0079-unify-lifecycle-policy.md) (the ADR that collapsed the public `fetch` *verb* into `get`'s read-through, leaving the capability orphaned of a same-named verb — the source of the confusion this ADR names), [ADR 0048](./0048-fetch-subsystem-three-concerns.md) (the byte-pulling *mechanism* — `IntakeFetch`/`FetchWorker`/`FetchOrchestrator` — keeps its fetch-flavored names; it literally fetches over a transport), [ADR 0087](./0087-fold-build-into-reconcile.md) (symmetry: that ADR made *derived* materialization system-pushed; the ingest lane is the quarantine analogue).

> **One sentence:** the quarantine lane's capability was named `fetch` — a verb-shaped name for a thing that is not a verb (the `fetch` verb was deleted in ADR 0079) and that collides with the still-living byte-pulling *mechanism* also called fetch — so this ADR renames the **capability token** `fetch` → `ingest` (a lane-flavored noun: "may originate bytes into the quarantine lane"), keeps every *mechanism* name as-is, and writes down the two-vocabulary model (verbs vs capabilities) that the collision exposed.

## Context

textus has **two overlapping vocabularies**, and until now nothing documented the split — so the same word, `fetch`, named two different things at two different layers, and a third (a deleted verb) haunted the first two.

- **Verbs** are typed, caller-initiated actions in the dispatcher registry (`put`, `get`, `propose`, `accept`, `reconcile`, …). A caller speaks a verb.
- **Capabilities** are the five lane-gates that authorize *originating bytes* into a zone-kind — a total bijection in `Schema::LANES` (ADR 0034): `canon→author`, `workspace→keep`, `quarantine→fetch`, `queue→propose`, `derived→reconcile`. A role *holds* a capability.

Two capabilities (`propose`, `reconcile`) happen to share a name with a verb; three (`author`, `keep`, `fetch`) are capabilities only. That overlap is fine — except for `fetch`, where three things tangled:

1. **The capability** `fetch` — "may write the quarantine lane."
2. **The mechanism** — `IntakeFetch` / `FetchWorker` / `FetchOrchestrator` / the `:fetch_*` events — the collaborator that actually pulls bytes over a transport (ADR 0048).
3. **A deleted verb** — `fetch` *was* a public verb until ADR 0079 collapsed it into `get`'s read-through. The verb is gone; the capability kept its name.

The result is the recurring question *"is `fetch` redundant — doesn't `reconcile` do it all?"* It is **not** redundant: `fetch`/ingest gates **quarantine** writes; `reconcile` gates **derived** writes. They are different lanes. But the verb-shaped name on a capability whose verb no longer exists made the lane look like a leftover. The capability needed a name that reads as *a lane it authorizes*, not *an action a caller takes*.

## Decision

### 1. Rename the capability token `fetch` → `ingest`

`ingest` is a lane-flavored noun: holding it means "may originate bytes into the quarantine lane." The rename is to the **capability token only**, and it flows from the one source of truth — `Schema::LANES` `"quarantine" => "ingest"`. `CAPABILITIES` and `KIND_REQUIRES_VERB` derive from `LANES`, so no other constant changes. The default role map becomes `automation → [ingest, reconcile]`; the `init` scaffold and the guard floor (`base_guards`) and the capability-gate call sites (`FetchWorker`'s `for(:ingest, …)`, the detached port's `actor_for("ingest")`) follow.

### 2. Keep every *mechanism* name

The byte-pulling machinery is **not** renamed — it literally fetches over a transport, and ADR 0048's three-concern split stands: `FetchWorker`, `IntakeFetch`, `FetchOrchestrator`, the `:fetch_started`/`:fetch_failed`/`:fetch_backgrounded` events, the per-key fetch lock. The capability answers *"who may originate quarantine bytes"*; the mechanism answers *"how the bytes are pulled."* They are different layers and may legitimately carry different names. This ADR makes that split explicit so a future reader does not "finish the rename" by renaming the mechanism too.

### 3. Breaking — no shim

Every manifest's `roles: … can:` list using `fetch` must change to `ingest`; the default role map changes. There is **no migration shim** (textus is pre-1.0 and breaking changes are accepted at ADR cadence). A manifest still declaring `can: [fetch]` is rejected at load like any unknown capability, but with a **pointed hint**: `unknown capability 'fetch' … — the quarantine capability was renamed to 'ingest' (ADR 0088)`.

## Consequences

- The capability vocabulary now reads cleanly as five lane-authorizations — `author`, `keep`, `ingest`, `propose`, `reconcile` — none of which is a dangling former-verb.
- The verb/capability model is written down (here and in `reference/zones.md`), so the "is fetch redundant" question has a durable answer.
- Mechanism and capability names diverge by design; the `Ports::Fetch` namespace and `FetchWorker` keep fetch in their names while the gate they consult is `ingest`. A one-line comment at each capability-gate call site points back here.
- Breaking: every downstream manifest with a `fetch`-holding role must update. The load-time hint makes the migration mechanical.

## Alternatives considered

- **Rename the mechanism too (`IntakeIngest`, `IngestWorker`).** Rejected: the mechanism *fetches* — renaming it buys nothing and churns ADR 0048's stable subsystem. The confusion was at the capability layer, not the mechanism layer.
- **Keep `fetch`, document the overlap only.** Rejected: a verb-shaped name on a verb-less capability is the defect; documentation around a misleading name is a weaker fix than the right name.
- **A migration shim accepting `fetch` as an alias.** Rejected: pre-1.0, breaking is cheaper than a permanent alias, and the load-time hint already makes the break self-explaining.
