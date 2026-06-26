---
name: '0121-api-interface-hygiene'
uid: 73D74CA486A29352
---

# ADR-0121: API and interface hygiene — consolidation pass

## Status

Proposed

## Date

2026-06-23

## Context

An architectural review of textus's API surfaces, interface boundaries, and
module/class namespace identified several accumulated inconsistencies. None are
blockers, but they create friction for new readers, complicate testing, and make
the code harder to reason about than necessary.

Eight findings were flagged:

### 1. Duplicate error classes (CursorExpired)

Two classes define a cursor-expired error:

- `Textus::CursorExpired` (`lib/textus/errors.rb:234`) — raised by audit-log
  rotation checks. Carries `requested` and `min_available` attributes. JSONRPC
  code `-32001` (via `ContractDrift::JSONRPC_CODE`).

- `Textus::Surface::MCP::CursorExpired` (`lib/textus/surface/mcp/errors.rb:6`)
  — raised by MCP cursor handling. JSONRPC code `-32002`.

A consumer catching `Textus::Error` will not catch the MCP variant. The two
classes have different constructor signatures and different error codes. A
single class should serve both surfaces.

### 2. Top-level Result alias

`lib/textus.rb:27` assigns `Textus::Result = Textus::Value::Result`. This
injects a constant into the `Textus` module's own namespace, shadowing any
class that might legitimately be named `Result` and making it unclear whether
`Result` is a value type or a module boundary.

### 3. FileStore port abstraction leak

`Textus::Store::Envelope::Writer` (`lib/textus/store/envelope/writer.rb:88,133,136`)
calls `@file_store.respond_to?(:mv)` and similar checks to decide whether to
use the port or fall back to `FileUtils`/`Dir` directly. This means the port
interface is implicit — a reader must scan the writer to discover which methods
a FileStore is expected to support. Per ADR 0109, every port should be an
instantiable class with a documented interface.

### 4. Validation coupled to the write path

Schema validation, raw-entry validation, and name-match enforcement live in
`Store::Envelope::Writer#put` (`writer.rb:49-51`). Per good API design
practice, validation belongs at the system edge (CLI/MCP handlers) so the
write path stays a thin commit. Currently, testing validation requires going
through the full write pipeline.

### 5. Duplicate write-verb categorization

`Textus::Surface::MCP::Catalog` (`lib/textus/surface/mcp/catalog.rb:10-15`)
maintains hardcoded `WRITE_VERBS` and `MAINTENANCE_VERBS` lists. Adding a new
write verb requires updating both the `VerbRegistry` and the `Catalog`. The
verb-to-surface mapping (which verbs are read vs. write vs. maintenance) should
be a property of the verb spec, not a separate constant.

### 6. Redundant contract fetch in Dispatch.dispatch

`lib/textus/dispatch.rb:6` fetches `VERB_TO_CONTRACT.fetch(spec.verb)` — but
the `Binder` middleware in the pipeline (`middleware/binder.rb:11`) performs
the exact same fetch. This is dead work on every dispatch.

### 7. Schema::Store silently swallows load errors

`lib/textus/schema/store.rb:37-39` catches `StandardError` and calls `next` on
YAML load failures. A broken schema file produces no feedback until a write
fails with an opaque "schema not found" error for a *different* schema.

### 8. Inconsistent module vs class nesting

Under `Store::`, some sub-namespaces are modules (`Envelope`) while others are
classes (`Container`, `Geometry`, `Cursor`, `Freshness::Evaluator`, `Index`).
A reader must check each path to know whether they are extending a module or
subclassing a class. This is cosmetic but adds cognitive load.

## Decision

### 1. Unify CursorExpired

Fold `Textus::Surface::MCP::CursorExpired` into `Textus::CursorExpired`. The
MCP-specific JSONRPC code becomes a constant on the single class. Both error
codes are preserved (`-32001` for contract drift, `-32002` for cursor
expired) on the unified class.

### 2. Remove the Textus::Result alias

Delete `Textus::Result = Textus::Value::Result` from `lib/textus.rb`. All
existing references use `Textus::Value::Result` or are updated to do so.

### 3. Make the FileStore interface explicit

Define a base class or `Interface` module in `Port::Storage` that declares the
expected methods (`read`, `write`, `delete`, `exists?`, `etag`, `mkdir_p`,
`mv`, `rmdir`, `dir_empty?`). `FileStore` inherits from it. The Writer stops
checking `respond_to?` and calls the interface directly.

### 4. Move validation to the boundary

Extract schema validation, raw-entry validation, and name-match enforcement
from `Writer#put` into middleware (or pre-dispatch checks) so the Writer
assumes pre-validated input. The Writer becomes a thin commit that serializes
and writes bytes.

### 5. Categorize verbs in the VerbSpec

Add a `:category` field to `VerbRegistry::VerbSpec` (values: `:read`,
`:write`, `:maintenance`). The MCP Catalog derives its write/maintenance lists
from this field instead of hardcoded constants. The CLI can also use it for
help grouping.

### 6. Remove redundant fetch from Dispatch.dispatch

Delete the `VERB_TO_CONTRACT.fetch` call at `dispatch.rb:6`. The Binder
middleware already handles contract resolution.

### 7. Report Schema::Store load errors

Replace the silent `rescue StandardError; next` with a logged warning or a
re-raise. A broken schema file should be diagnosed immediately, not on the
next write.

### 8. Adopt a namespace convention

Standardise on modules as namespace containers. `Store::Envelope` is already a
module — keep it as the convention. No immediate renames; document the
convention and enforce it for new additions.

## Consequences

**Positive**

- Single cursor-expired error class across CLI and MCP surfaces.
- Port interfaces are documented and enforceable — no more `respond_to?` checks.
- Validation is testable at the boundary without the full write pipeline.
- Adding a new verb requires exactly one change (the VerbSpec) — surface
  categorisation is automatic.
- Fewer redundant lookups in the hot dispatch path.
- Schema loading problems are reported early.
- Consistent namespacing convention for future code.

**Negative**

- Moving validation out of Writer requires restructuring the write pipeline and
  updating all callers that bypass middleware (tests, direct Writer calls).
- The VerbSpec category field is a schema change — all 32 verb registrations
  in `verb_registry.rb` must declare a category.
- Removing the `Textus::Result` alias is a minor breaking change for any code
  (or agent prompts) referencing the top-level constant.

**Neutral**

- The MCP `CursorExpired` error code changes from `-32002` to the unified
  class code, but MCP clients see it only in JSON-RPC error objects and should
  key off the `code` field, not the class name.

## Alternatives Considered

### Keep FileStore implicit

The current `respond_to?` approach works and is flexible for test doubles.
Rejected because it makes the interface invisible — a reader must scan every
call site to know what a FileStore must implement. An explicit interface is
self-documenting.

### Delay validation extraction

Validation could stay in Writer and be tested via Writer unit tests. Rejected
because it couples validation to serialization, making it impossible to
validate input before building the write payload (e.g., in a pre-write preview
or dry-run path).
