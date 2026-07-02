# ADR 0039 — The MCP catalog derives from one declared verb contract; no unguarded hand-maintained mirror

**Date:** 2026-05-31
**Status:** Accepted — ships 0.37.0 (**breaking**: MCP tool surface and core verb set change)
**Refines:** [ADR 0036](./0036-transports-as-pure-framings.md) (transports are pure framings over one verb vocabulary), [ADR 0037](./0037-boot-pulse-derive-or-guard.md) (derive-or-guard: every agent-facing fact is derived from one source of truth, or guarded by a contract spec)
**Touches:** [ADR 0022](./0022-container-call-dispatcher.md) (`Dispatcher::VERBS` as the canonical operation map), [ADR 0033](./0033-complete-primitives-and-vocabulary.md) (the complete verb set), [ADR 0027](./0027-hook-signature-and-mcp-policy.md) (MCP policy)

## Context

ADR 0036 declared that CLI, Ruby, and MCP are **three framings of one contract**,
differing in *mechanism* (argv / method call / JSON-RPC) only — never in vocabulary or
capability. ADR 0037 then established the governing rule for agent-facing facts:

> Every agent-facing fact is either *derived* from a single source of truth, or it is a
> deliberate editorial copy *guarded* by a contract spec that fails the build when it
> diverges. No agent-facing fact may be a hand-maintained mirror with no derivation and
> no guard.

ADR 0037 applied that rule to `boot`/`pulse`. It was never applied to the **MCP tool
catalog**, which remains the last unguarded hand-maintained mirror in the tree — and the
one that costs the maintainer most. The core already has a single canonical operation
registry, `Dispatcher::VERBS` (33 verbs), and `RoleScope` / `Store` both *derive* their
entire method surface from it (`role_scope.rb:43`, `store.rb:69`). The MCP transport does
not. It hand-maintains three separate copies of facts that live elsewhere, and **nothing
fails when they diverge:**

1. **`MCP::Tools::REGISTRY`** (`lib/textus/mcp/tools.rb`) — 15 dispatch lambdas, a hand-curated
   subset of the 33 `Dispatcher::VERBS`. **21 verbs are absent** (`accept`, `audit`, `blame`,
   `delete`, `deps`, `doctor`, `freshness`, `mv`, `publish`, `stale`, `uid`, `where`, …) with
   **no record of which omissions are deliberate and which are accidental**. Add verb #34 to
   the dispatcher and nothing prompts a decision about MCP.

2. **`MCP::ToolSchemas.all`** (`lib/textus/mcp/tool_schemas.rb`) — 15 hand-written JSON
   `inputSchema` objects that mirror each use-case's `#call` keyword signature. When
   `Write::Put#call` grew `if_etag:`, the JSON had to be hand-edited to add `"if_etag"`.
   Rename a kwarg and the schema lies: the agent sends the documented name, the lambda's
   `args["…"]` reads `nil`, no error surfaces.

3. **The exposed set itself** — encoded implicitly across both files, recording a decision
   ("which verbs does an agent get?") that nobody wrote down.

These are exactly the drift class ADR 0037 names: *a copy of a fact that already lives
elsewhere, where the original can change and the copy silently rots.* Three of the 15 MCP
tools are not 1:1 dispatcher verbs — `propose` composes `put` + a `propose_zone` prefix
(`tools.rb:53`), and `schema` / `rules` reach *around* the dispatcher into `store.schemas`
and `manifest.rules`. Because MCP is not a *pure* projection, nobody could derive it
mechanically, so the whole catalog fell back to hand-maintenance — including the ~12 tools
that are trivial pass-throughs (`ops.public_send(verb, **kwargs)` plus a small response
shape). That residue of genuinely-composed tools is what blocks derivation, and removing it
is the lever.

The symptom the maintainer reports: *change an interface in core, and MCP silently goes
stale; catching it requires a manual audit and a hand-fix.* That is the status quo ADR 0037
already rejected for boot/pulse — left standing only because MCP was out of its scope.

## Decision

**The MCP catalog is a mechanical projection of one declared verb contract. Each verb
declares its interface once; CLI, Ruby, MCP, and boot all project from that declaration;
the only per-verb residue on MCP is response shaping, which is guarded.** This finishes
ADR 0036's "pure framings" thesis and brings MCP under ADR 0037's derive-or-guard rule.

### 1. Verbs declare a contract (derive the schema)

Each use-case declares its interface as class-level metadata — the argument shape and an
agent-facing summary — so the contract stops being implicit in a Ruby method signature and
re-typed by hand into JSON:

```ruby
class Write::Put
  verb     :put
  summary  "Create or update an entry. Schema-validated."
  surfaces :cli, :ruby, :mcp
  arg :key,     String, required: true
  arg :meta,    Hash,   required: true
  arg :body,    String
  arg :content, Hash
  arg :if_etag, String
  response { |env| { "uid" => env.uid, "etag" => env.etag } }
end
```

- `MCP::ToolSchemas` is **generated** from `arg`/`summary` — no hand-written JSON.
- The 12 pass-through `REGISTRY` lambdas collapse into **one generic adapter** that maps
  JSON `arguments` → kwargs via the declared `arg` set and dispatches through
  `Dispatcher::VERBS`. Only the `response` shaper is per-verb.
- The `surfaces` list is the *written record* of which transports expose the verb — the
  decision that was previously implicit.
- A guard spec asserts each contract's declared `arg` names equal the use-case `#call`
  parameters (`method(:call).parameters`), so a renamed kwarg fails the build rather than
  silently desyncing the schema.

