# ADR 0109 — board-exact schema split + single port shape

**Date:** 2026-06-08
**Status:** Accepted
**Supersedes:** [ADR 0108](./0108-port-shape-convention.md) (the two-shapes convention — there is now a single shape: every port is an instantiable class).
**Partially supersedes:** [ADR 0107](./0107-split-manifest-schema.md) (its "the constants stay on `Schema`" choice — the constants now live in `Schema::Vocabulary` / `Schema::Keys`, re-exported on `Schema`).

> **One sentence:** the original review board specified a literal 3-file schema split (`Schema` + `Schema::Vocabulary` + `Schema::Keys`) and a single port shape (every port an instantiable class); ADRs 0107 and 0108 deliberately deviated toward lower churn — 0107 kept the constants on `Schema`, 0108 left `Clock`/`Publisher`/`BuildLock` as stateless modules — and this ADR executes the board's literal shapes instead, re-exporting the moved constants under their original `Schema::` names so the split is organizational (file layout) rather than a reference change.

## Context

ADRs 0107 and 0108 both faced a board recommendation and both declined the
literal form, choosing the lower-churn path:

- **0107** extracted the validation walk into `Schema::Validator` but **kept the
  constants on `Schema`**, reasoning that nesting them (`Schema::Vocabulary::LANES`)
  would ripple across ~21 validator refs and ~18 external sites for no behavioural
  gain over extracting the methods (which were the bulk of the overflow).
- **0108** **named two sanctioned port shapes** rather than converting the
  modules to classes, reasoning that `Clock.now` is a pure function of nothing,
  time is already injected as data via `Call#now` (ADR 0024), and wrapping a
  stateless port in an object buys ceremony and nothing else.

Both arguments were sound on churn-vs-value grounds. This ADR is the explicit
decision to prefer the board's literal uniformity over that trade — the board
asked for the exact shapes, and the plan's premise is to deliver them.

## Decision

**(a) Split the schema constants into two topic files, re-exported on `Schema`.**
`Schema::Vocabulary` (`lib/textus/manifest/schema/vocabulary.rb`) holds the
coordination vocabulary — `LANES` and its derived `ZONE_KINDS` / `CAPABILITIES` /
`KIND_REQUIRES_VERB`. `Schema::Keys` (`lib/textus/manifest/schema/keys.rb`) holds
the key whitelists, `FIELD_REGISTRY`, and `OWNER_SUBJECT_PATTERN`. `schema.rb`
re-exports every constant under its original `Schema::` name, so every
`Schema::LANES` / `Schema::FIELD_REGISTRY` / `Schema::CAPABILITIES` path — and the
validator's bare references — is unchanged. The data now lives in the topic files
the board drew; the public constant surface does not move.

**(b) Convert `Clock` and `Publisher` to instantiable classes** so that *every*
port is an instantiable class — one shape, no exceptions. `BuildLock` was already
a class. The `spec/conformance/architecture/port_shape_spec.rb` guard now enforces
the single shape: every port under `ports/**/*.rb` is an instantiable class.

## Consequences

Stated honestly, this **reverses two recently-accepted decisions** (0107 §"the
constants stay on `Schema`", 0108's whole premise):

- `Clock` and `Publisher` gain a `.new` with no state to hold — exactly the
  ceremony 0108 declined. The payoff is uniformity, not capability.
- Because the moved constants are re-exported, **every `Schema::` path is
  unchanged** — so the schema "split" is organizational (file layout matching the
  board's drawing), not a reference change. Consumers see no difference.
- Benefit: uniform port construction (a newcomer learns one shape, not two) and
  schema data that lives in topic files matching the board's diagram.

## Alternatives considered

- **Keep 0107/0108 as shipped.** Rejected by this plan's premise — the board's
  literal uniformity (one port shape, the topic-file schema split) was explicitly
  requested, and this ADR exists to deliver it.
- **Full constant rename without re-exports** (`Schema::Vocabulary::LANES`
  everywhere). Rejected: high ripple across the ~21 validator refs + ~18 external
  sites for zero behavioural gain over the re-export — the re-export gets the
  board's file layout at none of the reference churn.

No `SPEC.md` change — internal file organization + a port construction
convention; the manifest grammar, wire contracts, and verb surface are unchanged.
