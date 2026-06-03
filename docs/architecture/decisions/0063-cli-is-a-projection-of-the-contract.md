# ADR 0063 — The CLI is a projection of the contract: close the last derive-or-guard gap

**Date:** 2026-06-03
**Status:** Proposed
**Refines:** [ADR 0036](./0036-transports-as-pure-framings.md) (transports are pure framings over one verb vocabulary — this makes the CLI framing *actually* derived, not a hand-authored parallel surface that merely agrees by reconciliation), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP catalog is fully derived from per-verb contracts — this extends the same derive-or-guard discipline to the CLI, the one surface still hand-wired).
**Touches:** [ADR 0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) (boot already derives its verb lists from the catalog — same family), [ADR 0057](./0057-agent-legible-mcp-contracts.md) (the contract already carries per-arg descriptions and `wire_name`; this adds a parallel CLI facet to the same record), [ADR 0058](./0058-one-verb-name-across-surfaces.md) / [ADR 0059](./0059-one-rule-verb-two-depths.md) / [ADR 0061](./0061-build-publish-vocabulary.md) (each fixed a *name/dispatch drift that originated in a hand-typed CLI verb*; this removes the class of bug those three paid for one at a time), [ADR 0062](./0062-one-get-read-through.md) (established that one contract feature — the literal arg default — can be honored *identically* at every dispatch chokepoint, `RoleScope` and `MCP::Catalog.map_args`; the CLI runner is the third such chokepoint).

> **One sentence:** the `Contract` is already the single source of truth that the Ruby (`RoleScope`), MCP (`MCP::Catalog`), and boot surfaces *project* from — but the CLI is the lone exception, 36 hand-authored `CLI::Verb::*` classes that each re-type the command name, the option flags, and (the load-bearing part) the dispatched verb method, so a verb can wear a different name or dispatch the wrong use-case on the CLI alone; this ADR makes the CLI a **projection** of the contract like the others — a generic runner derives the command, flags, arg-mapping, and dispatch from `contract`, per-verb classes shrink to opt-in escape hatches for genuine behavior, and the reconciliation specs become a safety belt rather than the only strap.

## Context

textus has one verb vocabulary lifted to core (ADR 0036) and one declared `Contract` per verb that every transport is supposed to project from (ADR 0039). The contract's own docstring says so: *"CLI/Ruby/MCP and boot project from this."* For three of the four surfaces that is literally true:

- **Ruby (`RoleScope`)** metaprograms one method per `Dispatcher::VERBS` key and injects each arg's contract default. Derived.
- **MCP (`MCP::Catalog`)** generates `tools/list`, the input schema, arg-mapping (`map_args`), and the generic `tools/call` dispatch from `contract`. *No per-tool code.* Derived.
- **boot** derives `read_verbs`/`write_verbs` from the catalog (ADR 0056). Derived.

The **CLI is the exception.** Each of the 36 `CLI::Verb::*` classes hand-authors:

- the **command path** — `command_name "get"`, or a group leaf like `schema show`;
- the **option flags** — `option :no_fetch, "--no-fetch"`, `--as=ROLE`, `--dry-run`;
- **argument parsing** — `positional.shift`, building the keyword hash — duplicating `MCP::Catalog.map_args`;
- and, load-bearing, the **dispatched verb method** — the literal call `session.get(...)` / `ops.publish(...)`.

That last line is where every drift in the 0.44.0 cycle was born. The CLI command and the verb it dispatches are two independently hand-typed tokens, so they can disagree:

- **ADR 0058** — the MCP tool `schema` vs the CLI `schema show`; the CLI `fetch stale` leaf that called `fetch_all`. Name disagreements between a hand-typed CLI path and the contract.
- **ADR 0059** — `rule list` computed its rows *inline in the CLI verb* with no use-case, and the for-key rule read wore `rules` on MCP but `rule explain` on the CLI.
- **ADR 0061** — the CLI command `build` dispatched `ops.publish` (`Write::Publish`); the command and the verb it ran were different words.

Each was fixed as its own ADR, by hand-editing the CLI verb *and* the contract *and* keeping a reconciliation spec in lockstep. The reconciliation specs (`contract_signature_reconciliation_spec`, `mcp_catalog_dispatcher_reconciliation_spec`, `boot_cli_verbs_*`) **guard** the gap — they catch drift at test time — but guarding is not deriving: the second edit site still exists, the hand-labor is still paid, and a verb's CLI name is still authored independently of its contract. The root cause is structural, not a sequence of unrelated naming mistakes: **the CLI is the one surface that re-states the contract instead of projecting it.**

The CLI does carry information the contract does not yet model, which is *why* it was hand-written and not derived in the first place:

1. **Command grouping** — `schema show`, `key delete`, `rule explain`. This is *not* losslessly recoverable from the `_`-joined verb token: `fetch_all`, `validate_all`, and `schema_show` contain underscores that are not group boundaries, so the path must be **declared**, not inferred.
2. **Flag spellings and cross-cutting flags** — `--no-fetch` (the negation of `fetch: true`), and the universal `--as=ROLE` / `--dry-run` / `--stdin` framing that are not per-verb args at all (role and `dry_run` live on `Call`, not in `contract.args`).
3. **Genuine per-verb behavior** — `build` wraps `Ports::BuildLock.with`; `get` raises `UnknownKey` with resolver suggestions on a nil result; `put` reads its body from the `--stdin` envelope. These are real, and they resist pure derivation.

The fix is not to pretend (3) away, but to separate *naming/dispatch* (which must be derived) from *behavior* (which may be overridden) — exactly the split MCP already lives with via its opt-in `response:` block.

## Decision

