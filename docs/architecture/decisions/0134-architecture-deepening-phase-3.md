---
_meta:
  title: "Architecture deepening phase 3 — Writer port, single Infrastructure, manifest→workflow boundary"
  authors: [patrick]
  status: proposed
  date: 2026-07-01
---

# ADR-0134: Architecture deepening phase 3 — Writer port, single Infrastructure, manifest→workflow boundary

## Status

Proposed

## Date

2026-07-01

## Context

### Container fragmentation

Three container-like objects with overlapping fields:

- **`Store::Infrastructure`** (12 fields) — built by Builder, holds all ports
- **`Store::UseCaseContainer`** (10 fields) — manual projection of Infrastructure for use cases
- **`ContainerHelpers`** (3 methods) — re-delegates manifest, repo_root, store_root from container

Use cases receive `UseCaseContainer` while the dispatch pipeline receives `Infrastructure`. Adding a new port requires updating both structs and the proxy builder.

### Writer/Reader construction proliferation

`Store::Entry::Writer` is constructed in 5 places via a `.from(container:, call:)` factory: PutEntry, ProposeEntry, AcceptProposal, Workflow::Runner, Retention. The factory checks for a test-injection point, then constructs from scratch. Same pattern for Reader.

### Double event emission

`Event::EntryWritten` is emitted by both the use case and the `AuditIndex` middleware for every put. The `CascadeSubscriber` (and thus the Planner) runs twice, scheduling duplicate materialize jobs.

### Manifest carries lifecycle config

The manifest YAML declares `publish`, `source`, `rules` (guard, retention, react) alongside structural fields (lanes, entries, roles). The workflow DSL already has `match`, `step`, `publish` — duplicating publish targets and match patterns. Lifecycle config is spread across two declaration systems with no clear seam.

### Shallow wrappers

`Workflow::Collector` (thread-local singleton proxy), `Workflow::Registry` (array wrapper), `Dispatch::HandlerRegistry` (hash wrapper) — each adds zero behavior. `Produce::Publisher` is a 7-line bootstrap called from exactly one site.

## Decision

### 1. Single Infrastructure container

Collapse `Infrastructure` + `UseCaseContainer` + `ContainerHelpers` into one `Data.define`:

```ruby
Infrastructure = Data.define(
  :manifest, :file_store, :schemas, :audit_log, :job_store,
  :layout, :link_edge_store, :workflows, :root,
  :reader, :writer,
  :event_bus, :freshness_evaluator, :trace_buffer, :pipeline,
)
```

- `reader` and `writer` are pre-constructed in Builder and stored as ports
- `root` moves from UseCaseContainer into Infrastructure
- `UseCaseContainer` is deleted — use cases receive `Infrastructure` directly as `container`
- `ContainerHelpers` is deleted — its 3 methods inlined at call sites
- `Store#build_container_proxy` is deleted — `@ctx` is the container

### 2. Writer as Container port

- `Writer#initialize` drops `call:` — takes only ports: `file_store, manifest, schemas, audit_log, reader, layout`
- `call:` moves to `put(key, ..., call:)`, `delete(key, ..., call:)`, `move(from_key:, ..., call:)` as per-method keyword arg
- `Writer.from()` factory deleted — callers use `container.writer` directly
- `Reader.from()` factory deleted — callers use `container.reader` directly
- Writer never emits events — cascade is the caller's responsibility

### 3. Single event emitter per operation

- `AuditIndex` middleware is the sole event emitter for surface-initiated write operations (put, delete, mv, propose, accept)
- Use cases drop their `Event::Bus` emission
- Automation path (Workflow::Runner) never emits events — the Planner handles cascades via workflow `depends_on`

### 4. Manifest → Workflow boundary

Manifest becomes a pure data tree descriptor. The following move from manifest YAML into workflow DSL files:

| Manifest (removed) | Workflow DSL (added) |
|---|---|
| `entries[].publish.{to,tree,template}` | `publish to:, template:` |
| `entries[].source.sources` | `depends_on` |
| `rules[].match` | `match` (already exists) |
| `rules[].retention.{ttl,action}` | `ttl`, `on_expire` |
| `rules[].guard` (converge) | Dropped — Writer validates schema |
| `rules[].react` | Dropped — depends_on drives cascades |
| `worker.{pool,poll,lease_ttl}` | Dropped — runtime infrastructure |

Workflow DSL gains:
- `priority: N` — scheduling priority (higher = runs first during drain)
- `depends_on "pattern"` — declares upstream dependencies for cascade scheduling
- `ttl "24h"` — retention TTL
- `on_expire :archive` — retention action
- Inline `publish to:, template:` — per-target publish destinations

### 5. Remove shallow wrappers (cleanup)

- `Workflow::Collector` — replace thread-local singleton with direct block parameter
- `Workflow::Registry` — replace with plain `Array<Definition>`
- `Dispatch::HandlerRegistry` — replace with plain `Hash`
- `Produce::Publisher` — inline its 7 active lines into `Engine#publish_only`

### Breaking changes accepted

This is a hard cut. Manifest YAML drops `publish`, `source`, `rules`, `worker` sections. Workflow DSL gains `depends_on`, `priority`, `ttl`, `on_expire`. All Writer/Reader construction sites change from `Writer.from(container:, call:)` to `container.writer.put(key, ..., call:)`. Wire format unchanged; protocol version stays textus/4.

## Consequences

### Positive

- One container object — add a port once, available everywhere
- Writer as port — one construction site, clear seam for testing
- Single event emitter — no duplicate jobs from double cascade
- Manifest is honestly structural — workflow is honestly behavioral
- Planner derives cascades from workflow `depends_on`, not react rules
- ~130 lines of pass-through wrappers deleted

### Negative

- Breaking: existing manifest YAML files must remove `publish`, `source`, `rules`, `worker` sections
- Breaking: existing workflow files must add `depends_on`, `ttl`, `on_expire` where applicable
- Breaking: test code that calls `Writer.from()` must switch to `container.writer`
- Workflow DSL gains surface area (~5 new declarations) — learning cost

## Alternatives considered

### Keep container split (Infrastructure + UseCaseContainer)

The phase-2 ADR-0119 proposed splitting into Infrastructure/Coordination; this ADR takes the opposite direction (merge into one). The split was motivated by "some fields are boot-only" but in practice carrying `event_bus`, `trace_buffer`, `freshness_evaluator` in a single struct is harmless — they're never accessed by use cases that don't need them. A single struct eliminates the projection cost and the dual-maintenance tax.

### Keep middleware event emission AND use case event emission

Rejected: the double emission is a bug, not a feature. The middleware has the most accurate view of the complete operation (after the handler returns, after audit is committed), so it is the natural single emitter.

### Keep react rules for cascade

Rejected: workflow `depends_on` is more explicit and more visual than manifest YAML react blocks. The Planner iterates workflow definitions instead of manifest rules — same logic, clearer source.

### Keep Worker config in manifest

Rejected: pool size, poll interval, lease TTL are runtime/infrastructure configuration that should not live in the data tree descriptor. They belong in environment configuration or a separate runtime config file.
