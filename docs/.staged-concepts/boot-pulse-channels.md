## Two channels: boot & pulse

Textus exposes two distinct verbs for agents:

| Verb     | Cadence              | Shape              | Answers                          |
|----------|----------------------|--------------------|----------------------------------|
| `boot`   | once per session     | static contract    | "how do I talk to this store?"   |
| `pulse`  | per turn / per N sec | delta + cursor     | "what changed since I last looked?" |

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

<!-- TASK 6 NOTE: framing prose salvaged from the original agents-mcp.md intro (line 6), preserved here so concepts.md can fold it in. The 5-minute Claude Code setup and MCP-transport pointers from that intro are operational/navigational and live in the split docs' headers, so only the conceptual framing is kept: -->
> How an AI agent reads from and writes to a textus store — the mental model, the MCP transport, and a 5-minute Claude Code setup.
