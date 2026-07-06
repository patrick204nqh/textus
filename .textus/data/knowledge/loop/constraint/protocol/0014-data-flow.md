---
name: 0014-data-flow
uid: 9b3574ef8d9aa6e8
---
# Data Flow Architecture

All entry points converge at `Session.open` → `StoreEngine`, which dispatches through `Gate` to handler groups. The write pipeline executes an 11-step commit inside `Put.call`; the workflow event chain fans out from that commit via the `EventEmitter` → `WorkflowQueue` → `Consumer` → `Runner` path.

## Entry Points

### CLI Surface

```
argv → CLI.run → Verb#parse → Verb#call(store)
  → Session.open(root)
  → store.with_role(role)
  → Dispatch.call(store, verb, **inputs)
    → store.store_engine → Gate → Handler
```

### MCP Surface

```
JSON-RPC → Server#dispatch
  → Catalog.call(verb_name, store:, args:)
    → store.send(verb, **bound)
  → DriftAnnotation.apply
  → post_dispatch!(verb_name)
```

### Web Surface

```
POST /api/:verb → Web app → Dispatch.call → JSON envelope
```

## StoreEngine

```
StoreEngine
  ├── read(key:)       → resolve → exists? → read → parse → build Envelope
  ├── put(key:, ...)   → Put.call (12-step pipeline)
  ├── delete(key:)     → Delete.call
  ├── move(from, to)   → Move.call
  └── list(...)        → resolve → enumerate
```

## Gate — dispatch seam

```
Gate#dispatch(role, verb, params, call: nil)
  → authorize! → Binder.bind → build context → resolve handler → dispatch
```

## Write pipeline

```
 1. resolve path       6. serialize          11. index_entry
 2. validate_input     7. check_etag         12. emit_event
 3. validate_schema    8. file_store.write
 4. read_existing      9. build_envelope
 5. inject_meta       10. append_audit
```

## Workflow event chain

```
write → emit_event("entry.written") → EventEmitter
  → [workflows_for(event_type), workflows_for_key(key)] → WorkflowQueue
  → Consumer → Runner per match → save/notify/publish → cascade
```

## Read path

Reads are pure — resolve → read → parse → envelope + freshness.
