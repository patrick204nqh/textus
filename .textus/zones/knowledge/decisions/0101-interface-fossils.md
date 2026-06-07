# ADR 0101 — interface-layer fossils

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0089](./0089-ingest-is-system-pushed.md) (it established that `put` stores bytes only and that each CLI verb owns its own stdin parsing — the `cli_stdin: :json` declaration on `Write::Put`'s contract is therefore a redundant fossil of the pre-0089 era when the contract DSL was the authority for stdin; this ADR removes it), [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (it established that CLI verbs are generated from contracts and that hand-authored escape hatches are the exception, not the norm — the hand-authored `CLI::Verb::Boot` and `CLI::Verb::Doctor` classes are exactly the exception this ADR retires), [ADR 0069](./0069-single-path-lifecycle.md) (it named the two categories of non-projected verbs — `BEHAVIORAL_HATCHES` and `NON_PROJECTED_CLI` — and noted that `NON_PROJECTED_CLI` should shrink toward zero as the projection machinery matures; this ADR removes `boot` and `doctor` from that list).
**Touches:** [ADR 0068](./0068-declarative-facets-dissolve-escape-hatches.md) (it introduced `cli_stdin` as a declarative contract facet, dissolving the acquisition escape hatch — the fossil this ADR removes is `cli_stdin: :json` surviving on `Write::Put`'s contract after 0089 moved stdin ownership into the verb; the facet and its projection logic are otherwise unchanged).

> **One sentence:** the interface layer (CLI verbs, MCP tools, contract DSL) accumulated three small fossils — a redundant `cli_stdin: :json` declaration on `Write::Put`'s contract (dead since ADR 0089 moved stdin ownership into `CLI::Verb::Put` itself), hand-authored `CLI::Verb::Boot` and `CLI::Verb::Doctor` classes that special-case verbs the projection machinery can already generate, and a thin `MCP::Tools` delegator that does nothing but forward every call to `MCP::Catalog` — so this ADR removes all three, leaving the interface layer a faithful projection of its contracts with no pass-through delegators and no `NON_PROJECTED_CLI` entries for `boot`/`doctor`.

## Context

Three independent cleanups share the same theme: a piece of interface-layer code was written before a later ADR made it redundant, and it was not pruned at the time.

### 1. `Write::Put`'s `cli_stdin: :json` is a dead declaration

ADR 0068 introduced `cli_stdin` as a declarative contract facet: the contract could declare `cli_stdin: :json` and the CLI projection would wire up stdin parsing automatically, dissolving the corresponding escape hatch. `Write::Put` adopted this facet.

ADR 0089 then changed the model: `put` stores bytes only, and `CLI::Verb::Put` owns its own stdin parsing — it reads, parses, and validates the JSON payload itself before passing the result to the use-case. The contract DSL declaration became **dead**: the verb already handles stdin before the projection machinery can act on `cli_stdin:`. Nothing breaks if the declaration remains, but it misleads a reader into thinking the contract DSL is the authority for `put`'s stdin — it is not.

### 2. `CLI::Verb::Boot` and `CLI::Verb::Doctor` are unnecessary hand-authored classes

ADR 0063 established that CLI verbs should be **generated from contracts**: `CLI::Runner` reads the `cli` + `cli_response` facets of each contract and emits a command automatically, with hand-authored subclasses reserved for verbs with behavioral complexity the DSL cannot express. ADR 0069 formalized this split as `BEHAVIORAL_HATCHES` (genuine escape hatches) vs `NON_PROJECTED_CLI` (verbs that *could* be generated but were not yet), and named `NON_PROJECTED_CLI` as a target for reduction.

`CLI::Verb::Boot` and `CLI::Verb::Doctor` are in `NON_PROJECTED_CLI`. Their `Read::Boot` and `Read::Doctor` contracts already carry the full `cli` + `cli_response` facets that the generator needs. Generating their CLI verbs from those contracts produces **byte-identical output** to the hand-authored classes. The hand-authored classes and their entries in `NON_PROJECTED_CLI` / `CLI::Runner`'s special-casing logic exist only because the cleanup was deferred — there is no behavioral justification for keeping them.

### 3. `MCP::Tools` is a pass-through delegator

`MCP::Tools` is a thin module that does nothing but forward every public method call to `MCP::Catalog`. It has exactly one caller. It exists as a seam from an earlier era when the tools and the catalog were expected to diverge; they did not diverge, and the seam never added value. The caller can be repointed to `MCP::Catalog` directly, and `MCP::Tools` can be deleted.

## Decision

### 1. Remove `cli_stdin: :json` from `Write::Put`'s contract

Delete the `cli_stdin: :json` line from the `Write::Put` contract declaration. `CLI::Verb::Put` continues to own stdin parsing exactly as before; no behavior changes. The contract DSL stops misrepresenting itself as the authority for `put`'s stdin.

### 2. Drop `CLI::Verb::Boot` and `CLI::Verb::Doctor`; remove them from `NON_PROJECTED_CLI`

Delete `CLI::Verb::Boot` and `CLI::Verb::Doctor`. Remove their entries from `NON_PROJECTED_CLI` in `CLI::Runner` (and any associated special-casing). The `CLI::Runner` generator already emits identical verbs from the `Read::Boot` and `Read::Doctor` contracts; after this change it does so unconditionally, with no guard list entry needed.

**Precondition:** verify the generated output is byte-identical to the hand-authored classes before deleting them.

### 3. Delete `MCP::Tools`; repoint its caller to `MCP::Catalog`

Update the one call site that references `MCP::Tools` to reference `MCP::Catalog` directly. Delete `MCP::Tools`. No behavior changes — every method that existed on `MCP::Tools` delegated unchanged to the same method on `MCP::Catalog`.

### No behavior change

All three changes are **pure deletions of dead or redundant code**:

- The verb surface (`boot`, `doctor`, `put`, and all other CLI/MCP verbs) is **unchanged**.
- The manifest grammar (`source:`, `publish:`, `kind:`, etc.) is **unchanged**.
- The MCP tool surface (tool names, input schemas, responses) is **unchanged**.
- No migration hint is needed — nothing user-observable changes.

## Consequences

- **`NON_PROJECTED_CLI` shrinks to its honest floor.** `boot` and `doctor` are gone from the list; only genuine behavioral escape hatches remain. The contract-projection model is the default for every verb without a behavioral reason to opt out.
- **The contract DSL regains a clean reading.** `Write::Put`'s contract no longer carries a declaration that conflicts with the verb's actual stdin-ownership behavior (ADR 0089). A reader of the contract sees only what the contract machinery actually acts on.
- **`MCP::Tools` pass-through is gone.** The MCP path has one fewer indirection layer; the catalog is the unambiguous authority.
- **No user-observable change.** Verb surface, manifest grammar, wire protocol, and MCP tool names are all frozen; this commit removes dead declarations, hand-authored duplicates, and a delegator — nothing more.

## Alternatives considered

- **Keep `CLI::Verb::Boot` and `CLI::Verb::Doctor` in `NON_PROJECTED_CLI` indefinitely.** Rejected: they are not behavioral escape hatches — they are deferred cleanups. Leaving deferred cleanups in a "to shrink" list indefinitely is the definition of a fossil. The byte-identical precondition makes the deletion safe.
- **Keep `cli_stdin: :json` as documentation.** Rejected: a declaration that the DSL no longer acts on is not documentation — it is misinformation. A comment in the verb or in this ADR is the right place for historical context, not a live contract facet.
- **Introduce a `MCP::Tools` interface for future use.** Rejected: speculative seams have a cost (reader confusion, maintenance surface) with no present benefit. If a genuine divergence between tools and catalog arises, it can be introduced then with a concrete motivation.
