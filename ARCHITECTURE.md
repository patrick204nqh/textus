# Textus architecture

```
┌─ Interface ────────────────────────────────────────────────┐
│  CLI verbs:  ctx = Composition.context(store, role:)       │
│              Composition.<use_case>(ctx).call(...)         │
└──────────────────────┬─────────────────────────────────────┘
                       │
┌─ Application ────────▼─────────────────────────────────────┐
│  Context          (per-request: store, role, correlation,  │
│                    clock, dry_run; can_read?/can_write?)   │
│  Composition      (factory module)                         │
│                                                            │
│  reads/get.rb              writes/put.rb                   │
│  refresh/worker.rb         writes/delete.rb                │
│  refresh/orchestrator.rb   writes/build.rb                 │
│  refresh/all.rb            writes/accept.rb                │
│                            writes/publish.rb               │
└──────────┬───────────────────────────────┬─────────────────┘
           │ uses domain                   │ uses ports
┌─ Domain ─▼─────────────────────────────────────────────────┐
│  Permission             ← NEW: predicate, not Action       │
│  Freshness::Policy      Freshness::Verdict                 │
│  Freshness::Evaluator   Action  Outcome                    │
└──────────────────────────────────────────┬─────────────────┘
                                           │ implements
┌─ Infrastructure ─────────────────────────▼─────────────────┐
│  Store              (pure adapter — exposes ports only)    │
│    Reader#read_envelope         Writer#write_envelope_…    │
│    AuditLog, Staleness, Validator, Mover                   │
│  Manifest           (incl. permission_for)                 │
│  Hooks::Registry    EventBus     Clock                     │
│  Refresh::Lock      Refresh::Detached                      │
│  Publisher          (file copy + sentinel)                 │
└────────────────────────────────────────────────────────────┘

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

## Write path (`store.put`)

1. CLI verb calls `ctx = Composition.context(store, role:)` then `Composition.writes_put(ctx).call(key, ...)`.
2. `Writes::Put#call` checks `ctx.can_write?(zone)` — raises `write_forbidden` if denied.
3. Delegates pure I/O to `Store::Writer#write_envelope_to_disk(key, ...)`.
4. On success, fires `:put` event via the injected `Infra::EventBus`, including `correlation_id` from the Context.

The same pattern applies to `Writes::Delete`, `Writes::Build`, `Writes::Accept`, and `Writes::Publish`: each takes a `Context`, checks permissions at the use-case layer, then delegates raw I/O to the corresponding `Store::Writer` or `Infra::Publisher` primitive.

## Refresh path (`textus refresh KEY`)

1. CLI `Verb::Refresh` calls `Textus::Refresh.call(store, key, as:)`.
2. That shim instantiates `Application::Refresh::Worker` and runs it.
3. `Worker#run`:
   - Resolves the manifest entry, looks up the `:intake` handler.
   - Publishes `:refresh_began` via the injected `Infra::EventBus`.
   - Invokes the handler under a 30s `Timeout.timeout` budget.
   - On any error: publishes `:refresh_failed`, then re-raises (or wraps in `UsageError`).
   - On success: normalizes the return shape, persists via `store.put`, publishes `:refreshed` (unless the etag is unchanged).
