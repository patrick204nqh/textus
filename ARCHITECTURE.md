# Textus architecture

```
┌─ Interface ────────────────────────────────────────────────┐
│  CLI verbs:  session = Session.for(store, role:)           │
│              session.<name>(...)   # one method per         │
│                                # registered use case        │
│                                # (put/get/refresh/…)        │
│                                                            │
│  MCP gate:   textus mcp serve — same use cases, JSON-RPC.  │
└──────────────────────┬─────────────────────────────────────┘
                       │
┌─ Application ────────▼─────────────────────────────────────┐
│  Context          (slim Data: role, correlation_id, now,   │
│                    dry_run — request state only)           │
│  Caps             (Read/Write/Hook records — store slices) │
│  Session          (per-call dispatch; methods generated    │
│                    from UseCase registry)                  │
│  UseCase          (registry: verb → module, caps_kind)     │
│                                                            │
│  read/{get,get_or_refresh,list,where,uid,schema_envelope,  │
│        deps,rdeps,published,stale,validate_all,            │
│        freshness,audit,blame,policy_explain,pulse}.rb      │
│  write/{put,delete,mv,accept,reject,publish,               │
│         materializer,authority_gate,                       │
│         refresh_worker,refresh_orchestrator,refresh_all}   │
│  maintenance/{migrate,key_mv_prefix,key_delete_prefix,     │
│               zone_mv,rule_lint}.rb                        │
│  envelope/{reader,writer}.rb  (split: parse vs persist)    │
│  projection.rb                                             │
└──────────┬───────────────────────────────┬─────────────────┘
           │ uses domain                   │ uses ports
┌─ Domain ─▼─────────────────────────────────────────────────┐
│  Authorizer         (manifest + role → allow / deny)       │
│  Permission         (write/read predicate per zone)        │
│  Freshness::{Policy,Verdict,Evaluator}                     │
│  Staleness          (Generator/Intake checks)              │
│  Action  Outcome  Sentinel                                 │
│  Policy::{Promote,Refresh,Matcher,HandlerAllowlist,        │
│           Predicates::{SchemaValid,AcceptAuthoritySigned}} │
└──────────────────────────────────────────┬─────────────────┘
                                           │ implements
┌─ Infrastructure ─────────────────────────▼─────────────────┐
│  Store              (composition root — wires ports,       │
│                      vends Sessions)                       │
│  Storage::FileStore (bytes-only port: read/write/delete/   │
│                      exists?/etag)                         │
│  Manifest           (Data, Resolver, Policy, Rules)        │
│  Schemas            (eager-load cache)                     │
│  Infra::{AuditLog,AuditSubscriber,Publisher,Clock,         │
│          Refresh::Lock,Refresh::Detached,BuildLock}        │
│  Hooks::{EventBus,RpcRegistry,Loader,Context,FireReport,   │
│          Builtin,ErrorLog}                                 │
│  Entry::{Markdown,Json,Yaml,Text}  (format strategies)     │
└────────────────────────────────────────────────────────────┘

   Dependency rule: arrows point DOWN. Domain has zero outbound
   imports. Application imports Domain + Infra (via ports).
   Use cases declare their real collaborators in their Impl
   constructor; UseCase.register hooks them into Session.
```

## How a verb becomes a method

Each application use case is a module under `lib/textus/application/{read,write,maintenance}/`. The shape is uniform:

```ruby
module Textus
  module Application
    module Read
      module Get
        def self.call(*, session:, ctx:, caps:, **)
          Impl.new(ctx: ctx, caps: caps).call(*, **)
        end

        class Impl
          def initialize(ctx:, caps:, ...)
            @ctx = ctx; @manifest = caps.manifest; ...
          end

          def call(key) ... end
        end
      end
    end
  end
end

Textus::Application::UseCase.register(:get, Textus::Application::Read::Get, caps: :read)
```

`Session` generates one dispatch method per registered entry (see `lib/textus/session.rb` — the `Application::UseCase.each do |entry| ... end` block at the bottom). Adding a new verb is **one `UseCase.register` line** plus the module — no edits to `Session`.

Two collaborators live outside the registry because they're composed by other use cases, not invoked as verbs:

- `Application::Write::RefreshOrchestrator` — composes `RefreshWorker` with the freshness `Action` returned by `Domain::Freshness`. Session memoizes one (`session.refresh_orchestrator`).
- `Application::Envelope::{Reader,Writer}` — own the parse and persist halves of the write pipeline; the audit-append-as-final-step invariant lives in `Writer`. Session memoizes both.

## Caps

Use cases never see the raw `Store`. `Application::Caps` defines three role-scoped slices:

```ruby
ReadCaps  = Data.define(:manifest, :file_store, :schemas, :root, :audit_log, :events)
WriteCaps = Data.define(:manifest, :file_store, :schemas, :root, :audit_log, :events, :authorizer)
HookCaps  = Data.define(:events, :rpc, :manifest, :root)
```

`Session.for(store, role:)` builds all three via `Application.caps_from_store(store)`; the dispatch method picks `read_caps` or `write_caps` based on the `caps_kind` declared at registration time. RPC hook callables (`:resolve_intake`, `:transform_rows`, `:validate`) receive a `caps:` kwarg that is the appropriate Read/Write slice — legacy `store:` is rejected by `Hooks::RpcRegistry#invoke`.

## Read path (`session.get(key)`)

