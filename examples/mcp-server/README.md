# mcp-server example

A ~40-line MCP server that exposes textus to any MCP client (Claude Code,
Claude Desktop, etc.).

## Wire it up

Drop into your `~/.claude/mcp_servers/textus.json`:

```json
{
  "textus": {
    "command": "ruby",
    "args": ["/absolute/path/to/examples/mcp-server/server.rb"],
    "cwd": "/path/to/your/project/with/.textus"
  }
}
```

Restart Claude. Five tools become available:

| Tool | Effect |
|---|---|
| `textus_get`        | Read an entry by key |
| `textus_list`       | List entries under a prefix |
| `textus_put`        | Write to a working entry (role: `ai`) |
| `textus_refresh`    | Refresh an intake entry via its registered fetcher (role: `script`) |
| `textus_extensions` | List registered fetchers, reducers, and hooks |

## How it works

The server reads newline-delimited JSON-RPC from stdin, calls into
`Textus::Store`, and writes the result to stdout. Writes go through
`store.put(..., as: "ai")` so the role policy in `manifest.yaml` decides which
zones the agent can actually touch — `derived` stays locked, `canon` stays
locked, `working` is open.

`textus_refresh` routes through `Textus::Refresh.call`, so the registered
fetcher receives a read-only `StoreView` — even if the agent invokes it, it
cannot escape the role gate or use the fetcher to write to a forbidden zone.

That's the whole boundary: MCP is dumb transport, textus is policy. Every
call lands in `audit.log` with the resolved role and etag.
