---
uid: 1e4f8a2b9c0d7e3f
refines: knowledge.loop.judgment.engineering.0009-conventions
---

# ADR 0130: Runtime architecture deepening — Store consolidation, state layout split, audit unification, cursor atomicity

**Status:** Accepted

**Date:** 2026-07-04

## Context

The runtime infrastructure had accumulated several structural weaknesses:

1. **State directory catch-all.** `.textus/.state/` mixed four unrelated concerns under one namespace: SQLite database, append-only audit log, cursor checkpoints, sentinel metadata. An operator couldn't tell which parts needed backup and which were ephemeral.

2. **Dual event systems.** The audit log (flat JSONL file with custom rotation) and the `events` SQLite table (workflow scheduling with retry state) recorded the same write operations independently. Querying both required scanning a flat file AND a SQLite table — `pulse` couldn't report workflow progress alongside audit history.

3. **Cursor race condition.** Two independent paths (MCP server checkpoint thread every 30s, `pulse` handler after each response) wrote to the same flat cursor file without locking. A race regressed the cursor, causing event replay.

4. **Scattered persistence.** Six modules each managed their own I/O: `Protocol::Audit` (flat file + flock), `Protocol::Cursor` (flat file), `Protocol::Index` (SQLite directly), `Protocol::Links` (SQLite directly + resolver logic), `Protocol::Events::EventStore` (SQLite directly), `Protocol::EntryStore` (filesystem I/O). No single seam for persistence.

5. **Hypothetical port interfaces.** `Infra::Port::*` defined 6+ module Interfaces with one implementation each. The seam existed on paper but was never exercised — no adapter was ever swapped.

6. **Agent loop state invisible to protocol.** The knowledge pipeline loop nodes existed only as manifest entries and an agent-prompt description. `pulse` returned change history but couldn't tell an agent which loop phase was active.

## Decision

### 1. State directory split

`.textus/.state/` splits into four subdirectories of `.textus/`:

- `db/` — SQLite database (backup target)
- `log/` — append-only logs (logrotate target)
- `run/` — ephemeral scratch: cursors, locks (safe to delete)
- `track/` — sentinel metadata (durable but derivable)

Hard cut — no backward compat. Old `.state/` path methods removed from Layout.

### 2. Single Store seam

All persistence consolidates into `Infra::Store` with four sub-stores:

| Sub-store | Tables | Absorbs |
|---|---|---|
| `Store::EntryStore` | `entries`, `entries_fts` + file I/O | `Protocol::EntryStore`, `Protocol::Index` |
| `Store::EventStore` | `audit_events`, `workflow_events` | `Protocol::Audit`, `Protocol::Events::EventStore` |
| `Store::CursorStore` | `cursors` | `Protocol::Cursor` |
| `Store::LinkStore` | `link_edges` | `Protocol::Links` (edge storage only) |

### 3. Remove Infra::Port::* interfaces

Six port modules removed: `Port::Clock`, `Port::Database`, `Port::EventStore`, `Port::Storage`, `Port::Publisher` interface, `Port::SentinelStore` interface. All had single adapters — the `Infra` implementations are the real seam. Publisher, Sentinel, and SentinelStore remain as concrete classes (they do orchestration, not persistence).

### 4. Flat-file audit log removed

Audit history moves entirely to the `audit_events` SQLite table. Custom rotation (flock, file rename, sidecar meta) is replaced by SQLite retention queries. `Protocol::Audit` file deleted.

### 5. Cursor moves to SQLite

Cursor checkpoints move from a flat file to the `cursors` SQLite table with atomic UPSERT. MCP server checkpoint thread removed — `pulse` writes cursor inside its own transaction. Race condition eliminated.

### 6. Events table renamed

`events` → `workflow_events` for symmetry with `audit_events`.

### 7. Infra::FileStore renamed to FileSystem

Reflects the raw layer naming convention: `FileSystem` is the lowest-level concept, same as `Database`, `Clock`, `Locks`.

### 8. Advisory loop state in pulse

`pulse` response gains a `loop_state` field with `current_node`, `index`, `total`, and `nodes`. The `Knowledge::Runner` is not deepened into a state machine — it remains descriptive. Agents read `pulse.loop_state` to decide what to work on.

### 9. Container simplified

Container drops 7 fields (`file_system`, `entry_store`, `entry_index`, `event_store`, `audit_log`, `link_graph`) in favor of a single `store` field. Builder drops inline construction of 5 intermediate objects.

## Consequences

### Positive

- **Single persistence seam.** All SQLite access flows through `Store`. One adapter, one test surface.
- **No cursor race.** Atomic SQLite UPSERT replaces unlocked file writes. No checkpoint thread.
- **Unified event query.** `pulse` reads from the same SQLite table as workflow consumers.
- **Clear operational layout.** Operators know which dirs need backup (`db/`, `track/`) and which are ephemeral (`run/`).
- **Agents discover loop state.** `pulse` returns loop phase — no CLAUDE.md parsing needed.
- **~20 files deleted.** Port interfaces, ghost infra modules, scattered persistence wrappers removed.
- **Container is deeper.** 6 fields instead of 13. One `store` object replaces 5 distinct dependencies.

### Negative

- **Hard cut.** All existing `.textus/.state/` directories must migrate by hand or via a migration script. No backward compat.
- **Large diff.** ~2500 lines across ~50 files.
- **Link resolver stays split.** `Store::LinkStore` handles edge storage; `Protocol::Links::Resolver` handles URI resolution. Two modules where one could suffice, but the resolver has domain logic (URI rewriting) that doesn't belong in the infra store.

### Migration

1. Delete or rename old `.textus/.state/` directory
2. `textus init` creates `db/`, `log/`, `run/`, `track/` with correct gitignore
3. No audit log import — old flat-file history is discarded (ADR 0038 audit log was ephemeral runtime state)
4. No cursor import — next pulse starts from seq 0

## Alternatives Considered

### Keep Port::* interfaces

Rejected. Every `Port::Interface` had exactly one implementation. The seams were hypothetical — no adapter was ever swapped, and the interface modules added ceremony without leverage. The real seam is `Infra::Store`.

### Gradual migration with symlinks

Rejected (user decision). The old `.state/` paths are used directly in 49 source files. A symlink bridge adds complexity without value — the hard cut forces all callers to update, which was going to happen anyway.

### Deepen Knowledge::Runner into a state machine

Rejected. The loop is a protocol concern between agent and project — driving it from the runtime would couple the project's development cycle to a state machine. Advisory loop_state preserves agent autonomy.

## Implementation

Implementation order:
1. Layout paths + Infra renames
2. Store module (EntryStore, EventStore, CursorStore, LinkStore)
3. Container/Builder simplification, delete old modules
4. Update callers (handlers, MCP server, init, doctors)
5. Pulse enrichment
6. Test updates + file deletions
