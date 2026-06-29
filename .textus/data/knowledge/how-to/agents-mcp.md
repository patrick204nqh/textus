---
sources:
- raw.2026.06.20.url-mcp-specification
uid: e83bf3140722f215
---
# Agents & MCP — wiring an agent to a store

> **How-to** · for agent authors & integrators · **read when** you're wiring an AI agent to a store
> **SSoT for** Claude Code quickstart, the boot → pulse session loop, and the propose → accept flow · **reviewed** 2026-06 (v0.55)

How an AI agent reads from and writes to a textus store over MCP — setup, the session protocol, and the operational loop.

For the normative wire protocol and full verb table, see [`../../SPEC.md`](../../SPEC.md).

> New here? Start with [Concepts](../explanation/concepts.md).

---

## Quickstart: Claude Code (~5 minutes)

### 1. Install

```sh
gem install textus
```

Requires Ruby ≥ 3.3. Verify with `textus --version`.

### 2. Initialize the store

```sh
textus init
```

Creates `.textus/` with default lanes (`knowledge`, `scratchpad`, `artifacts`, `queue`, `raw`), baseline schemas, and a starter manifest. Commit `.textus/` to git.

### 3. Wire the MCP server

Create `.mcp.json` at your project root:

```json
{
  "mcpServers": {
    "textus": {
      "command": "textus",
      "args": ["--root", "${workspaceFolder}/.textus", "mcp", "serve"]
    }
  }
}
```

Pin `--root` explicitly. When Claude Code launches `textus mcp serve` as a subprocess its working directory is not guaranteed to be your project root, so upward `.textus/` discovery can miss. Role resolution is `--as` flag → `TEXTUS_ROLE` env → `.textus/role` file → transport default (`agent` over MCP). See [ADR 0040](../architecture/decisions/0040-mcp-connection-role-and-two-channels.md).

To connect one agent to multiple stores, add a second entry with a different `--root`.

### 4. Tell Claude how to use it

Add to `CLAUDE.md`:

```markdown
## Context store

This project uses textus for durable agent memory. On session start,
call the `boot` MCP tool — it returns your write authority, lane topology,
and the verb catalog. Call `pulse` once per turn to see what changed.

Write your working notes to `scratchpad/`. Use `propose` to suggest
changes to `knowledge/`; a human runs `textus accept` to promote them.
```

---

## Session protocol

### `boot` — orient once per session

The first call every agent makes. Returns the full orientation contract:

```json
{
  "protocol": "textus/4",
  "contract_etag": "sha256:abcd1234",
  "store_root": "/path/to/.textus",
  "lanes": [
    { "name": "raw",        "kind": "raw",       "writers": ["human"] },
    { "name": "knowledge",  "kind": "canon",      "writers": ["human"] },
    { "name": "scratchpad", "kind": "workspace",  "writers": ["agent"] },
    { "name": "queue",      "kind": "queue",      "writers": ["agent"] },
    { "name": "artifacts",  "kind": "machine",    "writers": ["automation"] }
  ],
  "agent_quickstart": {
    "read_verbs":     ["boot","get","list","pulse","where","deps","rdeps","schema_show"],
    "write_verbs":    ["put","key_delete","key_mv","propose","accept","reject","enqueue"],
    "writable_lanes": ["scratchpad", "queue"],
    "propose_lane":   "queue",
    "latest_seq":     42
  },
  "agent_protocol": {
    "recipes": { "read": {...}, "write": {...}, "propose": {...}, "drain": {...} },
    "role_resolution": { "roles": ["human","agent","automation"], ... }
  }
}
```

From this single call the agent learns:
- Which lanes it can write directly (`writable_lanes`)
- Its `propose_lane` — the queue lane proposals go into
- Its cursor anchor (`latest_seq`) — the starting point for `pulse`
- Its `contract_etag` — a hash of manifest + hooks + schemas

**`contract_etag` is the session guard.** Every non-read verb call checks that the live contract hash still matches. If a human edits the manifest, hooks, or a schema mid-session, the next write returns `contract_drift` (JSON-RPC `-32001`) and the agent must call `boot` again before writing. `boot` itself rebuilds the session — resets the cursor and re-derives the propose lane from the updated manifest.

### `pulse` — delta per turn

Call without arguments; the handler reads the per-role file cursor from disk:

