## 11. Versioning

- The current wire string is `textus/4`.
- Backward-compatible additions (new fields, new error codes, new schema types) MAY be made under `textus/4`.
- Breaking changes (renamed/removed envelope fields, lane semantics, key grammar) require a new wire string `textus/4`.
- Implementations MUST reject envelopes whose `protocol` they do not recognize.

The reference Ruby gem follows semver independently and speaks `textus/4`.
## 11.1 Agent integration

Agents interact with a textus store through two verbs: `boot` (once per session, for orientation) and `pulse` (per turn, for deltas). The `boot` envelope's `agent_quickstart` block gives the agent its starting cursor (`latest_seq`), its writable lanes, and its propose lane. The `pulse` verb returns a delta envelope keyed on that cursor. When audit log rotation expires a cursor, `CursorExpired` signals the agent to call `boot` again.

For the full boot → pulse loop with pseudocode and cursor-expiry handling, see [`docs/how-to/agents-mcp.md`](../../how-to/agents-mcp.md).

