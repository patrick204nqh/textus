# ADR 0040 — The MCP connection acts as `agent`; human authority is a separate channel

**Date:** 2026-05-31
**Status:** Accepted — §1/§2/§4 ship 0.38.0; §3 (role-aware `surfaces`) tracked separately
**Refines:** [ADR 0015](./0015-agent-gate-mcp.md) (the agent gate is MCP-shaped), [ADR 0036](./0036-transports-as-pure-framings.md) (transports are framings over one verb vocabulary; one resolution chain), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP catalog derives from `surfaces`; this resolves its open question Q2)
**Touches:** [ADR 0030](./0030-capability-based-roles.md) / [ADR 0033](./0033-complete-primitives-and-vocabulary.md) (capability roles; `author` vs `propose`), [ADR 0035](./0035-proposal-target-zone-constraint.md) (proposal target zone; the accept/reject anchor-gate), [ADR 0038](./0038-runtime-artifacts-under-run-and-layout.md) (`role` is tracked config, shared across transports), [ADR 0027](./0027-hook-signature-and-mcp-policy.md) (MCP policy)

## Context

ADR 0036 declared CLI, Ruby, and MCP three framings of one contract, and lifted
the session into core. ADR 0039 made the MCP tool catalog a pure projection of
that contract. Neither addressed **which role the MCP connection acts as** — and
the answer today is an accident of omission.

`MCP::Server#initialize` defaults `role:` to `Textus::Role::DEFAULT` (`"human"`),
and `CLI::Verb::MCPServe#call` constructs the server with **no role override**
(`mcp_serve.rb`). It never calls `Role.resolve`, the resolution chain every other
entry point uses (`cli/verb.rb:96`). So every MCP `tools/call` dispatches through
`store.as("human")` (`tools.rb:21`) — the agent on the other end of the stdio pipe
operates with **human write authority**.

This contradicts what the integration guide promises. `docs/agents-mcp.md` and the
suggested `CLAUDE.md` snippet both state the agent "cannot write to `working/` or
`identity/` directly; it can only propose to `review/`." Under the current wiring
that gate is decorative: a `human`-roled connection holding the `author` capability
(as `human` does in `examples/project`) can `put` straight into `working/` and
`identity/`.

The rest of the design **already leans the other way.** ADR 0039's `MCP_OMITTED`
list withholds exactly the human-authority verbs — `accept`, `reject`, `publish`,
`delete`, `mv`, and the destructive maintenance ops — from MCP. Textus has already
decided those actions don't ride the agent channel. The only thing inconsistent
with that decision is the *role the connection runs as*: `accept` is correctly off
MCP, yet `put working/...` is reachable because the role is `human`. The omit-list
started a boundary the role assignment quietly undoes.

Two further facts constrain the fix:

- **`role` is tracked, shared config (ADR 0038).** `.textus/role` is classified
  *authored config* — committed, read by `Role.resolve` for *every* transport. It
  is the project-wide default identity, not a per-connection knob. Committing
  `role: agent` to gate the MCP connection would also demote the human's own CLI
  (they could no longer `accept`). It is the wrong lever.
- **The catalog is now role-blind (ADR 0039).** `surfaces :mcp` is a per-verb
  boolean; the agent's `tools/list` advertises the full MCP set including
  `zone_mv`, `migrate`, and `key_delete_prefix`. Combined with the `human` role,
  an agent both *sees* and *can execute* destructive bulk maintenance. ADR 0039
  left this as its open question Q2.

## Decision

### 1. Two channels, by design: the agent proposes, the human disposes

The MCP connection is the **agent channel**: it stages work (`propose`, plus the
read verbs). The actions that make a write load-bearing — `accept`/`reject`,
direct `put` to `working/`/`identity/`, destructive maintenance — are the **human
channel**, reached through the human's own CLI (`textus accept`, `textus put
--as=human`). The two channels coexist; the human does not toggle the agent's
role to dispose, they use their own hands.

This is not a limitation imposed on the agent — it is the gate's reason to exist.
The control point ADR 0035 made explicit (the accept/reject anchor-gate) is only
meaningful if `accept` happens through a channel the agent does not drive. The
rationale is **authorship ≠ authority**: a human at the keyboard *authors* a
request, but a load-bearing write requires a *deliberate human ratification act*.
"A human is present" does not authenticate every byte the agent emits — that is
the prompt-injection and agent-error threat model the gate closes. If the agent
channel could carry human authority because the human asked, "the human's
decision" silently becomes "whatever the agent did this turn."

### 2. The default acting role differs by transport; the override chain is uniform

Resolution stays exactly as ADR 0036 / `Role.resolve` defines it, with one change:
the *fallback* is transport-specific.

```
  CLI transport   default role = human   (the person typing)
  MCP transport   default role = agent   (the subprocess)
        │
        └── both honor:  --as flag  >  TEXTUS_ROLE  >  .textus/role  >  transport-default
```

`MCPServe#call` resolves its role through `Role.resolve` with an `agent` fallback
instead of inheriting the global `human` default. `.textus/role` stays the team's
deliberate CLI default (ADR 0038) and is left absent (or `human`); it is **not**
the place agent-mode is set.

This keeps ADR 0036's thesis intact — transports are framings sharing one
resolution chain — while letting the *default identity* legitimately differ
(human at the CLI, agent over stdio).

