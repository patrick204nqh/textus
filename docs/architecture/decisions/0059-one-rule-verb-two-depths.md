# ADR 0059 — One rule verb, two depths: merge `rules` + `policy_explain` into `rule_explain`

**Date:** 2026-06-02
**Status:** Accepted (ships 0.44.0)
**Refines:** [ADR 0058](./0058-one-verb-name-across-surfaces.md) (one name per verb across surfaces — this removes the last for-key rule-introspection name mismatch: MCP `rules` vs CLI `rule explain`), [ADR 0031](./0031-unified-guard.md) (the verbose explanation becomes the `detail: true` depth of one verb rather than a separate use-case).
**Touches:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the merged verb carries the `:mcp` surface; the old `rules` tool disappears and `rule_explain` appears, derived).

> **One sentence:** for-key rule introspection lived under two names on two transports — the lean `rules` (`{fetch, guard}`, MCP+Ruby) and the verbose `policy_explain` (matched blocks + per-transition guard predicates, CLI `rule explain`) — and a code review showed they are **not** redundant but an *audience split* (agent-cheap vs human-debug), so this ADR unifies them into a single verb `rule_explain` that is **lean by default and verbose under `detail: true`**, keeping both response shapes while collapsing the names.

## Context

ADR 0058's review flagged the `rule` family as overlapping under three names and pre-registered a consolidation. Reading the code before merging corrected the premise:

- **`Read::Rules`** (verb `rules`, `surfaces :ruby, :mcp`) returns the lean effective winners: `{ fetch, guard }`. Cheap; agent-shaped.
- **`Read::PolicyExplain`** (no contract; CLI `rule explain` only) returns the verbose explanation: `{ key, matched_blocks[], effective{...}, guards{...} }` — which blocks matched and the effective guard *predicate names* per transition. Human-debugger-shaped.

These are **not** a subset relationship — they serve different audiences. A naive "collapse to one shape" would degrade one of them: forcing the verbose shape onto MCP makes the agent pay a large token cost for what was a two-field answer; forcing the lean shape onto the CLI loses the whole point of `explain`. The real defects were narrower: (a) the same concept wore two names across two transports (the ADR 0058 smell, one layer down), and (b) `rule list` computed its rows inline in the CLI verb with no use-case.

A latent bug surfaced while merging: `Read::Rules` did `set.fetch&.to_h`, but `Domain::Policy::Fetch` has no `to_h` — it only ever worked because its single spec used a key with no fetch rule (nil). Any key *with* a fetch rule would have raised.

## Decision

1. **One verb, two depths.** Introduce `Read::RuleExplain` (`verb :rule_explain`, `surfaces :cli, :ruby, :mcp`) with `call(key, detail: false)`:
   - **lean (default)** — `{ fetch, guard }`, the agent-cheap effective read (was `rules`), now with `fetch` built explicitly (`ttl_seconds`, `on_stale`, `sync_budget_ms`, `fetch_timeout_seconds`) instead of the broken `to_h`;
   - **verbose (`detail: true`)** — the matched-blocks + per-transition guard-predicate explanation (was `policy_explain`, ADR 0031).
2. **Delete the two old use-cases.** Remove `Read::Rules` and `Read::PolicyExplain`; drop their `Dispatcher::VERBS` entries; add `rule_explain`. `RoleScope` metaprograms the method from the key, so `store.as(role).rule_explain(key, detail:)` exists by construction.
3. **Back `rule list` with a use-case.** Extract the inline manifest walk into `Read::RuleList` (CLI-only, no MCP contract — an agent reasons per-key via `rule_explain`); the CLI verb becomes thin. Its output `verb` label is `rule_list` (was `policy_list`); `rule explain` emits `rule_explain` (was `policy_explain`).
4. **CLI `rule explain` gains `--detail`.** Lean by default; `rule explain KEY --detail` for the verbose view.
5. **Guard it.** The reconciliation omit-list drops `policy_explain`; the catalog/boot read-verb specs swap `rules` → `rule_explain`; the merged spec covers both depths.

## Consequences

- **One name per operation, both audiences preserved.** The thing an agent calls `rule_explain` is the thing a human types as `rule explain`; the agent keeps its cheap default; the human gets the full explanation with `--detail`/`detail: true`.
- **The latent `to_h` bug is fixed** — the lean read now works for keys that actually have a fetch rule.
- **Breaking, no shims:** the MCP tool `rules` is gone (use `rule_explain`); the CLI output `verb` labels change (`policy_explain`→`rule_explain`, `policy_list`→`rule_list`). Pre-1.0, consistent with house style (ADR 0058).
- **`boot.read_verbs` changes** (`rules`→`rule_explain`); derived, so automatic and guarded.

## Alternatives considered

- **Don't merge — the two are complementary, fix names only.** Tenable, and the most honest read of "not redundant." Rejected because the `detail:` parameter preserves both shapes *and* collapses the names — strictly better than carrying two verbs whose only real difference is depth.
- **Collapse to the verbose shape on both surfaces (the original 0058 framing).** Rejected: imposes verbose token cost on every agent rule-read and deletes the lean canonical read.
- **Collapse to the lean shape.** Rejected: destroys the `explain` capability (matched blocks, guard predicates) the human path depends on.
- **Surface `rule_list` to MCP too.** Rejected: it is a whole-manifest enumeration; the agent's rule reasoning is per-key via `rule_explain`. Kept CLI-only and listed in the omit-list with that reason.
