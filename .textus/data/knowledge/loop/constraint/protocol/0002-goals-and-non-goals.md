## 2. Goals and non-goals

**Goals**
- Stable wire format (`textus/4`) any language can speak.
- Deterministic read/write of structured Markdown via a CLI returning JSON.
- Schema-validated frontmatter using YAML schemas as data.
- Capability-based write gates (roles hold capabilities; write authority per lane is derived from the role's capabilities and the lane's kind).
- Optimistic concurrency via ETags.
- Pure declarative data sources: produced entries acquire their data via workflow DSL steps; rendering (ERB) is a separate publish concern.
- Publish derived entries to well-known paths as body-only plain files.
- Plain-file backend — consumers can also read raw if they prefer.

**Non-goals**
- Not a database. No queries, indexes, joins, or full-text search.
- Not a graph store. Keys are hierarchical strings; cross-links are unindexed.
- Not a sync protocol. Single-writer per file, ETag-checked.
- Not a transport. Spawn the CLI or wrap it in MCP/HTTP downstream.
- Not a UI. Filesystem + CLI. Viewers ship elsewhere.
- Not a fetcher. textus declares sources; external automation invokes actions to materialize them.
- Not an executor. textus computes pure projections but never spawns shell commands.
