# ADR 0107 — split `manifest/schema.rb`: data vs validation walk

**Date:** 2026-06-08
**Status:** Partially superseded by [ADR 0109](./0109-board-exact-schema-ports.md) (the constants it kept on `Schema` now live in `Schema::Vocabulary`/`Schema::Keys`, re-exported on `Schema`).
**Refines:** [ADR 0018](./0018-manifest-carving.md) (carved `Manifest` into Data/Resolver/Policy/Rules; this continues that decomposition one level down, separating the schema's *data* from its *validation logic*).

> **One sentence:** `manifest/schema.rb` had grown to 420 lines — ~2× the next-largest file and the *only* file in the codebase carrying a `rubocop:disable Metrics/ModuleLength` — by mixing three concerns that change for different reasons (the coordination **vocabulary** `LANES` + derived, the **key whitelists / `FIELD_REGISTRY`**, and the **validation walk**); this extracts the validation walk into a lexically-nested `Schema::Validator`, leaving the constants on `Schema` so every `Schema::FIELD_REGISTRY` / `Schema::CAPABILITIES` reference keeps working unchanged, and drops the lint waiver.

## Context

`Schema` was doing two jobs. It *is* the manifest's data dictionary — the closed
`LANES` vocabulary and its derived `ZONE_KINDS`/`CAPABILITIES`/`KIND_REQUIRES_VERB`,
the `ROOT_KEYS`/`ZONE_KEYS`/`ENTRY_KEYS`/… whitelists, and the `FIELD_REGISTRY`
single-source-of-truth for rule fields. It *also* held the entire validation
walk: `validate!` and its ~15 helpers (`validate_zones!`, `validate_entries!`,
the retired-key interceptors, owner validation, the generic `walk`, the
single-queue/single-machine guards, zone-kind consistency).

Those two halves change for unrelated reasons — a new zone kind edits the data;
a stricter validation rule edits the walk — but lived in one 420-line module
that tripped `Metrics/ModuleLength` and wore the codebase's only
`rubocop:disable` for it. The waiver is a smell: it is the file announcing it
has outgrown one responsibility.

## Decision

**Extract the validation walk into `Textus::Manifest::Schema::Validator`,** a
module lexically nested under `Schema`. All ~15 validation methods move there as
`module_function`s. Because `Validator` is nested inside `Schema`, their bare
constant references (`ROOT_KEYS`, `LANES`, `FIELD_REGISTRY`, …) still resolve to
`Schema`'s constants via Ruby's lexical scope — the methods move verbatim.

**The constants stay on `Schema`.** This is the load-bearing choice: every
external reference is `Schema::FIELD_REGISTRY`, `Schema::CAPABILITIES`,
`Schema::LANES`, etc. (in `rules.rb`, `policy.rb`, `capabilities.rb`,
`rule_explain`/`rule_list`, `doctor`'s rule-ambiguity check, and their specs).
Leaving the constants put means **zero** reference churn — the split is invisible
to every consumer of the schema's data.

**`Schema` keeps exactly two public entry points** — `validate!` (called by
`Manifest::Data`) and `validate_source_and_retention!` (called by `Manifest`) —
as thin delegators to `Validator`. Callers keep speaking to `Schema`. White-box
unit tests that poked internal helpers (`valid_owner?`, `validate_rules!`,
`validate_single_machine!`, `validate_zones!`) follow those helpers to their new
home and now target `Schema::Validator` directly — the refactor is reflected in
the tests rather than papered over with delegators that exist only for tests.

The result: `schema.rb` drops to ~124 lines (the data + two delegators),
`validator.rb` is ~323, and the `rubocop:disable Metrics/ModuleLength` is
deleted.

## Consequences

- `schema.rb` reads as what it is — the manifest's data dictionary. The walk
  reads as what it is — validation. Each fits in one screen.
- No consumer changed: the constant paths are identical, the two public methods
  are identical. Behaviour is preserved (characterization: the 247 manifest/
  schema specs are green before and after; full suite green).
- The lone `Metrics/ModuleLength` waiver is gone; nothing in `lib/` now suppresses
  that cop.

## Alternatives considered

- **Nest the constants too** (`Schema::Vocabulary::LANES`, `Schema::Keys::*`).
  Rejected: it renames every `Schema::LANES`/`Schema::FIELD_REGISTRY` reference
  across the manifest layer for no gain over extracting the methods — the methods
  are the bulk of the lines, and they are what made the module overflow.
- **Move `FIELD_REGISTRY` to its own file.** Rejected as unnecessary: extracting
  the walk alone brings `schema.rb` comfortably under the threshold, so splitting
  the data further would be churn (a 5-file reference ripple) with no payoff.
- **Keep the `rubocop:disable`.** Rejected: the waiver was the signal, not the
  fix. Suppressing the cop leaves the two-responsibilities problem in place.

No `SPEC.md` change — internal file organization only; the manifest grammar and
validation behaviour are unchanged.
