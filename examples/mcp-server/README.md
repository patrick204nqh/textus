# mcp-server example

A ~30-line MCP server that exposes textus `get`/`list`/`put` to any MCP client
(Claude Code, Claude Desktop, etc.).

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

Restart Claude. `textus_get`, `textus_list`, and `textus_put` are now
available as tools.

## How it works

The server reads newline-delimited JSON-RPC from stdin, calls into
`Textus::Store`, and writes the result to stdout. Writes go through
`store.put(..., as: "ai")` so the role policy in `manifest.yaml` decides which
zones the agent can actually touch — `derived` stays locked, `canon` stays
locked, `working` is open.

That's the whole boundary: MCP is dumb transport, textus is policy.
