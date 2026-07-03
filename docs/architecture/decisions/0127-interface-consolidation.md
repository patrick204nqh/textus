# ADR 0127: Interface Consolidation — Port Split, Container Groups, Use Case Classes

**Status:** Accepted

**Date:** 2026-07-03

**Author:** Agent (opencode)

## Context

Phase 1 of the architecture deepening removed four legacy subsystems (doctor, enqueue, rules, schema validation) and replaced the event/job system with a unified Sequel-backed events table. This left several inconsistent boundaries:

- **`Port::Store`** conflated database connection management with event semantics
- **`Port::Storage`** was a fragmented namespace with `Interface`, `FileStore`, and `FileStat` — no single port for all filesystem operations
- **`Store::Infrastructure`** was a flat `Data.define` with 16 fields — no semantic grouping
- **Use cases** were modules with raw `HANDLES`/`NEEDS` constants read reflectively — no enforced shape
- **Event emission** was duplicated in every write use case
- **`Boot`** was a single 185-line module handling catalog, protocol, and context assembly
- **Filesystem I/O** was scattered across ports calling `File`/`FileUtils`/`Dir` directly

## Decision

### 1. Port Splits

- **`Port::Store`** split into `Port::Database` (connection lifecycle) and `Port::EventStore` (event semantics). The old implementation's table creation and WAL setup moved to `Port::Database#setup!`; event CRUD moved to `Port::EventStore` (implemented via `Store::EventStore` wrapping Sequel).
- **`Port::Storage::Interface/FileStore/FileStat`** retired in favor of a single `Port::FileSystem` with 17-method `Interface`. Implementation `Store::FileSystem` wraps `File`, `FileUtils`, `Dir`. Every port (`Publisher`, `AuditLog`, `BuildLock`, `WatcherLock`, `SentinelStore`) now accepts `file_system:` and routes all I/O through it.

### 2. Container Restructuring

- **`Store::Container`** replaces `Store::Infrastructure`. Uses five `Data.define` component groups:
  - `Storage` (file_system, entry_store, layout)
  - `Events` (event_store, workflows)
  - `Governance` (manifest, schemas)
  - `Logging` (audit_log)
  - `Links` (link_graph)
- `Container#to_h` provides a flat view for HandlerResolver backward compatibility.
- `Store::EntryStore` merges the old `Entry::Reader` + `Entry::Writer` into one facade.
- `Store::LinkGraph` merges `Links::LinkEdgeStore` + `Links::Resolver` + `Links::UriRewriter`.
- `Store::Builder` was rewired to construct the grouped `Container`.

### 3. Use Case Classes

- **`UseCases::Base`** provides a class-level DSL: `handles(contract)` and `needs(*fields)`. The `.call(command, call, deps)` class method instantiates, injects deps via `needs`, and runs the instance method `call`.
- All 25 use cases converted from modules to classes.
- `HandlerResolver` reads `handles_contract`/`needs_fields` class methods instead of `HANDLES`/`NEEDS` constants, with `respond_to?` fallback.

### 4. Events Middleware

- **`Dispatch::Middleware::Events`** replaces inline `EventEmitter` in all write use cases. Fires after successful use case completion using an `EVENT_MAP` from contract class to event type string.
- Pipeline order: Binder → Trace → Auth → Events → UseCase.

### 5. Boot Split

- **`Boot::Catalog`** — CLI verb catalog (`CURATED_CLI_VERBS`, `contract_summaries`, `build`)
- **`Boot::Protocol`** — agent protocol envelope shape + lanes/roles
- **`Boot::Context`** — boot envelope assembly (reads artifacts/boot context entries)
- `Boot.build` reduced to a coordinator calling the three modules.
- `recipes` block removed from protocol output (diverged from actual agent protocol).

### 6. VerbRegistry Split

- `ArgSpec` and `VerbSpec` Data.define types extracted to `verb_registry/arg_spec.rb` and `verb_registry/verb_spec.rb`.

### 7. WritePipeline Split

- `Store::Entry::WriteStep` (312 lines) split into `store/write_pipeline.rb` (shared types) + `write_pipeline/put.rb`, `delete.rb`, `move.rb`.

## Consequences

### Positive

- Each port now has a documented `module Interface` with method signatures
- Container communicates architectural structure through named component groups
- Use cases have an enforced shape and consistent dependency injection
- Event emission is a cross-cutting concern handled once in middleware
- Boot has three focused modules instead of one catch-all
- All filesystem operations route through a single port, making testing/replacement easier
- Write pipeline has one concern per file

### Negative

- Large diff (~2500 lines across ~50 files) makes review harder
- `call: call` in use case `#call` methods caused infinite recursion (fixed by using `@call`)
- `HandlerResolver` uses `respond_to?` instead of checking `to_h` keys, which is more flexible but less explicit
- `Container#to_h` doesn't include all delegation methods (`writer`, `reader`, `link_edge_store`) — kept as `respond_to?` fallback in HandlerResolver

### Migration

All changes are backward-compatible within this branch. No data migration required. The old `Store::Infrastructure`, `Port::Store`, `Port::Storage::*`, `Store::Entry::*`, and `Links::LinkEdgeStore` files have been deleted.
