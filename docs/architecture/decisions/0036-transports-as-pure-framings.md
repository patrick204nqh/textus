# ADR 0036 — Transports are pure framings: one verb vocabulary, one session, lifted to core

**Date:** 2026-05-31
**Status:** Proposed — targets 0.36.0 (**breaking**: MCP tool names change)
**Refines:** [ADR 0029](./0029-concept-vocabulary.md) (one canon term per concept), [ADR 0033](./0033-complete-primitives-and-vocabulary.md) (the complete primitive/verb set), [ADR 0027](./0027-hook-signature-and-mcp-policy.md) (MCP policy), [ADR 0015](./0015-agent-gate-mcp.md) (the agent gate).
**Touches:** [ADR 0021](./0021-session-and-module-use-cases.md) / [ADR 0022](./0022-container-call-dispatcher.md) — the per-call `Session` was replaced by `RoleScope`; the name `Textus::Session` is reclaimed here for the *agent* session (cursor + orientation), a distinct concept.

## Context

textus exposes three transports — CLI, Ruby API, MCP — over the same store
([`docs/agents-mcp.md`](../../agents-mcp.md) §"Three transports"). The thesis of the
project is that **coordination is a protocol invariant** (README), so the three
transports are supposed to be three ways of speaking *one* contract. Two leaks break
that promise today.

### Leak 1 — the MCP transport renames five core verbs

The MCP tool catalog is not the core verb set; it relabels half of it. Every renamed
tool is a thin alias whose implementation immediately calls the core verb:

```
lib/textus/mcp/tools.rb
  "tick"        → ops.pulse(since:)        # :36
  "find"        → ops.list(...)            # :26
  "read"        → ops.get(key)             # :30
  "write"       → ops.put(...)             # :41
  "fetch_stale" → ops.fetch_all(...)       # :73
```

The CLI and Ruby API use `pulse` / `list` / `get` / `put` / `fetch_all`; MCP uses
`tick` / `find` / `read` / `write` / `fetch_stale`. The justification on record
("`tick` reads as a heartbeat; `find` is agent-natural") does not survive scrutiny: an
agent reads tool *descriptions* from `boot`, never the bare names, so the rename buys the
agent nothing. What it costs is real and lands on humans:

