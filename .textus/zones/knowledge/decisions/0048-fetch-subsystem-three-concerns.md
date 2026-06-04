# ADR 0048 — Fetch subsystem: separate intake invocation, deadline/async policy, and lifecycle events

**Date:** 2026-06-02
**Status:** Accepted (ships 0.41.0)
**Touches:** [ADR 0024](./0024-domain-purity-ports.md) (extends the "no raw FS in the application layer" boundary to the fetch path — see Decision 4), [ADR 0022](./0022-container-call-dispatcher.md) (use cases on `(container:, call:)`), [ADR 0026](./0026-use-case-construction-seams.md) (named constructors for the new kernel seam), [ADR 0027](./0027-hook-signature-and-mcp-policy.md) (`:resolve_intake` handlers declare `caps:` — Decision 1 makes that `caps` uniform), [ADR 0044](./0044-system-actors-resolved-by-capability.md) (detached fork runs as `actor_for("fetch")`).

> **One sentence:** the fetch path braids three concerns — *invoke the intake handler*, *enforce a deadline / run async*, and *emit lifecycle events* — through four files, and implements the handler-invocation-with-timeout concern **twice with divergent contracts**; this ADR gives each concern exactly one home.

## Context

A `fetch` runs a manifest-declared intake handler to refresh a quarantine entry. Today the work is spread across four collaborators:

| File | Role today |
|---|---|
| `lib/textus/write/intake_fetch.rb` (`IntakeFetch`, module) | `invoke(rpc:, handler:, config:, args:, label:, timeout:)` — wraps `rpc.invoke(:resolve_intake, …, caps: nil)` in `Timeout.timeout`, maps `Timeout::Error → UsageError`. Used by `put --fetch` (`cli/verb/put.rb:20`) and `hook run` (`cli/verb/hook_run.rb:32`). |
| `lib/textus/write/fetch_worker.rb` (`FetchWorker`, verb `:fetch`) | The full single-entry fetch: resolve entry → publish `:fetch_started` → `call_intake` (its **own** `Timeout.timeout` over `rpc.invoke(:resolve_intake, …, caps: @container)`) → normalize → guard → persist via `Writer` → publish `:entry_fetched`. |
| `lib/textus/write/fetch_orchestrator.rb` (`FetchOrchestrator`, collaborator) | Maps a `Domain::Action` to sync / timed / detached execution: `Thread.new` + `join(budget)`, single-flight `Ports::Fetch::Lock` probe, `Ports::Fetch::Detached.spawn`, publishes `:fetch_backgrounded`. Constructed by `Read::GetOrFetch` (`read/get_or_fetch.rb:29-34`). |
| `lib/textus/write/fetch_all.rb` (`FetchAll`, verb) | Lists stale rows via `Read::Stale`, loops `worker.run(key)`, classifies fetched/failed/skipped. |

The call graph has two distinct entry shapes that **both** invoke the same `:resolve_intake` hook:

```
:fetch verb ─────────────▶ FetchWorker#run ──▶ call_intake ─┐
get_or_fetch ─▶ Orchestrator#execute ─(thread)─▶ worker.run ┘ rpc.invoke(:resolve_intake, caps: @container)
                                                              under Timeout #1  (per-key, fires :fetch_failed)

put --fetch ─┐
hook run ────┴──────────▶ IntakeFetch.invoke ──────────────▶ rpc.invoke(:resolve_intake, caps: nil)
                                                              under Timeout #2  (fixed 30s, no events)
```

Three concrete defects fall out of this tangle:

1. **The handler-invocation-with-timeout concern is implemented twice, with divergent contracts.** `IntakeFetch.invoke` (`intake_fetch.rb:15-20`) and `FetchWorker#call_intake` (`fetch_worker.rb:82-103`) each open their own `Timeout.timeout` block and each map `Timeout::Error → UsageError`. Two homes for one rule; a change to timeout semantics has to be made in two places or it drifts.

2. **`caps:` is non-uniform for one hook.** The same `:resolve_intake` handler receives `caps: nil` on the `put --fetch` / `hook run` path (`intake_fetch.rb:16`) but `caps: @container` on the `:fetch` / `get_or_fetch` path (`fetch_worker.rb:85`). A handler that reads `caps.manifest` (the documented `caps:` contract, ADR 0027) works under one entry point and `NoMethodError`s under the other. The hook contract is supposed to be one shape.

3. **The application layer touches the filesystem raw, bypassing the port.** `FetchWorker#run` computes the before-change etag with `File.exist?(path)` + `Etag.for_file(path)` (`fetch_worker.rb:38`) instead of `container.file_store.exists?` / `etag`. This is the *only* spot in the 39 application use cases that reaches past the `FileStore` port to `File`/`Etag` directly — a quiet breach of the ADR 0024 boundary (which the `domain_purity_spec` enforces for `domain/` but nothing enforces for `read/` `write/`).

