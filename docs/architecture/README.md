# Textus architecture

> **Explanation** · for contributors · **read this first** for orientation before SPEC
> **SSoT for** the Ruby implementation layout (layers, container, ports, dispatch/pipeline paths) · **reviewed** 2026-06 (v0.46)

```mermaid
flowchart TD
    surfaces["Surfaces — CLI verbs · MCP gate (JSON-RPC) · RoleScope"]
    contract["Contract — per-verb DSL (source of truth for public interfaces)"]
    dispatch["Dispatch — Gate · Auth · Ledger · Executor · Actions<br/>planner/ · pipeline/ · runtime/ · catalog/"]
    manifest["Manifest — declarative config, no IO (policy/, schema/, entry/)"]
    core["Core — pure value types (Freshness, Job, Duration, Sentinel)"]
    ports["Ports — IO adapters (FileStore, AuditLog, Queue, Publisher…)"]
    step["Step — user-injectable wrappers (Fetch, Transform, Validate, Observe)"]
    surfaces --> contract
    contract --> dispatch
    dispatch --> manifest
    dispatch --> core
    dispatch --> ports
    dispatch --> step
```

*Dependency rule: inward only.* `dispatch/planner/`, `dispatch/pipeline/`, and `dispatch/runtime/` are private sub-namespaces of `dispatch/` — never referenced directly from `surfaces/` or `contract/`. Use cases are plain classes receiving `(container:, call:)`. Verbs are looked up in the static `Dispatcher::VERBS` table.

### What lives in each layer

**Interface**

```
CLI verbs:  store.<verb>(..., role:)
            store.as(role).<verb>(...)    # (put/get/fetch/…)

MCP gate:   textus mcp serve — same use cases, JSON-RPC.
```

The CLI is a **projection of the per-verb `Contract`** (ADR 0063), the operator
mirror of `MCP::Catalog`. The contract now owns the whole request lifecycle —
`acquire → bind → invoke → render` (ADRs 0066–0068): one `Contract::Binder.bind`
splits the uniform by-name `inputs` hash into the use-case's positional/keyword
args for every surface; per-surface `view`s shape the output (`view` for
MCP/Ruby, `view(:cli)` for the operator envelope); declarative `source:`/
`coerce:`/`cli_stdin` populate inputs from files and stdin; `around:` resources
wrap the single dispatch site (`RoleScope#dispatch_bound`) for stateful verbs;
and `cli_default:` declares a CLI default that diverges from the agent default.
`CLI::Runner` generates a command per `:cli` contract, dispatching `contract.verb`
by construction. Only verbs with genuine *behavior* — `put` (entry persistence),
`get` (UnknownKey + resolver suggestions, CLI-only), and `doctor` (not yet
generatable) — stay hand-authored, plus commands with no dispatcher verb (`init`,
`hook`, `mcp serve`, `schema diff/init`). `boot` is auto-generated from its
contract. Total reconciliation specs make name/dispatch/facet drift unrepresentable.

**Surfaces**

```
CLI verbs:  store.<verb>(..., role:)
            store.as(role).<verb>(...)

MCP gate:   textus mcp serve — same actions, JSON-RPC.
RoleScope   (Store#as(role) — builds Call, forwards to Dispatcher)
```

**Dispatch (all runtime)**

```
Gate             (thin coordinator: Auth → Ledger → Executor)
Auth             (authorization engine — FLOOR predicates + rule guards)
Ledger           (append event to audit before execution)
Executor         (sync/async routing per action BURN mode)
Event            (Data.define: name, actor, target, payload, actions)

actions/{get,list,put,key_delete,key_mv,accept,reject,propose,
         drain,materialize,refresh_data,sweep,observe,
         enqueue,audit,blame,deps,rdeps,published,boot,doctor,
         rule_explain,rule_list,rule_lint,pulse,
         data_mv,key_mv_prefix,key_delete_prefix,
         schema_envelope,where,uid,jobs}.rb

planner/{planner,scheduler,seeder}.rb  (rules-driven job planning)
pipeline/{engine,render,acquire/{intake,handler,projection,serializer}}.rb
runtime/{worker,watch,retention/apply,plan}.rb
catalog/events.rb                      (dotted event name constants)
```

**Core (pure value types)**

```
Freshness::{Verdict,Evaluator}
Jobs::Job          (immutable job value object)
Duration  Sentinel
```

**Infrastructure**

