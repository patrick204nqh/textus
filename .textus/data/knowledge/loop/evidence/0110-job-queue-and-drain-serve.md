# ADR 0110 — job queue execution model; `reconcile` → `drain`/`serve`; async-only materialize

**Date:** 2026-06-08
**Status:** Accepted
**Supersedes:** [ADR 0087](./0087-fold-build-into-reconcile.md) (its in-process `AsyncRunner` + per-entry `source.on_write: sync|async` knob — materialization is now async-only through a durable queue) and the inline-engine framing of [ADR 0093](./0093-source-retention-over-one-reconcile-engine.md) (`reconcile` is no longer an inline two-phase pass; it is seed-jobs + drain-the-queue, exposed as `drain`).

> **One sentence:** convergence becomes a durable, file-backed **job queue** drained by a worker — a canon write enqueues a `materialize` job instead of spawning an in-process thread, the `reconcile` verb is hard-renamed to **`drain`** (converge-and-exit) + **`serve`** (the daemon that also schedules TTL re-pull/sweep), materialization is **async-only** (the `on_write` knob is deleted), and per-key produce failures surface as `:produce_failed` events; the `reconcile` *capability/lane* token is kept.

## Context

ADR 0087 folded `build` into `reconcile` and made materialization system-pushed:
a canon write spawned a tracked in-process thread (`Produce::Engine::AsyncRunner`)
to rebuild the written key's derived dependents, with a per-entry
`source.on_write: sync|async` knob choosing inline-under-lock vs deferred. That
worked but had three weaknesses: (1) deferred work lived only in memory — a
crash lost it, and there was no inspection/retry surface; (2) freshness for
deletions/renames was never reactive (ADR 0087's own as-shipped note — the events
fired but nothing acted on them); (3) the `sync`/`async` knob was per-entry
configuration guarding an intra-session window that the commit/CI gate already
re-guards.

## Decision

**(a) Everything is a job; a file-backed queue is the only deferral.** A generic
substrate — `Ports::Queue` (a file adapter under `.run/queue/{ready,leased,done,
failed}`, claiming via atomic `rename(2)`, leases reclaimed on crash),
`Domain::Jobs::{Job,Registry}`, and `Maintenance::Worker` (single-pass `drain`
+ an N-thread `drain_pool` primitive) — runs a closed allow-list of job types.
Convergence is its first client: `materialize`/`re-pull` wrap `Produce::Engine`,
`sweep` wraps the extracted `Retention::Apply`. Delivery is at-least-once; handlers
are idempotent (ADR 0070). The queue is plain files in the repo's runtime dir —
no external service ("survives the vendor").

**(b) `reconcile` → `drain` (converge-and-exit) + `serve` (daemon).** `drain`
seeds the full convergence set (mirroring the old `produce_scope`) and runs the
worker to empty, exiting non-zero on dead-letter — what CI runs and the manual
backstop. `serve` is the same loop, never exiting, with a `Scheduler` that seeds
TTL re-pull + sweep each tick. `jobs` inspects/retries/purges the queue. The
verb is **hard-renamed** (no alias); the **`reconcile` capability/lane token is
kept** (machine-zone write authority, `actor_for("reconcile")`) to bound blast
radius — only the verb/CLI/MCP/quickstart surface and the CI no-op gate move to
`drain`.

**(c) Async-only materialize.** The write subscriber enqueues a `materialize`
job (stamped `automation`) for each producible dependent — one path, no `sync`
branch, no in-process thread. The `source.on_write` knob is deleted from the
schema. Freshness is re-homed to `drain` (at the commit/CI gate) and `serve`
(continuous). Because `key_delete`/`key_mv` fire `:entry_deleted`/`:entry_renamed`
(not `:entry_written`), the subscriber now listens on all three — **closing the
ADR 0087 deletion/rename gap.**

**(d) Authority is frozen at enqueue.** A job carries `enqueued_by`; the worker
runs the handler as that role. Produce self-elevates to `automation` (pure);
destructive `sweep` runs as the caller (ADR 0079/0093 — destructiveness decides
authority). No escalation via the queue. Per-key produce failures (which
`Engine#call` isolates into its result rather than raising) are re-published as
`:produce_failed` events by the materialize handler — the worker discards the
return, so the handler surfaces them.

## Consequences

- **Drain is single-pass (serial), not pooled.** `Produce::Engine.converge`
  self-acquires the non-reentrant build lock; a concurrent pool would make
  all-but-one produce job hit `BuildInProgress` and skip. A held lock during
  drain is a graceful **soft-miss** (exit 0), replacing the old "second
  concurrent pass exits 75". `drain_pool` stays a tested primitive for a future
  lock-coordinated phase.
- **The `serve` daemon is a process, not an agent command** — omitted from the
  boot catalog and from contract-spec's run-every-verb guard (it blocks forever).
- **A write with no running worker leaves jobs in `ready/`** until a `drain` or
  `serve`. This is the intended async-only trade — the commit/CI `drain`-no-op
  gate (renamed from `reconcile`-no-op) is the freshness backstop.
- The general `enqueue` surface (callers pushing registered job types) is a
  follow-up (Phase 5), bounded by the same closed allow-list.

No `SPEC.md` change (repo-local execution machinery). Breaking: the `reconcile`
verb/CLI/MCP tool is gone (`drain`/`serve`/`jobs` replace it) and the
`source.on_write` manifest key is removed.