1. CLI verb (or MCP tool) builds `session = Session.for(store, role:)` then `session.get(key)`.
2. `Session#get` dispatches to `Application::Read::Get.call(key, session:, ctx:, caps:)`.
3. `Read::Get::Impl#call` resolves the path through `caps.manifest`, reads bytes via `caps.file_store`, parses the envelope.
4. Looks up the refresh policy via `caps.manifest.rules.for(key)`. If absent, returns the envelope annotated fresh.
5. Otherwise `Domain::Freshness::Evaluator.call(policy, envelope, now:)` returns a `Verdict`; the envelope is annotated with `stale`, `reason`, `refreshing: false`.

`session.get_or_refresh(key)` composes `Read::Get` with `Write::RefreshOrchestrator` to optionally refresh on stale.

## Write path (`session.put(key, ...)`)

1. CLI verb calls `session = Session.for(store, role:)` then `session.put(key, meta:, body:, content:, if_etag:)`.
2. `Write::Put::Impl#call` validates the key, resolves the manifest entry, and calls `@authorizer.authorize_write!(mentry, role: @ctx.role)` — raises `WriteForbidden` if denied.
3. Delegates persistence to `session.envelope_writer.put`, which serializes, schema-validates, etag-checks (raises `EtagMismatch` on conflict), writes via the `FileStore` port, and appends the audit row.
4. Publishes `:entry_put` via `caps.events` with `ctx: session.hook_context`, `key:`, `envelope:`.

`Write::{Delete,Mv,Accept,Reject,Publish}` follow the same shape: explicit caps, `Authorizer` for authz, `Envelope::Writer` for persistence (where applicable), event published with the `Hooks::Context` handle.

`Write::Mv` delegates the file-move + audit to `Envelope::Writer#move`, then publishes `:entry_renamed` itself. UID injection (when the source lacks one) goes through `Envelope::Writer#write` directly — no `Put` bypass.

## Refresh path (`session.refresh(key)`)

1. CLI `Verb::Refresh` builds `session = Session.for(store, role: "runner")` then calls `session.refresh(key)`.
2. `Write::RefreshWorker::Impl#run(key)`:
   - Resolves the manifest entry, looks up the intake handler via `caps.rpc.callable(:resolve_intake, mentry.handler)`.
   - Publishes `:refresh_started` with the hook context.
   - Invokes the handler under a 30s thread-join deadline.
   - On any error: publishes `:refresh_failed`, then re-raises.
   - On success: applies `@authorizer.authorize_write!` and persists via `Envelope::Writer#write` directly (no `Put` round-trip); publishes `:entry_refreshed` unless etag is unchanged.
3. `session.refresh_all(prefix:, zone:)` lists stale entries via `Read::Stale` and runs `Worker#run` per entry; returns `{ refreshed:, failed:, skipped: }`.

## Hook payload contract

Pub-sub hooks (`:entry_put`, `:entry_refreshed`, …) receive `ctx:` — a `Textus::Hooks::Context` that wraps the session and exposes a narrow surface (`get`, `list`, `put`, `delete`, `audit`, `publish_followup`, plus `role` and `correlation_id`). The raw `Store` is not handed out.

RPC hooks (`:resolve_intake`, `:transform_rows`, `:validate`) receive `caps:` — a `ReadCaps` or `WriteCaps` slice. They are gem-internal: the framework calls them, not user pub-sub.

## Agent surface (boot + pulse + MCP)

Agents and plugins talk to a textus store through three layers:

```
soul (skill/agent)  ──▶  gate (CLI | MCP)  ──▶  Session  ──▶  memory (.textus/)
```

Two transports, one façade:

- **CLI** — human/script surface. `textus boot`, `textus pulse --since=N`, `textus get/put/...`.
- **MCP** — agent surface. `textus mcp serve` runs a stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. Tools are auto-derived from the manifest. Session state (cursor, role, manifest_etag) is server-side.

Both transports call `Session.for(store, role:)`. No duplicate logic.

The agent loop (cadence guide in `docs/agent-integration.md`):

1. **Session start:** `boot()` → contract envelope (zones, entries, schemas, write_flows, agent_quickstart with `latest_seq`).
2. **Per turn:** `pulse(since=cursor)` → `{cursor, changed, stale, pending_review, doctor}`.
3. **On demand:** `get`, `put`, `propose`, `refresh`, `schema`, `rules`.

Manifest drift surfaces as `ContractDrift` (manifest_etag mismatch); audit cursor falls off the keep window as `CursorExpired`. Both signal "call `boot` again."

## Hooks::EventBus event catalog

RPC (single handler, declares `caps:`):
- `resolve_intake(caps:, config:, args:)` — intake fetch handler.
- `transform_rows(caps:, rows:, config:)` — row transform for intakes.
- `validate(caps:)` — custom doctor validator.

Pub-sub (0..N handlers, declare `ctx:`):
- `entry_put(ctx:, key:, envelope:)`
- `entry_deleted(ctx:, key:)`
- `entry_refreshed(ctx:, key:, envelope:, change:)`
- `entry_renamed(ctx:, key:, from_key:, to_key:, envelope:)`
- `build_completed(ctx:, key:, envelope:, sources:)`
- `proposal_accepted(ctx:, key:, target_key:)`
- `proposal_rejected(ctx:, key:, target_key:)`
- `file_published(ctx:, key:, envelope:, source:, target:)`
- `store_loaded(ctx:)`
- `refresh_started(ctx:, key:, mode:)`
- `refresh_failed(ctx:, key:, error_class:, error_message:)`
- `refresh_backgrounded(ctx:, key:, started_at:, budget_ms:)`

Authoritative source: `lib/textus/hooks/event_bus.rb` `EVENTS`.
