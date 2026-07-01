---
name: '0123-mcp-session-resilience'
uid: ''
refines: knowledge.architecture.conventions
---

# ADR-0123: MCP session resilience — cursor persistence, soft drift, audit retention

## Status

Accepted

## Date

2026-07-01

## Context

The MCP server (Surface::MCP::Server) holds session state in process memory
— the audit cursor (`@cursor`) and the contract etag (`@contract_etag`).
Three failure modes degrade the agent experience:

1. **Cursor loss on restart.** When the MCP server process restarts (crash,
   Claude Code reconnection, deploy), `Store#build_session!` resets the cursor
   to `audit_log.latest_seq`. The agent silently misses everything that changed
   between the last pulse and the restart. The Cursor class (Store::Cursor)
   already supports `read`/`write` to `.state/cursors/<role>`, but the MCP
   server never writes to it.

2. **Hard ContractDrift error.** When the manifest/schemas change mid-session,
   the next write raises `ContractDrift` (-32001). ADR 0083 narrowed the guard
   to writes-only and made `boot` self-heal, but the error is still a hard
   JSON-RPC error that most agents handle poorly — they fail the write and
   move on without calling `boot`. The agent never sees the warning in the
   normal `pulse` flow.

3. **Cursor expiry.** The audit log rotates when it exceeds `max_size` bytes,
   keeping `keep` rotated files. If the cursor seq falls into a rotated file
   that was dropped, `pulse` raises CursorExpired. For stores with frequent
   writes and small rotation windows, this is a recurring problem.

## Decision

### 1. Periodic cursor checkpoint in MCP server

The MCP server starts a background thread that writes the current cursor to
`.state/cursors/<role>` every N seconds (configurable; default 30s):

```
Thread.new do
  loop do
    sleep(checkpoint_interval)
    Store::Cursor.new(root: @store.root, role: @store.role).write(@store.cursor)
  end
end
```

On server start, `build_session!` checks the cursor file first. If a
persisted cursor exists and is <= `latest_seq`, resume from it instead of
`latest_seq`. This survives process restarts and deploys.

The cursor file already exists and is gitignored — this decision just extends
who writes to it (previously: CLI only; now: MCP server too).

### 2. Soft contract drift in pulse response

Instead of raising a hard error on write, the MCP server checks drift before
_every_ verb (reads and writes) and attaches the drift status to the `pulse`
response:

```json
{
  "cursor": 1423,
  "changed": [...],
  "pending_review": [...],
  "contract_drifted": true,
  "contract_etag": "sha256:abc123..."
}
```

When `contract_drifted` is true, the agent knows to call `boot()` to
re-orient. Writes during drift raise a soft warning (not a hard error) — the
agent can choose to proceed or re-orient first.

Reads and `boot` bypass the check entirely (consistent with ADR 0083).

### 3. Never-expire audit log

Set the default `keep:` value to a number that guarantees the audit log never
rotates past any plausible cursor lifespan. Raised from `5` to a much higher
value. The audit log is NDJSON with rotation; rotation is an operational
concern, not a protocol invariant.

A `textus doctor` check warns when the store is approaching the retention
limit with active cursors still in the oldest rotated file — giving the
operator time to increase `keep:` before any cursor expires.

## Consequences

- **Positive:** MCP server survives restarts — cursor persists within 30s.
- **Positive:** Agent sees `contract_drifted: true` in pulse and can
  gracefully re-orient without error handling.
- **Positive:** Audit cursor expiry eliminated as a failure mode.
- **Neutral:** Adds one background thread per MCP server process. Thread is
  minimal (sleep-write-loop); overhead is negligible.
- **Negative:** Periodic cursor writes are eventually consistent — up to 30s
  of cursor loss on crash. Acceptable: pulse is a delta, not a checkpoint;
  re-emitting a few recent entries is harmless.
- **Cost:** ~50 lines of server code + config plumbing for checkpoint interval.

## Alternatives Considered

### Write cursor synchronously after every pulse
Rejected. Adds synchronous I/O to the pulse path. The agent calls pulse once
per turn; the latency of a single file write is fine, but coupling I/O to
the dispatch path is unnecessary when a background thread achieves the same
goal without adding latency to the agent's hot path.

### Write cursor to SQLite instead of file
Rejected. The cursor file is gitignored, trivially readable, and already
exists. SQLite adds no benefit for a single integer value that is written
periodically.

### Keep hard ContractDrift error but improve error message
Rejected. The hard error forces the agent into error-handling branches that
most LLMs handle poorly. A soft flag in the normal pulse flow is more
reliable — the agent sees it in the same response it always reads.

### Server-managed cursor via MCP session metadata
Rejected. The MCP protocol (2025-11-25) has no standard session metadata
mechanism. A file-based cursor is transport-agnostic.

### Cursor expiry as a warning instead of error
Rejected. A truly expired cursor (seq no longer exists in any rotated file)
means the agent permanently missed changes. Adding `keep:` defaults and a
doctor check addresses the root cause instead of papering over the symptom.
