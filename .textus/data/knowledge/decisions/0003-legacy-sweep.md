# ADR 0003 — Legacy Sweep (v0.12.0)

**Status:** Accepted
**Date:** 2026-05-25
**Supersedes / depends on:** [ADR 0002 — textus/3 vocabulary redesign](0002-textus-3-vocabulary-redesign.md)

## Context

v0.11.0 introduced textus/3 with a humane compatibility layer: every legacy
vocabulary slot (`ai`/`script`/`build`, `inbox`, `writable_by`, `policies`,
`projection:`/`generator:`/`reduce:`, `handler_allowlist`, `promote_requires`,
hook events `:put`/`:intake`/…, CLI verbs `mv`/`refresh-stale`/…) raised a
targeted error with a migration hint. A one-shot `textus migrate --to=textus/3`
verb performed the mechanical rewrite.

That layer was load-bearing for the cutover. v0.12.0 deletes all of it.

## Decision

1. Drop every legacy rename map (Role, Manifest zones, Hooks::Registry events,
   CLI verb/group renames). Legacy values fall through to the generic
   "unknown X" error.
2. Replace the eight ad-hoc legacy-key guards across `manifest.rb`,
   `manifest/entry.rb`, `manifest/rules.rb` with a single
   `Manifest::Schema.validate!` walker that emits `unknown key 'X' at '<path>'`.
3. Delete `lib/textus/migration/**` and `lib/textus/cli/verb/migrate.rb`
   (eight files, ~924 lines removed).
4. Keep the audit-log reader permissive on legacy `ai`/`script`/`build` role
   values. Pre-0.11.0 audit history is tolerated verbatim indefinitely (the
   reader returns whatever string is in the row; new writes always use
   canonical roles). No rewrite tooling ships in this release.
5. Late upgraders from textus/2 must install 0.11.x first. The
   `protocol_version` doctor check refuses textus/2 stores with a hint that
   points at the 0.11.x docs.

## Consequences

**Smaller production code:** removed compatibility shims (rename maps,
ad-hoc guards, migrator) across ~14 files. One vocabulary, one error format
per concern.

**Test suite net growth:** baseline 102 files / 7788 LOC (main) → final
110 files / 8428 LOC (+8 files, +640 LOC; +8.2%). The plan originally targeted
a 25-40% LOC reduction; that was based on an inflated baseline estimate of
9093 LOC at plan-write time. The actual baseline was smaller, and the new
behavior introduced in P1-P6 (the schema walker, permissive audit-log
tolerance) needed coverage that outweighed the legacy-test deletions.

**Phase 7 cleanup delivered modest but disciplined reduction:** from post-P6
peak of 8562 LOC down to 8428 LOC (-134 LOC, -1.6% in five batches).
Whole-file deletions only landed where coverage was genuinely subsumed by
another spec (each commit lists the subsuming file in its message). Several
TRIM candidates were rejected after closer inspection found unique behavior.
The "noise budget" in the suite turned out to be smaller than the plan
estimated.

**Sharper failure modes:** unknown manifest keys now error uniformly with a
JSON-path-like address. Typos that previously matched a legacy alias by
coincidence now surface as "unknown key" rather than a misleading rename hint.

**Late-upgrader friction:** users still on textus/2 cannot upgrade directly to
0.12.0. The 0.11.x stepping-stone is documented in `CHANGELOG.md` and in
`textus doctor`'s output.

## Alternatives considered

- *Keep the migrator one minor longer.* Rejected: every consumer who needed
  the migrator has had a release window. Carrying it forward only delays the
  cleanup.
- *Permissive manifest parser (accept-and-ignore unknown keys).* Rejected:
  silent acceptance of typos is the failure mode that legacy compat hints
  were *itself* trying to fix.
- *Strict audit reader + one-shot `textus audit-rewrite-legacy-roles` verb.*
  Considered and briefly implemented during this branch. Rejected on
  reconsideration: the verb added ~95 LOC of compat surface scheduled for
  0.13.0 removal — the same kind of debt v0.12.0 set out to eliminate.
  The 0.11.x stepping-stone story already handles the rare case where a
  user has unmigrated legacy rows: read tolerance is three lines of code,
  rewrite tooling is a release commitment.
- *Drop Phase 7 cleanup entirely once the inflated target was identified.*
  Rejected: the 1.6% reduction is real value, the verifications during P7
  surfaced two genuinely redundant test files that would have continued
  drifting. Disciplined cleanup is its own deliverable even at small scale.
