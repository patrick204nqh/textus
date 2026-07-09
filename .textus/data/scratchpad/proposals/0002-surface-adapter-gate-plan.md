---
summary: Phase 1 complete — Request, StoreResolver, SessionStore, 3 adapters, Gate.
  Gap resolutions documented.
uid: f39043aadecd3420
---
# Surface Adapter + Gate Implementation Plan

**Goal:** Replace the 180-line Session class + 3 duplicate surface dispatch paths with a pluggable adapter layer + unified Gate + persistent SQLite sessions. Plus UX refinements: `--under` rename, propose constraint, search ranking.

**Architecture:** Each surface implements a thin adapter (`match?` + `normalize`) that produces a `Request`. A new `Gate` acts as a pure core dispatch engine — it receives a `Request`, resolves the session, authorizes, binds params, calls the handler, and raises on error. The adapter never formats responses; response formatting lives in each surface's own code. Sessions persist in `sessions` SQLite table (linked to `scratchpad.sessions.<id>`). `StoreResolver` replaces duplicated store-discovery logic.

**Tech Stack:** Ruby 3.x, Sequel, RSpec, SQLite (FTS5)

**Constraint:** `.textus/` is dogfood — use `create_table?` (idempotent, reset-safe), not Sequel migrations.

**Migration strategy:** Hard cut. Phase 1 is purely additive (new files, no existing code changes). Phase 2 replaces old wiring + deletes old files in one shot.

---

## Design Gap Resolutions (ADR 0049)

The following gaps were identified during architecture review and resolved before implementation:

### Gap A: Gate#dispatch return type
**Resolution:** Document as `Hash | Array | String` — handler results vary per verb (list returns Array, session_close returns Hash, etc.). Gate raises exceptions on error; never returns error hashes.

### Gap B: Session auto-creation conflict
**Resolution:** B1 — Gate creates the SQLite session row first, generating the session_id. The `session_open` handler receives that ID (via `call.correlation_id` which is set to `session[:id]`) and uses it for the scratchpad scratchpad entry. Single source of truth for session identity. Phase 1: separate IDs (additive, no conflict resolution yet). Phase 2: `session_open` uses Gate's ID.

### Gap C: Loop navigation verbs orphaned
**Resolution:** Create a `Handlers::Loop` module that encapsulates the node stack logic currently in `Session` (node_enter, node_exit, node_back, node_switch, node_status). Stored in-memory per-call — the loop_position table is separate persistence. Created in Phase 2 alongside Session deletion.

### Gap D: CLI binding asymmetry
**Resolution:** CliAdapter is a thin verb router only (`match?` for initial routing, `normalize` extracts verb + `--as=` role). The actual CLI param binding (positionals, flags, stdin, defaults) stays in `Runner.dispatch`, which feeds `Gate.dispatch(Request.new(...))`. Adapter contract documents: "`params` may be partial; the surface fills remaining params before dispatch."

---

## Interface Contracts

### Request

The contract boundary between adapters and Gate.

```ruby
Request = Data.define(:verb, :params, :role, :session_id) do
  def initialize(verb:, params: {}, role: nil, session_id: nil)
    super
  end
end
```

| Field | Type | Required | Purpose |
|---|---|---|---|
| `verb` | Symbol | yes | Verb to dispatch (:get, :put, ...) |
| `params` | Hash | no | Bound parameters (keys symbolized). May be partial — surface fills remaining before dispatch |
| `role` | String/nil | no | Role override; nil = use Gate default |
| `session_id` | String/nil | no | Session to resume; nil = create new |

Gate treats every Request identically — no surface metadata leaks through.

### Adapter Contract

Each surface adapter implements:

```ruby
def match?(raw) -> bool              # Can this adapter handle the raw input?
def normalize(raw) -> Request         # Strip surface concerns → pure Request
```

Adapters do NOT serialize responses. Response formatting is each surface's own code.
For CLI, `normalize` returns `params: {}` — the surface fills params after binding.

### Gate Contract

```ruby
class Gate
  def initialize(store_engine:, container:, store_resolver: StoreResolver, session_store: nil, default_role: "agent")

  # Returns raw handler result (Hash, Array, or String depending on verb).
  # Raises Textus::Error subclasses on failure — never returns error hashes.
  def dispatch(request, env: ENV, cwd: Dir.pwd) -> Hash | Array | String
end
```

