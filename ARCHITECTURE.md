# Textus architecture

```
┌─ Interface ────────────────────────────────────────────┐
│  lib/textus/cli/       CLI verbs (get, refresh, …)     │
└──────────────────────┬─────────────────────────────────┘
                       │
┌─ Application ────────▼─────────────────────────────────┐
│  lib/textus/application/                               │
│    reads/get.rb               — Reads::Get use case    │
│    refresh/worker.rb          — one refresh (IO)       │
│    refresh/orchestrator.rb    — Action → Outcome       │
│    refresh/all.rb             — batch driver           │
└──────────┬────────────────────────────┬────────────────┘
           │ uses domain                │ uses ports
┌─ Domain ─▼────────────────────────────────────────────────┐
│  lib/textus/domain/                                       │
│    action.rb                  — Return | RefreshSync |    │
│                                  RefreshTimed(budget_ms)  │
│    outcome.rb                 — Skipped|Refreshed|Detached│
│                                  |Failed                  │
│    freshness/policy.rb        — Policy(ttl_seconds,       │
│                                         on_stale,         │
│                                         sync_budget_ms)   │
│                                  .decide(verdict) → Action│
│    freshness/verdict.rb       — fresh? / stale?           │
│    freshness/evaluator.rb     — pure (Policy, env, now)   │
└──────────────────────────────────────┬────────────────────┘
                                       │ implements
┌─ Infrastructure ─────────────────────▼────────────────────┐
│  lib/textus/infra/                                        │
│    event_bus.rb               — explicit pub-sub injection│
│    clock.rb                   — injectable time           │
│    refresh/lock.rb            — per-key flock             │
│    refresh/detached.rb        — fork+detach child         │
│  lib/textus/{store,manifest,hooks}/                       │
│                               — pre-existing adapters     │
└───────────────────────────────────────────────────────────┘

   Dependency rule: arrows point DOWN. Domain has zero outbound
   imports. Application imports Domain + Infra (via ports).
```

## Read path (`store.get`)

1. CLI verb (or any caller) invokes `store.get(key, as:)`.
2. `Store#get` constructs `Reads::Get(store, orchestrator)` and calls `.call(key, as:)`.
3. `Reads::Get#call` reads the envelope from disk via `store.reader.read_raw_envelope(key)`.
4. Resolves `Manifest::Entry#policy` — a `Domain::Freshness::Policy` value.
5. `Domain::Freshness::Evaluator.call(policy, envelope, now:)` returns a `Verdict`.
6. If fresh → annotate envelope (`stale: false`, `refreshing: false`) and return.
7. Otherwise `policy.decide(verdict) → Action` (data, not behavior).
8. `Orchestrator.execute(action, key, as)` interprets the Action:
   - `Action::Return` → `Outcome::Skipped`
   - `Action::RefreshSync` → run Worker inline → `Refreshed | Failed`
   - `Action::RefreshTimed(budget_ms:)` → race Worker thread vs budget; on timeout, kill thread, fire `:refresh_detached`, fork+detach child, return `Outcome::Detached`
9. Map outcome → envelope annotations (`stale`, `refreshing`, `refresh_error`) and return.

## Refresh path (`textus refresh KEY`)

1. CLI `Verb::Refresh` calls `Textus::Refresh.call(store, key, as:)`.
2. That shim instantiates `Application::Refresh::Worker` and runs it.
3. `Worker#run`:
   - Resolves the manifest entry, looks up the `:intake` handler.
   - Publishes `:refresh_began` via the injected `Infra::EventBus`.
   - Invokes the handler under a 30s `Timeout.timeout` budget.
   - On any error: publishes `:refresh_failed`, then re-raises (or wraps in `UsageError`).
   - On success: normalizes the return shape, persists via `store.put`, publishes `:refreshed` (unless the etag is unchanged).