- [`docs/agents-mcp.md`](../../agents-mcp.md) carries a permanent translation
  parenthetical ("`tick` is the MCP name for `pulse`, `find` for `list`, `read` for
  `get`, `write` for `put`") and a separate MCP tool table — a maintained mapping that
  exists only because the two surfaces disagree.
- The maintainer context-switches vocabulary per transport.
- A reader cannot tell whether the divergence is load-bearing (it is not).

`get`/`read` and `put`/`write` have no audience argument at all; they are simply
inconsistent. This directly violates [ADR 0029](./0029-concept-vocabulary.md)'s rule —
*one canon term per concept* — which ADR 0029 applied to the spatial vocabulary
(space/lane/zone) but never extended to verbs.

### Leak 2 — only the MCP transport remembers a cursor

The `boot`/`pulse` loop has two halves: a one-shot orientation and a per-turn delta
keyed by a monotonic cursor. The cursor is *session state*. Today that state exists only
inside the MCP transport:

```
lib/textus/mcp/session.rb     Session = Data.define(:role, :cursor, :propose_zone, :manifest_etag)
lib/textus/mcp/server.rb:84   @session = @session.advance_cursor(latest_seq) if name == "tick"
lib/textus/mcp/session.rb     check_etag! → raises ContractDrift on manifest drift
```

CLI and Ruby callers get none of it. The CLI's `pulse` takes `--since=N` and **the caller
must track `N` itself** between turns; the documented agent loop in `agents-mcp.md` is
exactly that hand-rolled cursor bookkeeping plus manual `CursorExpired` / drift recovery —
unguarded glue every non-MCP integrator re-writes. So MCP is special *twice*: it renames
verbs **and** it is the only transport that holds a session.

Both leaks are the same shape: **the MCP transport carries behavior that belongs to the
protocol.** Pull that behavior down into the core and the transports become what the
README already claims they are — three framings of one contract, differing only in
*mechanism* (argv / method call / JSON-RPC), never in *vocabulary* or *capability*.

## Decision

**Core owns the verb vocabulary and the agent session. CLI, Ruby, and MCP are pure
framings over the core. They differ in transport mechanism only.**

1. **One verb vocabulary, canonical = the core/CLI names.** The MCP catalog adopts the
   core verbs and renames nothing:

   | Concept | Everywhere (CLI · Ruby · MCP) | was, on MCP |
   |---|---|---|
   | orient | `boot` | `boot` |
   | per-turn delta | `pulse` | `tick` |
   | enumerate | `list` | `find` |
   | read one | `get` | `read` |
   | write one | `put` | `write` |
   | queue a proposal | `propose` | `propose` |
   | fetch one / all stale | `fetch` / `fetch_all` | `fetch` / `fetch_stale` |
   | introspect | `schema` · `rules` | `schema` · `rules` |

   The maintenance tools (`key_mv_prefix`, `key_delete_prefix`, `zone_mv`, `rule_lint`,
   `migrate`) already match the CLI and are unchanged.

2. **`propose` becomes a first-class CLI verb** — `textus propose KEY --as=agent --stdin`
   — auto-prefixing the manifest's `propose_zone` exactly as the MCP `propose` tool does
   (`tools.rb:53`). This closes the one genuine *capability* gap (today the CLI forces
   `put proposals.KEY --as=agent`, requiring the author to know the queue zone name) and
   makes the surfaces conceptually complete, not just consistently named.

3. **Lift the session into core as `Textus::Session`** (role + cursor + propose_zone +
   manifest_etag), owning cursor advance, manifest-drift detection (`ContractDrift`), and
   cursor-expiry detection (`CursorExpired`). The current `MCP::Session` becomes a thin
   delegate to it; the MCP server's `name == "pulse"` advance and `check_etag!` route
   through the core value.

4. **Every transport gets the session, framed for its mechanism:**
   - **MCP** — holds a `Textus::Session` in memory for the connection lifetime (today's
     behavior, now shared code).
   - **Ruby** — `store.session(role:)` returns a `Textus::Session`; the documented loop
     uses it instead of hand-tracking `since`.
   - **CLI** — `textus pulse` *with no `--since`* reads and writes the cursor from
     `.textus/.state/cursor.<role>` (gitignored), giving the CLI the same "what changed
     since *I* last looked" semantics MCP already has. `--since=N` stays as the explicit,
     stateless override for scripts that own their cursor.

## Consequences

- **`textus/3` wire format is unchanged.** Envelope shape, the role/zone gate, the audit
  log format, and the key grammar are untouched. This is an *interface*/*naming* change at
  the MCP and CLI surfaces, plus new local state (`.textus/.state/`), not a protocol-bytes
  change. Envelopes still carry `protocol: textus/3`.
- **Breaking for MCP consumers** that hardcode tool names: `tick`→`pulse`, `find`→`list`,
  `read`→`get`, `write`→`put`, `fetch_stale`→`fetch_all`. A *live* agent rediscovers tools
  via `tools/list`, so the real blast radius is hardcoded prose — `docs/agents-mcp.md`, the
  `examples/claude-plugin/` `CLAUDE.md`/templates and its generated `output/`, `SPEC.md` §9,
  `docs/README.md`. Enumerated and fixed in the same release.
- **The translation table dies.** `agents-mcp.md` loses its "tick is pulse…" parenthetical
  and its separate MCP-name column; one verb table serves all transports. ADR 0029's
  one-canon-term rule now covers verbs as well as spatial terms.
- **MCP stops being special.** It is stdio JSON-RPC framing around the same verbs and the
  same `Textus::Session` the CLI uses. New transports inherit both for free.
- **New local state.** `.textus/.state/cursor.<role>` is per-role, gitignored,
  single-writer. It is a convenience cache: deleting it just makes the next `pulse` behave
  like `--since=0` (re-emit recent deltas), never corrupts the store.

## Alternatives considered

- **Specify the split instead of removing it** (the non-breaking option from the design
  discussion): keep `tick`/`find`/… but declare in SPEC that the protocol owns *concepts*
  and each transport names them idiomatically. Rejected now that breaking changes are
  acceptable: it *adds* a layer (a concept→transport mapping maintained forever) to
  formalize an accident, where unification *removes* one. A protocol with one name per
  operation is simpler than one with a per-transport naming layer.
- **Unify on the MCP names** (`read`/`write`/`find`/`tick`) instead of the core names.
  Rejected: the core names are the canonical implementations (the MCP tools are aliases
  over them), `get`/`put`/`list` are the unambiguous unix/REST lineage, and `pulse` is
  already the concept term throughout SPEC/code/CLI and the cursor narrative.
- **Leave the cursor in MCP; ship a reference loop script for CLI/Ruby.** Rejected: fixes
  one transport with copy-pasteable glue and leaves MCP special. Lifting `Session` fixes
  all three from one place.
- **Keep `MCP::Session` as the home and have CLI/Ruby import from `MCP`.** Rejected:
  inverts the dependency (core depending on a transport); the session is a protocol
  concept and belongs in core.

## Open questions (for resolution before merge)

- **Q1 — concurrent agents under one role/checkout.** The `.textus/.state/cursor.<role>`
  file assumes a single writer per role. Two agent loops sharing a checkout under the same
  role would race the cursor. Proposed: **document single-writer as the supported model**;
  multi-agent stores already separate by role, and the file is a cache (a stale read costs
  a re-emitted delta, not correctness). Add a lock only if a concrete multi-writer case
  appears.
- **Q2 — deprecation shim for the old MCP names?** A one-release alias layer
  (`tick`→`pulse`, etc.) would soften the break for external `.mcp.json` consumers.
  Proposed: **no shim** — the gem is pre-1.0, the textus/3 wire is unchanged, agents
  rediscover tools dynamically, and a shim re-introduces exactly the dual vocabulary this
  ADR removes. Note the rename prominently in `CHANGELOG.md`.
- **Q3 — name collision with the retired per-call `Session`.** [ADR 0021](./0021-session-and-module-use-cases.md)'s
  `Session` is gone (→ `RoleScope`, ADR 0022), so `Textus::Session` is free. Confirm no
  lingering references before reclaiming the name.
