# ADR 0098 — Docs SSoT/DRY/SOLID cleanup: produce vs guard, single-sourced status

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0097](./0097-produced-reference-docs.md) (it introduced produced reference docs; this ADR cleans up the SSoT/DRY/SOLID debt that review surfaced — a duplicate ADR index, a layering slip in the reducer, a coupling slip in the verb producer — and names the second SSoT mechanism the produced-only framing was missing).
**Touches:** [ADR 0094](./0094-source-data-publish-render.md) (its "source produces data; publish renders" split is the rule the reducer fix restores), [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (the curated decisions log stays a keyless tree mirror), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) / [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (`Read::Capabilities` is the contract projection the verb producer now depends on).

> **One sentence:** a senior-architect review of ADR 0097 through SSoT/DRY/SOLID found four issues — a **duplicated ADR index** (the curated `decisions/README.md` and the produced `adr-log.md` both carried Status), a **layering slip** (the ADR reducer did markdown-table pipe-escaping — rendering — in the data producer), a **coupling slip** (the verb producer hand-navigated `Dispatcher::VERBS[...].contract` internals instead of the blessed `Read::Capabilities` projection), and **un-guarded prose docs** (`events`/`zones`/`mcp` hand-mirror machine truth) — so this ADR single-sources ADR status to a mechanical `adr-log.md` board (the curated README becomes a Status-free reading guide), moves the reducer's link-flattening to honest data-normalization while deleting its dead pipe-escape, repoints the verb producer onto `Read::Capabilities`, and adds **drift guards** asserting the prose docs cover their projections — establishing that textus has **two** SSoT mechanisms (produce, and guard), and prose uses guard.

## Context

ADR 0097 shipped produced reference docs (`verbs.md`, `schema.md`, `adr-log.md`). A review of that work against SSoT / DRY / SOLID found the coverage was total but the *single-sourcing* was not, and 0097 had introduced one fresh violation:

1. **Two ADR indexes (SSoT/DRY).** `docs/architecture/decisions/README.md` (curated, hand-maintained) and the new `docs/reference/adr-log.md` (produced) both listed every ADR with a Status column. Status now lived in three places — each ADR file's `**Status:**` line (the truth), `adr-log.md` (derived, correct), and the curated README (a hand-copy that drifts). Same header, even, while the "Decision" column meant different things in each.
2. **Reducer did rendering (SRP / ADR 0094).** `adr_index_reducer` escaped `|` for the markdown table — a render-target concern — inside the data producer, against ADR 0094's "source produces data; publish renders." (It was also dead: no ADR `**Status:**` line contains a literal pipe.)
3. **Verb producer coupled to internals (DIP).** The handler reached into `Textus::Dispatcher::VERBS[name].contract.summary` though `Read::Capabilities` already exists as the blessed contract projection (built so "integrators assert their docs against this in CI so they can't drift").
4. **Prose docs un-guarded (SSoT).** `events.md` / `zones.md` / `mcp.md` are narrative reference docs that cite machine facts (`Hooks::Catalog`, the manifest zones, `MCP::ToolSchemas`) with nothing stopping them from drifting.

The framing gap underneath all four: 0097 treated "produced" as the only SSoT mechanism. But prose can't be produced (no deterministic source; an LLM would break byte-stable idempotence and the CI no-op gate). The missing idea is a **second mechanism**.

## Decision

1. **Two SSoT mechanisms, named.** textus keeps machine facts single-sourced two ways:
   - **Produce** — generate the doc from data (`source` → template). For fully-derivable docs: `verbs.md`, `schema.md`, `adr-log.md`.
   - **Guard** — hand-author the doc, and assert in CI that its cited facts cover a machine projection. For prose docs that embed facts: `events.md`, `zones.md`, `mcp.md`.

2. **Single-source ADR status to a mechanical board.** `adr-log.md` becomes the canonical status board (`# | Title | Date | Status`, plus a static status legend), Status derived from each ADR file. The curated `decisions/README.md` **drops its Status column and legend**, becoming a pure annotated reading guide (`# | Decision`) that points at the board. Status now has one authored source (the ADR file) and one derived surface (the board) — no hand-copy.

3. **Reducer normalizes data, does not render.** `adr_index_reducer` flattens markdown links to label text (location-independent *data* normalization, legitimate because textus's pipeline is data + logicless mustache with no render-logic layer) and **drops the dead, render-target-specific pipe-escape**.

4. **Verb producer depends on the projection, not internals.** `verb_registry_handler` sources `Textus::Read::Capabilities` — the same contract projection CLI/MCP/boot derive from — instead of navigating `Dispatcher::VERBS` internals. This also enriches `verbs.md` (the full cross-surface contract set with real arg schemas).

5. **Guard the prose docs.** A conformance spec asserts every `Hooks::Catalog` event appears in `events.md`, every manifest zone in `zones.md`, and every `MCP::ToolSchemas` tool in `mcp.md`. (On landing it immediately caught real drift: `mcp.md` was missing `accept`/`reject`/`capabilities` and still listed the removed `migrate` — fixed.)

6. **No `SPEC.md` change.** Repo-local materialization and test-only guards; no wire-contract change.

## Consequences

- **One ADR status source.** Adding/superseding an ADR updates its file; the board re-derives; the curated guide never needs a status edit again.
- **The layering rule holds end-to-end** — the only Ruby in the produce path (the reducer) now produces data only.
- **The verb docs can't drift from the contract** — they ride the same projection as the live surfaces, and got richer for free.
- **Prose docs are drift-proof without being generated** — the guard fails CI when a doc omits a current event/zone/tool, which already caught a real `mcp.md` gap.
- **The mental model is complete** — "produce where derivable, guard where prose" replaces "produce everything," which was never achievable.

## Alternatives considered

- **Produce `events`/`zones`/`mcp`.** Rejected — they are prose (intros, transport explanations, wiring guides) with embedded fact tables; producing them would delete the narrative. Guarding the facts keeps the prose and kills the drift.
- **Keep both ADR indexes + a status-sync guard.** Rejected — it leaves two Status representations (DRY still bent); single-sourcing to the board is cleaner.
- **Add a real render-logic layer so the reducer can stay pure of the pipe-escape.** Rejected as YAGNI — link-flattening is honest data normalization, and the pipe-escape was dead; no new layer is warranted.
- **Leave the verb producer on `Dispatcher` internals.** Rejected — `Read::Capabilities` exists precisely to be the stable seam; depending on it is the DIP-correct choice and removes a silent-break hazard for the dogfood hook.
