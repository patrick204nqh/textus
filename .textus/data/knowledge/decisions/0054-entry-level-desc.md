# ADR 0054 — Entry-level `desc`: the manifest as a navigable index

**Date:** 2026-06-02
**Status:** Proposed
**Refines:** [ADR 0034](./0034-unify-lane-vocabulary.md) (zone-level `desc` describes the *lane*; this extends one human-readable line down to the *entry*), [ADR 0037](./0037-boot-pulse-derive-or-guard.md) (the new field is authored manifest data surfaced verbatim — derived, not a mirror, so no drift to guard).
**Touches:** [ADR 0015](./0015-agent-gate-mcp.md) (`boot` is the agent's one-time orientation; this enriches its `entries[]`), [ADR 0036](./0036-transports-as-pure-framings.md) (the field surfaces identically through `boot` and `list` across CLI/Ruby/MCP).

> **One sentence:** A zone declares a `desc:` but an entry does not, so `boot.entries[]` and `list` hand an agent a list of *addresses with no labels* — it must infer relevance from key spelling or pay a `get` per candidate; this ADR adds an optional one-line entry `desc:`, surfaced verbatim in `boot` and `list`, turning the manifest from a routing table into a navigable index so an agent finds the right data without a caller hardcoding the key.

## Context

An agent that doesn't already know a key has exactly three signals to decide *"is this entry relevant to my task?"*:

1. the **key segments** — `knowledge.network.org.acme`
2. the **schema family name** — `person`, `runbook`
3. **reading the body** — a `get` per candidate, which it cannot afford across the whole store

`boot.entries_for` (`lib/textus/boot.rb:215`) emits `key / zone / schema / nested / owner / format / derived / intake / publish_to`. `list` (`lib/textus/read/list.rb`) returns `key / zone / path`. **Neither carries a sentence of what the entry is *for*.** Meanwhile zones already do: `zone_descs` (`lib/textus/manifest/data.rb:45`) is surfaced into `boot` at `lib/textus/boot.rb:209`, and `desc` is an allowed zone key (`lib/textus/manifest/schema.rb:6`) — but it is absent from the entry allowlist `ENTRY_KEYS` (`lib/textus/manifest/schema.rb:25`).

The consequence shows up at the integration seam. When a skill or agent wants "the right data," the path of least resistance today is to **hardcode the key** in the prompt (`read knowledge.network.oncall`). That is the brittle layer: a `zone mv` or a key rename silently breaks the caller, and the agent cannot adapt to a store it has never seen. The robust alternative — boot, then navigate — is starved of the one input that makes navigation cheap: a label per node.

This is the gap that makes key-injection *feel* mandatory. The topology is published; it just doesn't say what anything is.

**Why a label, not a richer mechanism.** The key namespace is *already a tree* — dotted, hierarchical, longest-prefix-resolved. What it lacks is not structure but **labels on the nodes**. A label is the smallest thing that closes the gap, and it composes with the read path that already exists (`boot` → `list --prefix` → `get`). Two larger options — render the tree as a *visualization*, or add a *search* verb — are deliberately out of scope here; see Alternatives and the roadmap row for ADR 0055.

## Decision

Add an optional, human-readable, single-line `desc:` to a manifest entry. Surface it verbatim in `boot.entries[]` and in `list` rows. **Additive and non-breaking** — an entry without `desc` behaves exactly as today.

1. **Allow the key.** Add `desc` to `Manifest::Schema::ENTRY_KEYS` (`lib/textus/manifest/schema.rb:25`). Validate it as an optional string with a **120-char ceiling** — a one-liner, not prose; a body is what `get` is for. A `desc` over the ceiling fails at load (consistent with how other entry-shape violations surface).
2. **Carry it on the entry.** Add a `desc` attribute to the entry value objects (the shared `Entry::Base`, inherited by `Leaf`/`Nested`/`Intake`), defaulting to `nil`.
3. **Surface it, derived.** `Boot.entries_for` (`lib/textus/boot.rb:215`) adds `"desc" => e.desc`; `Read::List` adds `desc` to each row. The field is the authored value passed straight through — **derive-or-guard (ADR 0037) is satisfied by derivation**, no reconciliation spec needed, because there is no second copy to drift from.
4. **Nested entries: the entry `desc` labels the *family*.** A nested entry's `desc` describes the collection (`"step-by-step runbooks: release, adr"`); it is not per-file. Per-file labels, if ever wanted, are a separate decision (they would live in each file's frontmatter, not the manifest) and are explicitly not introduced here.
5. **Dogfood it.** Populate `desc` on every entry in the repo's own `.textus/manifest.yaml` (ADR 0041) and in `examples/project` + the `textus init` scaffold, so the worked example demonstrates a labeled index. (Not enforced — see Consequences.)
6. **SPEC.md.** Per the `adr` runbook step 4, document `desc` in the entry-shape section of `SPEC.md` (the *what*); this ADR is the *why*.

