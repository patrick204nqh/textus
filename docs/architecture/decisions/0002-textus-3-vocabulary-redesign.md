# ADR 0002 — textus/3 Vocabulary Redesign

**Status:** Accepted (2026-05-25)
**Supersedes:** none (additive to textus/2 design ADRs)

## Context

The textus/2 vocabulary accumulated three notable overloads:

- **`build`** served as a verb (`textus build`), a role (`build` in zone policies), and an event (`:built` hook).
- **`policy`** named both a per-zone write gate (`writable_by:`) and a top-level rules block (`policies:` with refresh/promotion/etc.).
- **`inbox`** named the zone, but the hook event was `:intake` and the manifest field was `intake:` — three names for one concept.

These collisions cost reviewers attention every time the docs were read, made error messages ambiguous, and forced special-case wording in `textus intro`.

## Decision

Ship `textus/3` as a hard cutover (no soft deprecation period). Rename across six conceptual axes — actor, place, thing, operation, event, rule — so each axis owns exactly one vocabulary slot:

| Axis | textus/2 | textus/3 |
|---|---|---|
| Actor | `ai`, `script`, `build` | `agent`, `runner`, `builder` |
| Place (zone) | `inbox` | `intake` |
| Thing (manifest) | `writable_by`, `readable_by` | `write_policy`, `read_policy` |
| Thing (compute) | `projection:` / `generator:` | `compute: { kind: projection \| external }` |
| Thing (reducer key) | `reduce:` | `transform:` |
| Rule (top-level) | `policies:` | `rules:` |
| Rule (intake) | `handler_allowlist:` | `intake_handler_allowlist:` |
| Rule (gate) | `promote_requires:` (reserved) | `promotion: { requires: [...] }` (enforced) |
| Event (RPC) | `:intake`, `:reduce`, `:check` | `:resolve_intake`, `:transform_rows`, `:validate` |
| Event (pub-sub) | `:put`, `:deleted`, `:built`, etc. | `:entry_put`, `:entry_deleted`, `:build_completed`, etc. |
| DSL | `Textus.intake/.hook/...` | `Textus.on(event, name)` |
| CLI flag | `--format=json` (envelope) | `--output=json` |
| CLI verbs | `textus mv`, `textus policy list`, `textus refresh-stale` | `textus key mv`, `textus rule list`, `textus refresh stale` |

Ship `textus migrate --to=textus/3` as the one-shot migration path covering manifest, zone directories, frontmatter owners, and audit-log marker. Hook DSL changes are reported (read-only scan) but not auto-rewritten — humans confirm each Ruby file.

## Consequences

- Existing stores must run `textus migrate --to=textus/3` before installing 0.11.0.
- All custom hooks must update to `Textus.on(event, name) { ... }`; the scanner reports call sites.
- SPEC.md is fully rewritten; the protocol identifier flips on the wire.
- `Doctor::Check::ProtocolVersion` refuses to operate on un-migrated stores; CLI emits a `protocol_mismatch` envelope.
- Several CLI verbs change spelling. Legacy spellings emit a `CommandRenamed` envelope with a hint.
- `promotion.requires` is now enforced (was reserved-but-no-op in textus/2). Predicates: `schema_valid`, `human_accept`.
- One small ergonomic loss: built JSON output's `_meta.reduce` legacy key may persist in old build artifacts until the next `textus build` regenerates them.

## Alternatives considered

- **Soft deprecation** with both vocabularies coexisting for one minor release: rejected. Doubles the parser surface area, makes error messages ambiguous ("which name should I use?"), and pushes the migration cost from one explicit step to a long tail of confusion.
- **Splitting into multiple minor releases** (actors in 0.11, zones in 0.12, etc.): rejected. The protocol bump is the natural gate; an interim half-state has worse UX than either edge.
- **Renaming `_meta`** (e.g., to `meta` or `frontmatter`): rejected. The underscore is a useful reserved-key signal, and downstream tools rely on it as a stable convention.
- **Auto-rewriting hook Ruby**: rejected. Static rewrites of arbitrary Ruby are unreliable; a hook scanner that reports findings + humans confirm is safer and not much slower for the typical project.
