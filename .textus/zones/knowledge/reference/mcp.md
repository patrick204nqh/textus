# MCP transport — reference

> **Reference** · for agent authors · **read when** you need the MCP tool catalog, error codes, transports, or plugin wiring
> **SSoT for** the MCP tool catalog, error mapping, transports, and Claude-plugin wiring · **reviewed** 2026-06 (v0.45)

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

MCP tools use the same verb names as the CLI and Ruby API (ADR 0036 — one vocabulary across all transports). The catalog is **derived from per-verb contracts** (ADR 0039) — there is no hand-maintained tool list; each verb's `arg` shapes, per-argument `description`s, and summary are generated from its declared contract, and ride the wire in every `tools/list` response (ADR 0057).

The `put` and `propose` tools take their frontmatter under the **`_meta`** property — the same key `get` returns and the CLI `--stdin` envelope already speaks — so a read → edit → write round-trip can reuse the field name unchanged (ADR 0057). The `dry_run` flag on the maintenance tools defaults to **false** (the operation applies immediately); pass `true` to get a plan back without writing.

| Tool | Returns | Args |
|---|---|---|
| `boot` | Contract envelope: zones, entries, schemas, write_flows, agent_quickstart | none |
| `pulse` | `{cursor, changed, stale, pending_review, doctor}` | `since?: int` |
| `list` | `[{key, ...}]` | `zone?: string, prefix?: string` |
| `get` | Envelope (uid, etag, _meta, body, freshness) | `key: string` |
| `put` | `{uid, etag}` | `key, _meta, body?, content?, if_etag?` |
| `propose` | Full wire envelope (`uid, etag, key, zone, owner, path, ...`; `key` prefixed with propose_zone) | `key, _meta, body?, content?` |
| `schema_show` | Field shape (schema for an entry's family) | `key: string` |
| `rule_explain` | Effective rules for a key — lean `{lifecycle, guard}` by default; verbose with `detail` | `key: string, detail?: bool` |
| `where` | Resolve a key to its zone, owner, and path (no body read) | `key: string` |
| `deps` | Keys a derived entry depends on (its sources) | `key: string` |
| `rdeps` | Derived entries that depend on a key (impact set) | `key: string` |
| `capabilities` | Machine-readable contract surface: every verb, its transports, and arg schema | `verb?: string` |
| `accept` | Apply a queued proposal to its target zone (requires the author capability) | `key: string` |
| `reject` | Discard a queued proposal | `key: string` |

Maintenance tools (admin / bulk operations). The four bulk-destructive verbs
default to **dry-run** (ADR 0060): omitting `dry_run` returns a Plan; pass
`dry_run: false` to apply. Pair with `deps`/`rdeps`/`where` to see blast radius first.

| Tool | Returns | Args |
|---|---|---|
| `key_mv_prefix` | Plan (default) or applied move | `from_prefix, to_prefix, dry_run?=true` |
| `key_delete_prefix` | Plan (default) or applied delete | `prefix, dry_run?=true` |
| `zone_mv` | Plan (default) or renamed zone (manifest + files) | `from, to, dry_run?=true` |
| `drain` | Converge everything now: seed produce + retention jobs and drain the queue to empty; reports health | `prefix?, zone?` |
| `jobs` | Inspect the convergence queue by state; retry a dead-lettered job or purge a state | `state?=ready, action?, job_id?` |
| `rule_lint` | Rule diff vs. live manifest (no writes) | `candidate_yaml` |

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

The agent now sees the full textus tool catalog in its registry. No `textus get` strings in the plugin's markdown.

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