### 2. `propose` / `schema` / `rules` become first-class dispatcher verbs (remove the residue)

The three composed MCP tools become real verbs in `Dispatcher::VERBS`, so MCP carries **zero**
transport-special-cases and becomes a literal projection:

- `propose` — a `Write::Propose` use-case that resolves `propose_zone_for(role)` and
  prefixes the key (the logic currently inlined in `tools.rb:53`). Also a first-class CLI
  verb, per ADR 0036 §2.
- `schema` — surfaced via the existing `Read::SchemaEnvelope` verb (already in the
  dispatcher) rather than a direct `store.schemas` reach.
- `rules` — a `Read::Rules` use-case returning the effective `fetch`/`guard` set for a key
  (the logic currently inlined in `tools.rb`).

The CLI `schema` and `rule` **groups** (`schema diff/init/migrate`, `rule explain/lint/list`)
stay as-is — they are multi-subcommand maintenance surfaces, not the single read the agent
needs; the new flat verbs serve the agent/MCP read path. (Open question Q1 revisits whether
the groups should eventually fold in.)

### 3. The exposed set is derived; guards are the floor (no unguarded mirror)

With `surfaces` on each contract, the MCP catalog is `VERBS.select { _1.surfaces.include?(:mcp) }`
— one registry, no second list. The 0037-style guard specs remain as the safety floor for the
residue derivation cannot cover:

- A verb marked `surfaces :mcp` with no `response` shaper, or whose return value won't
  serialize, fails the build.
- A verb added to `Dispatcher::VERBS` with no contract declaration fails the build — forcing
  the author to declare `surfaces` (which is the "expose on MCP or not?" decision), exactly as
  ADR 0037's `CLI_VERBS` reconciliation forces a boot decision.

## Consequences

- **`textus/3` wire format is unchanged.** Envelope shape, the role/zone gate, the audit log
  format, and the key grammar are untouched. This is an interface/derivation change at the
  MCP and core-verb surfaces, not a protocol-bytes change.
- **Breaking for the core verb set:** `propose`, `schema`, `rules` join `Dispatcher::VERBS`
  (new public Ruby/CLI verbs). **Breaking for MCP consumers** only if the exposed tool *set*
  changes as a consequence of writing down `surfaces` honestly — verbs previously absent by
  accident may appear; the change is enumerated in `CHANGELOG.md`. A live agent rediscovers
  tools via `tools/list`, so the blast radius is hardcoded prose and `examples/`.
- **The hand-written JSON schemas die.** `ToolSchemas` becomes a generator over the contracts.
  A kwarg rename can no longer desync the schema — the guard catches it, or the derivation
  carries it.
- **MCP stops being special** — no curated `REGISTRY` subset, no second name list, no composed
  reach-arounds. It is stdio JSON-RPC framing over the same contracts the CLI uses. New
  transports inherit the catalog for free, closing ADR 0036's thesis.
- **`Boot::CLI_VERBS` summaries can derive from the same `summary` field**, retiring one more
  ADR 0037 mirror (the name-set is already guarded; the summaries become derived).
- **New surface to design and guard:** the `verb`/`arg`/`summary`/`surfaces`/`response` DSL is
  itself load-bearing and gets its own guard (§1). It is net-new code; its value is that it is
  the *single* place a verb's interface is written.

## Alternatives considered

- **Guard only, derive nothing** (the cheap option: add reconciliation specs asserting
  `REGISTRY.keys == ToolSchemas` names and `REGISTRY ⊆ Dispatcher` minus an explicit omit
  list). Rejected as the *endpoint* but **adopted as the floor** (§3): it converts silent drift
  to a red build with hours of work, but leaves the hand-written JSON and the two parallel lists
  in place — it freezes the maintenance cost rather than removing it. The contract derivation
  removes it.
- **Derive the MCP schema directly from `method(:call).parameters`, no DSL.** Rejected: a bare
  Ruby signature yields argument *names* and required-ness but no types or descriptions, so the
  generated `inputSchema` would be uselessly permissive and the agent-facing summaries would
  have nowhere to live. The DSL carries the irreducible extra facts (type, description, summary,
  surfaces) that a signature cannot.
- **Keep `propose`/`schema`/`rules` as MCP-only composed tools; guard them as exceptions.**
  Rejected: it preserves MCP-special behavior ADR 0036 set out to delete, and the exception
  list is itself an unguarded judgement. Promoting them to verbs makes MCP a true projection and
  gives CLI/Ruby the same capability (ADR 0036 already promised `propose` on the CLI).
- **Declare contracts in a sibling `contracts/` registry, not on the use-case.** Considered and
  rejected for the primary design: co-locating the contract with the `#call` it describes keeps
  the guard (§1) trivial (same class) and avoids a second file to keep in sync — the very drift
  this ADR removes. (Recorded as Q2 in the design discussion; resolved in favour of on-class.)

## Open questions

- **Q1 — CLI `schema`/`rule` groups vs the new flat verbs.** This ADR adds flat `schema`/`rules`
  read verbs and leaves the multi-subcommand groups. If the groups' read subcommands become pure
  aliases of the flat verbs, a later ADR may fold them in. Out of scope here.
- **Q2 — per-role MCP projection.** If `surfaces` ever needs to vary by role (an agent sees a
  different catalog than a human connection), `surfaces :mcp` becomes `surfaces mcp: [:agent]`
  or similar, and the catalog filter and guard become role-parameterized. Carried from
  ADR 0037's open question; out of scope until that projection exists.
