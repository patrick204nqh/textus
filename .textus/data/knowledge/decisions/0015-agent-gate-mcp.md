# ADR 0015 — Agent gate (MCP-shaped surface)

**Date:** 2026-05-28
**Status:** Accepted (Phase 0 + Phase 1 shipped in 0.23.0)
**Depends on:** [ADR 0010](./0010-flat-operations-api.md), [ADR 0013](./0013-port-extraction-store-as-root.md)

## Context

Today, agents and plugins talk to a textus store by shelling out CLI
verbs as string-encoded commands inside skill prompts:

```
textus get KEY
textus put KEY --as=agent --stdin
textus schema get FAMILY
```

This works but leaks the CLI surface into every skill. Three concrete
problems:

1. **Verb drift breaks skills silently.** ADRs 0004, 0010, 0013 show
   the CLI/Operations surface evolves; skills with hardcoded strings
   don't know.
2. **No typed contract.** Schemas are *available* (`textus schema
   get`) but not *enforced* at the agent boundary. Agents parse JSON
   and trust.
3. **No separation between skeleton, soul, and memory.** The skill
   markdown ("soul") names the engine ("skeleton") and the on-disk
   files ("memory") in the same breath, via string composition.

`Operations` (ADR 0010) is already a clean, flat façade. `boot` already
ships a self-describing catalog (zones, entries, schemas,
write_flows). The missing piece is a **non-Ruby, schema-self-describing
transport** so the agent's tool registry *is* the entry catalog.

## Decision

**Introduce a single agent gate — `textus-mcp` — that exposes
`Operations` as MCP tools whose schemas are auto-derived from the
manifest.** The CLI does not go away; it remains the human/script
surface. MCP becomes the agent surface.

### Three layers, one gate

```
┌─────────────┐     ┌────────────────────┐     ┌──────────────┐
│    SOUL     │     │       GATE         │     │   MEMORY     │
│ skill / LLM │ ──▶ │  textus-mcp server │ ──▶ │  .textus/    │
│ prompt /    │ ◀── │  (session: cursor, │ ◀── │  files       │
│ agent code  │     │   role, contract)  │     │              │
└─────────────┘     └─────────┬──────────┘     └──────────────┘
                              ▼
                    Operations.for(store, role:)
                          (unchanged)
```

### Invariants

- The soul never sees a filesystem path.
- The soul never composes a CLI string.
- Schema validation is enforced at the gate boundary, not in prompts.
- Manifest drift surfaces as a typed error (`ContractDrift`,
  `CursorExpired`), not a stale boot snapshot.

### Tool surface (auto-generated from manifest)

| Tool | Returns | Notes |
|---|---|---|
| `boot()` | contract envelope | zones, entries, schemas, write_flows, agent_quickstart, manifest_etag, latest_seq |
| `find(zone?, prefix?)` | `[{key, uid, ...}]` | wraps `Reads::List` |
| `read(key)` | `Envelope` | typed (ADR 0007) |
| `write(key, meta, body)` | `{uid, etag}` | gated by role; schema-validated |
| `propose(key, meta, body)` | `{uid, etag}` | auto-picks `propose_zone` from agent_quickstart |
| `refresh(key | stale=true)` | `Outcome` | dispatches `Refresh::Orchestrator` |
| `tick()` | delta + cursor | server-side pulse; agent never tracks cursor itself |
| `schema(family)` | field shape | from `Schemas` |
| `rules(key)` | effective rules | from `Manifest#rules_for` |

### Session state

The MCP server holds session state per-client:

- `cursor` — last seen audit `seq`; advanced by `tick()`.
- `role` — bound at connect; default `agent`.
- `propose_zone` — derived from manifest role kinds.
- `manifest_etag` — hash of `manifest.yaml` at connect; mismatch on
  any later call raises `ContractDrift` so the client re-boots.

## Consequences

