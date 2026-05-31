# Agents & MCP — wiring an agent to a store

> **How-to** · for agent authors & integrators · **read when** you're wiring an AI agent to a store
> **SSoT for** the Claude Code quickstart, context-store setup, and the agent boot → pulse loop · **reviewed** 2026-05 (v0.37)

How an AI agent reads from and writes to a textus store — a 5-minute Claude Code setup, what you get, and the operational loop you run each turn.

For the MCP tool catalog, error codes, transports, and plugin wiring, see [`../reference/mcp.md`](../reference/mcp.md). For the wire protocol, see [`../../SPEC.md`](../../SPEC.md).

> New here? Start with [Concepts](../explanation/concepts.md).

## Table of contents

1. [Quickstart: Claude Code (~5 minutes)](#quickstart-claude-code-5-minutes)
2. [Context store](#context-store)
3. [Recommended agent loop](#recommended-agent-loop)

---

## Quickstart: Claude Code (~5 minutes)

If you want Claude Code (or any MCP-aware agent) to read and write
your project's context through textus, four steps. Should take ~5 minutes.

### 1. Install

```sh
gem install textus
```

Requires Ruby ≥ 3.3. Verify with `textus --version`.

### 2. Initialize the store in your project

From your project root:

```sh
textus init
```

You get a `.textus/` directory with five default zones (`identity`,
`working`, `intake`, `review`, `output`), baseline schemas, and a
starter manifest. Commit `.textus/` to git.

### 3. Wire the MCP server

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
`boot`, `pulse`, `list`, `get`, `put`, `propose`, `fetch`,
`fetch_all`, `schema`, `rules` (plus maintenance tools). The agent
calls them as MCP tools — no shell strings, no parsing. The MCP tool
names are the same as the CLI verbs (see [ADR 0036](../architecture/decisions/0036-transports-as-pure-framings.md)); the full
catalog with arguments is in [the MCP tool reference](../reference/mcp.md#tools).

### 4. Tell Claude how to use it

Add to your `CLAUDE.md` (or create one if you don't have it):

```markdown
## Context store

This project uses textus for durable agent memory. On session start,
call the `boot` MCP tool — it returns the manifest, your write
authority, and the tool catalog. Call `pulse` once per turn to see
what changed since you last looked.

You can't write to `working/` or `identity/` directly. Use the
`propose` tool to land a change in the `review/` queue; a human runs
`textus accept` to promote it to `working/`.
```

That's the full integration. Claude Code reads `CLAUDE.md` on session
start, sees the MCP tools advertised in the `.mcp.json`, and follows
the boot/pulse protocol.

## Context store

### What you get

- **`boot` once per session:** the agent knows your zone topology,
  schemas, write authority, and verb catalog without you explaining
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

### Next steps

- **For a worked end-to-end store** — the role gate (propose → accept),
  build/publish (`CLAUDE.md` / `AGENTS.md` generated from knowledge
  entries), schemas, templates, and a hook: `examples/project/`.

### Troubleshooting

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

## Recommended agent loop

For Ruby embedders, `store.session(role:)` boots and returns a `Textus::Session` that
tracks the cursor and propose_zone for you — no hand-rolled `since` variable needed
(ADR 0036). The `advance_cursor` call returns a new immutable session value each turn.

```ruby
# Ruby embedder loop
session = store.session(role: :agent)
loop do
  delta = store.as(session.role).pulse(since: session.cursor)
  session = session.advance_cursor(delta["cursor"])
  delta["changed"].each { |c| reload(c["key"]) }
  # propose a change:
  # store.as(:agent).put("#{session.propose_zone}.my-key", meta: {...}, body: "...")
end
```

The equivalent CLI / pseudocode loop:

```python
# Pseudocode
boot = run("textus boot --output=json")
cursor = boot["agent_quickstart"]["latest_seq"]
contract = boot  # cache the orientation for the session

while session_active:
    pulse = run(f"textus pulse --since={cursor}")
    if pulse.get("code") == "cursor_expired":
        boot = run("textus boot --output=json")
        cursor = boot["agent_quickstart"]["latest_seq"]
        continue

    cursor = pulse["cursor"]
    for change in pulse["changed"]:
        # reload the agent's view of this key
        envelope = run(f"textus get {change['key']}")
        ...

    if pulse["stale"]:
        # decide whether to ask automation to fetch, or proceed with stale data
        ...

    # do work; propose changes by writing to the proposals zone
    run(f"textus put proposals.proposal.x --as=agent --stdin", input=envelope_json)
```

For the conceptual framing of the two channels (boot vs pulse — what each is and why), see [Concepts](../explanation/concepts.md). For the exact transports, pulse fields, error codes, and retention facts, see [`../reference/mcp.md`](../reference/mcp.md).

## See also

- [`../../SPEC.md`](../../SPEC.md) §8 envelope shape, §9 verb table, §11.1 agent integration
- [`../reference/mcp.md`](../reference/mcp.md) — MCP tool catalog, error codes, transports, plugin wiring
- [ADR 0015](../architecture/decisions/0015-agent-gate-mcp.md) — the agent-gate decision and roadmap
- [`../../examples/project/`](../../examples/project/) — worked store: role gate, build/publish, schemas, hook
