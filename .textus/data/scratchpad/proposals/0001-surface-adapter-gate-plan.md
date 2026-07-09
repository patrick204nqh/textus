---
proposal:
  target_key: scratchpad.sessions.2026-07-08-surface-adapter-gate
  action: replace
summary: Phase 1-3 implementation plan for surface adapter + unified gate architecture
uid: 077a2dcf8885e339
---
# Surface Adapter + Unified Gate — Implementation Plan

**Date:** 2026-07-08
**Author:** agent

## Problem

Today's architecture has 3 duplicate patterns across CLI/MCP/Web surfaces:

1. **Store discovery duplicated** — CLI walks cwd for `.textus/`, `Session.open` re-creates Builder from root
2. **180-line Session class** — SRP violation: dispatch, cursor, drift, loop navigation, node stack
3. **MCP drift on every dispatch** — filesystem stat per JSON-RPC call, even reads
4. **Ingest index rebuild outside transaction** — crash risk
5. **FileStore is dead code** — pure delegation wrapper, never called from write path

## Design

### Adapter Interface

```ruby
SurfaceRequest = Data.define(:verb, :params, :raw_input, :surface_id)
```

Each surface implements `match?` + `normalize`. Gate owns: adapter registry, session resolve, authorize, bind, handler dispatch.

### Session Persistence

`sessions` SQLite table replaces ephemeral Session + CursorStore:

| Column | Type | Purpose |
|--------|------|---------|
| id | TEXT PK | UUID |
| role | TEXT | human/agent/automation |
| surface_id | TEXT | cli/mcp/web |
| cursor_seq | INT | last audit seq |
| contract_etag | TEXT | cached config digest |
| expires_at | DATETIME | TTL |
| created_at | DATETIME | - |

### Store Discovery

`StoreResolver.resolve(env:, cwd:)` — checks `TEXTUS_ROOT` env first, then walks cwd for `.textus/`. **Shared by all 3 surfaces**, replaces CLI's private root discovery + Session.open's internal build.

## Implementation Tasks

### Phase 1 — Additive Foundation (7 tasks)

**1.1 — Adapter interface** (`lib/textus/adapters/interface.rb`)
- `SurfaceRequest` Data.define
- Adapter duck type contract docs

**1.2 — StoreResolver** (`lib/textus/protocol/store_resolver.rb`)
- Extracted from CLI's `explicit_root`/`discovered_root` logic
- Shared by all surfaces

**1.3 — Sessions migration** (`.textus/db/migrate/001_create_sessions.rb`)
- Sequel migration for `sessions` table
- Wire migration runner into `Infra::Database#setup!`

**1.4 — SessionStore** (`lib/textus/protocol/session_store.rb`)
- CRUD on sessions table
- `sweep_expired!` for TTL cleanup

**1.5 — Adapters** (`lib/textus/adapters/{cli,mcp,web}.rb`)
- Each `match?` tests for its input shape (Array for CLI, Hash with jsonrpc for MCP, Sinatra params for Web)
- Each `normalize` returns `SurfaceRequest`

**1.6 — UnifiedGate** (`lib/textus/protocol/unified_gate.rb`)
- Adapter registry (`register`/`adapter_for`)
- Pipeline: normalize → resolve store → resolve session → authorize → bind → dispatch
- Session lifecycle managed internally (create on first dispatch, persist on write)

**1.7 — Dual-wire** in `Builder::Runtime`
- Create UnifiedGate alongside existing Gate
- Old Session still works — zero regression

### Phase 2 — Port + Delete (5 tasks)

**2.1** — Port CLI: `CLI#store` → `StoreResolver` + `UnifiedGate`
**2.2** — Port MCP: `McpAdapter` → `UnifiedGate` directly, skip Catalog→Session chain
**2.3** — Port Web: `WebAdapter` → `UnifiedGate`
**2.4** — Delete: `session.rb`, `bridge.rb`, `context.rb`, `dispatch.rb`
**2.5** — Clean `Builder::Runtime`: remove dual-wire, keep only UnifiedGate

### Phase 3 — Optimize (3 tasks)

**3.1** — Remove `IndexRebuilder.rebuild!` from ingest handler (Put.call step 11 already indexes)
**3.2** — Batch inserts via `multi_insert` in IndexRebuilder
**3.3** — Delete FileStore, CursorStore, their delegations in Infra::Store

### Phase 3.5 — Add session TTL sweep to `drain` handler

## Risk Mitigation

- **Phase 1 is 100% additive** — zero existing code changed, zero regression
- **Phase 2 port one surface at a time**: CLI → MCP → Web
- **Regression guard**: all surfaces must produce identical output for same verb+args (`spec/conformance/surface/cli/contract_spec.rb`)
- **Web auth remains TODO** (deferred, same as today's prototype skip)
