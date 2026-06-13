# ADR 0112 — the authority model is a produced reference doc

**Date:** 2026-06-09
**Status:** Accepted
**Extends:** [ADR 0097](./0097-produced-reference-docs.md) (produced reference docs: `verbs.md`/`schema.md`/`adr-log.md`), [ADR 0102](./0102-produced-event-catalog.md) (graduated the event catalog to a produced doc on that pattern). **Touches** [ADR 0098](./0098-docs-ssot-cleanup.md) (SSoT: produce vs guard) and [ADR 0091](./0091-fold-machine-zone.md) (the `LANES` bijection this projects).

> **One sentence:** the zone-kind↔capability bijection, the manifest's roles, and its zones — the "who may write what" tables — stop being hand-copied across `zones.md`/`concepts.md`/`docs-readme.md` and become a fourth **produced** reference doc, `docs/reference/authority.md`, projected on every `drain` from `Schema::Vocabulary::LANES` + the live manifest; the canon docs keep the *meaning* and link to the generated *values*.

## Context

A content audit of the `knowledge` zone found the authority model's structured
facts restated as hand-maintained tables in several canon docs. The
zone-kind↔capability bijection (`canon→author`, `workspace→keep`,
`machine→converge`, `queue→propose`), the role→`can` sets, and the
who-writes-which-kind matrix appeared in `reference/zones.md` (three tables),
were re-pointed-to from `explanation/concepts.md`, and were summarized in
`docs-readme.md`'s conventions.

These copies were in sync, but every copy is a future drift site — and the facts
are not prose. The bijection is a frozen code constant
(`Manifest::Schema::Vocabulary::LANES`); the roles and zones are declared in the
manifest. The repo already has the blessed mechanism for exactly this: ADR 0097
made `verbs.md`/`schema.md`/`adr-log.md` `kind: produced` entries projected from
the source of truth, and ADR 0102 extended the pattern to the event catalog
(table produced, irreducible prose guarded).

The role/capability model already self-declared its SSoT as `zones.md` (per the
`docs-readme.md` conventions), so most docs *linked* rather than re-tabulated.
But `zones.md` itself still hand-maintained the tables — making the SSoT a
retyped copy of code + manifest, not a projection.

## Decision

**(a) Add a fourth produced reference doc, `docs/reference/authority.md`.** A
new `artifacts.derived.authority` entry (`kind: produced`, `from: handler`)
publishes through `authority.mustache`, exactly like the verbs/schema/events
entries. A `intake_handler_allowlist: [authority]` rule guards it; the existing
`GeneratorDrift` doctor check flags a stale copy and `HandlerAllowlist` enforces
the write-guard — no new doctor check.

**(b) The `authority` handler projects three tables from the live truth, never
retyped:**
- **lanes** — the zone-kind↔capability bijection, verbatim from
  `Schema::Vocabulary::LANES`;
- **zones** — this manifest's declared zones (name, kind, derived capability via
  `LANES`, `desc`);
- **roles** — this manifest's declared roles (name, `can` set, and the
  zone-kinds each role's caps authorize — the inverse of `LANES`).

**(c) Split the SSoT along the produce/guard seam (ADR 0098).** The
*current-values* tables are owned by the generated `authority.md`; what each
capability *means* (and the accept/reject predicate semantics) stays prose in
`zones.md`. `zones.md` drops its three structured tables, keeps the editorial
descriptions, and links to `authority.md` for the values; `concepts.md` and
`docs-readme.md` re-point accordingly. The orientation template (→ `CLAUDE.md`/
`AGENTS.md`) now names four generated reference docs.

## Consequences

- The authority model is made from the bijection constant + the manifest, not
  retyped — it cannot drift, and a hand-edit to `authority.md` is clobbered on
  the next `drain` and flagged by `doctor`.
- A reader wanting "who may write what, right now" reads one generated table;
  a reader wanting "what does `converge` mean" reads `zones.md`. The two no
  longer duplicate each other.
- `authority.md` reflects *this* repo's manifest (the dogfood store), like
  `schema.md` — it is a projection of the live store, not a framework-default
  table.
- Deliberately **not** projecting `Capabilities::DEFAULT_MAPPING` as a separate
  framework-default table (the live manifest roles are the truth readers want),
  and **not** collapsing the intentional Diátaxis prose layering — only the
  structured tables were the DRY target.

No `SPEC.md` change — this is a docs-projection addition, not a protocol change.
