# MCP transport — reference

> **Reference** · for agent authors · **read when** you need the MCP tool catalog, error codes, transports, or plugin wiring
> **SSoT for** the MCP tool catalog, error mapping, transports, and Claude-plugin wiring · **reviewed** 2026-05 (v0.37)

The exact facts of how an agent talks to a textus store over MCP: the three transports, the stdio JSON-RPC server, its tool catalog, error codes, plugin wiring, and audit-log retention.

For the operational boot → pulse loop and the Claude Code quickstart, see [`../how-to/agents-mcp.md`](../how-to/agents-mcp.md). For the wire protocol, see [`../../SPEC.md`](../../SPEC.md).

## Table of contents

1. [Three transports](#three-transports)
2. [MCP transport (the agent gate)](#mcp-transport-the-agent-gate)
3. [Audit log retention](#audit-log-retention)

---

## Three transports

`boot` and `pulse` are *concepts*, available over three transports:

| Transport | Audience | How |
|---|---|---|
| CLI       | humans, scripts | `textus boot`, `textus pulse --since=N` |
| Ruby API  | embedders       | `store.pulse(since: N, role:)` |
| **MCP**   | agents, plugins | `textus mcp serve` — see [MCP transport](#mcp-transport-the-agent-gate) |

For agent code, prefer the MCP transport: schema-self-describing, session state held server-side, no shell-string composition.

## MCP transport (the agent gate)

Run a stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. This is how agents and plugins talk to a textus store *without* hardcoding CLI strings.

### Start

```sh
textus mcp serve
```

The server blocks on stdin. One JSON message per line. It expects an `initialize` request first; after that, `tools/list` returns the tool catalog and `tools/call` invokes a tool.

### Tools

MCP tools use the same verb names as the CLI and Ruby API (ADR 0036 — one vocabulary across all transports).

| Tool | Returns | Args |
|---|---|---|
| `boot` | Contract envelope: zones, entries, schemas, write_flows, agent_quickstart | none |
| `pulse` | `{cursor, changed, stale, pending_review, doctor}` | `since?: int` |
| `list` | `[{key, ...}]` | `zone?: string, prefix?: string` |
| `get` | Envelope (uid, etag, _meta, body, freshness) | `key: string` |
| `put` | `{uid, etag}` | `key, meta, body?, content?, if_etag?` |
| `propose` | `{uid, etag, key}` (prefixed with propose_zone) | `key, meta, body?` |
| `fetch` | `{outcome}` | `key: string` |
| `fetch_all` | `{fetched, failed, skipped}` | `zone?, prefix?` |
| `schema` | Field shape | `family: string` |
| `rules` | Effective rules for a key | `key: string` |

Maintenance tools (admin / bulk operations):

| Tool | Returns | Args |
|---|---|---|
| `key_mv_prefix` | Plan or applied move | `from_prefix, to_prefix, dry_run?` |
| `key_delete_prefix` | Plan or applied delete | `prefix, dry_run?` |
| `zone_mv` | Renamed zone (manifest + files) | `from, to, dry_run?` |
| `rule_lint` | Rule diff vs. live manifest (no writes) | `candidate_yaml` |
| `migrate` | Result of a YAML migration plan | `plan_yaml, dry_run?` |

### Errors

| Code | Class | Meaning |
|---|---|---|
| `-32001` | `ContractDrift` | manifest changed mid-session; call `boot` again |
| `-32002` | `CursorExpired` | audit cursor fell off keep window; call `boot` again |
| `-32000` | `ToolError` | tool execution failed (validation, authorization, IO) |
| `-32601` | (method-not-found) | unknown JSON-RPC method |
| `-32700` | (parse-error) | malformed JSON on the line |

### Wiring into a Claude plugin

Add an `.mcp.json` next to the plugin's `CLAUDE.md`:

```json
{
  "mcpServers": {
    "textus": {
      "command": "textus",
      "args": ["mcp", "serve"]
    }
  }
}
```

The agent now sees the full textus tool catalog in its registry (fifteen tools). No `textus get` strings in the plugin's markdown.

## Audit log retention

Configure rotation in `manifest.yaml`:

```yaml
audit:
  max_size: 10485760   # bytes; rotate when active log exceeds this
  keep:     5          # number of rotated files to keep (audit.log.1 .. .5)
```

Defaults if omitted: 10MB / 5 files. Each rotated file has a sidecar `audit.log.N.meta.json` recording its `min_seq`/`max_seq`/`rotated_at`, which is how cursor-expiry detection works.

## See also

- [`../../SPEC.md`](../../SPEC.md) §8 envelope shape, §9 verb table, §11.1 agent integration
- [`../how-to/agents-mcp.md`](../how-to/agents-mcp.md) — the quickstart and operational boot → pulse loop
- [ADR 0015](../architecture/decisions/0015-agent-gate-mcp.md) — the agent-gate decision and roadmap
- [ADR 0036](../architecture/decisions/0036-transports-as-pure-framings.md) — transports as pure framings