```json
{
  "cursor": 57,
  "changed": [
    { "key": "raw.articles.llm-patterns", "verb": "put", "seq": 53 }
  ],
  "pending_review": ["queue.decisions.feature-x"],
  "contract_etag": "sha256:abcd1234",
  "index_etag": "sha256:..."
}
```

`changed` — entries written since the last pulse. `pending_review` — keys sitting in the queue lane waiting for human `accept`. After each `pulse` the server advances its in-memory cursor; the file cursor is also written to disk so it survives process restarts.

---

## The four recipes

### Read

```
list(prefix: "knowledge.runbooks") → ["knowledge.runbooks.deploy", ...]
get(key: "knowledge.runbooks.deploy") → { _meta: {...}, body: "...", sources: [...], ... }
```

`get` returns the envelope including `sources` — each source object now carries `suspended: true/false` computed by comparing the stored etag snapshot to the current on-disk etag of the referenced raw entry.

### Write (direct — workspace lanes only)

```
schema_show(key: "scratchpad.notes.plan") → { fields: {...} }
put(key: "scratchpad.notes.plan", _meta: { title: "Plan" }, body: "...")
```

`_meta.sources` can reference raw entries by key. textus snapshots their current etag at write time and surfaces `suspended: true` on future `get` calls if the source is later replaced.

### Propose (canon changes go through the queue)

The agent cannot write to `knowledge/` directly. It writes a proposal to the queue lane:

```
propose(key: "decisions.feature-x",
        _meta: { proposal: { target_key: "knowledge.decisions.feature-x" } },
        body: "...")
→ writes queue.decisions.feature-x
```

A human then promotes it:

```sh
textus accept queue.decisions.feature-x
```

The proposal moves from the queue lane into `knowledge/`. `pulse` surfaces pending proposals in `pending_review` so the agent knows whether its proposals are still waiting.

### Drain (keep machine lanes fresh)

```
pulse()                          # → changed includes stale raw entries
drain(lane: "artifacts")         # → materialise + sweep
```

`drain` is a two-phase pass: materialize (re-run workflows for produced entries in scope) then sweep (apply retention rules). A `get` is a pure read and never triggers re-produce (ADR 0089).

---

## Role authority

```
                  write canon?  write workspace?  write queue?  write artifacts?
human (author)        ✓              ✓               ✓               ✗
agent (propose/keep)  ✗              ✓               ✓               ✗
automation (converge) ✗              ✗               ✗               ✓
```

Authority is derived from the manifest's `roles:` capabilities and each lane's `kind:`. The connection defaults to `agent` over MCP (ADR 0040). Override with `--as=human` to run with your own authority; the gate then becomes advisory.

---

## Agent loop

```
── boot() ────────────────────────────────────────────────────────────
← { contract_etag, writable_lanes, propose_lane, latest_seq: 42 }

── [per turn] ────────────────────────────────────────────────────────
── pulse() → { cursor: 57, changed: [...], pending_review: [...] }
── list / get for anything in changed
── put / propose based on work

── [contract changes mid-session] ───────────────────────────────────
── put() → contract_drift error (-32001)
── boot() → { contract_etag: "sha256:new", latest_seq: 60 }
── [resume writing]
```

---

## Troubleshooting

- **`textus mcp serve` exits immediately:** run it manually from your project root and type `^C`. If it errors, `textus doctor` will identify the manifest problem.
- **`no .textus directory found`:** pin `--root` in `.mcp.json` — the subprocess cwd is not your project root (see step 3).
- **Claude doesn't see the tools:** verify `.mcp.json` is at the project root, not a subdirectory, and Claude Code was launched with the project as workspace.
- **Writes rejected with `write_forbidden`:** run `textus boot | jq .agent_quickstart` — `writable_lanes` lists what the agent can write directly. Anything outside that goes through `propose`.
- **`contract_drift` on every write:** the manifest, a hook, or a schema was edited. Call `boot` to re-orient.

---

## See also

- [`../../SPEC.md`](../../SPEC.md) — normative wire-protocol spec (§8 envelope, §9 verb table, §11 agent integration)
- [ADR 0040](../architecture/decisions/0040-mcp-connection-role-and-two-channels.md) — MCP connection role and two-channel design
- [ADR 0074](../architecture/decisions/0074-contract-etag-drift-guard.md) — contract-etag drift guard
- [`../../.textus/`](../../.textus/) — textus's own self-development store (same setup with `bundle exec exe/textus`, ADR 0041)