An MCP connection is thus configured by a `(root, role)` pair, and **both halves
already share one resolution discipline.** Store-root resolution exists today
(`Store.discover`): `--root` flag → `TEXTUS_ROOT` env → upward `.textus`
discovery — the same flag/env/default shape as the role chain above, and it
already flows into `mcp serve` because that verb is built on the CLI store
plumbing (`cli.rb:67`). No new mechanism is needed; a committed root-pointer
file is *rejected* for the same reason a committed `role: agent` is (§ Alternatives)
— it would be shared across all transports (ADR 0038) when the need is
per-connection. One posture note follows from §1's "agent channel" framing: the
*default* root tier is cwd discovery, which is correct for a human in their
project directory but unreliable for a subprocess whose cwd is unspecified — so
the agent channel should **pin the root explicitly** (`--root`/`TEXTUS_ROOT` in
`.mcp.json`), exactly as it pins nothing and inherits the `agent` role default.
Root resolution fails loud (`IoError`), so unlike the role default it needs no
reconciliation guard.

### 3. `surfaces` becomes role-aware; the agent catalog drops human-authority verbs

ADR 0039's `surfaces :mcp` boolean becomes role-parameterized, resolving its Q2:

```ruby
surfaces cli: :all, ruby: :all, mcp: [:agent, :human]   # read/propose verbs
surfaces cli: :all, ruby: :all, mcp: [:human]           # zone_mv, migrate, key_delete_prefix
```

The MCP catalog is then `VERBS.select { _1.contract.mcp?(session.role) }` — an
agent connection's `tools/list` no longer advertises destructive maintenance, a
`human` connection's does. With §2 making `agent` the default, this is the floor
that stops an agent both seeing and running bulk-delete/migrate.

### 4. The default is declared and guarded; the escape hatch is explicit

A reconciliation spec pins the MCP transport default role, so it can never again
become an accident of omission — changing it is a visible edit, not silent drift
(the ADR 0037/0039 derive-or-guard discipline, applied to the connection role).

For a solo developer who wants the agent itself to run with full authority and
accepts that the gate is then advisory, the override chain already provides the
hatch — `mcp serve --as=human`, or `TEXTUS_ROLE=human`. It is explicit, per
connection, reversible by dropping the flag, and reconciled by the same spec.
Safe by default; convenient by deliberate choice.

## Consequences

- **The documented gate becomes true.** An MCP agent can `propose` but not `put`
  to `working/`/`identity/`; `accept`/`reject` remain off MCP (ADR 0039
  `MCP_OMITTED`). `docs/agents-mcp.md` stops over-promising.
- **`server.rb`'s `proposer_role` workaround can retire.** Its comment at
  `handle_initialize` derived `propose_zone` from `proposer_role` *because* the
  connection was `human`. With the connection acting as `agent`,
  `propose_zone_for(@role)` resolves directly — the special-case dissolves
  (this aligns with ADR 0039's `Write::Propose`, which resolves
  `propose_zone_for(@call.role)`).
- **Destructive verbs leave the agent's tool list** (§3), removing the worst
  blast radius: an agent cannot be steered into `key_delete_prefix`/`migrate`.
- **`.textus/role` keeps its ADR 0038 meaning** — project-wide tracked default —
  and is explicitly *not* repurposed as a per-connection gate.
- **Breaking for any consumer relying on MCP carrying human authority.** A store
  whose MCP agent silently wrote to `working/` will now get `write_forbidden` and
  must either `propose` + `accept`, or opt into `--as=human` knowingly. Enumerated
  in `CHANGELOG.md`.
- **Depends on ADR 0039's `surfaces` DSL** for §3; §1/§2/§4 can land independently
  if sequenced first.
- **New surface to guard:** the per-transport default and the role-aware `surfaces`
  filter are themselves load-bearing facts — both get reconciliation specs (§4).

## Alternatives considered

- **Set agent mode via committed `.textus/role`.** Rejected: ADR 0038 classifies
  `role` as tracked config read by *every* transport, so `role: agent` would also
  strip the human's CLI of `author`/`accept` — locking the disposer out of their
  own gate. The role file is a project-wide default, not a per-connection knob.
- **Keep `human` as the MCP default (status quo).** Rejected: it makes the
  integration guide's central promise false and leaves an agent one prompt-injection
  away from a load-bearing write under human authority.
- **A live in-session "elevate to human" MCP tool.** Rejected: it reopens the exact
  gate-collapse hole — the agent channel would carry human authority on demand,
  making ratification meaningless. The role is bound at the `initialize` handshake
  for the connection's lifetime; re-binding is a reconnect, deliberately.
- **Register two MCP servers (`textus` as agent, `textus-human` as human).**
  Rejected: it puts the human-authority tools into a catalog the agent can call,
  defeating §3. Human disposal belongs on the CLI, not a second agent-reachable
  server.
- **Role-aware `surfaces` only, leave the role `human`.** Rejected as a half-fix:
  hiding `zone_mv` from `tools/list` does not stop a `human`-roled agent from
  `put`-ing to `working/`; the role is the load-bearing control, the catalog
  filter is defense-in-depth on top of it.

## Open questions

- **Q1 — granularity of role-aware `surfaces`.** §3 assumes a small `:agent` /
  `:human` split. If more roles appear (ADR 0030 makes roles open-ended), the
  filter may need capability-based exposure (`mcp: { requires: :author }`) rather
  than a role allowlist. Out of scope until a third role needs MCP.
- **Q2 — should `accept` ever be MCP-reachable under `--as=human`?** Today
  `MCP_OMITTED` withholds it unconditionally. A human-roled connection arguably
  could accept; but it muddies the two-channel model. Deferred — the CLI is the
  disposer until a concrete need appears.
- **Q3 — per-project agent capability profile.** Some teams may want the agent to
  hold more than `propose` (e.g. `author` in a scratch zone). That is a manifest
  role-capability decision (ADR 0030/0033), orthogonal to the connection-role
  default decided here.