Gate is a pure core — never knows about surface constraints. Session lifecycle:
- If `request.session_id` is set, Gate finds existing session in SQLite
- If not found or nil, Gate creates a new session row
- On write verbs, Gate persists cursor_seq + contract_etag to session row

### Error Handling

Gate raises → surface catches → formats per surface convention:

| Layer | Error format |
|---|---|
| Gate | `raise Textus::UsageError.new("msg")` |
| CLI | catches → `@stderr.puts` + exit code |
| MCP | catches → `MCP::Tool::Response` error_code |
| Web | catches → HTTP status + JSON error |

---

## UX Changes

### 1. `--under` Rename

Hard cut, no backward compat.

| Before | After |
|---|---|
| `list --prefix=KEY` | `list --under=KEY` |
| `key delete-prefix PREFIX` | `key delete-under KEY` |
| `key mv-prefix FROM TO` | `key mv-under FROM TO` |

### 2. Propose Constraint

Reject proposals where `meta.proposal.target_key` doesn't start with `"knowledge."`.

### 3. Session ↔ scratchpad Link

Same session_id in both SQLite row and scratchpad entry. `session_open` handler receives Gate's session_id via `call.correlation_id`.

### 4. Search Optimization

- Index body text in FTS `content` column
- `bm25()` ranking for `list --q=`

---

## File Structure

```
NEW (Phase 1):
  lib/textus/adapters/request.rb          # Request Data.define
  lib/textus/adapters/cli_adapter.rb      # CliAdapter
  lib/textus/adapters/mcp_adapter.rb      # McpAdapter
  lib/textus/adapters/web_adapter.rb      # WebAdapter
  lib/textus/protocol/store_resolver.rb   # Shared store discovery
  lib/textus/protocol/session_store.rb    # CRUD on sessions table
  lib/textus/protocol/gate.rb             # Gate — core dispatch engine

NEW (Phase 2):
  lib/textus/protocol/handlers/loop.rb    # Loop nav verb handlers (node_enter, etc.)

MODIFY:
  lib/textus/infra/database.rb            # + create_table?(:sessions)
  lib/textus/protocol/builder/runtime.rb  # Phase 2: wire new Gate
  lib/textus/protocol/store_engine.rb     # prefix: → under:
  lib/textus/protocol/manifest/resolver.rb# prefix: → under:
  lib/textus/ops/bulk_planner.rb          # prefix: → under:
  lib/textus/lanes/scratchpad/handlers.rb # propose constraint, session link
  lib/textus/lanes/ingest/handlers.rb     # remove inline rebuild
  lib/textus/infra/store/entry_index.rb   # body indexing + bm25 ranking

DELETE (P2):
  lib/textus/protocol/session.rb, bridge.rb, context.rb
  lib/textus/surface/dispatch.rb

DELETE (P3):
  lib/textus/infra/store/file_store.rb, cursor_store.rb
  lib/textus/infra/store.rb              # remove delegations
```

---

## Phase 1 — Additive Foundation (zero existing code changes)

### Task 1.1: Request

**Create:** `lib/textus/adapters/request.rb`

```ruby
module Textus
  module Adapters
    Request = Data.define(:verb, :params, :role, :session_id) do
      def initialize(verb:, params: {}, role: nil, session_id: nil)
        super
      end
    end
  end
end
```

**Spec:** spec/unit/adapters/request_spec.rb — all 4 fields, frozen, default nil for role/session_id.

### Task 1.2: StoreResolver

**Create:** `lib/textus/protocol/store_resolver.rb`

```ruby
module Textus
  module Protocol
    module StoreResolver
      STORE_DIR = ".textus"

      def resolve(env: ENV, cwd: Dir.pwd)
        root = env["TEXTUS_ROOT"]
        return File.expand_path(root) if root && !root.empty?

        candidate = cwd
        loop do
          store_path = File.join(candidate, STORE_DIR)
          return File.expand_path(candidate) if File.directory?(store_path)
          parent = File.dirname(candidate)
          break if parent == candidate
          candidate = parent
        end
        raise Textus::IoError.new("no .textus store found from #{cwd}")
      end
    end
  end
end
```

