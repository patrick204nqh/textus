# ADR 0049 — Publish modes as a resolved sum type + one shared subtree mirror

**Date:** 2026-06-02
**Status:** Accepted
**Touches:** [ADR 0046](./0046-publish-leaf-subtrees.md) (`publish_each` whole-leaf subtree), [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (`publish_tree` key-less mirror — this ADR makes that ADR's three-key conceptual table the *code* structure, and relates to its Open Question Q1), [ADR 0042](./0042-native-ignore-patterns-for-entry-enumeration.md) (the shared `ignore` seam both mirrors reuse), [ADR 0007](./0007-envelope-data-class.md) (publish is copy, not parse).

> **One sentence:** the publish design is a clean three-key *concept* (ADR 0047) realized as a muddy four-way *implementation* — an implicit nil-cascade selector, four scattered pairwise exclusivity guards, and two near-duplicate walk/prune pipelines all living on one `Nested` class; this ADR resolves the mode once into a sum type and shares one subtree mirror, so the code structure matches the concept.

## Context

After ADR 0046 (`publish_each`) and ADR 0047 (`publish_tree`), a directory entry can publish four ways. The *external* model is a good carving — three manifest keys split on a real axis:

| Key | Axis | Today's code path |
|---|---|---|
| `publish_to` | 1 stored file → N fixed repo paths | `Base#publish_via` (`base.rb:86-103`) |
| `publish_each` (no `index_filename`) | key-driven: 1 leaf file → 1 templated path | `Nested#publish_via` → `publish_one` (`nested.rb:59,67-72`) |
| `publish_each` + `index_filename` | key-driven: 1 leaf *subtree* → 1 templated dir | `Nested#publish_via` → `publish_subtree` (`nested.rb:59,74-91`) |
| `publish_tree` | path-driven: whole entry subtree → 1 dir, no keys | `Nested#publish_via` → `publish_tree_via` (`nested.rb:42,97-122`) |

The *internal* realization does not reflect that clean split. Four problems, all in `lib/textus/manifest/entry/`:

1. **The mode selector is implicit — a cascade of nil-checks across three attributes plus one modifier.** `Nested#publish_via` (`nested.rb:41-65`) branches `@publish_tree` → `@publish_each.nil?` → `@index_filename ?` to pick one of four behaviours. There is no `mode` field; *which* publish happens is *inferred* from the combination of `{publish_to, publish_each, publish_tree, index_filename}` being set. This is the same "infer the unit from structure" implicitness ADR 0046/0047 reject for *keys*, reappearing for the publish *mode* itself.

2. **Mutual exclusivity is enforced negatively, in four scattered guards across two validators** — because the modes are three independent nullable attributes on one object, so "two modes set at once" is *representable* and only forbidden at runtime:

   ```
   publish_each.rb:18   publish_to     ✗ publish_each
   publish_tree.rb:19   publish_to     ✗ publish_tree
   publish_tree.rb:22   publish_each   ✗ publish_tree
   publish_tree.rb:26   index_filename ✗ publish_tree
   ```

   Four pairwise "not-both" checks simulate a one-of. Add a fifth mode and it is six.

3. **Two near-duplicate walk→publish→prune pipelines.** `publish_subtree` (`nested.rb:74-91`) and `publish_tree_via` (`97-122`) are structurally identical — `Dir.glob(base/**/*, FNM_DOTMATCH)` → skip non-files → `ignored?` → `Ports::Publisher.publish` → `pctx.emit(:file_published, …)` → prune — differing only in (a) the root the walk is rooted at (`leaf_dir` vs entry `base`), (b) the emit payload (real `row[:key]` + envelope vs `@key` + `envelope: nil`), and (c) which prune runs. Likewise the two prune methods, `prune_orphans` (`147-156`) and `prune_tree` (`129-142`), are identical except `prune_tree` honors `ignored?` (`:137`) and `prune_orphans` does not — a single load-bearing line of difference (it is what lets a derived `SKILL.md` survive the whole-target prune, ADR 0047 D4) that is undocumented at the `prune_orphans` site.

4. **The repo-escape guard is copy-pasted** (`nested.rb:53-57` and `100-104`), and `Nested` has become the god-class for every publish behaviour a directory entry can have: key templating, key enumeration, single-file publish, whole-leaf copy, tree mirror, two prunes, the ignore predicate, and the escape guards.

None of this is *broken* — it is well-tested and ships correctly (`publish_each_spec`, `publish_leaf_subtree_spec`, `publish_tree_spec`, `publish_spec`). It is *accreted*: each ADR added a branch and a near-copy rather than re-cutting the shape. The cost lands on the next contributor and the next mode.

## Decision

Make the code structure match ADR 0047's conceptual table. **No manifest key, wire contract, event, or `doctor` check changes** — purely an internal re-cut.

1. **Resolve the publish mode once, into a sum type.** Introduce a `Manifest::Entry::Publish` namespace with one small object per behaviour, each exposing `#publish(pctx, prefix: nil)` returning the existing `{ kind:, value:, pruned: }` shape:

   ```
   Publish::None       — nothing to publish (no publish_* key)
   Publish::ToPaths    — publish_to → N fixed paths      (today: Base#publish_via body)
   Publish::EachFile   — publish_each, file leaves        (today: publish_one path)
   Publish::EachDir    — publish_each + index_filename     (today: publish_subtree path)
   Publish::Tree       — publish_tree                      (today: publish_tree_via)
   ```

   Each entry answers `#publish_mode` (resolved once from its attributes); `Entry#publish_via(pctx, prefix:)` collapses to `publish_mode.publish(pctx, prefix:)`. The nil-cascade and the `index_filename ?` sub-fork (`nested.rb:42-43,59`) disappear into the resolver. `publish_target_for` / `publish_one` / `publish_subtree` / `publish_tree_via` move out of `Nested` onto the modes that own them.

2. **Exclusivity becomes structural.** Mode resolution raises a single `UsageError` if more than one publish key is set, naming the conflicting keys — replacing the four scattered pairwise guards (problem 2) with one check in one place. Per-mode *shape* validation (the `publish_each` template-var and directory-vs-file rules in `publish_each.rb:33-73`; the `publish_tree` no-template rule in `publish_tree.rb:31-37`) stays, but moves next to the mode it validates and is reached *because that mode resolved*, instead of each validator re-deriving "is some other key also set." The `Validators::REGISTERED` list (`validators.rb:5-13`) keeps the non-publish validators (`Events`, `InjectBoot`, `IndexFilename`, `Ignore`, `FormatMatrix`); the publish pair is folded into the mode resolution.

3. **One shared `Publish::SubtreeMirror`.** `EachDir` and `Tree` both delegate the walk to a single mirror that takes: the `base` to root the walk at, the `target_dir`, a per-file emit payload builder, and `prune_honors_ignore:`. This collapses `publish_subtree` + `publish_tree_via` into one walk and `prune_orphans` + `prune_tree` into one prune (the `ignored?`-in-prune difference becomes the explicit `prune_honors_ignore:` flag, finally documented as a parameter rather than a silent line). The repo-root escape guard becomes one helper called once per mode.

4. **The external surface is untouched.** Three manifest keys, their YAML shape, the `doctor` `publish_tree_index_overlap` check (`doctor/check/publish_tree_index_overlap.rb`), the `{ built:, published_leaves:, pruned: }` return consumed by `Write::Publish` (`publish.rb:30-38`), and every `:file_published` payload stay exactly as they are. `SPEC.md` does not change (ADR runbook step 4 — no normative contract touched).

## Consequences

- **Illegal multi-mode entries become unrepresentable past resolution.** "All three publish keys set" can no longer reach the publish path; it fails at mode resolution with one clear message. The four pairwise guards (problem 2) collapse to one.
- **The duplication (problems 3, 4) is removed at the source.** One mirror, one prune (flag-parameterized), one escape guard. The `prune_honors_ignore:` difference that protects the derived index (ADR 0047 D4) becomes an explicit, named parameter instead of an undocumented one-line divergence between two methods.
- **`Nested` shrinks to what it is — a directory-entry value** (attributes + `#publish_mode`), not the home of every publish algorithm. The behaviours live in named, separately-testable mode objects, so a unit test exercises `Publish::Tree` without standing up a full manifest.
- **The code finally reads like ADR 0047's table.** A contributor adding a fifth mode adds one `Publish::*` class and one resolver arm — not a fourth nil-branch, a fifth pairwise guard, and a third copy of the walk.
- **Cost: a new `publish/` namespace and a behaviour-preserving move of four methods out of `Nested`.** Mitigated by the existing spec coverage (four publish specs) as the safety net, and stageable mode-by-mode (extract the mirror first, then resolve into the sum type) so the suite stays green throughout.
- **Lower leverage than ADR 0048.** The publish design is accreted, not defective. This ADR is worth landing when publish is next touched or a new mode looms; it is not urgent.

## Alternatives considered

- **Leave it.** Valid — it is correct and tested. Rejected as the long-term answer only because the *next* mode (see ADR 0047 Q1) turns the nil-cascade and the pairwise-guard matrix from "smell" into "actively painful." Accepted as the right call *if no new publish mode is coming* — this ADR explicitly defers to that judgement.
- **Add an explicit `mode:` enum field to the entry, keep the methods on `Nested`.** Removes the implicit selector (problem 1) but not the duplication (3, 4) or the god-class. Half the win for most of the churn; rejected.
- **Push the behaviour fully into mode objects (chosen).** The most code movement, but the only option that addresses all four problems and makes the structure match the concept.
- **Merge `EachDir` and `Tree` into one "subtree" mode with a `keyed:`/`tree:` flag.** Rejected for the same reason ADR 0047 rejected `publish_each` with `tree: true`: two genuinely different semantics (key-anchored per-leaf vs key-less whole-entry) behind one name decided by a flag is worse than two named modes that share an *implementation* helper (`SubtreeMirror`) without sharing a *contract*.

## Open questions

- **Q1 — does `publish_to` (`ToPaths`) route through the sum type too, or stay as `Base`'s default? — RESOLVED: uniform.** `Base#publish_mode` returns `ToPaths` or `None`, so *every* entry resolves a mode and `publish_via` is one implementation on `Base` (`publish_mode.publish(pctx, prefix:)`). `Base#publish_via`'s old body became `Publish::ToPaths`. `Derived` keeps its own `publish_via` (it materializes a body before copying — a different axis, not one of the four publish modes), and therefore does not consult `publish_mode`. The escape guard stays scoped to the modes that had it (`EachFile`/`EachDir`/`Tree`); `ToPaths` keeps no guard, preserving today's behaviour.
- **Q2 — relationship to ADR 0047 Q1 (unify the derived index + sibling mirror into one entry).** A resolved sum type makes a future `IndexPlusTree` mode (derive the index *and* mirror the siblings from one entry) a natural fifth arm rather than the current two-entry `publish_to` + `publish_tree` coordination dance with the `ignore`-the-index footgun. This ADR does not build it, but it is the structural precondition that makes it cheap — which is itself an argument for doing this before, not after, tackling 0047 Q1.
