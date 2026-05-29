# Agent Integration

How an AI agent talks to a textus store.

## Two channels

Textus exposes two distinct verbs for agents:

| Verb     | Cadence              | Shape              | Answers                          |
|----------|----------------------|--------------------|----------------------------------|
| `boot`   | once per session     | static contract    | "how do I talk to this store?"   |
| `pulse`  | per turn / per N sec | delta + cursor     | "what changed since I last looked?" |

## Three transports

`boot` and `pulse` are *concepts*, available over three transports:

| Transport | Audience | How |
|---|---|---|
| CLI       | humans, scripts | `textus boot`, `textus pulse --since=N` |
| Ruby API  | embedders       | `store.pulse(since: N, role:)` |
| **MCP**   | agents, plugins | `textus mcp serve` — see [`mcp.md`](./mcp.md) |

For agent code, prefer the MCP transport: schema-self-describing, session state held server-side, no shell-string composition.

## Boot — one-shot orientation

```sh
textus boot --output=json
```

Returns the working model of the store: zones with write policies, entry families with their schemas, registered hooks, write flows by role, and the full verb catalog. Run this once per session and cache it.

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
- Which zones it's allowed to write (gated by manifest `write_policy`).
- Where to put proposals (`propose_zone`, usually `review`).
- The starting cursor for `pulse` (`latest_seq`).

The boot envelope's top-level key for the verb catalog is `cli_verbs` (not `verbs`). The `agent_quickstart` block is derived from the manifest's role kinds: `writable_zones` and `propose_zone` reflect whichever role has kind `proposer` (default: `agent`).

## Pulse — recurring delta

```sh
textus pulse --since=<cursor>
```

Returns a delta envelope. The agent advances the cursor each turn.

```json
{
  "cursor":          1845,
  "changed":         [ { "seq": 1843, "key": "working.x", "uid": "...", "verb": "put", "role": "human", "ts": "..." } ],
  "stale":           [ "output.marketplace" ],
  "pending_review":  [ "review.proposal.123" ],
  "doctor":          { "ok": true, "warn": 0, "fail": 0 },
  "manifest_etag":   "sha256:abc123...",
  "next_due_at":     "2026-05-28T12:34:56Z",
  "hook_errors":     [ { "seq": 1844, "event": "entry_put", "hook": "audit_extra", "key": "working.x", "error_class": "RuntimeError", "error_message": "...", "at": "..." } ]
}
```

`changed` is a thin aggregator over `audit --seq-since=N`. `stale` comes from `freshness`. `pending_review` lists keys in the review zone. `doctor` is a count summary.

### Drift, scheduling, and hook-error signals

- **`manifest_etag`** — sha256 of `manifest.yaml`. If it differs from the value at boot, the contract has drifted; agents should re-`boot`. The MCP server raises `ContractDrift` (-32001) automatically; CLI consumers compare manually.
- **`next_due_at`** — earliest `next_due_at` across all entries with a refresh policy, ISO-8601 UTC. Schedulers can sleep until this timestamp instead of polling.
- **`hook_errors`** — list of recent hook failures since cursor: `{seq, event, hook, key, error_class, error_message, at}`. Bounded in-memory ring (256 most recent); older entries are evicted.

Every audit row carries a `seq` integer — a monotonic counter stamped on each write. The `cursor` in pulse is always the `latest_seq` from the audit log; passing it back to the next `pulse --since=<cursor>` produces only rows written after that point.

When pulse returns `changed: []` and `cursor` unchanged from the value you passed, nothing happened. Cheap to poll.

### Cursor expiry

Audit logs rotate (default: 10MB per file, 5 rotated files kept). If the agent's cached cursor falls off the keep window, pulse raises `CursorExpired`:

```
error: audit cursor expired: requested seq=1842 but oldest available is 5000;
       call `textus boot` to re-orient and resume from latest_seq
```

Handle by calling `boot` again and resuming from the new `latest_seq`. Skip the gap intentionally — those events are gone from local audit storage.

## Recommended agent loop

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
        # refresh agent's view of this key
        envelope = run(f"textus get {change['key']}")
        ...

    if pulse["stale"]:
        # decide whether to ask a runner to refresh, or proceed with stale data
        ...

    # do work; propose changes by writing to the review zone
    run(f"textus put review.proposal.x --as=agent --stdin", input=envelope_json)
```

## Audit log retention

Configure rotation in `manifest.yaml`:

```yaml
audit:
  max_size: 10485760   # bytes; rotate when active log exceeds this
  keep:     5          # number of rotated files to keep (audit.log.1 .. .5)
```

Defaults if omitted: 10MB / 5 files. Each rotated file has a sidecar `audit.log.N.meta.json` recording its `min_seq`/`max_seq`/`rotated_at`, which is how cursor-expiry detection works.

## See also

- [SPEC.md](../SPEC.md) §8 envelope shape, §9 verb table
- `examples/claude-plugin/` — reference plugin using boot + pulse
