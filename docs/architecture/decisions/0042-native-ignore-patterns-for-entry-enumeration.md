# ADR 0042 — Native ignore patterns for entry enumeration (one shared filter seam, evaluated above legality)

**Date:** 2026-06-01
**Status:** Proposed
**Refines:** [ADR 0018](./0018-manifest-carving.md), [ADR 0025](./0025-boot-doctor-as-verbs-and-etag-via-port.md), [ADR 0034](./0034-unify-lane-vocabulary.md)

## Context

A `nested` entry with `index_filename:` enumerates a directory tree fully
recursively. In real projects that tree often contains vendored or generated
subtrees that ship their *own* files of the same index basename — a
`node_modules/` whose dependencies bundle `SKILL.md`/`README`-style index files,
or `build`/`dist` output. These are almost never store content, yet they are
swept in (issue #119).

The defect surfaces as an *inconsistency*: the same vendored path gets opposite
verdicts depending on which code path looks at it.

1. **Enumeration** (`list`, `build`) silently *drops* a vendored file when one
   of its path segments is not a legal key segment (e.g. `node_modules` contains
   an underscore), warning to stderr and returning `nil`. `list` looks clean.
2. **`doctor`** independently globs the same tree and reports the very same
   paths as `key.illegal` errors. `doctor` goes red.

A store can therefore `list` cleanly while `doctor` is red on paths the user
never intended to index, with no first-class way to say "ignore this subtree."

The root cause is structural, not cosmetic. There are **two independent
tree-walkers, each with its own private copy of the legality decision**:

- `Manifest::Resolver#enumerate_nested` → `Dir.glob` + `nested_row_for`, gated by
  the private `valid_segment?` (`lib/textus/manifest/resolver.rb:70-101`). Used
  by `Read::List` and, via the lister chain, by `build`.
- `Doctor::Check::IllegalKeys` → its own `check_index_paths` / `check_all_paths`
  walk, gated by `Key::Grammar::SEGMENT` inline
  (`lib/textus/doctor/check/illegal_keys.rb:21-44`).

Both consult the same regex but reimplement *the walk* and *the decision*, so
they already disagree about what participates in a store. Issue #119 is the
trigger that makes the latent divergence visible; an ignore primitive bolted on
as two separate implementations would deepen it.

## Decision

**1. One shared enumeration-filter seam, consulted by both walkers.**
Introduce a single predicate that decides whether a path participates in a
nested entry, and route both the resolver and the doctor check through it. The
filter is the one home for "should this path be considered at all," replacing
the two private copies of that judgement. This closes the existing
`list`/`doctor` divergence as a direct consequence — they can no longer reach
different conclusions because they ask the same function.

**2. Ignore is evaluated *above* legality, not folded into it.** An ignored
path is *excluded* — never judged. It is neither dropped-with-a-warning (the
resolver's treatment of illegal segments) nor flagged `key.illegal` (the
doctor's). Legality (`Key::Grammar::SEGMENT`) runs only on the paths that
survive the ignore filter. The order is: **walk → ignore? → (if kept) legal?**.
This is what makes `**/node_modules/**` silence *both* the silent-drop warning
and the doctor error from the same declaration.

**3. The ignore set is per-entry manifest config (`ignore:`).** Add `ignore` to
`Schema::ENTRY_KEYS` as an optional list of gitignore-style globs, parsed onto
`Manifest::Entry::Nested` alongside `index_filename`. Patterns are matched
against the entry-relative path segment-wise: `**` is a globstar (zero or more
path segments) and each other segment is matched with Ruby stdlib
`File.fnmatch` under `File::FNM_EXTGLOB` (anchored `*`, `{a,b}` alternation).
The segment-wise pass is necessary because a single `File.fnmatch` call cannot
express `**/node_modules/**` — under `FNM_PATHNAME` a trailing `**` will not
cross a `/`, and without it a leading `**/` will not match zero leading
segments. No new gem; stdlib-only, consistent with the codebase's path
handling.

This keeps the manifest the single source of truth (the same principle ADR 0034
applied to the zone-kind/capability bijection): the ignore set travels with the
entry that enumerates, validates through the existing schema walker, and is
reviewable in one file. It is entry-scoped because only nested entries
enumerate trees.

## Consequences

**`list`, `doctor`, and `build` agree on one effective file set.** They share
the walk-filter decision, so a configured `**/node_modules/**` removes matching
paths from enumeration *and* stops `doctor` flagging them — issue #119's primary
acceptance criterion, satisfied structurally rather than by keeping two
implementations in sync by hand.

**The latent divergence is retired, not just patched.** Even absent any `ignore`
declaration, the two walkers now route their participation decision through one
seam, so future drift between what `list` enumerates and what `doctor` flags is
designed out.

**Additive and backward-compatible.** `ignore` is optional; entries without it
behave exactly as before. No wire-format change, no `SPEC.md` contract change to
the envelope or verbs. The manifest schema gains one optional key — documented
in the manifest/zones reference per the issue's acceptance.

**Glob semantics are stdlib `fnmatch` per segment, plus a `**` globstar.**
A single `*` is anchored to one segment (does not cross `/`); `{a,b}` is
alternation; `**` spans zero or more segments. We do not reimplement gitignore's
full negation/anchoring algebra; `**/node_modules/**`-style patterns are the
supported shape.

## Alternatives considered

**A `.textusignore` sidecar file (gitignore-style).** Rejected. It introduces a
*second* configuration surface every walker must locate, parse, and merge with
manifest semantics — splitting the single source of truth and reopening
precedence questions (store root vs repo root, as the issue itself flags). ADR
0034 collapsed a two-table drift hazard into one table; a sidecar walks that
discipline back. The manifest already validates a closed vocabulary; `ignore`
belongs there.

**`.gitignore`-awareness for enumeration (skip what git ignores).** Rejected on
principle. It couples store semantics to git. textus's promise is durable memory
that survives "the session, the model, and the vendor"; a `canon` or `derived`
store materialised outside a working tree, or shipped as an artifact, has no
`.gitignore`, and the same store would enumerate differently in two checkouts.
A store's effective file set must be a function of the manifest, not of an
ambient VCS.

**Fold ignore into the legality check (treat ignored paths as "legal, skipped").**
Rejected. Conflating "not store content" with "valid key segment" muddies both
the resolver's warning and the doctor's report — an ignored `dist/` is not a
*legal* segment, it is simply *out of scope*. Keeping ignore strictly above
legality preserves honest diagnostics for genuinely malformed in-scope paths.

**Two ignore implementations (one in resolver, one in doctor).** Rejected — it
is the status quo that produced the bug. The whole point is one seam.

**A store-level default ignore list (top-level `ROOT_KEYS` member) now.**
Deferred, not rejected. Vendored subtrees are cross-cutting, so `**/node_modules/**`
may get repeated across entries. If that duplication shows up in practice, a
store-level default that *merges* with per-entry patterns is the clean follow-up.
Shipping per-entry first avoids building two tiers speculatively (YAGNI); the
merge point is easy to add later because the filter seam already exists.
