# ADR 0060 — Close the agent safety asymmetry: graph-reads on MCP + default-dry-run on bulk-destructive verbs

**Date:** 2026-06-02
**Status:** Accepted (ships 0.44.0) · the default-dry-run half (decision §2) is **reversed by [ADR 0071](./0071-dry-run-is-opt-in.md)** — verbs apply by default again; the graph-reads-on-MCP half stands
**Refines:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP surface is derived from per-verb contracts — this ADR adds three read contracts and tightens four write defaults, no catalog code changes), [ADR 0036](./0036-transports-as-pure-framings.md) (one verb vocabulary; this only changes *which* verbs carry `:mcp` and a default value, not the vocabulary).
**Touches:** [ADR 0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) (`boot.read_verbs` is derived from the catalog, so surfacing `deps`/`rdeps`/`where` auto-advertises them — the guard spec moves with it), [ADR 0058](./0058-one-verb-name-across-surfaces.md) (shipped in the same 0.44.0 release).

> **One sentence:** the MCP agent had the destructive *teeth* (`key_delete_prefix`, `key_mv_prefix`, `zone_mv`, `migrate`) but not the introspection *eyes* to wield them safely (`deps`/`rdeps`/`where` were CLI-only) and its only guardrail was remembering to pass `dry_run: true` — so this ADR surfaces the three graph-reads to MCP **and** flips `dry_run` to default-**true** on the four bulk-destructive verbs, making "look before you leap" the default an agent must override, not a flag it must remember.

