# ADR 0078 — `tend`: a composite upkeep pass so the cleanup lifecycle can run unattended

**Date:** 2026-06-04
**Status:** Accepted
**Refines:** [ADR 0069](./0069-single-path-lifecycle.md) (the single-path content lifecycle — `tend` adds no new transition; it composes existing ones into one schedulable pass).
**Touches:** [ADR 0076](./0076-build-gates-by-capability-actor-surface-to-mcp.md) (`build` self-elevates because it only projects canon; this ADR deliberately does **not** self-elevate, because `tend` performs authority-bearing writes — the contrast is the whole authority decision here), [ADR 0071](./0071-dry-run-is-opt-in.md) (`tend` honours the opt-in `--dry-run` so an operator can preview a pass before it deletes or fetches), [ADR 0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) (the safety framing for bulk, write-bearing operations).

> **One sentence:** the cleanup and intake-refresh lifecycle is *clean by construction* but *manual by trigger* — `fetch_all` (refresh stale intake), `retain` (apply retention), and `doctor` (health report) each exist as separate verbs that a human must remember to run, so stale `quarantine` entries persist until someone sweeps — this ADR adds a single composite `tend` verb that runs those existing passes in order, honours `--dry-run`, and runs as the *caller's* role (each sub-op stays gated, never self-elevated), so a host scheduler (cron, an agent routine) can keep a store tidy unattended without textus growing an in-process daemon.

## Context

textus has three lifecycles, and their cleanup coverage is uneven:

- **Content** (`put → propose → accept/reject → delete`) is clean *by construction*: `accept`/`reject` delete the drained proposal, `delete` prunes empty parent dirs, UIDs survive renames. Nothing rots.
- **Runtime state** (`.run/`) is bounded: the audit log rotates by size, sentinels are rewritten idempotently on every `build`, cursors are disposable. All git-ignored, all regenerable.
- **Intake / staleness** (`quarantine`) is the weak link. The primitives all exist — `Read::Retainable` reports what retention would expire/archive, `Write::RetentionSweep` (`retain`) applies it, `Write::FetchAll` (`fetch_all`) refreshes stale intake, `Read::Doctor` reports drift — but **every one of them is a verb a human must invoke.** Nothing schedules them. A stale `feeds.*` entry past its TTL persists indefinitely until an operator remembers to run `retain`.

So the gap is not correctness — the GC is safe and deliberate, which is *right* for a git-committed substrate where deletions should be reviewable. The gap is **autonomy**: keeping a store tidy currently depends on a human running three separate verbs in the right order, and that does not happen reliably.

**The tension.** The obvious fix — a background sweeper inside textus — is off-thesis. textus deliberately executes nothing: it has no in-process runner (this is exactly why `External` entries are a *non-build* path, ADR 0076 / v0.47.1 — textus only tracks their staleness rather than running their generator). Adding a daemon would betray that. The upkeep cadence belongs to the **host** (cron, a Claude Code scheduled routine), not to textus. What's missing is not a scheduler but a single *verb worth scheduling*.

## Decision

1. **Add a composite `tend` maintenance verb that runs the existing passes in a fixed, safe order:** `fetch_all` (refresh stale intake) → `retain` (apply retention to what's now expired) → `doctor` (report residual health). It introduces **no new storage semantics** — it constructs and invokes the existing `Write::FetchAll`, `Write::RetentionSweep`, and `Read::Doctor` use-cases and aggregates their results into one report (`{ fetched:, expired:, archived:, failed:, health: }`).

2. **`tend` runs as the caller's role; it does *not* self-elevate.** This is the load-bearing contrast with `build` (ADR 0076). `build` self-elevates safely because it only writes deterministic projections of canon — triggering it grants no authority over content. `tend` is different: it *deletes* (via `retain`) and *writes* (via `fetch_all`), which are authority-bearing. So `tend` stays gated per sub-op, exactly as those verbs already are — rows whose zone the caller's role cannot write surface in `failed` rather than aborting the pass (the behaviour `RetentionSweep` already has). Scheduling `tend` as `automation` therefore grants precisely automation's capabilities (fetch + retain in `quarantine`) and nothing more. The authority surface is unchanged.

3. **`tend` honours the opt-in `--dry-run` (ADR 0071).** `tend --dry-run` reports what each sub-pass *would* refresh, expire, and archive without applying anything — the preview an operator wants before wiring it to a schedule, and the safe default to run by hand the first time.

4. **`tend` accepts the same scoping args as its components** — `--prefix` and `--zone` — and threads them through, so a schedule can tend one zone (e.g. only `feeds.*`) on its own cadence.

5. **Scheduling lives in the host, and is documented, not built.** A how-to shows wiring `tend` to cron and to a Claude Code routine. textus ships the verb; the host owns the timer. No daemon, no in-process loop.

`tend` surfaces to both `:cli` and `:mcp`: the CLI form is what a cron line calls; the MCP form lets an agent run upkeep in-conversation over the same connection it already uses for the edit→accept→build loop (ADR 0076).

## Consequences

- **The intake/staleness lifecycle gains an autonomous trigger without a new mechanism.** A single scheduled `tend` keeps a store tidy; the §weak-link gap closes by *composition*, not by new storage primitives or new authority.
- **One verb to remember instead of three, in a known-safe order.** `fetch_all` before `retain` means retention acts on freshly-evaluated staleness, not stale staleness; `doctor` last reports what (if anything) the pass couldn't resolve.
- **The authority surface does not widen.** Because `tend` runs as the caller and each sub-op stays gated, there is no new way to write content — `tend` can do exactly what its caller's role could already do by running the three verbs by hand.
- **textus still executes nothing on its own.** The daemon temptation is declined; the cadence is the host's. This keeps `tend` consistent with the `External` non-build stance — textus is invoked, it does not invoke itself.
- **A partially-failing pass is observable, not fatal.** `failed` rows (e.g. a zone the scheduled role can't write) surface in the report and in `doctor`'s output rather than silently aborting upkeep — the operator sees the gap on the next run.

## Alternatives considered

- **Leave the three verbs separate (status quo).** Rejected: this *is* the gap. Manual, multi-verb upkeep does not happen reliably, so stale `quarantine` entries accumulate until noticed — the one lifecycle that doesn't self-clean.
- **A background sweeper / daemon inside textus.** Rejected: textus has no in-process runner by design (the same reason `External` entries are a non-build path). Owning a timer would couple textus to a process lifecycle it deliberately avoids. The host schedules; textus supplies the verb.
- **Self-elevate `tend` like `build` (ADR 0076), so it always runs at full authority.** Rejected: `build` is safe to self-elevate *only because* it writes deterministic projections of canon. `tend` deletes and fetches — authority-bearing writes — so it must stay gated as the caller's role. Self-elevation here would let scheduling a low-authority role perform high-authority deletes, which is exactly the surface the capability model exists to prevent.
- **Fold `migrate` / `zone_mv` into `tend` too.** Rejected: those are one-shot, high-blast-radius *structural* operations, not periodic upkeep. They run when a human evolves the schema or renames a zone — the wrong cadence and the wrong risk profile for an unattended pass. `tend` stays scoped to the recurring, low-risk passes.
