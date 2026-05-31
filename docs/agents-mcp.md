# Agents & MCP — talking to a textus store

> **How-to** · for agent authors & integrators · **read when** you're wiring an AI agent to a store
> **SSoT for** the agent boot → pulse loop, the MCP tool catalog, and Claude Code wiring · **reviewed** 2026-05 (v0.36)

How an AI agent reads from and writes to a textus store — the mental model, the MCP transport, and a 5-minute Claude Code setup.

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
names are the same as the CLI verbs (see [ADR 0036](architecture/decisions/0036-transports-as-pure-framings.md)); the full
catalog with arguments is in [the MCP tool reference below](#mcp-transport-the-agent-gate).

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

- **Try the 5-command demo first:** `examples/hello/` (single
  terminal scroll, no MCP setup needed) to see the role-gating
  before you commit to the integration.
- **For a full Claude plugin example** that ships agents/skills/commands
  whose source-of-truth lives in textus: `examples/claude-plugin/`.
- **For using textus as your own project's context** (not shipping a
  plugin): `examples/project/`.

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

## Two channels: boot & pulse

Textus exposes two distinct verbs for agents:

| Verb     | Cadence              | Shape              | Answers                          |
|----------|----------------------|--------------------|----------------------------------|
| `boot`   | once per session     | static contract    | "how do I talk to this store?"   |
| `pulse`  | per turn / per N sec | delta + cursor     | "what changed since I last looked?" |

### Three transports

`boot` and `pulse` are *concepts*, available over three transports:

| Transport | Audience | How |
|---|---|---|
| CLI       | humans, scripts | `textus boot`, `textus pulse --since=N` |
| Ruby API  | embedders       | `store.pulse(since: N, role:)` |
| **MCP**   | agents, plugins | `textus mcp serve` — see [MCP transport](#mcp-transport-the-agent-gate) |

For agent code, prefer the MCP transport: schema-self-describing, session state held server-side, no shell-string composition.

### Boot — one-shot orientation

```sh
textus boot --output=json
```

Returns the working model of the store: zones with their kinds and derived write authority, entry families with their schemas, registered hooks, write flows by role, and the full verb catalog. Run this once per session and cache it.

Key field for agents: **`agent_quickstart`**.

```json
{
  "agent_quickstart": {
    "read_verbs":     ["boot", "get", "list", "audit", "pulse", "freshness", "doctor"],
    "write_verbs":    ["put KEY --as=agent --stdin"],
    "writable_zones": ["review"],
    "propose_zone":   "review",
    "latest_seq":     1842
  }
}
```

After boot, the agent knows:
- Which zones it's allowed to write (gated by the role's capabilities × the zone's kind).
- Where to put proposals (`propose_zone`, usually `review`).
- The starting cursor for `pulse` (`latest_seq`).

The boot envelope's top-level key for the verb catalog is `cli_verbs` (not `verbs`). The `agent_quickstart` block is derived from capabilities: `writable_zones` and `propose_zone` reflect whichever role holds `propose` and is not the accept-anchor (default: `agent`).

### Pulse — recurring delta

```sh
textus pulse --since=<cursor>
```

Returns a delta envelope. The agent advances the cursor each turn.

```json
{
  "cursor":          1845,
  "changed":         [ { "seq": 1843, "key": "knowledge.notes.x", "uid": "...", "verb": "put", "role": "human", "ts": "..." } ],
  "stale":           [ "artifacts.marketplace" ],
  "pending_review":  [ "proposals.proposal.123" ],
  "doctor":          { "ok": true, "warn": 0, "fail": 0 },
  "manifest_etag":   "sha256:abc123...",
  "next_due_at":     "2026-05-28T12:34:56Z",
  "hook_errors":     [ { "seq": 1844, "event": "entry_put", "hook": "audit_extra", "key": "knowledge.notes.x", "error_class": "RuntimeError", "error_message": "...", "at": "..." } ]
}
```

`changed` is a thin aggregator over `audit --seq-since=N`. `stale` comes from `freshness`. `pending_review` lists keys in the queue zone. `doctor` is a count summary.

#### Drift, scheduling, and hook-error signals

- **`manifest_etag`** — sha256 of `manifest.yaml`. If it differs from the value at boot, the contract has drifted; agents should re-`boot`. The MCP server raises `ContractDrift` (-32001) automatically; CLI consumers compare manually.
- **`next_due_at`** — earliest `next_due_at` across all entries with a fetch policy, ISO-8601 UTC. Schedulers can sleep until this timestamp instead of polling.
- **`hook_errors`** — list of recent hook failures since cursor: `{seq, event, hook, key, error_class, error_message, at}`. Bounded in-memory ring (256 most recent); older entries are evicted.

Every audit row carries a `seq` integer — a monotonic counter stamped on each write. The `cursor` in pulse is always the `latest_seq` from the audit log; passing it back to the next `pulse --since=<cursor>` produces only rows written after that point.

When pulse returns `changed: []` and `cursor` unchanged from the value you passed, nothing happened. Cheap to poll.

#### Cursor expiry

Audit logs rotate (default: 10MB per file, 5 rotated files kept). If the agent's cached cursor falls off the keep window, pulse raises `CursorExpired`:

```
error: audit cursor expired: requested seq=1842 but oldest available is 5000;
       call `textus boot` to re-orient and resume from latest_seq
```

Handle by calling `boot` again and resuming from the new `latest_seq`. Skip the gap intentionally — those events are gone from local audit storage.

### Recommended agent loop

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

### Audit log retention

Configure rotation in `manifest.yaml`:

```yaml
audit:
  max_size: 10485760   # bytes; rotate when active log exceeds this
  keep:     5          # number of rotated files to keep (audit.log.1 .. .5)
```

Defaults if omitted: 10MB / 5 files. Each rotated file has a sidecar `audit.log.N.meta.json` recording its `min_seq`/`max_seq`/`rotated_at`, which is how cursor-expiry detection works.

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

## See also

- [`../SPEC.md`](../SPEC.md) §8 envelope shape, §9 verb table, §11.1 agent integration
- [ADR 0015](architecture/decisions/0015-agent-gate-mcp.md) — the agent-gate decision and roadmap
- [`../examples/claude-plugin/`](../examples/claude-plugin/) — reference plugin using boot + pulse + `.mcp.json`
- [`../examples/hello/`](../examples/hello/) — 5-command demo, no MCP needed
