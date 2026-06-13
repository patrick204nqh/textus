# ADR 0053 — Remove `index_filename`: nested entries enumerate files

**Date:** 2026-06-02
**Status:** Accepted (ships 0.43.0)
**Supersedes:** the `index_filename` enumeration feature (SPEC §4); orphaned by [ADR 0051](./0051-remove-publish-each.md) (which removed `EachDir`, `index_filename`'s only motivating consumer).
**Touches:** [ADR 0046](./0046-publish-leaf-subtrees.md) (`index_filename` introduced the directory-keyed leaf), [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (`publish_tree`, with which `index_filename` was mutually exclusive — that exclusivity goes away with the key), [ADR 0052](./0052-typed-publish-block.md) (ships in the same 0.43.0).

> **One sentence:** `index_filename` let a nested entry enumerate *directories* as addressable keys via a fixed index file (e.g. `SKILL.md`), but it had zero real usage, its only motivating consumer (`EachDir` per-leaf publish) was removed by ADR 0051, and it cannot compose with the surviving `publish_tree` mode — so it is removed and a nested entry now always enumerates its files.

## Context

`index_filename` (ADR 0046) made a nested entry surface one fixed basename per directory as the addressable row, keyed by the directory path: with `index_filename: SKILL.md`, `zones/skills/ask/SKILL.md` enumerates as `skills.ask` and the siblings are not keys. Without it, a nested entry enumerates every file matching its format extension as its own key.

It existed to power `EachDir` — "a directory leaf that is *both* an addressable key *and* published per-leaf to a templated path." ADR 0051 removed `EachDir` (and all of `publish_each`). What remained of `index_filename` is "addressable directory unit, **not** mirrored as a tree." That residue is unmotivated:

- **Zero real usage.** No manifest declares it — not the dogfood store, not `examples/project`, not the `textus init` scaffold. (The same emptiness that justified removing `publish_each`.)
- **It cannot compose with the one publish mode left.** `index_filename` is mutually exclusive with `publish_tree` (ADR 0047 D4). So an entry can be *addressable by directory* or *mirrored out as a subtree* — never both. The "addressable index + mirrored siblings" use that would justify keeping it is exactly the unproven `IndexPlusTree` case parked in [#145](https://github.com/patrick204nqh/textus/issues/145) / ADR 0051 option-b.
- **Native skill authoring does not use it.** ADR 0050's supported path mirrors skills with `publish_tree` (keyless, path-driven); it never enumerates an index. Removing `index_filename` leaves that path untouched.

So `index_filename` is not *redundant* (nothing else does directory-keyed enumeration) but it is *orphaned*: a feature whose reason to exist was deleted one version prior, exercised by nothing.

## Decision

Remove `index_filename`. A nested entry always enumerates the files under its tree (each file matching the format extension is a key). **Breaking change, no backward compatibility** — a manifest declaring `index_filename:` fails at load with a migration-pointing error.

1. **Resolver simplifies to one nested enumeration.** `Resolver#enumerate_nested` drops the index branch and always globs the format extension; `build_resolution` and `nested_row_for` lose their `index_filename` forks. The shallowest-index claiming logic (ADR 0046 D5) goes with it.
2. **The mutual-exclusivity guard disappears.** `Publish::Tree.validate!` no longer rejects `index_filename` + `publish_tree` — there is no `index_filename` to conflict with.
3. **Drop the machinery.** `Validators::IndexFilename` (and its `REGISTERED` entry), the `index_filename` attr/param on `Nested`, the `Base` stub, and the `doctor` `illegal_keys` index branch are removed.
4. **Fail loudly at load.** `Schema` drops `index_filename` from the allowed entry keys and intercepts it with a migration message: *index_filename was removed in 0.43.0 (ADR 0053) — a nested entry now enumerates each file as a key; to mirror a directory of files to a consumer path use `publish: { tree: "..." }`.* Per the `adr` runbook step 4, `SPEC.md` §4 drops the `index_filename` subsection in the same change.

## Consequences

- **One nested enumeration semantics.** A nested entry keys each file under its tree — no second, directory-keyed mode to learn or document. The resolver, validator set, and `doctor` shrink.
- **A manifest using `index_filename` breaks at load** — by design, with the migration named. Migration: drop the key (the entry will key its files), or, to publish a directory of files as a unit, use `publish: { tree: }` (which is keyless — the files become opaque payload, not keys).
- **Native skill authoring (ADR 0050) is unaffected** — it rides `publish_tree`, never `index_filename`.
- **The "addressable index + mirrored subtree" capability is now fully gone**, not just fused-then-removed. If a real corpus ever needs it (#145), it returns as a *composed* feature — `publish_tree` plus a re-introduced enumeration primitive — decided then, against evidence, on the ADR 0052 `publish:` block. The door is documented, not propped open with unused code.
- **Rollback is a single-commit revert.** The feature was self-contained behind one key.

## Alternatives considered

- **Keep it.** Valid — it is correct and tested, and directory-keyed enumeration is a real (if unused) capability. Rejected for the same reason as `publish_each`: unused, undermotivated surface costs every reader and every enumeration-touching change; pre-1.0 is when removing it is cheapest.
- **Keep it and lift `index_filename ⊥ publish_tree` so they compose (IndexPlusTree).** The "more capable" end state, and the honest path *if* the addressable-published-skills corpus exists. Rejected now because that corpus is unproven (#145) and building composition for a hypothetical is the opposite of this cleanup; recorded as the evidence-triggered re-entry path.
- **Defer to its own version after 0.43.0.** Reasonable, but `index_filename` and the `publish:` block are the same publish/enumeration surface; folding both into 0.43.0 is one breaking change for users to absorb instead of two back-to-back. The maintainer chose to bundle.