- **Skill prompts shrink.** A skill says "call `propose(key, meta=…,
  body=…)`" instead of teaching the agent to compose CLI strings,
  shell-escape stdin, and parse JSON envelopes.
- **CLI verbs can rev without breaking plugins.** The gate is the
  versioned API; CLI strings in skills are eliminated.
- **Schema enforcement moves to the boundary.** Bad writes fail at
  the gate with a structured error, not after a subprocess returns
  non-zero.
- **Two surfaces, one core.** CLI verbs and MCP tools both call
  `Operations`. No duplicate logic.
- **Manifest drift is observable.** `manifest_etag` makes "your boot
  snapshot is stale" a first-class signal.

## Roadmap

### Phase 0 — Documentation truth-up (~1 day)

- [ ] `ARCHITECTURE.md`: `s/registry/bus/g`, fix `Worker` example.
- [ ] Add an "Agent surface" section linking `boot`/`pulse`.
- [ ] List actual `Hooks::Bus` events (incl. `refresh_*`,
      `store_loaded`).
- [ ] Note `Manifest::Entry` polymorphism + `Builder/`.

### Phase 1 — The gate (~1–2 weeks)

- [ ] This ADR (0015) accepted.
- [ ] `textus-mcp` server (Ruby) wrapping `Operations`.
- [ ] Tool schemas auto-derived from manifest entries + `schemas/`.
- [ ] Session: cursor + role + `manifest_etag` held server-side.
- [ ] `ContractDrift` / `CursorExpired` error envelopes.
- [ ] `examples/claude-plugin/` migrated to MCP — **zero CLI strings
      in skill markdown** (acceptance test for the abstraction).

### Phase 2 — Context-structure ergonomics (~2 weeks)

- [ ] `textus migrate` — declarative schema/format/rule moves.
- [ ] `textus key mv --prefix` — bulk relocation.
- [ ] `textus key delete --prefix`.
- [ ] `textus zone mv` — safe zone rename.
- [ ] `textus rule lint` — dry-run manifest rule edits.
- [ ] `textus diff` — preview manifest changes pre-commit.

### Phase 3 — Pulse hardening (~1 week)

- [ ] Pulse: include `manifest_etag` (drift detection without a
      separate verb).
- [ ] Pulse: per-entry `next_due_at`.
- [ ] Pulse: `hook_errors_since(seq)` (`FireReport` surfaced).
- [ ] Freshness verdict cache by `(key, last_refreshed_at)`.
- [ ] Windows fallback for `RefreshTimed` (cooperative cancel).

## Acceptance criteria

- ✓ Search `examples/claude-plugin/**/*.md` for the literal string
  `textus ` → zero matches outside authoring docs.
- ✓ Renaming a CLI verb breaks nothing in any example plugin.
- ✓ Changing a schema field is one `textus migrate` invocation, not
  a hand-rolled `find | xargs put` loop.
- ✓ Agent code reads:
  ```python
  h = connect_textus(root)
  for change in h.tick().changed: ...
  h.propose(key, meta=..., body=...)
  ```
  instead of `subprocess.run("textus ...")`.
- ✓ Soul, skeleton, and memory each have one job; the gate is the
  only place they meet.

## Alternatives considered

- **HTTP/JSON-RPC instead of MCP.** Workable, but MCP is the 2026
  default for agent ↔ tool plumbing and ships tool-schema
  introspection for free. Picking MCP avoids reinventing the
  discovery protocol.
- **Generated typed Ruby/Python clients only (no daemon).** Leaves
  session state (cursor, role, drift detection) to each client.
  Pushes complexity outward; every plugin re-implements the loop.
- **Keep the CLI as the only surface, ship a "client library" that
  shells out under the hood.** Doesn't solve the leak — it just
  hides it. Verb renames still break the library version, and
  schema validation still happens after the subprocess returns.
- **Do nothing.** Skills keep accumulating hardcoded CLI strings;
  every ADR that touches the CLI surface forces a sweep of every
  downstream plugin. Cost grows with adoption.

## Dependency graph

```
Phase 0 ──┐
          ├──▶ Phase 1 ──┐
          │  (gate)      ├──▶ examples plugin migration (proof)
          ├──▶ Phase 2 ──┤
          │  (migrations)├──▶ adopters can refactor stores safely
          └──▶ Phase 3 ──┘
             (pulse polish) ──▶ cheap polling, no drift
```
