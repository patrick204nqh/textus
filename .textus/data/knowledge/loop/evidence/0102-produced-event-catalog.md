# ADR 0102 — produce the event catalog from the registry

**Date:** 2026-06-08
**Status:** Proposed
**Refines:** [ADR 0098](./0098-docs-ssot-cleanup.md) (it named the two SSoT mechanisms — **produce** for derivable docs, **guard** for prose docs — and classified `events.md` as *guard*; this ADR proposes graduating the *derivable half* of `events.md`, the event catalog table, from guard to produce, the same path `verbs.md`/`schema.md` already took).
**Touches:** [ADR 0097](./0097-produced-reference-docs.md) (`docs/reference/verbs.md` and `schema.md` are produced via a `from: handler` registry introspection — this ADR mirrors that pattern for events), [ADR 0094](./0094-source-data-publish-render.md) (its "source produces data; publish renders" split and standardized hook-event names are the contract the produced catalog projects), [ADR 0089](./0089-ingest-is-system-pushed.md) / [ADR 0085](./0085-two-observability-verbs-remove-freshness.md) (the event *semantics* the catalog describes are unchanged).

> **One sentence:** `docs/reference/events.md` (and the README hook tables) are hand-authored prose whose **catalog table** merely restates `Textus::Hooks::Catalog` — ADR 0098's guard (extended in this PR to also catch *stale* events and to cover the README) now fails CI when they drift, but the tables are still hand-maintained, so this ADR proposes graduating the event catalog to a **produced** doc on the `verbs.md`/`schema.md` pattern: enrich `Hooks::Catalog` with a one-line description per event (kwargs are already there; mode is derivable), add an `events` registry handler that projects it to `artifacts.derived.events.json`, and render the catalog table from that data while the irreducible prose (per-verb lifecycle timelines, failure-mode table, `:resolve_handler` args, built-in parsers) stays static in the template — turning "add an event in code" into "`reconcile` updates the doc," with the guard kept as the safety net for the prose that can't be derived.

## Context

ADR 0097 graduated the reference docs with a machine source of truth — `verbs.md` and `schema.md` — from hand-authored canon to `kind: produced` entries that introspect the live registry (`source: { from: handler }`). ADR 0098 then named the split: **produce** (data → template) for derivable docs, **guard** (projection + CI assertion) for prose docs, and shipped a conformance guard asserting that `events.md`/`zones.md`/`mcp.md` *cover* their projections.

`events.md` was placed on the **guard** side — and most of it earns that. Roughly 90% of the file is irreducible prose: the per-verb **lifecycle timelines** (hand-drawn ASCII flow per verb), the **failure-mode** table, the **`:resolve_handler` args** reference, and the **built-in parsers** reference. None of that is mechanically derivable.

But its **catalog table** — *event · mode · payload kwargs* — is a faithful projection of `Textus::Hooks::Catalog::PUBSUB`/`RPC`. It is derivable, which makes it a **produce** candidate that was left as guard. Two facts explain why it wasn't already produced, and they define the work:

1. **The registry carries structure but not prose.** `verbs.md` produces cleanly because `Read::Capabilities` carries a `summary` per verb. `Hooks::Catalog` is just `event => [kwargs]` — the mode is derivable (PUBSUB vs RPC membership) and the kwargs are present, but there is **no "what it's for" description** in code. A naive "generate `events.md` from the catalog" would *drop* every description and all the surrounding prose — a regression, not a refresh.
2. **The doc is mixed.** A produced `events.md` must keep the timelines/failure-modes/parsers prose. That is expressible — a template whose static body holds the prose and whose loops render only the derivable tables — but it is real work, not a one-file add.

The interim already shipped: this PR extended ADR 0098's guard so it also fails on a **stale** event (one removed from the catalog but still cited in a doc table) and now covers the **README** hook tables, not just `events.md`. That holds the line — code and docs cannot silently diverge — but a human still edits the catalog table by hand. This ADR proposes removing that hand-maintenance for the derivable part.

