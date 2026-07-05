# ADR 0089 — Ingest is system-pushed: remove `get`'s read-through and `put --fetch`

**Date:** 2026-06-05
**Status:** Accepted
**Reverses:** [ADR 0062](./0062-one-get-read-through.md) (the single read-through `get` — the read-that-writes seam it introduced is removed; `Read::Get` survives as a pure read).
**Refines:** [ADR 0087](./0087-fold-build-into-reconcile.md) (that ADR made *derived* materialization system-pushed by deleting on-demand `build`; this ADR applies the identical move to the *quarantine* lane — stop the verb/flag triggers and leave ingest to the system), [ADR 0079](./0079-unify-lifecycle-policy.md) (the unified `lifecycle:` policy stands; `on_expire: refresh` is now actioned by the reconcile sweep, not a read).
**Touches:** [ADR 0048](./0048-fetch-subsystem-three-concerns.md) (`FetchWorker`/`IntakeFetch` survive as the ingest executor driven by reconcile + hook; the `FetchOrchestrator` async/`timed_sync`/detached wrapper — only ever reachable through the read-through — is deleted along with the per-key fetch lock, `Domain::Outcome`, `Freshness::Policy`/`Verdict`, and the `:fetch_backgrounded` event), [ADR 0088](./0088-rename-quarantine-capability-fetch-to-ingest.md) (this is the capstone of the same reconcile-era sweep that renamed the capability).

> **One sentence:** a read that writes (`get`'s refresh-on-stale) and a write that transforms-via-handler (`put --fetch`) are the exact smell ADR 0087 excised for derived entries; this ADR removes **both** quarantine triggers, making ingest **purely system-pushed** — `reconcile` (scheduled sweep) and `hook run` (event push) are the only paths that pull external bytes, so `get` becomes a pure read and `put` only stores bytes.

## Context

ADR 0062 unified textus's read paths into one `Read::Get` that, by default, **refreshed a stale `on_expire: refresh` entry in-process** before returning — a read-through. ADR 0087 then took the opposite stance for *derived* entries: it deleted on-demand `build` and made materialization system-pushed (reactive on write + the reconcile sweep), on the thesis that **non-destructive projection should be pushed by the system, not pulled by an operator**. That left the two lanes inconsistent:

- **Derived** freshness: system-pushed (ADR 0087). No verb fetches a projection on demand.
- **Quarantine** freshness: pulled, two ways —
  1. `get`'s read-through refreshed a stale entry as a side effect of reading it, and
  2. `put --fetch=NAME` ran an intake handler over the stdin bytes as a side effect of writing.

Both quarantine triggers are the smell ADR 0087 named:

- A **read that writes** is surprising and expensive: a `get` could fire `:fetch_*` events → hooks → re-entrancy; spawn the orchestrator's threads/fork; contend the single-flight fetch lock; and inject network latency into any read. `Hooks::Context` even had to opt *out* of read-through to stay safe — a guard that existed only because reads fetched.
- A **write that transforms-via-handler** (`put --fetch`) overloads `put` with an ingest concern that already has a home (the `:resolve_intake` handler invoked by the sweep).

## Decision

### 1. `get` is a pure read

`Read::Get` resolves the path, reads bytes, parses the envelope, and annotates a freshness verdict. It **never** ingests and **never** mutates. The `fetch:` argument is gone from every surface (no CLI `--no-fetch`, no MCP `{fetch:false}` — there is nothing to opt out of). A stale `on_expire: refresh` entry reads back **stale** until the next `reconcile`.

### 2. `put` only stores bytes

The `--fetch=NAME` flag and its handler-over-stdin branch are removed. `put` collapses to "store the stdin JSON." Running a handler over bytes is the sweep's job, not a write flag's.

### 3. Ingest is system-pushed — reconcile + hook only

External bytes are pulled by exactly two triggers, symmetric with ADR 0087's derived model:

- **`reconcile`** (scheduled/batch) — its sweep re-pulls every stale `on_expire: refresh` intake entry via `FetchWorker` → `:resolve_intake`. This is the freshness workhorse; run it on a cron/timer.
- **`hook run`** (event) — an external event pushes ingest of specific keys through the same handler path.

The byte-pulling mechanism (`FetchWorker`/`IntakeFetch`, ADR 0048) is unchanged — it is now reached only from these two. The read-through-only machinery is deleted: `FetchOrchestrator`, the per-key fetch lock (`Ports::Fetch::Lock`) and detached fork (`Ports::Fetch::Detached`), `Domain::Outcome`, `Freshness::Policy`/`Verdict`, the `:fetch_backgrounded` event, and the doctor `fetch_locks` check (no locks are created anymore). The `Hooks::Context` read-through opt-out guard is removed — `get` is pure for everyone.

## Consequences (accepted costs)

- `textus get feeds.x` no longer transparently freshens — it is **stale-until-next-reconcile**. `pulse`/`freshness` already surface staleness; the mitigation is "run `reconcile`" (typically on a schedule).
- A freshly-declared intake entry is empty until `reconcile` runs (or a hook fires). First-population workflow: `put` the declaration, then `textus reconcile`. There is no ad-hoc "run handler X over these bytes now" (that was `put --fetch`).
- Reads become trivially safe — no read can trigger network I/O, events, threads, or lock contention. The re-entrancy/deadlock guard `Hooks::Context` carried is no longer needed.
- Breaking: the `get` `fetch` flag (`--no-fetch`/`{fetch:false}`) and `put --fetch` are removed from the verb surface; the `:fetch_backgrounded` event is gone.

## Alternatives considered

- **Keep `get`'s read-through, remove only `put --fetch`.** Rejected: the read-that-writes is the larger smell and the source of the re-entrancy guard; removing one trigger but not the other leaves the lanes inconsistent with ADR 0087.
- **Keep `FetchOrchestrator` for a future async ingest.** Rejected (YAGNI): reconcile drives `FetchWorker` synchronously; the async/`timed_sync`/detached wrapper existed only to keep a *read* from blocking. With no read-through there is no caller, and dead infrastructure is what this reconcile-era sweep exists to remove.
- **A `refresh KEY` verb to replace on-demand pull.** Rejected: `reconcile` already re-pulls by scope (`--prefix`/`--zone`), and a forced single-key recompute is the same dev-only hatch ADR 0087 declined for `build`.