**Spec:** spec/unit/protocol/store_resolver_spec.rb — env override, cwd walk, IoError, env priority.

### Task 1.3: Sessions Table

**Modify:** `lib/textus/infra/database.rb` — add `create_table?(:sessions)` with id (PK), role, surface_id, cursor_seq, contract_etag, expires_at, created_at.

### Task 1.4: SessionStore

**Create:** `lib/textus/protocol/session_store.rb`

```ruby
class SessionStore
  def initialize(database)
  def find(id) -> Hash | nil
  def create(id:, role:, surface_id: nil, expires_at: nil) -> Hash
  def save(id, cursor_seq: nil, contract_etag: nil)
  def sweep_expired! -> Integer
end
```

**Spec:** spec/unit/protocol/session_store_spec.rb — each method with in-memory SQLite.

### Task 1.5: Adapters

**CliAdapter** — `match?` checks Array, `normalize` extracts first non-flag as verb, strips `--as=` for role, returns `params: {}`.

**McpAdapter** — `match?` checks JSON-RPC shape, `normalize` reads method→verb, params→symbolized hash, role/session_id passthrough.

**WebAdapter** — `match?` checks for "verb" key, `normalize` deletes verb/role/session_id from raw, remaining→symbolized params.

**Specs:** spec/unit/adapters/{cli,mcp,web}_adapter_spec.rb — match? (pos/neg), normalize extracts verb/params/role/session_id.

### Task 1.6: Gate (v2)

**Create:** `lib/textus/protocol/gate.rb` — `Textus::Protocol::Gate`

Implementation:
- Takes `store_engine`, `container`, `store_resolver`, `session_store`, `default_role`
- `dispatch(request, env:, cwd:)` → validates Request, resolves verb spec, authorizes, binds params, dispatches to handler
- Session lifecycle: resolve by session_id or create new; persist on write verbs
- Never returns error hashes — always raises `Textus::Error` subclasses

**Spec:** spec/unit/protocol/gate_spec.rb — Request validation, unknown verb, lane dispatch, session create/resume, no-session-store fallback.

---

## Phase 2 — Hard Cut

### Task 2.1: `--under` Rename

StoreEngine#list(under:), Resolver#enumerate(under:), BulkPlanner prefix→under. CLI_PATHS: key_mv_under/key_delete_under.

### Task 2.2: Wire New Gate in Builder::Runtime

Replace old Gate with new `Gate`. Add SessionStore dependency. Update Container to expose session_store.

### Task 2.3: Port CLI

Runner.dispatch keeps binding logic but calls `Gate.dispatch(Request.new(...))` instead of `Dispatch.call(session, ...)`. Catches errors → CLI formatting. Remove Session.open.

Test: `bundle exec rspec spec/conformance/surface/cli/contract_spec.rb`

### Task 2.4: Port MCP

McpAdapter → Gate → MCP::Tool::Response. Delete CursorManager.

### Task 2.5: Propose Constraint

Add `target_key.start_with?("knowledge.")` validation in propose handler.

### Task 2.6: Session ↔ scratchpad Link

`session_open` handler reads session_id from `call.correlation_id` (set to Gate's session[:id]) and uses it for the scratchpad entry key. No duplicate ID generation.

### Task 2.7: Create Loop Handlers

`lib/textus/protocol/handlers/loop.rb` — encapsulates node_enter/node_exit/node_back/node_switch/node_status logic currently in Session. In-memory node stack per call.

### Task 2.8: Delete Old Files

session.rb, bridge.rb, context.rb, dispatch.rb. Remove requires.

---

## Phase 3 — Optimize

### Task 3.1: Remove Inline Rebuild from Ingest

Delete IndexRebuilder.rebuild! line.

### Task 3.2: Search — Index Body Text

FTS content column includes body.

### Task 3.3: Search — BM25 Ranking

ORDER BY rank in list --q=.

### Task 3.4: Delete FileStore + CursorStore

git rm files. Remove delegations.

### Task 3.5: Session TTL Sweep

In drain handler.