**The CLI is a projection of the contract, not a parallel hand-authored surface.** The contract grows a CLI facet; a generic runner projects it; per-verb classes shrink to behavior-only escape hatches; the reconciliation guard becomes total.

1. **The contract carries a CLI facet.** Add `cli` to the `Contract` DSL: the declared command path (`cli "schema show"`, defaulting to the verb token for ungrouped verbs) and any flag-spelling overrides. Boolean-arg flag spelling follows a convention from the arg's `default` (`fetch: true` → `--no-fetch`; a `false`/absent default → `--<name>`), so the common case needs no override. The cross-cutting `--as=ROLE` / `--dry-run` / `--stdin` are runner-global, not per-verb, and stay out of the contract.

2. **A generic `CLI::Runner` projects the contract** — the CLI mirror of `MCP::Catalog`. Given a `:cli`-surfaced contract it registers the command at its declared path, declares options from `contract.args` (+ the global flags), parses the wire input into `(positional, keyword)` by **reusing the same `map_args` logic** MCP uses (one arg-mapping implementation, not two), dispatches `store.as(role).public_send(contract.verb, *pos, **kw)`, and emits via `contract.response`. Naming and dispatch are therefore **derived** — the CLI command *is* `contract.verb` by construction; it cannot dispatch a differently-named use-case.

3. **Per-verb classes become opt-in escape hatches for behavior only.** A verb with genuine extra behavior (`build`'s `BuildLock`, `get`'s `UnknownKey` suggestions, `put`'s `--stdin` body) registers a thin override that the runner invokes around the derived dispatch — the same shape as MCP's opt-in `response:` block. The override may shape I/O and wrap the call; it **may not** restate the verb name or the dispatch target. Verbs with no special behavior have no class at all.

4. **The reconciliation guard becomes a belt, not the strap (Phase A, shippable alone).** Make `contract_signature_reconciliation`/`mcp_catalog_dispatcher_reconciliation` *total* for the CLI: assert every `:cli`-surfaced contract resolves to a command whose path equals its declared `cli` path and whose dispatched method equals `contract.verb`. Once dispatch is derived (steps 2–3) this guard can only fail on a declaration typo, never on hand-wiring — it documents the invariant the runner already enforces.

5. **No wire-contract change; this is an internal restructuring.** The set of CLI commands, their paths, their flags, and their output are identical before and after. `SPEC.md` is unaffected (the *what* is unchanged); this ADR is purely about *how* the CLI surface is produced. No `boot`/MCP change — those already derive.

## Consequences

- **Name/dispatch drift becomes unrepresentable, not merely caught.** The bug behind ADR 0058/0059/0061 — a CLI command dispatching a differently-named verb — cannot be written: the runner dispatches `contract.verb`. A future rename is a one-token change in the contract that all four surfaces follow, the way MCP and Ruby already do.
- **The reconciliation specs change role.** They stop being the load-bearing strap that holds two hand-authored layers together and become a thin assertion of an invariant the runner enforces structurally — cheaper to keep green, and no longer the thing that *must* be edited in lockstep with every verb change.
- **One arg-mapping implementation.** `map_args` is shared by the MCP and CLI runners, so an agent and an operator parse the same contract the same way; the per-verb `positional.shift` hand-parsing disappears.
- **The 36 verb classes shrink to a handful of behavior overrides.** Most CLI surface area becomes a registry of `(contract → command)` projections; only verbs with real extra behavior keep a class, and those classes shrink to the behavior.
- **The contract gains a CLI facet — a deliberate, bounded growth.** The record that already holds the agent-facing summary, arg schema, wire names (ADR 0057), and surfaces now also holds the operator-facing command path. One record describes a verb on every surface.
- **Phased, stoppable.** Phase A (total guard) hardens today's hand-authored state immediately and is shippable on its own; Phase B/C (the runner + escape hatches) removes the hand-labor and can land verb-by-verb behind the guard.

## Alternatives considered

- **Status quo: keep hand-authored CLI verbs, rely on reconciliation specs.** Rejected as the root cause, not a fix. The specs guard drift but do not prevent the second edit site; ADR 0058/0059/0061 are three instances of the same hand-wiring bug, each paid separately. Guarding is strictly weaker than deriving, and the codebase already derives every *other* surface.
- **Full generic driver, zero per-verb classes.** Rejected: `build`'s `BuildLock`, `get`'s suggestion-bearing `UnknownKey`, and `put`'s `--stdin` body are genuine per-verb behavior, not naming. Forcing them into a uniform driver would either bloat the contract with behavioral hooks or push that behavior somewhere worse. The hybrid keeps naming derived and behavior explicit — the same line MCP already draws with `response:`.
- **Derive the CLI command path from the verb token (`schema_show` → `schema show`).** Rejected: not lossless. `fetch_all`, `validate_all`, and `schema_show` carry underscores that are not group boundaries; an inferred split would mis-group them. The path must be declared. (Declaring it in the contract is still single-source — it is the one place the path lives, projected everywhere — which is the whole point.)
- **Flatten the CLI to bare tokens to match MCP exactly (no groups).** Rejected for the reason ADR 0058 already gave: the CLI groups (`schema {show,diff,init,migrate}`, `key {delete,mv,uid}`) are good operator ergonomics. The goal is to *derive* the grouped CLI from the contract, not to delete the grouping.
- **Move role/`dry_run`/`stdin` into the contract as args too.** Rejected: they are cross-cutting framing that lives on `Call`, not per-verb arguments, and every CLI command shares them. The runner applies them globally; modeling them as per-verb contract args would duplicate them 36 times and blur "what this verb takes" with "how the CLI is invoked."
