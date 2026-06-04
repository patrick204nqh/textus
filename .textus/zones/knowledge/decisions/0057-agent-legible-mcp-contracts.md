# ADR 0057 — Agent-legible MCP contracts: arg descriptions, `_meta` wire parity, derived `write_verbs`

**Date:** 2026-06-02
**Status:** Accepted (ships 0.43.2)
**Refines:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP catalog is derived from per-verb contracts — the contract is now also where each *argument* is documented), [ADR 0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) (de-CLI'd `read_verbs`/recipes and named full `write_verbs` de-CLI-ing as a follow-up — this is that follow-up).
**Touches:** [ADR 0036](./0036-transports-as-pure-framings.md) (one vocabulary across transports — the read shape and the write shape must name the same concept identically), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (the MCP connection *is* the agent channel; its role is connection-resolved, so `--as`/`--stdin` have no meaning on it).

> **One sentence:** the MCP surface was structurally sound (derive-or-guard) but under-documented and internally inconsistent for an agent — nearly every tool argument shipped with no `description`, `put`/`propose` exposed frontmatter as `meta` while every *read* and the CLI `--stdin` envelope speak `_meta`, and `boot.agent_quickstart.write_verbs` still carried the CLI string `"put KEY --as=agent --stdin"` — so this ADR fills the per-arg descriptions, gives the contract a `wire_name` so `put`/`propose` expose `_meta` on the wire while keeping the `meta:` kwarg, and derives `write_verbs` from the catalog like `read_verbs`.

## Context

A senior-architect review of the agent-facing interface (MCP + CLI) found the *architecture* healthy — one vocabulary across CLI/Ruby/MCP (ADR 0036), the whole MCP catalog derived from per-verb contracts with a signature guard (ADR 0039), `boot`/`pulse` as a real stateful protocol with explicit re-boot signals. The gaps were all in the **legibility** layer an agent actually reads, and all fixable in the contracts without touching dispatch:

1. **Argument descriptions were 1-of-30 populated.** The `Contract::DSL` `arg` macro has supported `description:` since its introduction, and it rides the wire in every `tools/list` `inputSchema` — but only `pulse.since` and `propose.key` used it. The worst case is the most-used write tool: `put` advertised `{ key, meta, body, content, if_etag }` with **zero** descriptions, so an agent could not tell from the schema when to send `body` (string) vs `content` (object), that `if_etag` is an optimistic-concurrency guard, or the dotted-key convention.

2. **`meta` vs `_meta` — the read shape and the write shape disagreed.** `get` returns the envelope under `_meta` (`lib/textus/envelope.rb`), the canonical wire envelope is `{ _meta, body, ... }` (SPEC §8, §5.12), and the CLI `put --stdin` already reads `payload["_meta"]` (`lib/textus/cli/verb/put.rb`). But the **MCP** `put`/`propose` argument was named `meta`. An agent doing the natural round-trip — read an envelope, edit it, write it back under the field name it just saw — sent the wrong key. The inconsistency lived only on the MCP transport; the CLI was already correct.

3. **CLI strings still leaked into the MCP `boot` surface.** ADR 0056 derived `read_verbs` from the catalog and de-CLI'd the recipes, but explicitly deferred `write_verbs`, which still returned `["put KEY --as=#{role} --stdin"]`. `--as` (role is connection-resolved over MCP, ADR 0040) and `--stdin` (there is no stdin on a tool call) are meaningless to an MCP caller — the read side spoke verbs, the write side still spoke CLI.

Two further interface facts were invisible on the wire: `put`'s `body`/`content` mutual exclusivity (format-determined), and that the maintenance `dry_run` flag **defaults to `false`** — i.e. omitting it on `key_delete_prefix` *applies the delete*, the opposite of what the prose "dry-run returns a Plan" implies.

## Decision

Make the contract the single place an argument is documented and named-for-the-wire, and finish deriving the agent verb surface from the catalog.

1. **`wire_name` on `Contract::Arg`.** `arg` gains an optional `wire_name:`; `Arg#wire` returns `wire_name || name`. `Spec#input_schema` keys properties and `required` by `wire`, and `MCP::Catalog.map_args` matches incoming JSON by `wire` (and reports a missing required arg by its wire name) while still assigning the value to the use-case kwarg by `name`. This lets `put`/`propose` declare `arg :meta, Hash, required: true, wire_name: :_meta` — the wire speaks `_meta` (matching `get` and the CLI envelope), the use-case still receives `meta:`, and the ADR 0039 signature guard (which reconciles by kwarg `name`) keeps passing.
2. **Fill every argument description.** All MCP-surfaced verbs now carry a one-line `description:` per argument, including the `body`/`content` mutual-exclusivity note and the `dry_run` "default false applies immediately" note. These cost nothing per call — they ship once in `tools/list`.
3. **Derive `write_verbs`.** `MCP::Catalog.write_verbs` mirrors `read_verbs`: the MCP-surfaced verbs whose dispatcher class is under `Textus::Write::` (`put propose fetch fetch_all`). `boot.agent_quickstart.write_verbs` consumes it (empty when the connection has no proposer role). The `--as`/`--stdin` string is gone; `writable_zones`/`propose_zone` already carry the agent's write authority.
4. **Guard it (ADR 0037).** `spec/boot_quickstart_derive_or_guard_spec.rb` gains a `write_verbs` guard symmetric to the `read_verbs` one: every entry is in `MCP::Catalog.names` and is a bare verb token (no `--as`/`--stdin`). `spec/contract_spec.rb` pins `wire_name`; `spec/mcp/catalog_spec.rb` pins that `put` exposes `_meta` (not `meta`) and reports `_meta` on a missing-arg error.
5. **Docs.** `docs/reference/mcp.md` shows `_meta` in the `put`/`propose` arg rows and states the descriptions-ride-`tools/list`, `_meta`-matches-`get`, and `dry_run`-defaults-false facts.

## Consequences

- **An agent can write correctly on the first try from the schema alone.** `put`'s arguments now explain themselves; the frontmatter key it reads from `get` is the key it writes to `put`. The most common round-trip stops being a guessing game.
- **Wire change on `put`/`propose`: `meta` → `_meta`.** This is a breaking change for any MCP client that hardcoded the `meta` argument name. It is a deliberate correction — the old name disagreed with `get`, the CLI, and SPEC — and the cost is one key rename in client code. The Ruby API kwarg (`store.put(meta:)`) and the CLI `--stdin` envelope are unchanged.
- **The agent verb surface is fully catalog-derived.** Both `read_verbs` and `write_verbs` now come from `MCP::Catalog`; neither can drift, and the last CLI string is out of the MCP `boot` output (closing the ADR 0056 follow-up).
- **The dangerous `dry_run` default is now legible, not changed.** This ADR documents that omitting `dry_run` applies immediately; it does **not** flip the default. Flipping it (preview-by-default for destructive bulk ops) is a behavioral change with its own blast radius and is left as a separate decision.
- **`body`/`content` remains a soft constraint.** The mutual exclusivity is documented in both descriptions but not yet enforced as a JSON-Schema `oneOf`. Encoding it structurally would require the derived `input_schema` to emit `oneOf`/conditional schemas — deferred as disproportionate to the current risk; the description carries the rule.

## Alternatives considered

- **Rename the kwarg to `_meta` instead of adding `wire_name`** (or rename what `get` returns to `meta`). Rejected both directions: `_meta:` is an awkward Ruby kwarg (reads as "intentionally unused"), and renaming the read envelope key breaks every reader and contradicts SPEC §8. `wire_name` keeps the idiomatic kwarg, fixes only the wire, and is a small, reusable contract primitive.
- **Document descriptions in the how-to / reference prose only, leave the schema bare.** Rejected: the schema is what the agent's tool-use layer actually consumes; prose in a doc the agent may never load does not help it form a valid call. Descriptions belong on the wire.
- **Fold the `dry_run` default-flip into this change.** Rejected for scope and safety: changing apply-by-default to preview-by-default is a behavioral break for scripts and agents that rely on the current default; this ADR makes the existing behavior legible and leaves the policy question separate.
- **Emit `oneOf` for `body`/`content` now.** Rejected as disproportionate: it complicates the derived-schema path for a constraint two clear descriptions already convey; revisit if malformed both-fields writes show up in practice.
