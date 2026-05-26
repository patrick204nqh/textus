# Textus architecture

```
┌─ Interface ────────────────────────────────────────────────┐
│  CLI verbs:  ops = Operations.for(store, role:)            │
│              ops.<name>(...)   # flat methods, one per use │
│                                # case (put/get/refresh/…)  │
└──────────────────────┬─────────────────────────────────────┘
                       │
┌─ Application ────────▼─────────────────────────────────────┐
│  Context          (per-request: store, role, correlation,  │
│                    clock, dry_run; can_read?/can_write?;   │
│                    authorize_read!/authorize_write!; bus;  │
│                    Context.system(store) for infra path)   │
│  Operations       (flat facade — memoized use cases)       │
│                                                            │
│  reads/{get,list,where,uid,schema_envelope,deps,rdeps,     │
│         published,stale,validate_all,freshness,audit,      │
│         blame,policy_explain}.rb                           │
│  writes/{put,delete,mv,accept,reject,build,publish}.rb     │
│  refresh/{worker,orchestrator,all}.rb                      │
└──────────┬───────────────────────────────┬─────────────────┘
           │ uses domain                   │ uses ports
┌─ Domain ─▼─────────────────────────────────────────────────┐
│  Permission         (write/read predicate per zone)        │
│  Freshness::{Policy,Verdict,Evaluator}                     │
│  Action  Outcome                                           │
│  Policy::Promotion (proposal accept gates)                 │
└──────────────────────────────────────────┬─────────────────┘
                                           │ implements
┌─ Infrastructure ─────────────────────────▼─────────────────┐
│  Store              (pure adapter — filesystem + hooks)    │
│    Reader#{get,list,where,uid,deps,rdeps,published,        │
│            stale,validate_all,read_raw_envelope,           │
│            schema_envelope}                                │
│    Writer#{write_envelope_to_disk,delete_envelope_from_    │
│            disk,existing_uid_for,ensure_uid,               │
│            enforce_name_match!,serialize_for_put}          │
│    AuditLog, Staleness, Validator, Sentinel                │
│  Manifest           (Entry, Rules, Schema, permission_for) │
│  Hooks::{Registry,Dispatcher,Loader,Dsl,Builtin}           │
│  Infra::{Publisher,EventBus,Clock,Refresh::Lock,           │
│          Refresh::Detached}                                │
│  Entry::{Markdown,Json,Yaml,Text}  (format strategies)     │
└────────────────────────────────────────────────────────────┘

   Dependency rule: arrows point DOWN. Domain has zero outbound
   imports. Application imports Domain + Infra (via ports).
```

## Read path (`ops.get(key)`)

1. CLI verb (or any external caller) builds `ops = Textus::Operations.for(store, role:)` then `ops.get(key)`.
2. `Operations#get` delegates to a memoized `Application::Reads::Get.new(ctx:, orchestrator:)` instance bound to the request context.
3. `Reads::Get#call(key)` reads the bare envelope from disk via `@ctx.store.reader.read_raw_envelope(key)`.
4. Resolves the manifest rules for the key via `@ctx.store.manifest.rules_for(key)` and extracts the `refresh` policy.
5. `Domain::Freshness::Evaluator.call(policy, envelope, now:)` returns a `Verdict`.
6. If fresh → annotate envelope (`stale: false`, `refreshing: false`) and return.
7. Otherwise `policy.decide(verdict) → Action` (data, not behavior).
8. `Refresh::Orchestrator#execute(action, key:)` interprets the `Action`:
   - `Action::Return` → `Outcome::Skipped`
   - `Action::RefreshSync` → run `Refresh::Worker` inline → `Refreshed | Failed`
   - `Action::RefreshTimed(budget_ms:)` → race Worker thread vs budget; on timeout, kill thread, fire `:refresh_backgrounded`, fork+detach child, return `Outcome::Detached`
9. Map outcome → envelope annotations (`stale`, `refreshing`, `refresh_error`) and return.

## Write path (`ops.put(key, ...)`)

1. CLI verb calls `ops = Operations.for(store, role:)` then `ops.put(key, meta:, body:, content:, if_etag:, suppress_events:)`.
2. `Writes::Put#call` validates the key, resolves the manifest entry, and calls `@ctx.authorize_write!(mentry)` — raises `WriteForbidden` (carrying the zone's writers list) if denied.
3. Delegates raw I/O to `Store::Writer#write_envelope_to_disk(key, mentry:, payload:, ctx:, if_etag:)`, which:
   - Resolves the path via `Manifest#resolve`
   - Serializes via `Entry.for_format(...).serialize(...)`
   - Validates against schema if declared
   - Etag-checks if `if_etag:` provided (raises `EtagMismatch` on conflict)
   - Writes to disk via `File.binwrite`
   - Appends the audit row
4. On success, publishes `:entry_put` via `@ctx.bus`, with `store: @ctx.with_role(@ctx.role)`, `key:`, `envelope:`, `correlation_id:`.

The same pattern applies to `Writes::{Delete,Mv,Accept,Reject,Build,Publish}`: each takes a `Context`, calls `ctx.authorize_write!` (Mv authorizes both source and destination zones), delegates raw I/O to `Store::Writer` or `Infra::Publisher`, and fires the matching event through `ctx.bus`.

## Refresh path (`ops.refresh(key)`)

1. CLI `Verb::Refresh` builds `ops = Operations.for(store, role: "runner")` then calls `ops.refresh(key)`.
2. `Refresh::Worker#run(key)`:
   - Resolves the manifest entry, looks up the intake handler via `store.registry.rpc_callable(:resolve_intake, mentry.intake_handler)`.
   - Publishes `:refresh_started` via the bus.
   - Invokes the handler under a 30s `Timeout.timeout` budget.
   - On any error: publishes `:refresh_failed`, then re-raises (or wraps in `UsageError`).
   - On success: normalizes the return shape, persists via `Application::Writes::Put` with `suppress_events: true`, publishes `:entry_refreshed` (unless the etag is unchanged).
3. The batch entry point is `Application::Refresh::All.call(ctx, prefix:, zone:)` which lists stale entries via `Application::Reads::Stale`, then runs `Worker#run` per entry, returning a summary envelope `{ refreshed: [...], failed: [...], skipped: [...] }`.

## Infrastructure-side hook dispatch

The hook bus needs an `Application::Context` even when fired from inside `Store#initialize` or other infrastructure-side code paths. `Application::Context.system(store)` returns a Context with `role: "human"` and a fresh correlation_id, designed for exactly this case — see `lib/textus/store.rb` (the `:store_loaded` publish), `lib/textus/doctor.rb` (the doctor-check view), and `lib/textus/projection.rb` (the transform_rows view).
