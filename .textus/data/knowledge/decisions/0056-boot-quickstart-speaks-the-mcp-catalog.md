# ADR 0056 — `boot`'s agent surface speaks the MCP catalog, not a CLI dialect

**Date:** 2026-06-02
**Status:** Proposed
**Refines:** [ADR 0037](./0037-boot-pulse-derive-or-guard.md) (boot/pulse facts are derived-or-guarded — `read_verbs` was an unguarded hand-maintained mirror and had drifted), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP catalog is the one derived verb surface — `read_verbs` now derives from it too), [ADR 0036](./0036-transports-as-pure-framings.md) (recipes were CLI strings inside a transport-neutral surface).
**Touches:** [ADR 0015](./0015-agent-gate-mcp.md) (`boot` is the agent's orientation), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (the MCP connection *is* the agent channel — its advertised verbs must match what that channel exposes; `accept` stays human-only).

> **One sentence:** `boot.agent_quickstart.read_verbs` and `agent_protocol.recipes` were hand-maintained in CLI dialect and had drifted from the actual MCP catalog — advertising read verbs the agent cannot call over MCP (`audit`, `freshness`, `doctor`) while omitting ones it can and needs (`schema`, `rules`), and phrasing the schema-discovery step as a `textus schema …` shell line — so `read_verbs` now **derives** from the MCP catalog and recipe steps **reference verbs** instead of CLI strings, with a guard spec that fails the build on either kind of drift.

## Context

An agent connects over MCP. Its real, callable surface is the MCP catalog, which is fully derived from the per-verb contracts (`Textus::MCP::Catalog`, ADR 0039): `boot get list pulse rules schema` (read) plus `put propose fetch fetch_all` (write) and the maintenance verbs. `schema` and `rules` both `surfaces :ruby, :mcp` (`lib/textus/read/schema_envelope.rb:8`, `lib/textus/read/rules.rb`).

But two agent-facing facts in `boot` were authored by hand, in CLI dialect, and had silently drifted from that catalog:

1. **`agent_quickstart.read_verbs`** was the literal `%w[boot get list audit pulse freshness doctor]` (`lib/textus/boot.rb`). Against the catalog this is wrong in *both* directions:
   - `audit`, `freshness`, `doctor` are **not** MCP-surfaced — the agent is told to call verbs that aren't tools on its connection.
   - `schema` and `rules` — the two read verbs the write/propose flow depends on (field shape; freshness/guard policy) — are **absent**.
2. **`agent_protocol.recipes`** (surfaced to every transport) phrased every step as a shell command: `"textus schema get FAMILY"`, `"echo ENVELOPE | textus put KEY --as=ROLE --stdin"`. The only place `boot` mentioned schema discovery, it mentioned a CLI — and not even a verb the agent calls.

The downstream cost is concrete. A skill author wiring an MCP agent reads `boot` for orientation, sees schema discovery expressed as `textus schema …`, and copies a CLI shell-out into the skill — even though the agent could call the `schema` verb directly. That is exactly the contradiction reported against a consumer build (`envato-textus`): skill files reading schema via `envato-textus schema show` while the project's own `protocol.md` says "no CLI in skills." The skills faithfully copied what `boot` modelled. The root cause is upstream: **`boot` did not present `schema` as an MCP verb the agent can call.**

This is a derive-or-guard regression (ADR 0037): the rule is that every agent-facing fact in `boot`/`pulse` is derived live or guarded by a reconciliation spec. `read_verbs` was neither — a hand-kept list free to drift — and it did.

## Decision

`boot`'s agent-facing verb surface derives from the MCP catalog, and its recipes reference verbs rather than a transport's CLI syntax. A guard spec fails the build on drift.

1. **Derive `read_verbs`.** `MCP::Catalog.read_verbs` (`lib/textus/mcp/catalog.rb`) returns the MCP-surfaced verbs whose dispatcher class is under `Textus::Read::` — `get list pulse schema boot rules`. `agent_quickstart` consumes it. The CLI-only `audit`/`freshness`/`doctor` drop off; `schema`/`rules` appear. It can no longer drift, because there is no second copy.
2. **Recipes reference verbs.** Each recipe step names a verb (`get KEY`, `schema KEY`, `put KEY`, `propose KEY`, `fetch_all (zone: …)`) or is a plain build step (`assemble an envelope: { _meta, body }`) — never a `textus …` / `echo … | textus …` string. Each transport frames the verb itself (CLI renders `textus get KEY`; MCP calls the `get` tool). The schema step now reads *"schema KEY — learn the _meta field shape before writing,"* pointing at the verb.
3. **Guard it (ADR 0037).** `spec/boot_quickstart_derive_or_guard_spec.rb` asserts: every `read_verb` is in `MCP::Catalog.names`; `schema` and `rules` are present; the CLI-only trio is absent; and every verb referenced by an **agent-facing** recipe step (`steps`/`agent_steps`) is MCP-callable. `human_steps` are exempt — they are the human/CLI channel, where `accept` (the author-only trust-anchor transition, ADR 0035/0040) legitimately appears and is deliberately not an MCP tool.
4. **SPEC.md** (the *what*): the `agent_quickstart` example lists the derived `read_verbs`, with a note that an agent learns an entry's `_meta` shape via the `schema` verb before a `put`/`propose`, not via a CLI.

**Out of scope (named, not fixed):** `write_verbs` is still the CLI usage hint `"put KEY --as=#{role} --stdin"` (`--as`/`--stdin` are CLI-only; an MCP connection carries its role per ADR 0040 and passes JSON). Normalising it is entangled with role-capability resolution and earns its own decision; this ADR fixes the *read/discovery* surface, which is where the reported defect lives.

## Consequences

- **An MCP agent is told only what it can do.** `read_verbs` is exactly its callable read surface; the recipes name verbs, not shell lines. The CLI-only schema-discovery step that leaked into downstream skills is gone at the source — the gem stops modelling the mistake.
- **`schema` and `rules` are now discoverable from `boot` alone.** An agent orienting itself sees the verbs that make a first-try-valid `propose` possible, without inspecting `tools/list` separately or reading the how-to.
- **The drift cannot recur silently.** The guard fails the build if `read_verbs` ever advertises a non-MCP verb, drops `schema`/`rules`, or a recipe references an agent verb that isn't a tool.
- **Wire change, low blast radius.** `read_verbs` values change and recipe strings lose their `textus `/flag syntax; recipes remain illustrative prose (no shape change). The boot/pulse snapshot spec pins quickstart *keys*, not values, so it is unaffected; `docs/how-to/agents-mcp.md` already lists `schema`/`rules` as agent tools and needs no change. Consumers that *parsed* recipe strings as runnable commands (they were examples, never a contract) must read them as verb references.
- **CLI users are unaffected.** The full CLI verb set still ships in `boot.cli_verbs`; `read_verbs` was always the *agent* quickstart (ADR 0040), and aligning it to the agent's channel is the correction, not a removal of CLI capability.

## Alternatives considered

- **Just add the `schema` string to the existing `read_verbs` list.** The smallest patch. Rejected: it leaves `read_verbs` a hand-maintained mirror (still listing the non-MCP `audit`/`freshness`/`doctor`), leaves the recipes CLI-phrased (the ADR 0036 leak that actually produced the downstream bug), and lets the omission recur unguarded. It treats the symptom, not the derive-or-guard gap.
- **Keep `read_verbs` curated but add a reconciliation guard** (the `cli_verbs` pattern, ADR 0037). Defensible. Rejected here because, unlike `cli_verbs` (an editorial human-facing catalog), the agent read surface has no curation value to preserve — the derived set *is* the right set, and deriving is strictly simpler than curating-plus-guarding.
- **Declare schema-inspection human-only and have the agent template off an existing entry** (the consumer's "FIX B"). Rejected: it discards a capability the gem already ships over MCP, and the fallback is strictly degraded — no template exists for a brand-new family, and an existing entry hides which fields are *required* vs *optional* and their enum domains, which the `schema` envelope states outright.
- **Fully de-CLI `write_verbs` in the same change.** Rejected for scope: it is tangled with role-capability resolution (ADR 0040) and is not the reported defect; named above as a separate follow-up.