`desc` is **descriptive, not semantic**: it is a label an agent (or human) reads, not a field anything branches on. Nothing in the resolver, guard, or fetch path reads it. This keeps it on the open-policy side of the topology/transition/policy split (ADR 0028) — pure orientation.

## Consequences

- **The manifest becomes a navigable index.** An agent reads ~N one-liners once in `boot` and picks by relevance, instead of `get`-ing candidates to discover what they hold. Semantic matching without a search index — the cheapest possible closing of the discovery gap.
- **The injectable layer collapses to one anchor.** A skill/agent now legitimately hardcodes *exactly one* thing — "call `boot` first; find your data by its `desc`/prefix" — and zero keys. Renaming a leaf no longer breaks a caller, because the caller never named the leaf. This is the property the integration UX was missing.
- **`desc` is unenforced by design.** An entry without one is valid; `doctor` may *warn* on a missing `desc` (a quality nudge, like a lint), but never fails. Forcing labels would be policy creep into a field whose only consumer is a reader's judgment.
- **It can rot.** A `desc` is authored text with no machine check that it still matches the body — the standard cost of any human label. The mitigation is social (review on `accept`), not mechanical; the field is cheap enough that a stale label is still better than no label.
- **120 chars is a hard ceiling**, chosen to force a *label*, not a summary — it keeps the `boot` index scannable and pushes anything longer into the body where `get` belongs. If a real store later proves it needs two lines, raising the ceiling is a one-constant change, not a redesign.
- **Search and visualization stay deferred, now on firmer ground.** With labels in place, the question "do we need `find`/search?" becomes empirical: it is needed only once the labeled index outgrows a single cheap read. Pre-registered as the ADR 0055 roadmap row.

## Alternatives considered

- **Do nothing; rely on key spelling + schema names.** The status quo. Works for a tiny store with disciplined keys, and it is why the gap went unnoticed in the dogfood store (a handful of entries). Rejected: it pushes every real integration toward hardcoding keys — the exact brittleness this codebase otherwise designs out (cf. ADR 0034 "zone = authority, not topic," ADR 0044 "no hardcoded role names"). A label is the consistent move.

- **Build a `find` / search verb instead** (full-text or tag-filter over `desc` + frontmatter). The "more capable" end state for discovery at scale. Rejected *as the first step*: it is a retrieval mechanism for when the index is too large to scan, and you cannot know whether you need it until labels exist and a store grows past one cheap read. `desc` is ~80% of the discovery value at ~5% of the cost, and it is the substrate a future search would index anyway. Recorded as the evidence-triggered follow-up (ADR 0055).

- **Render the context space as a tree/map** (ASCII or Mermaid, via a `map`/`tree` verb). Tempting because the namespace *is* a tree. Rejected as conflating two audiences: **an agent does not consume a rendered visualization — it consumes a structured, labeled text index**, which `boot.entries[] + desc` already is (the dotted keys supply the hierarchy, `desc` supplies the node labels). A rendered tree is a *human* DX affordance — useful for a maintainer auditing the store, not for the model. It is therefore separable, optional, and not on the agent's critical path; if built, it is a pure projection over the same `desc` data and belongs in its own small ADR, not bundled here.

- **Put the description in each file's frontmatter, not the manifest.** Co-locates the label with the content. Rejected for the index use case: `boot`/`list` would have to read every file to assemble the index — reintroducing the per-`get` cost this ADR removes. Frontmatter remains the right home for *per-file* description of a nested family (point 4); the manifest `desc` is the *entry/family* label, read in one shot.
