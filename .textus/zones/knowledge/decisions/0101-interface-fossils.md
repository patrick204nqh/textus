# ADR 0101 — interface-layer fossils

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (it established that CLI verbs are generated from contracts and that hand-authored escape hatches are the exception, not the norm — the hand-authored `CLI::Verb::Boot` and `CLI::Verb::Doctor` classes are exactly the exception this ADR retires), [ADR 0069](./0069-single-path-lifecycle.md) (it named the two categories of non-projected verbs — `BEHAVIORAL_HATCHES` and `NON_PROJECTED_CLI` — and noted that `NON_PROJECTED_CLI` should shrink toward zero as the projection machinery matures; this ADR removes `boot` and `doctor` from that list).
**Touches:** [ADR 0089](./0089-ingest-is-system-pushed.md) (it established that `put` stores bytes only and that `CLI::Verb::Put` owns its own stdin parsing — this ADR audits that boundary, confirms `put`'s contract carries no redundant `cli_stdin` declaration, and pins the verb-owned stdin path with a conformance test; nothing changes), [ADR 0068](./0068-declarative-facets-dissolve-escape-hatches.md) (it introduced `cli_stdin` as a declarative contract facet — the facet and its projection logic are unchanged; it remains in use by `Write::Propose`).

> **One sentence:** the interface layer (CLI verbs, MCP tools) carries two small fossils — hand-authored `CLI::Verb::Boot` and `CLI::Verb::Doctor` classes that special-case verbs the projection machinery can already generate byte-for-byte, and a thin `MCP::Tools` delegator that does nothing but forward every call to `MCP::Catalog` — so this ADR removes both, leaving the interface layer a faithful projection of its contracts with no pass-through delegators and no `NON_PROJECTED_CLI` entries for `boot`/`doctor`; an audit of a third suspected fossil (`put`'s stdin handling) found it already clean and pins it with a conformance test instead.

## Context

Two independent cleanups share the same theme: a piece of interface-layer code was written before a later ADR made it redundant, and it was not pruned at the time. A third suspected fossil turned out not to exist.

### 1. `CLI::Verb::Boot` and `CLI::Verb::Doctor` are unnecessary hand-authored classes

ADR 0063 established that CLI verbs should be **generated from contracts**: `CLI::Runner` reads the `cli` + `cli_response` facets of each contract and emits a command automatically, with hand-authored subclasses reserved for verbs with behavioral complexity the DSL cannot express. ADR 0069 formalized this split as `BEHAVIORAL_HATCHES` (genuine escape hatches) vs `NON_PROJECTED_CLI` (verbs that *could* be generated but were not yet), and named `NON_PROJECTED_CLI` as a target for reduction.

`CLI::Verb::Boot` and `CLI::Verb::Doctor` are in `NON_PROJECTED_CLI`. Their `Read::Boot` and `Read::Doctor` contracts already carry the full `cli` + `cli_response` facets that the generator needs. Generating their CLI verbs from those contracts produces **byte-identical output** to the hand-authored classes. The hand-authored classes and their entries in `NON_PROJECTED_CLI` / `CLI::Runner`'s special-casing logic exist only because the cleanup was deferred — there is no behavioral justification for keeping them.

### 2. `MCP::Tools` is a pass-through delegator

`MCP::Tools` is a thin module that does nothing but forward every public method call to `MCP::Catalog`. It has exactly one caller. It exists as a seam from an earlier era when the tools and the catalog were expected to diverge; they did not diverge, and the seam never added value. The caller can be repointed to `MCP::Catalog` directly, and `MCP::Tools` can be deleted.

### 3. `put`'s stdin handling — audited, already clean

ADR 0089 established that `put` stores bytes only and that `CLI::Verb::Put` owns its own stdin parsing — it reads, parses, and validates the JSON payload itself (`JSON.parse(@stdin.read)`) before calling the use-case. This ADR set out to remove a suspected leftover `cli_stdin: :json` declaration on `Write::Put`'s contract.

That declaration does not exist. `Write::Put`'s contract declares no `cli_stdin` facet; the facet is declared on `Write::Propose`, where it is correct and still in use. `CLI::Verb::Put` is a hand-authored verb that has always owned its stdin parse and never routed through the generated `cli_stdin` path. There is no fossil to remove — `put` already conforms to the 0089 boundary. The only gap was the absence of a regression guard, which this ADR adds.

## Decision

### 1. Drop `CLI::Verb::Boot` and `CLI::Verb::Doctor`; remove them from `NON_PROJECTED_CLI`

Delete `CLI::Verb::Boot` and `CLI::Verb::Doctor`. Remove their entries from `NON_PROJECTED_CLI` in `CLI::Runner` (and any associated special-casing). The `CLI::Runner` generator already emits identical verbs from the `Read::Boot` and `Read::Doctor` contracts; after this change it does so unconditionally, with no guard list entry needed.

**Precondition:** verify the generated output is byte-identical to the hand-authored classes before deleting them. If it is not byte-identical, keep the verb and record why instead of shipping a behavior change.

### 2. Delete `MCP::Tools`; repoint its caller to `MCP::Catalog`

Update the one call site that references `MCP::Tools` to reference `MCP::Catalog` directly. Delete `MCP::Tools`. No behavior changes — every method that existed on `MCP::Tools` delegated unchanged to the same method on `MCP::Catalog`.

### 3. Pin `put`'s verb-owned stdin path with a conformance test

No code change to `put`. Add a conformance example asserting that piping a JSON envelope to `textus put KEY --stdin` stores the body and returns `{uid, etag}` — locking in the 0089 verb-owned-stdin behavior the audit confirmed.

### No behavior change

All changes are **pure deletions of dead or redundant code, plus one regression test**:

- The verb surface (`boot`, `doctor`, `put`, and all other CLI/MCP verbs) is **unchanged**.
- The manifest grammar (`source:`, `publish:`, `kind:`, etc.) is **unchanged**.
- The MCP tool surface (tool names, input schemas, responses) is **unchanged**.
- No migration hint is needed — nothing user-observable changes.

## Consequences

- **`NON_PROJECTED_CLI` shrinks to its honest floor.** `boot` and `doctor` are gone from the list; only genuine behavioral escape hatches remain. The contract-projection model is the default for every verb without a behavioral reason to opt out.
- **`MCP::Tools` pass-through is gone.** The MCP path has one fewer indirection layer; the catalog is the unambiguous authority.
- **`put`'s stdin contract is pinned.** A conformance test now guards the 0089 boundary, so a future refactor cannot silently break the verb-owned stdin path.
- **No user-observable change.** Verb surface, manifest grammar, wire protocol, and MCP tool names are all frozen; this work removes hand-authored duplicates and a delegator, and adds one test — nothing more.

## Alternatives considered

- **Keep `CLI::Verb::Boot` and `CLI::Verb::Doctor` in `NON_PROJECTED_CLI` indefinitely.** Rejected: they are not behavioral escape hatches — they are deferred cleanups. Leaving deferred cleanups in a "to shrink" list indefinitely is the definition of a fossil. The byte-identical precondition makes the deletion safe.
- **Introduce a `MCP::Tools` interface for future use.** Rejected: speculative seams have a cost (reader confusion, maintenance surface) with no present benefit. If a genuine divergence between tools and catalog arises, it can be introduced then with a concrete motivation.
- **Convert `CLI::Verb::Put` to a projected verb via `cli_stdin: :json`.** Rejected (out of scope): the hand-authored `put` verb carries v1-specific behavior (`--stdin` required, `--as=ROLE` role resolution) that is deliberately verb-owned per ADR 0089. Routing it through the declarative facet would be a behavior-bearing change, not a fossil removal.