```
Store              (composition root — wires ports,
                    vends a Container + dispatches verbs)
Storage::FileStore (bytes-only port: read/write/delete/exists?/etag)
Manifest           (Data, Resolver, Policy, Rules)
Schemas            (eager-load cache)
Ports::{AuditLog,AuditSubscriber,Publisher,Clock,
        BuildLock,Queue,SentinelStore,WatcherLock}
Step::{EventBus,RegistryStore,Loader,Context,FireReport,
       Signature,Builtin,ErrorLog,Fetch,Transform,Validate,Observe}
Entry::{Markdown,Json,Yaml,Text}  (format strategies)
Doctor::Validator  (schema + role-authority validation — called by doctor check)
```

## How a verb becomes a method

All actions live under `lib/textus/dispatch/actions/`. The shape is uniform:

```ruby
module Textus
  module Dispatch
    module Actions
      class Get < Base
        BURN = :sync

        def call(container:, call:)
          ...
        end
      end
    end
  end
end
```

Verbs are looked up in a static frozen table (`Textus::Dispatcher::VERBS`) that maps `:get → Dispatch::Actions::Get`, `:put → Dispatch::Actions::Put`, etc. Adding a new verb is **one entry in `Dispatcher::VERBS`** plus the class — no metaprogramming.

The instantiate-and-call step lives in `Dispatcher.invoke`. `RoleScope` builds the `Call` (request state) and delegates to `Dispatcher.invoke`. Every system interaction flows through `Dispatch::Gate#fire(event)` — surfaces, internal cascades (rdeps), and async job workers all use the same path. Gate runs Auth → Ledger → Executor in sequence.

`boot` and `doctor` are actions like any other — reached through `Dispatcher::VERBS`.

One collaborator lives outside the dispatcher because it's composed by actions, not invoked as a verb:

- `Envelope::IO::{Reader,Writer}` — own the parse and persist halves of the write pipeline; the audit-append-as-final-step invariant lives in `Writer`.

## Container

Use cases never see the raw `Store`. `Textus::Container` is a single record holding the wired collaborators:

```ruby
Container = Data.define(
  :manifest, :file_store, :schemas, :root,
  :audit_log, :steps, :gate
)
```

The `Store` builds one `Container` at boot; every action receives it via `(container:, call:)`. Step handlers (Fetch, Transform, Observe) receive `caps: <Container>` — they access `caps.manifest`, `caps.steps`, etc.

## Ports

Ports are infrastructure adapters with an interface defined by the domain. Each port is independently replaceable — swap the implementation for tests or alternative runtimes without touching application or domain code.

| Class | Role |
|---|---|
| `Ports::Storage::FileStore` | Bytes-only FS I/O — `read`, `write`, `delete`, `exists?`, `etag`. No knowledge of envelopes or schemas. |
| `Ports::AuditLog` | Append-only structured log (`audit.log`). Owns seq numbering, file-locking, and rotation. |
| `Ports::Clock` | Supplies `Time.now` — a module-function so tests can swap it without dependency injection boilerplate. |
| `Ports::Publisher` | Copies a built artifact to a repo-relative consumer path and writes a sentinel so the next publish can confirm the target is managed. |
| `Ports::BuildLock` | Process-exclusive `flock` guard over the produce pipeline. Raises `BuildInProgress` if a build is already running. |
| `Ports::Queue` | Persistent job queue used by `drain`/`watch` workers; tracks ready/leased/done/failed jobs and powers async dispatch actions (`materialize`, `observe`). |
| `Ports::SentinelStore` | Reads and writes the per-target sentinel file that `Publisher` uses to detect unmanaged overwrites. |
| `Ports::WatcherLock` | Single-watcher `flock` guard used by `Dispatch::Runtime::Watch` to ensure only one watcher loop is active per store root. |

Application use cases access ports only through `Container` fields — never through the raw `Store`.

### EnvelopeIO

`Envelope::IO::Reader` and `Envelope::IO::Writer` split the envelope pipeline into read-only parse and write-with-audit halves.

**Reader** (`lib/textus/envelope/io/reader.rb`) — resolves a key through `manifest.resolver`, reads bytes via `FileStore`, delegates parsing to the format strategy (`Entry.for_format`), and returns an `Envelope`. No audit, no events, no permission checks. Also used by `Writer` for the existing-uid lookup on `put`.

**Writer** (`lib/textus/envelope/io/writer.rb`) — owns the full write pipeline: serialize → schema-validate → etag-check → `FileStore#write` → `AuditLog#append`. The class comment states the invariant directly: every public method's final action is `@audit_log.append(...)`. If the audit append fails, the caller sees the underlying error — the byte write already happened, but the pipeline contract treats audit as the commit step. No permission check, no event firing — those stay in the calling use case (`Write::Put`, `Write::Delete`, `Write::Mv`).

The three public methods are `put`, `delete`, and `move`; all follow the same validate → write → audit sequence.

