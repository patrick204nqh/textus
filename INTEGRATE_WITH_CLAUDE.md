# Integrate textus with Claude Code

If you want Claude Code (or any MCP-aware agent) to read and write
your project's context through textus, four steps. Should take ~5 minutes.

## 1. Install

```sh
gem install textus
```

Requires Ruby ≥ 3.3. Verify with `textus --version`.

## 2. Initialize the store in your project

From your project root:

```sh
textus init
```

You get a `.textus/` directory with five default zones (`identity`,
`working`, `intake`, `review`, `output`), baseline schemas, and a
starter manifest. Commit `.textus/` to git.

## 3. Wire the MCP server

Create `.mcp.json` at your project root:

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

That's it. When Claude Code opens your project, it launches
`textus mcp serve` as a subprocess and the agent gets these tools:
`boot`, `pulse`, `get`, `list`, `put`, `accept`, `audit`, `freshness`,
`doctor`. The agent calls them as MCP tools — no shell strings, no
parsing.

## 4. Tell Claude how to use it

Add to your `CLAUDE.md` (or create one if you don't have it):

```markdown
## Context store

This project uses textus for durable agent memory. On session start,
call the `textus.boot` MCP tool — it returns the manifest, your
write authority, and the list of available verbs. Use `textus.pulse`
once per turn to see what changed since you last looked.

You write to `review.*` only. A human runs `textus accept` to
promote your proposals to `working/`.
```

That's the full integration. Claude Code reads `CLAUDE.md` on session
start, sees the MCP tools advertised in the `.mcp.json`, and follows
the boot/pulse protocol.

## What you get

- **`boot` once per session:** the agent knows your zone topology,
  schemas, write policies, and verb catalog without you explaining
  them in `CLAUDE.md`.
- **`pulse` per turn:** the agent sees what files changed since its
  last turn — no full re-read of the project.
- **Role-gated writes:** the agent cannot write to `working/` or
  `identity/` directly; it can only propose to `review/`. You
  retain control over what becomes load-bearing.
- **Audit log:** every write the agent makes is in
  `.textus/audit.log`. You can replay or revert.
- **Schema validation:** if you declare `_meta` field shapes per
  entry family, every write is checked. No malformed entries
  silently land.

## Next steps

- **Try the 5-command demo first:** `examples/hello/` (single
  terminal scroll, no MCP setup needed) to see the role-gating
  before you commit to the integration.
- **For a full Claude plugin example** that ships agents/skills/commands
  whose source-of-truth lives in textus: `examples/claude-plugin/`.
- **For using textus as your own project's context** (not shipping a
  plugin): `examples/project/`.
- **The wire protocol:** [`SPEC.md`](SPEC.md).
- **The MCP transport in detail:** [`docs/mcp.md`](docs/mcp.md).

## Troubleshooting

- **`textus mcp serve` exits immediately when Claude launches it:**
  run it manually from your project root (`textus mcp serve` and type
  `^C`); should print a JSON banner. If it errors, your `.textus/`
  manifest has a problem — `textus doctor` will tell you which.
- **Claude doesn't see the tools:** verify `.mcp.json` is at the
  project root (not in a subdirectory) and Claude Code was launched
  with the project open as the workspace.
- **Agent writes are rejected with `write_forbidden`:** check
  `textus boot | jq .agent_quickstart` — the `writable_zones` list
  tells you which prefixes the agent can write. Anything outside
  that is forbidden by design.
