---
proposal:
  target_key: knowledge.loop.evidence.0129-dependency-adapter-gate
uid: fb22429ee25d4f15
---
# Dependency Adapter Gate

**Status:** Accepted
**Date:** 2026-07-03

## Context

The codebase depends on several external libraries (Sequel, sqlite3, MCP SDK)
and concurrency primitives (Thread). These dependencies need to be swappable
for testing, future migration, or alternative implementations without changing
domain code.

## Decision

All external dependencies are gated behind a `DependencyAdapters` namespace.
Each adapter exposes a minimal interface consumed by the rest of the codebase
at construction time via `Store::Builder`.

### Adapters

| Adapter | Dependency | Interface |
|---------|-----------|-----------|
| `SequelAdapter` | `sequel` gem | `connect(path) -> Sequel connection` |
| `SqliteAdapter` | `sqlite3` gem | `connect(path) -> SQLite3 connection` |
| `MCPAdapter` | `mcp` gem | `serve(server) -> transport` |
| `ConcurrencyAdapter` | `Thread`/`Queue` | `pool(size, &block) -> pool` |

### Wiring

```ruby
class Builder
  SEQUEL_ADAPTER = DependencyAdapters::SequelAdapter.new

  def call(root)
    @db = SEQUEL_ADAPTER.connect(layout.store_db_path)
  end
end
```

Ports consume the adapters result, not the adapter itself — the adapter is
a construction-time concern only.

## Consequences

- Dependencies are explicit and centralized
- Adapters can be swapped in tests without monkey-patching
- Adding a new backend (e.g. PostgreSQL) requires only a new adapter
- Slight indirection at construction time