Beyond the defects, the **conceptual** problem: `FetchWorker` mixes *what a fetch is* (resolve → invoke → normalize → guard → persist) with *when/how it runs* (timeout) and *what it announces* (events); `FetchOrchestrator` owns the rest of *when/how it runs* (threads, budget, single-flight) plus one stray event (`:fetch_backgrounded`). The async/deadline concern has two part-owners and the event vocabulary has two emit sites with two separately-derived `hook_context`s (`fetch_worker.rb:68-69`, `fetch_orchestrator.rb:86`).

## Decision (proposed)

Re-layer the subsystem into three concerns, each with one home. **No public verb, no wire contract, and no manifest key changes** — `:fetch`, `:fetch_all`, `get_or_fetch`, `put --fetch`, `hook run`, and every hook event keep their current behaviour. This is an internal seam change.

1. **One intake-invocation kernel owns "call the handler under a deadline."** Collapse `IntakeFetch.invoke` and `FetchWorker#call_intake` into a single seam (`IntakeFetch`, kept as the name) that is the *only* code that opens `Timeout.timeout` around `rpc.invoke(:resolve_intake, …)`. It:
   - always passes `caps: <Container>` (fixing defect 2 — `put --fetch` / `hook run` construct or thread through a `Container` like every other use case per ADR 0022; the `caps: nil` path is deleted);
   - takes the timeout as an explicit argument so the per-key source (`FetchWorker`'s `rule.fetch.fetch_timeout_seconds`, `fetch_worker.rb:72-74`) and the default (`FETCH_TIMEOUT_SECONDS`) are decided by the *caller*, not duplicated in the kernel;
   - fires **no events** — keeping it event-free is what lets `put --fetch` / `hook run` reuse it without emitting `:fetch_started` (they never have).

   This removes the second `Timeout.timeout` (defect 1): there is now exactly one.

2. **`FetchWorker` becomes pure synchronous fetch semantics.** Its `#run` is: resolve entry → `IntakeFetch` kernel → `normalize_action_result` → `GuardFactory.for(:fetch, key).check!` → `Writer#put`. No `Thread`, no budget, no `Timeout` of its own (it passes the per-key timeout *into* the kernel). It is callable and fully testable as a synchronous unit, and it is exactly what runs as the `:fetch` verb and inside the orchestrator's threads and the detached fork (`Detached.spawn` → `store.as(role).fetch(key)`, `ports/fetch/detached.rb`).

3. **`FetchOrchestrator` owns *all* async/deadline-budget policy, and nothing else.** It stays the single place that knows `Thread`, `join(budget_ms)`, the single-flight `Ports::Fetch::Lock` probe, `Ports::Fetch::Detached`, and the `FetchSync`/`FetchTimed`/`Return` → outcome mapping (`fetch_orchestrator.rb:15-95`). The distinction held crisp by this ADR: the **kernel's timeout** is "the handler call must not hang" (a property of the risky external call, applies to every path); the **orchestrator's budget** is "this interactive read won't wait longer than `budget_ms` before backgrounding" (a property of the *timed/detached* action only). They are different deadlines and now live in different layers instead of both inside the fetch path.

4. **The before-change etag read goes through the `FileStore` port.** Replace `File.exist?(path)` + `Etag.for_file(path)` (`fetch_worker.rb:38`) with `container.file_store.exists?(path)` / `container.file_store.etag(path)`. This closes defect 3 and extends the ADR 0024 boundary to the fetch use case. To keep it enforced, the existing `domain_purity_spec` style grep guard is widened (or a sibling spec added) so that `read/` and `write/` may not reference `File.`/`Dir.`/`Etag.for_file` except for pure path math — making the boundary a red test, not a convention (consistent with ADR 0037/0039 "derive-or-guard").

5. **Lifecycle events fire from one observation seam wrapping the synchronous fetch.** `:fetch_started`, `:fetch_failed`, `:entry_fetched` (today interleaved through `FetchWorker`, `fetch_worker.rb:78,91-101,123`) and `:fetch_backgrounded` (today in the orchestrator, `fetch_orchestrator.rb:87`) are emitted from a single point that observes the synchronous fetch and the async decision — one derived `hook_context`, one place that knows the fetch event vocabulary. The exact mechanism (a thin emitter object the worker/orchestrator call, vs. an event-wrapping decorator around the worker) is an implementation choice for the plan; the invariant this ADR fixes is *one emit seam, one context derivation*, not two.

## Consequences

- **Defects 1–3 are eliminated and guarded.** One `Timeout` home, one uniform `caps:` for `:resolve_intake`, and the last raw-FS access in the application layer is routed through the port — with a widened grep spec so `write/` can't regress (Decision 4).
- **The hook contract for `:resolve_intake` becomes honestly uniform.** A handler may rely on `caps.manifest` / `caps.events` regardless of whether it was reached via `fetch`, `put --fetch`, or `hook run`. This removes a latent footgun that ADR 0027's "one hook shape" intended to prevent but the second invocation path quietly violated.
- **`FetchWorker` gains a clean unit-test seam.** With timeout and async lifted out, the worker is a deterministic synchronous function of `(container, call, key)`; the thread/budget/fork behaviour is tested only against the orchestrator (where `spec/write/fetch_orchestrator_cooperative_spec.rb` and `fetch_orchestrator_spec.rb` already live).
- **No `textus/N` wire change; no `SPEC.md` change.** Per the `adr` runbook step 4, this decision touches no normative contract — verbs, events, manifest keys, and outputs are unchanged. The `CHANGELOG` entry at ship time is an internal-refactor note.
- **`put --fetch` and `hook run` must now build a `Container`.** Today they call `IntakeFetch.invoke` with `caps: nil` from the CLI layer; under Decision 1 they thread a `Container` through (these two CLI verbs already hold a `store`, so `store.container` is in reach). This is the one caller-side cost, and it converges these two paths onto the same construction story as every Dispatcher verb (ADR 0022/0026). It also relates to the `cli/verb/hook_run.rb` cleanup flagged in the audit (the dead `Role.resolve`, `hook_run.rb:29`) — folded in here since the file is touched anyway.
- **Migration is mechanical and stepwise.** Decisions 1, 4, and the `hook_run` tidy are small, independently shippable, and reduce risk before the larger 2/3/5 re-layering. The plan sequences them so the suite stays green at each step.

## Alternatives considered

- **Leave it; fix only the three defects.** Tempting — defects 1–3 are each a few lines and deliver most of the *correctness* value. Rejected as the *whole* answer because the defects are symptoms: the duplicated timeout exists *because* there was no shared kernel; the split events exist *because* the worker owns both semantics and announcement. Fixing only the symptoms leaves the next contributor to re-introduce a third invocation path. But accepted as the *first phase* — Decisions 1 & 4 ship first (see Consequences, and the plan).
- **Fold `FetchOrchestrator` into `FetchWorker`.** Rejected: it merges the two concerns this ADR is separating. The orchestrator's async/budget/single-flight policy is genuinely distinct from "run one fetch," and `Read::GetOrFetch` wants the orchestrator without being the `:fetch` verb. One class would re-tangle what Decisions 2/3 untangle.
- **Make events a pub-sub side effect of `Writer#put` instead of an explicit emit seam.** Rejected: `:fetch_started`/`:fetch_failed` have no `Writer` call to hang off (the failure path never persists), and `Writer` deliberately owns only the persist+audit invariant (ADR 0017). Fetch lifecycle events are a fetch concern, not a write concern; they belong at the fetch seam (Decision 5), not smuggled into the writer.
- **Keep `caps: nil` on the `put --fetch` / `hook run` path and document "no caps there."** Rejected: a hook contract that is conditionally `nil` depending on which transport reached it is exactly the kind of implicit, position-dependent behaviour the unified-guard / one-hook-shape line of ADRs (0027, 0031) exists to remove. Uniform `caps:` is cheap (both callers hold a store) and removes a real `NoMethodError` cliff.
- **Move the kernel's timeout up into the orchestrator too (one deadline to rule them all).** Rejected: it conflates "the external handler must not hang" (applies to *every* fetch, including the synchronous `:fetch` verb and `put --fetch`, neither of which goes through the orchestrator) with "this interactive read won't block past `budget_ms`" (a `FetchTimed`-only policy). They are different deadlines with different scopes; collapsing them would force `put --fetch` to drag in the orchestrator or lose its hang-protection.

## Open questions

- **Q1 — does the kernel belong under `write/` at all?** Invoking a `:resolve_intake` handler and normalizing its result is arguably a `ports`-adjacent concern (it brokers an external call), not a write use case. Deferred: keeping it as `Write::IntakeFetch` minimizes churn and the plan can relocate it later if a second non-write consumer appears.
- **Q2 — should `:fetch_started` fire for `put --fetch`?** Today it does not (that path uses the event-free `IntakeFetch`). Decision 1 preserves that (kernel is event-free; only `FetchWorker` wraps with events). If we later decide an inline `put --fetch` *should* announce a fetch, that is a deliberate event-vocabulary change with its own note — not silently introduced by this refactor.
- **Q3 — widen the purity guard to all of `lib/textus/` non-port code?** Decision 4 widens it to `read/` `write/`. The `maintenance/` and `builder/` paths may have their own justified raw-FS use (e.g. `Materializer`); cataloguing those is out of scope here but worth a follow-up so the boundary spec is complete rather than fetch-shaped.