Both are built from a `Container` via named constructors — `Writer.from(container:, call:)` (which builds its own `Reader.from`) and `Reader.from(container:)` (ADR 0026). Write use cases call `Writer.from` rather than reconstructing the object graph by hand, so a change to the Writer's dependencies is a one-line edit in one place.

## Manifest carving

Manifest carving means slicing the parsed manifest YAML into four purpose-specific sub-objects. Each consumer sees only the fields it needs; none reach into the full raw document.

`Manifest` itself is a `Data.define` struct — a composition record with four named members:

| Member | Class | Responsibility |
|---|---|---|
| `data` | `Manifest::Data` | Frozen value: `raw`, `root`, `zones`, `entries`, `audit_config`, `role_caps` (role name → capability set). Structural data only — no behaviour beyond accessors and key validation. |
| `resolver` | `Manifest::Resolver` | Key → `Resolution(entry, path, remaining)`. Handles nested entry enumeration and fuzzy-match suggestions. |
| `policy` | `Manifest::Policy` | Zone/capability authority — `verb_for_zone` (zone-kind → required verb), `roles_with_capability(verb)`, `zone_writers` (derived: roles holding the verb the zone's kind requires), `permission_for`, `declared_kind`, `proposer_role`, `propose_zone_for(role)`. Write authority is derived from capabilities × zone-kind (ADR 0030); no filesystem I/O. `propose_zone_for` returns the single `kind: queue` zone when the role can write it (ADR 0027). |
| `rules` | `Manifest::Rules` | Pattern-matched rule engine. `rules.for(key)` returns a `RuleSet(fetch, handler_allowlist, guard, retention)` by evaluating all `match:` blocks against the key. |

Rationale: cleaner test seams — a use case that only needs key resolution constructs a `Manifest::Resolver` from a stub `Data`; one that only needs rule lookup constructs a `Manifest::Rules` directly. No consumer is forced to build the full manifest to exercise one sub-view.

The four members are wired in `Manifest.build` (`lib/textus/manifest.rb`). `Manifest::Data` constructs `Policy` internally during `initialize`; the others are assembled by the loader and handed in as named arguments.

## Read path (`store.get(key)`)

`Read::Get` is the single public read verb. It is a **pure read** (ADR 0089): it resolves the path, reads bytes, parses the envelope, and annotates a freshness verdict — it NEVER ingests and NEVER mutates. The read-through that once refreshed a stale entry in-process (ADR 0062) is removed; quarantine freshness is system-pushed via `drain` (scheduled sweep) and `hook run` (event push).

1. CLI verb (or MCP tool) calls `store.get(key, role:)` (or `store.as(role).get(key)`).
2. `Store#get` looks up `Dispatcher::VERBS[:get] → Read::Get`, builds a `Call`, instantiates `Read::Get.new(container:, call:).call(key)`. The verb takes only `key` — there is no `fetch` flag on any surface.
3. `Read::Get#call(key)` resolves the path through `container.manifest`, reads bytes via `container.file_store`, parses the envelope, and annotates a freshness verdict (`stale`, `reason`, `fetching: false`). When the key has no `upkeep` rule, the envelope is annotated fresh. A stale entry with `upkeep: { ttl:, action: refresh }` is returned **stale** — the read does not refresh it; the next `drain` does.

Because the read is always pure, every caller — interactive reads, dashboards, and the direct in-process callers (accept/reject/publish, materializer, uid, schema/tools, hooks/context) — gets the same orchestrator-free, side-effect-free read. The prior read-through path (`get_or_fetch`, then the `fetch:`-flagged `Read::Get`, ADR 0062) and its `Write::FetchOrchestrator` are gone (ADR 0089).

## Write path (`store.put(key, ...)`)

1. CLI/MCP surface calls `store.as(role).put(key, meta:, body:, content:, if_etag:)`.
2. `Surfaces::RoleScope#dispatch_bound` fires `Gate.fire(Event.new("entry.put", actor: role, ...))`.
3. `Dispatch::Gate` runs Auth → Ledger → Executor. `Auth#check_event!` evaluates FLOOR predicates (`lane_writable_by`) plus any rule-declared guards — raises `WriteForbidden` / `GuardFailed` on failure.
4. `Actions::Put#call` validates the key, resolves the manifest entry, delegates persistence to `Envelope::IO::Writer#put` (serialize → schema-validate → etag-check → `FileStore#write` → `AuditLog#append`).
5. Publishes `:entry_written` via `container.steps` and fires a cascade Gate event for rdep materialization.

`Actions::{KeyDelete,KeyMv,Accept,Reject,Propose}` follow the same shape. All write actions inherit `WriteVerb#run_with_cascade`, which enqueues `materialize` jobs for rdeps after the write completes.

## Pipeline path (`drain` + reactive `entry.written`)

The pipeline handles two concerns — **acquire** (pull live data via an intake handler) and **render** (template-driven artifact publish) — unified under `Dispatch::Pipeline::Engine`.

`Pipeline::Engine.converge(container:, call:, keys:)` is the entry point `Actions::Materialize` calls. Both the batch path (`drain` seeds jobs via `Planner::Seeder`) and the reactive path (write actions enqueue `materialize` jobs via `WriteVerb#cascade_to_rdeps`) flow through the queue worker into `converge`.

For each key, `Engine#produce_one`:

1. **Acquire phase** — `Pipeline::Acquire::Intake#run(key)`:
   - Resolves the manifest entry; looks up the step handler via `container.steps`.
   - Publishes `:entry_fetch_started` via `container.steps`.
   - Invokes the `Step::Fetch` handler under a timeout deadline.
   - On error: publishes `:entry_fetch_failed`, re-raises.
   - On success: normalises the handler result, checks auth, persists via `Envelope::IO::Writer`, publishes `:entry_fetched` unless the etag is unchanged.
   - `Acquire::Handler` resolves and invokes the step under the timeout deadline. (The sibling **projection** sub-path — `from: derive` entries — runs `Acquire::Projection`, which renders data files through `Acquire::Serializer::{Json,Yaml,Text}` before persisting.)
2. **Render phase** — `entry.publish_via(context)` calls `Pipeline::Render#bytes_for(target:, data:, boot:)` to expand the Mustache template and copy the result to the publish target via `Ports::Publisher`. Returns `nil` if no publish is configured (skipped).

Per-entry failures are published as `:produce_failed` by `Actions::Materialize` after `Engine.converge` returns. A held `BuildLock` is a soft miss — the in-flight build already produces fresh output.

Reactive produce is enqueued as `materialize` jobs onto `Ports::Queue` when `entry_written`/`entry_deleted`/`entry_renamed` fires; a worker (`drain`/`serve`) runs them through `converge`. A held `BuildLock` is a soft miss — the in-flight build already produces fresh output.

## Hook payload contract

Pub-sub hooks (`:entry_written`, `:entry_fetched`, …) receive `ctx:` — a `Textus::Hooks::Context` that exposes a narrow surface (`get`, `list`, `put`, `delete`, `audit`, `publish_followup`, plus `role` and `correlation_id`). The raw `Store` is not handed out.

RPC hooks (`:resolve_handler`, `:transform_rows`, `:validate`) receive `caps:` — a `Textus::Container`. They are gem-internal: the framework calls them, not user pub-sub.

## Agent surface (boot + pulse + MCP)

Agents and plugins talk to a textus store through three layers:

```
soul (skill/agent)  ──▶  gate (CLI | MCP)  ──▶  Store  ──▶  memory (.textus/)
```

Two transports, one façade:

- **CLI** — human/script surface. `textus boot`, `textus pulse --since=N`, `textus get/put/...`.
- **MCP** — agent surface. `textus mcp serve` runs a stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. Tools are auto-derived from the manifest. Session state (cursor, role, contract_etag) is server-side.

Both transports call `store.<verb>(..., role:)` (or `store.as(role).<verb>(...)`). No duplicate logic.

The agent loop (cadence guide in [`agents-mcp.md`](../how-to/agents-mcp.md)):

1. **Session start:** `boot()` → contract envelope (zones, entries, schemas, write_flows, agent_quickstart with `latest_seq`).
2. **Per turn:** `pulse(since=cursor)` → `{cursor, changed, stale, pending_review, doctor}`.
3. **On demand:** `get`, `put`, `propose`, `fetch`, `schema_show`, `rule_explain`.

Contract drift surfaces as `ContractDrift` (contract_etag mismatch — a change to the manifest, hooks, or schemas; ADR 0074); audit cursor falls off the keep window as `CursorExpired`. Both signal "call `boot` again."

## Hooks event catalog

`Hooks::Signature` is the single home of callable keyword-introspection — both `EventBus` (pub-sub dispatch) and `RpcRegistry` (RPC dispatch) delegate to it for `accepts_keyrest?`, `declared_keys`, `missing`, and `filter` rather than each maintaining a hand-rolled copy (ADR 0027). RPC handlers declare `caps:` (single handler); pub-sub handlers declare `ctx:` (0..N handlers).

The event names, payloads, and per-verb firing order are documented once in [`reference/events.md`](../reference/events.md) (the friendly SSoT); the authoritative source is `lib/textus/step/catalog.rb` (`Catalog::RPC` and `Catalog::PUBSUB`) and `lib/textus/dispatch/catalog/events.rb` (dotted Gate event name constants).
