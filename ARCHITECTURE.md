# Textus architecture

```
┌─ Interface ────────────────────────────────────────────────┐
│  CLI verbs:  ops = Operations.for(store, role:)            │
│              ops.<name>(...)   # flat methods, one per use │
│                                # case (put/get/refresh/…)  │
│                                                            │
│  Or, for embedders bringing their own ports:               │
│              Operations.new(ctx:, manifest:, file_store:,  │
│                             schemas:, audit_log:, bus:,    │
│                             registry:, root:, store:)      │
└──────────────────────┬─────────────────────────────────────┘
                       │
┌─ Application ────────▼─────────────────────────────────────┐
│  Context          (slim Data: role, correlation_id, now,   │
│                    dry_run — request state only)           │
│  Operations       (flat facade; inline use-case factories) │
│                                                            │
│  reads/{get,list,where,uid,schema_envelope,deps,rdeps,     │
│         published,stale,validate_all,freshness,audit,      │
│         blame,policy_explain,get_or_refresh}.rb            │
│  writes/{put,delete,mv,accept,reject,build,publish,        │
│          envelope_io}.rb                                   │
│  refresh/{worker,orchestrator,all}.rb                      │
│  policy/{promotion,predicates/{schema_valid,human_accept}} │
└──────────┬───────────────────────────────┬─────────────────┘
           │ uses domain                   │ uses ports
┌─ Domain ─▼─────────────────────────────────────────────────┐
│  Authorizer         (manifest + role → allow / deny)       │
│  Permission         (write/read predicate per zone)        │
│  Freshness::{Policy,Verdict,Evaluator}                     │
│  Action  Outcome                                           │
│  Policy::{Promote,Refresh,Matcher,HandlerAllowlist}        │
└──────────────────────────────────────────┬─────────────────┘
                                           │ implements
┌─ Infrastructure ─────────────────────────▼─────────────────┐
│  Store              (composition root — wires ports)       │
│  Storage::FileStore (bytes-only port: read/write/delete/   │
│                      exists?/etag)                         │
│  Manifest           (Entry, Rules, Schema, permission_for) │
│  Schemas            (eager-load cache)                     │
│  AuditLog                                                  │
│  Hooks::{Registry,Dispatcher,Loader,FireReport}            │
│  Infra::{Publisher,EventBus,Clock,Refresh::Lock,           │
│          Refresh::Detached,BuildLock,AuditSubscriber}      │
│  Entry::{Markdown,Json,Yaml,Text}  (format strategies)     │
└────────────────────────────────────────────────────────────┘

   Dependency rule: arrows point DOWN. Domain has zero outbound
   imports. Application imports Domain + Infra (via ports).
   Use cases declare their real ports in their constructor.
```

## Read path (`ops.get(key)`)

1. CLI verb (or any external caller) builds `ops = Textus::Operations.for(store, role:)` then `ops.get(key)`.
2. `Operations#get` constructs `Application::Reads::Get.new(ctx:, manifest:, file_store:)` and calls it.
3. `Reads::Get#call(key)` resolves the path through `@manifest`, reads bytes via `@file_store`, parses the envelope.
4. Looks up the refresh policy via `@manifest.rules_for(key)`. If absent, returns the envelope annotated fresh.
5. Otherwise `Domain::Freshness::Evaluator.call(policy, envelope, now:)` returns a `Verdict`; the envelope is annotated with `stale`, `reason`, `refreshing: false`.

`ops.get_or_refresh(key)` composes `Reads::Get` with `Refresh::Orchestrator` to optionally refresh on stale — same as 0.18.x.

## Write path (`ops.put(key, ...)`)

1. CLI verb calls `ops = Operations.for(store, role:)` then `ops.put(key, meta:, body:, content:, if_etag:)`.
2. `Writes::Put#call` validates the key, resolves the manifest entry, and calls `@authorizer.authorize_write!(mentry, role: @ctx.role)` — raises `WriteForbidden` if denied.
3. Delegates persistence to `EnvelopeIO#write`, which serializes, schema-validates, etag-checks (raises `EtagMismatch` on conflict), writes via the `FileStore` port, and appends the audit row.
4. Publishes `:entry_put` via `@bus` with `store: @store`, `key:`, `envelope:`, `role: @ctx.role`, `correlation_id: @ctx.correlation_id`.

`Writes::{Delete,Mv,Accept,Reject,Build,Publish}` follow the same shape: explicit ports, `Authorizer` for authz, `EnvelopeIO` for persistence (where applicable), event published with `store: real Store + role:` in payload.

`Writes::Mv` delegates the file-move + audit to `EnvelopeIO#move`, then publishes `:entry_renamed` itself. UID injection (when the source lacks one) goes through `EnvelopeIO#write` directly — no `Put` bypass.

## Refresh path (`ops.refresh(key)`)

1. CLI `Verb::Refresh` builds `ops = Operations.for(store, role: "runner")` then calls `ops.refresh(key)`.
2. `Refresh::Worker#run(key)`:
   - Resolves the manifest entry, looks up the intake handler via `@registry.rpc_callable(:resolve_intake, mentry.intake_handler)`.
   - Publishes `:refresh_started` with `role:` in the payload.
   - Invokes the handler under a 30s thread-join deadline.
   - On any error: publishes `:refresh_failed`, then re-raises.
   - On success: applies `@authorizer.authorize_write!` and persists via `EnvelopeIO#write` directly (no `Put` round-trip); publishes `:entry_refreshed` unless etag is unchanged.
3. `ops.refresh_all(prefix:, zone:)` lists stale entries via `Reads::Stale` and runs `Worker#run` per entry; returns `{ refreshed:, failed:, skipped: }`.

## Hook payload contract

Hooks/intakes/transforms receive the actual `Textus::Store` (the composition root) as `store:`. Every write/refresh event payload carries `role:` directly so hook authors observe the actor without reaching through `store:`.
