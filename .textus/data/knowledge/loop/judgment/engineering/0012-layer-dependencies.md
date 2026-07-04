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

## Violations to fix

- `lanes/ingest/` bypasses Protocol and hits `Infra::Store::Index` directly —
  route through Protocol EntryStore.
- `value/etag.rb` previously constructed `Protocol::Layout` — fixed in 0011:
  now accepts `layout` as parameter.

---

See also: `knowledge.loop.judgment.engineering.0009-conventions`, commit `97abe966`
