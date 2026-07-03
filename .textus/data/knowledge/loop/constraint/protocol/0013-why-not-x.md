## 13. Why not X?

- **Why not MCP?** MCP is a transport; textus is a data model. The two compose: a 50-line MCP server can wrap `textus get/put` as tools. textus exists because the *shape* of agent-readable project memory deserves a standalone spec, separate from how it's served.

- **Why doesn't textus execute external build commands itself?** textus is a dataflow oracle, not a build runner. The moment a spec includes process execution, it inherits shell-injection surface, OS-portability concerns, and signal-handling semantics — and ends up duplicating whatever build system the consumer already runs (make, rake, just, lefthook, CI). Keeping execution external means a Python or TypeScript port of `textus/4` only has to parse YAML and emit JSON; it doesn't have to spawn processes safely. External build systems stay the executor; textus stays a data tool.

- **Why not plain Markdown vaults (Obsidian / Foam)?** No schema enforcement, no write-gating, no addressable wire format. Fine for human notes; underspecified for agents that must act on the contents deterministically.

- **Why not Notion / Coda?** Closed, hosted, lossy export. textus is local-first, plain-files, diffable in git.

- **Why not JSON Schema for the schemas?** Considered. Bespoke YAML chosen for v1: simpler implementation, lighter dependency footprint, matches the reference impl's house language. JSON Schema MAY be added as an alternate schema-language adapter in a future minor revision without breaking `textus/4`.

- **Why not a database (SQLite, kv store)?** textus's whole point is that the storage is plain files agents and humans both read. A binary store loses git-diff, grep, and editor support.

- **Why not vector embeddings?** Different problem. textus is for facts agents act on deterministically; embeddings are for fuzzy retrieval. They compose — index a textus tree into a vector store if you need both.
## 13.1 Layered architecture (internal)

Textus internals are organized as one-way layers — **Surfaces** (`surfaces/cli/`, `surfaces/mcp/`) → **Contract** (`contract/`) → **Dispatch** (`dispatch/`) → **Manifest + Core + Ports + Step** (domain and adapters). Each layer imports only from layers to its right. Plugin authors touch only the Step DSL and the manifest YAML; the layering is internal and may evolve.

See [`docs/architecture/README.md`](../../architecture/README.md) for an ASCII diagram and the full read-path walkthrough.


