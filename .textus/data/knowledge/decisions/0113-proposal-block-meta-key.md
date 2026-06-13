# ADR 0113 — the proposal block speaks `_meta`, not `frontmatter`

**Date:** 2026-06-09
**Status:** Accepted
**Refines:** [ADR 0057](./0057-agent-legible-mcp-contracts.md) (gave `put`/`propose` a `wire_name` so the wire speaks `_meta` while the kwarg stays `meta:` — this finishes the job by fixing the one place the metadata concept still surfaces a third name).
**Touches:** [ADR 0002](./0002-textus-3-vocabulary-redesign.md) (`_meta` is the reserved metadata key — a proposal's payload metadata should carry the same reserved signal), [ADR 0035](./0035-proposal-target-zone-constraint.md) (proposals target canon; their payload shape is the thing this ADR names).

> **One sentence:** the `frontmatter` / `meta:` / `_meta` triad is *intentional and correct* — on-disk YAML is "frontmatter", the Ruby kwarg is `meta:`, and every wire/read surface speaks `_meta` (ADR 0057) — but there is exactly one leak: inside a proposal entry the proposed payload's metadata is nested under a literal `frontmatter:` key, so `accept` reads `env.meta["frontmatter"]` and `schema_valid` special-cases the same path, making "frontmatter" the *only* place the on-disk word appears as a runtime data key; this renames that key to **`_meta`** so a proposal carries the exact envelope shape it intends to write (`{ _meta, body }`), removing the special case.

## Context

A terminology audit confirmed the three names for entry metadata are a deliberate
per-layer split, not an accident:

| Layer | Name | Where |
| --- | --- | --- |
| On-disk / human prose | `frontmatter` | the YAML block between `---` fences |
| Ruby API (kwargs, internal) | `meta:` | `def call(key, meta:, body:)`, `arg :meta` |
| Wire / JSON / MCP / `get` envelope | `_meta` | every external surface (`Envelope#to_h_for_wire`) |

ADR 0057 made this explicit with the `wire_name: :_meta` primitive: `put`/`propose`
keep the `meta:` kwarg but expose `_meta` on the wire, matching every *read* and the
CLI `--stdin` envelope. ADR 0002 reserves `_meta` as *the* metadata key. This is good
design and is **not** what this ADR changes.

The one inconsistency is the **proposal block**. A proposal entry's frontmatter
(parsed into its `_meta`) carries two keys — `proposal:` (the directive: `target_key`,
`action`) and `frontmatter:` (the metadata to write at the target when accepted):

```yaml
---
proposal:
  target_key: working.network.org.bob
  action: put
frontmatter:          # ← the only runtime data key named "frontmatter"
  name: bob
  relationship: peer
---
Proposed body content.
```

So `accept` reads the payload as `env.meta["frontmatter"]`
(`lib/textus/write/accept.rb:35`) and `schema_valid` must special-case the same path
(`lib/textus/domain/policy/predicates/schema_valid.rb:33` — "for accept, the
frontmatter lives under `envelope.meta["frontmatter"]`; for a direct put it is
`envelope.meta`"). Everywhere *else* in the system, the metadata-of-an-entry concept
reads back as `_meta`. A proposal is, conceptually, *"the envelope I intend `accept`
to write"* — and an envelope's metadata is `_meta`. The block names it `frontmatter`,
the on-disk word, used nowhere else as a key.

## Decision

**Rename the proposal block's `frontmatter:` key to `_meta`.** A proposal entry then
carries, under its own `_meta`, exactly two keys: `proposal:` (the directive) and
`_meta:` (the metadata of the target write) — i.e. the proposed payload is the same
`{ _meta, body }` envelope shape that `get` returns and `put` consumes. `accept`
becomes a literal replay of that envelope.

```yaml
---
proposal:
  target_key: working.network.org.bob
  action: put
_meta:                # was: frontmatter:
  name: bob
  relationship: peer
---
Proposed body content.
```

Touch points:

- `lib/textus/write/accept.rb` — `env.meta["_meta"]` in the `put` branch.
- `lib/textus/domain/policy/predicates/schema_valid.rb` — the dual-path dig reads
  `meta.dig("_meta")` for the proposal case (still falls back to `meta` for a direct
  `put`), and its comment updates.
- `SPEC.md §5.5` — the proposal YAML example and the prose ("The remaining `_meta`
  and body are the proposed new content").
- `propose` arg description and any how-to / cookbook / `examples/` fixtures that show
  a proposal with the `frontmatter:` key.

This is **breaking** for any in-flight proposal authored with the old `frontmatter:`
key, but the blast radius is bounded: proposals live in the `queue` zone — they are
ephemeral, awaiting human review, not durable canon. There is **no shim** (the textus
house style for vocabulary renames — cf. ADR 0088/0111): an old-shaped proposal whose
`_meta` lacks the `_meta` key accepts with empty metadata, which `schema_valid` then
rejects if the target schema requires fields — a loud failure, not silent drift. A
held queue can be re-proposed.

## Consequences

- The proposal payload is now the wire envelope shape `{ _meta, body }` verbatim;
  `accept` replays it with no key translation. The `schema_valid` special case shrinks
  to "dig `_meta`, fall back to the whole meta hash."
- "frontmatter" is retired as a runtime data key — it survives only where it belongs:
  prose describing the on-disk YAML syntax. The three-layer model is now clean (no
  layer's name leaks into another's data).
- One-time break for in-flight proposals using the old key; documented in the
  CHANGELOG and SPEC §16. No durable data migration (queue entries are transient).

## Alternatives considered

- **Leave it (status quo).** Rejected as the open question this ADR exists to close —
  but a *defensible* rejection: the inconsistency is small, already documented, and
  touches only the proposal path. If the break is judged not worth the tidiness, this
  is the do-nothing option and the ADR is marked Rejected rather than Accepted.
- **Rename to `meta` (not `_meta`).** Rejected: `meta` is the *Ruby kwarg* name, an
  internal-layer word; a stored YAML key is wire/read-shape territory, which speaks
  `_meta` (ADR 0057) and is the reserved key (ADR 0002). Using `meta` would create the
  same cross-layer leak in the other direction.
- **Accept both keys (read `_meta` then fall back to `frontmatter`).** Rejected as the
  shim textus consistently declines for vocabulary renames — it preserves the old name
  forever in the read path, which is exactly the dual-vocabulary state ADR 0111 spent
  an ADR removing. The break is cheap here (transient queue), so pay it once.

`SPEC.md` **must** change — §5.5's proposal example and prose are part of the wire
contract for what a proposal entry looks like — and a §16 breaking-change note is
added. The ADR is the *why*; SPEC §5.5 is the *what*.