## Decision (proposed)

1. **Enrich `Hooks::Catalog` with per-event metadata.** Add a one-line `description` per event (mode is derived from PUBSUB/RPC membership; kwargs already exist). Because the comment on `Catalog` is explicit that **EventBus, RpcRegistry, and the Loader router read its tables directly**, the enrichment must be *additive*: keep `PUBSUB`/`RPC` returning their kwargs lists (or expose a kwargs-only view the registries call) and carry descriptions in a sibling table, so no bus reader changes behavior. The catalog stays the single source of truth — now for the event's *purpose* as well as its shape.
2. **Add an `events` registry handler** (`reg.on(:resolve_handler, :events)`, mirroring `.textus/hooks/verb_registry_handler.rb`) that projects `Hooks::Catalog` → `artifacts.derived.events.json`: each row `{ name, mode, payload: [kwargs], description }`.
3. **Render `events.md` from that data.** A produced entry `artifacts.derived.events` with `source: { from: handler, handler: events }` and `publish: { to: docs/reference/events.md, template: events.mustache }`. The template's **static body** holds the timelines, failure-mode prose, `:resolve_handler` args, and parser tables; a `{{#events}}…{{/events}}` loop renders the catalog table. (The failure-mode table — a uniform per-event row — may also become a loop; the ASCII timelines stay static text.)
4. **Retire the hand-authored source.** Delete `.textus/zones/knowledge/reference/events.md` and add `**/events.md` to the `knowledge.reference` entry's `ignore:` list (joining `verbs.md`/`schema.md`/`adr-log.md`), so the canon tree-publish defers to the produced entry. Add the `artifacts.derived.events` ⇄ `events` handler-allowlist rule.
5. **README defers, doesn't duplicate.** The README keeps a short *illustrative* hook example plus a link to the produced `events.md`; it stops restating the full catalog. The drift guard remains the safety net for the README's illustrative subset and for the parts of `events.md` that stay prose.

## Consequences

- **"Add or rename an event in code → `reconcile` updates `events.md`."** The catalog table and its descriptions are produced from the registry, so they cannot drift from behavior — the produce guarantee, stronger than the guard's "CI tells you it drifted."
- **The description becomes code.** Putting the one-liner in `Hooks::Catalog` makes the registry the SSoT for *why each event fires*, not just its kwargs — useful beyond the doc (e.g. `pulse`/MCP introspection could surface it later).
- **The README's duplication — the thing that actually drifted — goes away.** It links to the produced doc instead of restating the catalog.
- **Cost is front-loaded and bounded.** The `Catalog` reshape touches three readers; keeping a kwargs-only view confines it to additive change. Porting ~250 lines of prose into `events.mustache` is one-time work; Mustache's limits (depth 8, no partials, no HTML escaping) only have to pass *static* prose through untouched, which is safe.
- **Until this lands, the guard holds.** This ADR is **Proposed**: ADR 0098's guard (as extended in this PR) is the accepted interim. Implementation is a scheduled follow-on, best as its own PR led by the `Hooks::Catalog` enrichment.

## Alternatives considered

- **Stay on the guard (status quo, Option A).** Keep `events.md` hand-authored, rely on the CI drift guard. Accepted as the *interim*, rejected as the *end state*: the guard catches divergence but still makes a human re-type the derivable table on every event change. Produce removes that for the part that is mechanically derivable.
- **Generate `events.md` wholesale from the catalog as it is today.** Rejected: `Hooks::Catalog` has no descriptions and the doc is 90% prose, so this would regress `events.md` to a bare name/kwargs table — losing the timelines, failure modes, parser docs, and every "what it's for" line.
- **Projectify the whole README too.** Rejected (out of scope, and likely permanently): the README is overwhelmingly bespoke narrative (mermaid, the trust-quadrant ASCII, prose); templating badges and diagrams through Mustache is fragile for no benefit. The README should *defer* to the produced `events.md`, not become a projection itself.
