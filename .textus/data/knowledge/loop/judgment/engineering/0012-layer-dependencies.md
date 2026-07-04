# Layer Dependency Rules

## Rule: Dependencies point inward

```
Surface → Protocol → Infra → Value
     ↘         ↓         ↓
       Workflow ←────────┘
```

- **Value** — zero dependencies beyond Ruby stdlib. Pure data objects only.
- **Infra** — depends on Value. May reference Protocol types (Format, Layout)
  via injection, never by construction.
- **Protocol** — depends on Value + Infra. Owns all dispatch, manifest,
  session, and boot logic.
- **Workflow** — depends on Protocol + Value + Infra. Owns the workflow
  engine (runner, registry, publisher).
- **Surface** — depends on Protocol + Workflow + Value + Infra thin.
  Owns CLI, MCP, and Watcher entry points.
- **Lanes** — depends on Protocol. Must NOT reach into Infra directly
  (route through Protocol EntryStore instead).

## What each layer constructs vs receives

| Layer | Constructs | Receives (injected) |
|-------|-----------|---------------------|
| Value | — | — |
| Infra | FileSystem, Database, Store | — |
| Protocol | Session, Gate, Builder, Handlers | Container (from Builder) |
| Workflow | Runner, Registry, Publisher | Container |
| Surface | CLI, MCPServer, Watcher | Session |

## Store conventions

`lib/textus/infra/store/` contains the raw persistence layer. Each store wraps one
database table or the filesystem. The organizing principle is **domain concern**,
not table count.

| Pattern | Convention | Stores |
|---------|-----------|--------|
| **Store** | `get`/`set` for single-record read/write | `CursorStore` |
| **Queue** | `push`/`pop` for state-machine lifecycle | `WorkflowQueue` |
| **Index** | `record`/`remove`/`search` for search index | `EntryIndex` |
| **Graph** | `add`/`remove`/`from`/`to`/`reachable` for edges | `LinkStore` |
| **Log** | `append`/`list` for append-only history | `AuditLog` |
| **File** | `read`/`write`/`delete`/`move` for raw bytes | `FileStore` |

These are naming conventions, not shared implementation. A generic CRUD base
is avoided because each store has unique insert semantics (upsert vs replace
vs append vs ignore). `Store::Base` provides only `table()`, `result()`, and
`results()` helpers for Sequel queries and symbol-keyed row normalization.

Every store returns **symbol-keyed hashes** or nil — never raw integers, raw
Sequel rows, or string-keyed hashes. This gives callers a consistent data
format regardless of which store they access.

## Violations to fix

- `lanes/ingest/` bypasses Protocol and hits `Infra::Store::Index` directly —
  route through Protocol EntryStore.
- `value/etag.rb` previously constructed `Protocol::Layout` — fixed in 0011:
  now accepts `layout` as parameter.

---

See also: `knowledge.loop.judgment.engineering.0009-conventions`, commit `97abe966`
