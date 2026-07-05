---
proposal:
  target_key: knowledge.loop.evidence.0137-agent-surface-deepening
  action: put
uid: d8f1b0a3488bcb3b
---
# ADR 0137 — Agent surface deepening: script format, schema validation, boot catalog, MCP integration test

**Date:** 2026-07-05
**Status:** Proposed
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (CLI/MCP surface contract), [ADR 0089](./0089-ingest-is-system-pushed.md) (put pipeline), [ADR 0115](./0115-role-trust-model.md) (role capability gates)

> **One sentence:** Six deepening candidates from an architecture review of the agent surface were implemented: (1) fix propose→accept format breakage, (2) remove dead scratchpad scripts/ directory, (3) add script format to the registry, (4) wire schema validation into the put pipeline, (5) add MCP end-to-end integration tests, (6) add schema catalog to boot envelope and schema_list verb.

## Context

An architecture review of textus from the agent's perspective surfaced six candidates where modules were shallow — interfaces nearly as wide as their implementations — or where complexity leaked across seams.

### 1. Propose→Accept format breakage (real bug)

The `accept` handler promoted proposals to their target by calling `ctx.put(key: target, meta: env.meta["_meta"] || {}, body: env.body, content: nil, call:)`. Two problems:

- **`content: nil` unconditionally** — for JSON/YAML proposals with structured `content` hashes, the data was discarded on promotion. The proposal's body string was re-serialized by the target put, losing structure.
- **`env.meta["_meta"]`** — the meta hash returned by `read` is the frontmatter itself; there is no nested `_meta` key inside it. This always returned nil, discarding any user metadata on promotion.
- **Proposal block leaked** — the `proposal` control key (`target_key`, `action`) was silently passed through to the target entry's meta.

### 2. Dead scratchpad scripts/ directory

`session_open` created `scripts/`, `notes/`, and `output/` subdirectories under each session workspace, but no surface tool (MCP or CLI) could write to them, read from them, or execute scripts within them. The deletion test confirmed shallowness: deleting the three `mkdir_p` calls removed no observable behaviour.

### 3. No executable/script format in the type system

The format registry supported `[markdown, json, yaml, text]` — none of which express "this is runnable." An agent writing a Ruby/Python/bash script had no way to signal shebang, executable bit, or language. All script content collapsed into the `text` format.

### 4. Schema validation was a hypothetical seam

`Schema#validate!` existed and worked on any frontmatter hash, but `validate_raw_entry!` only fired for the `raw` lane (YAML format). For all other lanes (`knowledge`, `scratchpad`, `artifacts`), entries declaring `schema:` in the manifest passed through unchecked. The interface (`validate_raw_entry!` on every format class) was as wide as the no-op.

### 5. No MCP end-to-end integration test

The MCP surface — the primary way agents interact with textus — had no test sending real messages through `Server#dispatch`. The `dispatch` method (error handling, drift annotation, cursor advance) had coverage only via unit-mocked callers. The JSON-RPC protocol layer (`@sdk.handle_json`) was wholly untested.

### 6. Agent cannot discover schemas from the protocol

`schema_show` required a key — but the agent didn't know which keys existed or which schemas were available until reading the manifest directly. The `boot` envelope listed verbs and lanes but not schemas or formats. Every agent had to rediscover the schema catalog through trial and error.

## Decision

### 1. Propose→Accept meta and content propagation

`accept` now strips only the `proposal` control key from the proposal's meta and passes the remaining meta to the target put. It also passes `env.content` (the structured content) instead of `content: nil`, so JSON/YAML proposals preserve their data shape on promotion.

```ruby
target_meta = env.meta.to_h.reject { |k, _| k == "proposal" }
ctx.put(key: target, meta: target_meta, body: env.body, content: env.content, call:)
```

### 2. Dead directories removed

The three `mkdir_p` calls removed from `session_open`. The `workspace` field removed from the response hash. The `FileUtils` assertions removed from the spec. Agents write script content as entries in the data lane.

### 3. Script format registered

A new `Format::Script` class — raw-bytes serialization (same as `Text`) but with `.rb`/`.py`/`.sh`/`.js`/`.pl`/`.rs`/`.exs` extensions. No shebang injection, no executable-bit manipulation, no execution verb. The `script` format is registered in `STRATEGIES` and `EXT_TO_FORMAT`. Language is stored in `_meta.lang` when provided.

The format is available for any manifest entry declaring `format: script`. Restriction to scratchpad is a deployment policy, not a format constraint.

### 4. Schema validation in the put pipeline

A new `ValidateSchema` step in `PutPipeline::STEPS`, running after `ValidateInput` and before `ReadExisting`. When an entry's manifest declares `schema: X`, the pipeline loads `Schema::Registry.fetch(X)` and calls `schema.validate!(meta)`. Lane-aware policy:

- `knowledge` / `artifacts` / `raw`: violation raises `SchemaViolation` — the write is rejected
- `scratchpad`: violation silently swallowed — working drafts can be schema-invalid

Access to schemas is threaded through `StoreEngine` → `WriteDeps` → `ValidateSchema`. The `Builder` passes the schema registry to `StoreEngine` on construction. All existing `StoreEngine.new` call sites updated.

### 5. MCP integration test

Three integration tests in `spec/integration/surface/mcp_agent_workflow_spec.rb` using the `textus/4 conformance fixture`:

- **Full cycle**: session_open → get → put → propose → diff → accept → list → pulse
- **Reject flow**: propose → reject → verify proposal deleted
- Each test creates real `MCP::Server`/`Session.open` instances and exercises `Server#dispatch`

The `session_open`/`session_close` verbs were added to `ENTRY_VERBS` in `VerbRegistry` so the `Session#method_missing` dispatcher can route them. The conformance fixture gained a `scratchpad.proposals` directory and manifest entry.

### 6. Schema catalog in boot + schema_list verb

The `boot` envelope now includes a `schemas` block listing every registered schema: name, required fields, optional fields, field types, and evolution history. Added by `Boot.build_schemas(container.schemas)` in `Boot.build`.

A new `schema_list` verb (no arguments, `:read` category) returns the same schema catalog. Registered in `VerbRegistry`, wired through `Handlers::System#schema_list`, available on both CLI (`textus schema list`) and MCP.

## Consequences

- **Propose→Accept now format-agnostic.** JSON/YAML structured content survives promotion. Text and markdown proposals unaffected (content is nil, falls back to body).
- **Script format exists for declarative use.** No manifest change yet — the format is available when an entry declares `format: script`.
- **Schema validation enforces canon.** Knowledge and artifact entries that declare a schema are now validated at write time. Existing schema-declared entries in `knowledge.contacts` and `execution.runbook/*` will be enforced.
- **Agent workflow is integration-tested.** The full propose→accept cycle now has coverage through `Server#dispatch`. No more blind spots in the MCP surface.
- **Agent can discover schemas at boot time.** No need to probe keys to learn schema shape.
- **Root cause of leaky meta propagation in accept identified.** The UID from the proposal entry overwrites the target entry's UID because `InjectMeta` preserves the incoming UID. A future fix should strip system-managed fields (`uid`, `sources`) from the accepted meta at the accept handler level.
