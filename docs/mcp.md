# textus mcp — the agent gate

Run a stdio JSON-RPC 2.0 server speaking MCP draft 2024-11-05. This is how agents and plugins talk to a textus store *without* hardcoding CLI strings.

## Start

```sh
textus mcp serve
```

The server blocks on stdin. One JSON message per line. It expects an `initialize` request first; after that, `tools/list` returns the tool catalog and `tools/call` invokes a tool.

## Tools

| Tool | Returns | Args |
|---|---|---|
| `boot` | Contract envelope: zones, entries, schemas, write_flows, agent_quickstart | none |
| `tick` | `{cursor, changed, stale, pending_review, doctor}` | `since?: int` |
| `find` | `[{key, ...}]` | `zone?: string, prefix?: string` |
| `read` | Envelope (uid, etag, _meta, body, freshness) | `key: string` |
| `write` | `{uid, etag}` | `key, meta, body?, content?, if_etag?` |
| `propose` | `{uid, etag, key}` (prefixed with propose_zone) | `key, meta, body?` |
| `refresh` | `{outcome}` | `key: string` |
| `refresh_stale` | `{refreshed, failed, skipped}` | `zone?, prefix?` |
| `schema` | Field shape | `family: string` |
| `rules` | Effective rules for a key | `key: string` |

## Errors

| Code | Class | Meaning |
|---|---|---|
| `-32001` | `ContractDrift` | manifest changed mid-session; call `boot` again |
| `-32002` | `CursorExpired` | audit cursor fell off keep window; call `boot` again |
| `-32000` | `ToolError` | tool execution failed (validation, authorization, IO) |
| `-32601` | (method-not-found) | unknown JSON-RPC method |
| `-32700` | (parse-error) | malformed JSON on the line |

## Wiring into a Claude plugin

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

The agent now sees ten textus tools in its registry. No `textus get` strings in the plugin's markdown.

## See also

- [ADR 0015](./architecture/decisions/0015-agent-gate-mcp.md) — the decision and roadmap.
- [`agent-integration.md`](./agent-integration.md) — boot/pulse model the MCP server is built on.
- `examples/claude-plugin/.mcp.json` — reference wiring.