> **Amendment (2026-06-03, pre-merge, same 0.44.0 PR).** This ADR shipped the graph-reads-eyes + bulk dry-run-default half of the agent-safety fix but left two related gaps the same review had pre-registered (the single-key write capability gap was row 0060's own scope; the `deps`/`rdeps` shape note proved wrong once the wire shapes were aligned). The amendment completes both:
>
> - **(5) Single-key `delete` and `mv` gain `:mcp` contracts** — the precise, lower-blast-radius counterparts to the bulk `*_prefix` ops, so an agent that can delete a *whole prefix* can now also delete *one key*. The tool names are the canonical verbs `delete` and `mv` (the use-case methods, ADR 0039); the CLI's `key` grouping is organizational, not part of the name. **Safety scales with blast radius:** the bulk `*_prefix` ops default to a dry-run Plan (the (2) flip above); single-key `delete` *executes* but is guarded by an optional `if_etag` optimistic-concurrency check; single-key `mv` defaults `dry_run: false` (it applies immediately) but exposes an optional `dry_run`, and its arg description explicitly contrasts that default with the bulk default so an agent calling it is not surprised.
> - **(6) `deps`/`rdeps` now return a structured `{key, deps}` / `{key, rdeps}` hash on every surface.** This **supersedes this ADR's original statement** (decision §1) that "response shapes are unchanged (bare key array for deps/rdeps)": the shape now matches `where`/`put`/`delete`/`mv`, and the CLI dropped the hand-built wrapper it used to put around the bare array. One verb, one wire shape, all three transports.

## Context

A senior-architect review of the 0.43.2 surface found a capability/guardrail mismatch. MCP exposes the bulk-destructive maintenance verbs — an agent can `zone_mv` a whole zone or `key_delete_prefix` a subtree — but the reads that reveal blast radius (`deps`, `rdeps`, `where`) were CLI-only. So an agent could delete or relocate a prefix without being able to first ask *what depends on this* (`rdeps`) or *where does this resolve* (`where`). The single guardrail was the optional `dry_run: true` parameter, which the agent had to remember to pass and then eyeball the returned Plan. Destructive power was surfaced without the introspection that makes it safe, and the safe path was opt-in.

Two independent gaps, one risk:

1. **No eyes.** `deps` (a derived entry's sources), `rdeps` (what would be stranded if a key moved), and `where` (zone/owner/path without reading) had no contract at all — present in the dispatcher and on the CLI, but invisible to MCP.
2. **Unsafe default.** `zone_mv`, `key_mv_prefix`, `key_delete_prefix`, and `migrate` all defaulted `dry_run: false` — execute-first. An agent that omits the flag mutates immediately.

## Decision

1. **Give the agent eyes.** `Read::Deps`, `Read::Rdeps`, and `Read::Where` each gain a contract (`extend Contract::DSL`; `verb`/`summary`/`surfaces :cli, :ruby, :mcp`/`arg :key`). Because the catalog and `boot.read_verbs` derive from contracts (ADR 0039/0056), they become MCP tools and self-advertise — no catalog or boot code changes. Response shapes are unchanged (bare key array for deps/rdeps; `{zone, owner, path}` for where), so the existing CLI verbs and Ruby callers are untouched.

2. **Make dry-run the default on the four bulk-destructive verbs.** Flip the `#call` keyword default from `dry_run: false` to `dry_run: true` in `ZoneMv`, `KeyMvPrefix`, `KeyDeletePrefix`, and `Migrate`. The contract DSL has no wire-level default; the absent-arg default is the method signature, and MCP's `map_args` omits an absent optional arg — so an agent that calls `zone_mv(from:, to:)` now gets a **Plan**, and must pass `dry_run: false` to execute. The arg descriptions are rewritten to state the new default.

3. **The CLI keeps its explicit opt-in.** Every CLI verb already passes `dry_run: dry_run || false` (the `--dry-run` flag is opt-in by operator convention), so operator ergonomics are unchanged — and the operator already had the eyes (CLI `deps`/`rdeps`/`where`). The asymmetry being fixed is the *agent's*, and the default lands exactly where the agent's calls resolve it.

4. **Guard it (ADR 0039/0056).** `deps`/`rdeps`/`where` move out of `MCP_CATALOG_INTENTIONALLY_OMITTED`; `boot.read_verbs` and the derive-or-guard specs gain them; the MCP tool-list specs assert them.

## Consequences

- **An agent can now look before it leaps, and leaps only on purpose.** It can `rdeps` a key to see what a `zone_mv` would strand, and a forgotten `dry_run` returns a Plan instead of mutating. The guardrail is the contract default, not the agent's memory.
- **MCP gains three read tools** (`deps`, `rdeps`, `where`); the catalog grows from 15 to 18, derived not hand-maintained.
- **Behavioural change for programmatic Ruby callers** of the four bulk verbs that relied on the old `dry_run: false` default: they now dry-run unless they pass `dry_run: false`. This is deliberate (safe-by-default) and caught by the maintenance specs, which pass `dry_run` explicitly.
- **CLI behaviour is unchanged** — `--dry-run` stays opt-in.
- **(Amendment) The agent can now delete or move one key, not only a whole prefix.** `delete` and `mv` join the catalog as the single-key, lower-blast-radius counterparts to `key_delete_prefix`/`key_mv_prefix`; the safety story scales with blast radius — bulk plans-first, single-key `delete` executes under an optional `if_etag`, single-key `mv` applies immediately but offers an optional `dry_run`. The catalog grows from 18 to 20 tools (+`delete`, +`mv`).
- **(Amendment) The graph reads have one wire shape across surfaces.** `deps`/`rdeps` return `{key, deps}`/`{key, rdeps}` everywhere (superseding this ADR's original "bare key array" note), matching `where`/`put`/`delete`/`mv`; the CLI no longer hand-wraps the bare array.

## Alternatives considered

- **Eyes only (surface the reads, leave `dry_run` optional).** Rejected: it fixes introspection but leaves the unsafe execute-first default — an agent can still forget the flag. The default is the cheap, durable half of the fix.
- **A confirm-token gate (dry-run issues a plan hash; execution must echo it).** Rejected for this release: it adds protocol state and new failure modes (stale/absent token) for marginal gain over default-dry-run. Reconsider if default-dry-run proves insufficient.
- **Per-surface defaults (dry-run default on MCP only, execute default on Ruby).** Rejected: it would split one verb's behaviour by transport, violating "transports are pure framings" (ADR 0036). The method-signature default is the single source; the CLI's explicit pass-through is a pre-existing, visible choice, not a hidden divergence.
- **Fold into ADR 0058.** Rejected there (0058 was pure renames); pulled into the same 0.44.0 *release* but kept a separate, verifiable decision with its own ADR and specs.
