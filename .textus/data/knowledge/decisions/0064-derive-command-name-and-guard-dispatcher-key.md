# ADR 0064 — Derive the CLI command name; guard the dispatcher key against the contract verb

**Date:** 2026-06-03
**Status:** Accepted (ships 0.44.0)
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (the CLI is a projection of the contract — 0063 made the *dispatched verb* contract-derived and the reconciliation specs a safety belt; this ADR removes the two name-restatements 0063 left standing, so the belt guards an invariant the code can no longer violate by construction).
**Touches:** [ADR 0058](./0058-one-verb-name-across-surfaces.md) (one verb name across surfaces — this makes the *dispatcher key* and the *CLI command name* the last two spellings to collapse into the contract), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (derive-or-guard discipline), [ADR 0037](./0037-boot-pulse-derive-or-guard.md) (boot's catalog is already curated+guarded; this ADR records it as the deliberate exception, not a gap).

> **One sentence:** ADR 0063 made the CLI's *dispatch* derive from the contract but left two places where a verb's name is still authored twice — the escape-hatch `command_name "get"` literal and the `Dispatcher::VERBS` key, which no spec checked against the contract's own `verb` — so this ADR derives `command_name` from `spec.cli_leaf` and adds the one missing guard, turning 0063's "drift is unrepresentable" from a reconciled property into a structural one.

## Context

ADR 0063's own summary calls the reconciliation specs "a safety belt rather than the only strap" — an honest signal that two restatements survived the projection:

1. **The escape-hatch `command_name`.** A `Runner::Base` subclass sets `self.spec = Read::Get.contract` (so the dispatched verb is derived) but still hand-types `command_name "get"`. The reconciliation spec asserts `path_of(klass) == spec.cli_path`, so a drifted literal is *caught*, but it is still authored twice.
2. **The `Dispatcher::VERBS` key.** `dispatcher.rb` registers `get: Read::Get`; `Read::Get` independently declares `verb :get`. `contract_signature_reconciliation_spec` iterates `VERBS.each |verb, klass|` but only checks *arg names* — nothing asserted `klass.contract.verb == verb`. A mismatch would surface only indirectly (RoleScope defines `#get` off the key while MCP/CLI `public_send(spec.verb)`), as a confusing `NoMethodError`, not a clear guard.

So at the identity level the architecture was **reconciled, not derived**: drift was representable but CI-caught. That is a strictly weaker guarantee than "unrepresentable."

A third surface, `boot`'s `CURATED_CLI_VERBS`, also spells verb names literally — but it is *already* derive-or-guard (ADR 0037): summaries derive from `contract.summary`, and `boot_cli_verbs_registry_reconciliation_spec` fails the build if a catalog name has no registered command or a new top-level command is neither catalogued nor explicitly omitted. It is a deliberately curated agent-orientation list (mixing group labels like `key`/`rule`/`schema` with verbs), so full membership-derivation is neither possible nor desirable. This ADR records it as the intended exception.

## Decision

1. **Derive the CLI command name.** `CLI::Runner::Base.command_name` falls back to `spec.cli_leaf` when not set explicitly. The 13 escape-hatch classes drop their literal `command_name "…"`. Because the reconciliation spec already proved `command_name == cli_leaf` for every such class, this is an equivalence, not a behavior change — the set of CLI commands, flags, and output is identical.
2. **Guard the dispatcher key.** `contract_signature_reconciliation_spec` gains one assertion per verb: `Dispatcher::VERBS[sym].contract.verb == sym`. The key and the contract verb can no longer disagree silently.
3. **Record boot as the curated+guarded exception** (ADR 0037), not a derivation gap.

## Consequences

- Adding or renaming a verb now touches the name in **one** authored place — the use-case's `verb :x` declaration. The CLI command name derives; the dispatcher key is guarded equal; boot is reconciled.
- The plain `< Verb` commands with no dispatcher verb (`init`, `hook`, `mcp serve`, `schema diff/init/migrate`, `boot`, `doctor`, `fetch` family) keep their literal `command_name` — they have no contract to derive from, by design.
- 0063's reconciliation specs remain as defense in depth; they now guard an invariant the code cannot express incorrectly, rather than being the only thing standing between the surfaces and drift.

## Alternatives considered

- **Derive `Dispatcher::VERBS` keys from `contract.verb` (full single-sourcing).** Build the hash as `[Read::Get, …].to_h { [_1.contract.verb, _1] }`, so the symbol lives only in the use-case. This makes the mismatch *impossible* rather than guarded. Rejected for 0.44.0 to keep the change low-risk and the dispatcher's explicit, greppable, ordered manifest intact; the guard (Decision 2) closes the correctness gap at near-zero cost. Re-evaluate if a future ADR wants the keys gone entirely.
- **Derive boot's catalog membership.** Rejected — the catalog is editorial orientation (curated subset, group labels), already guarded against ghosts and silent omissions by ADR 0037.
- **Push escape-hatch behavior into the contract as `cli_invoke` strategies (collapse generated + escape-hatch populations).** A larger refactor that eliminates the hand-class layer entirely; deferred — out of scope for a 0.44.0 fold-in.
