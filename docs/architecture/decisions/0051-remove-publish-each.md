# ADR 0051 — Remove `publish_each`: collapse publish to two modes

**Date:** 2026-06-02
**Status:** Accepted (ships 0.42.0)
**Supersedes:** the `publish_each` half of [ADR 0046](./0046-publish-leaf-subtrees.md) (`publish_each` whole-leaf subtree — both the file-leaf and directory-leaf behaviours are removed; `index_filename` survives as pure enumeration)
**Touches:** [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (`publish_tree` — now the single subtree-publish mode), [ADR 0049](./0049-publish-modes-as-sum-type.md) (the resolved sum type — what makes both this removal and any future re-add a one-arm change), [ADR 0050](./0050-native-authoring-and-content-identical-adoption.md) (native authoring now rides `publish_tree`).

> **One sentence:** `publish_each` is the lowest-demand publish mode with zero real-world usage; its one irreducible niche has not appeared in any actual use case, so we remove both `EachFile` and `EachDir` rather than carry a well-built but unmotivated capability — the ADR 0049 sum type keeps the door open to re-adding one mode cheaply if the niche ever materializes.

## Context

After ADR 0049 a directory entry resolves, once, to one of five publish modes: `None`, `ToPaths` (`publish_to`), `EachFile` (`publish_each`, file leaves), `EachDir` (`publish_each` + `index_filename`), and `Tree` (`publish_tree`). The three manifest keys split on a real axis and the code is clean. But the surface is wider than the demand:

- **`publish_each` has zero real-world usage.** The dogfood manifest (`.textus/manifest.yml`), the `examples/project` manifest, and the `textus init` scaffold all publish exclusively via `publish_to`. No shipped store uses `publish_each` in either form.
- **Its one irreducible niche never appeared.** `EachDir`'s reason to exist — "a collection where each leaf is *both* an addressable key *and* published to a per-leaf templated path" — has not shown up in any actual use case, including the native skill-authoring pipeline that ADR 0050 settled. That pipeline routes through `publish_tree` (whole-subtree mirror) or a derived-entry index, never through `publish_each`.
- **It is well-built but unmotivated.** ADR 0046 built it carefully (subtree copy, ignore filter, per-file sentinel, prune, file-vs-dir validation); ADR 0049 made it a tidy sum-type arm. None of that is *broken* — it is simply capability we maintain, document (SPEC §4, §5.3), and test for a use case that has not arrived.

We prefer a smaller surface over a speculative capability. The cost of `publish_each` is the cost of every contributor learning a fourth-and-fifth mode, the SPEC paragraphs describing the file-vs-dir discriminator rules, and the spec suite exercising templating + the directory-leaf footgun guards — all for a mode nothing invokes.

## Decision

Remove `publish_each` entirely — both `EachFile` and `EachDir`. Keep `publish_to`, `publish_tree`, and `None`. **Breaking change, no backward compatibility:** a manifest declaring `publish_each:` fails at load with a clear error pointing to the replacement.

1. **Delete the two key-driven subtree modes and their shared base.** `Publish::Each`, `Publish::EachFile`, `Publish::EachDir` go. `Publish.resolve` drops `publish_each` from the structural exclusivity set, and `mode_for` loses both its `publish_each` arm and the `entry.index_filename ? EachDir : EachFile` sub-fork — the last implicit selector in the resolver. With `publish_each` gone, the resolver is a flat one-of over `{publish_to, publish_tree}`.

2. **Fail loudly at load.** `Publish.resolve` *raises* a `UsageError` if `publish_each` is present, naming the replacement: "publish_each was removed in 0.42.0; mirror the subtree with publish_tree (and index_filename to keep the index addressable)." `Schema`'s allowed-entry-key list also drops `publish_each`, so an unknown-key check rejects it independently — belt-and-suspenders with the resolve-time raise.

3. **`index_filename` is kept, as pure enumeration.** It was only *coupled* to publishing through `EachDir` (which derived "a leaf is a directory" from its presence). Its own job — surfacing one fixed basename per directory as the row, validated and resolved in `resolver.rb` / `validators/index_filename.rb` / `doctor/check/illegal_keys.rb` — is independent of publish and unchanged. After removal it does that enumeration job exactly as before.

4. **`Tree.validate!` keeps `index_filename` ⊥ `publish_tree`.** This is the deliberately-small choice (see Alternatives): a `publish_tree`'d entry still cannot also declare `index_filename`. A skill batch mirrored by `publish_tree` therefore loses per-skill `SKILL.md` addressability — acceptable given zero proven demand, and reversible (see "the re-entry path").

5. **The external surface shrinks by one key.** `publish_each` leaves the manifest vocabulary, SPEC §4 / §5.3, the `boot` entry-row payload, and the `build` command summary. `publish_to`, `publish_tree`, their YAML shape, the `:file_published` event, the `{ built:, published_leaves:, pruned: }` build envelope, and the `publish_tree_index_overlap` doctor check are untouched. Per the `adr` runbook step 4, `SPEC.md` is updated in the same change.

## Consequences

- **The publish surface is two modes wide** (plus `None`): a fixed-path copy (`publish_to`) and a whole-subtree mirror (`publish_tree`). The resolver is a flat one-of with no nested discriminator. A contributor learns two publish behaviours, not four-plus-a-sub-fork.
- **A manifest using `publish_each` breaks at load** — by design. The message names the replacement; the migration is mechanical (a directory-leaf `publish_each: "skills/{leaf}"` over a `nested` skills entry becomes `publish_tree: "skills"` over the parent). No silent reinterpretation.
- **No real use case loses a capability it needs.** The skill-authoring pipeline (ADR 0050) already rides `publish_tree`. File-collection → remapped-path publishing, if it ever appears, is expressible as a derived entry (projection + template + `publish_to`).
- **`SubtreeMirror` is now used only by `Tree`.** It is left as-is; inlining it into `Tree` is a possible later cleanup, explicitly *not* part of this change.
- **The lost niche has a cheap re-entry path.** ADR 0049's sum type means re-adding one subtree mode — or lifting the `index_filename` ⊥ `publish_tree` exclusivity so the two compose — is a one-arm change, not a re-architecture. The door is open; we just stop carrying the room unused.
- **Cost: a breaking change pre-1.0.** Recorded in `CHANGELOG.md` with the one-line migration. Acceptable at 0.42.0; the rollback is a single-commit revert (the sum type means nothing else entangles with `Each`).

## Alternatives considered

- **Keep `publish_each`.** Valid — it is correct, tested, and a clean sum-type arm after 0049. Rejected as the long-term answer only because it is capability with no demand: every mode has an ongoing documentation and test cost, and a speculative one we cannot point a real use case at is the first to cut. Re-addable cheaply if the niche arrives.
- **Keep only `EachFile`, drop `EachDir`.** Half-measure: `EachFile` (1 leaf file → 1 templated path) is the *more* speculative of the two — the directory case at least had the skill-artifact motivation that ADR 0050 then routed elsewhere. Dropping one and keeping the other leaves the resolver sub-fork's *shape* (a key-driven mode) for no clearer demand. Rejected; remove both or neither.
- **Lift `index_filename` ⊥ `publish_tree` now, so enumeration and publish compose** — recovering `EachDir`'s "addressable index + mirrored subtree" from two orthogonal primitives (`index_filename` for enumeration, `publish_tree` for publish) instead of one fused mode. Arguably the *more* simplifying end state, and the natural re-entry path. **Deferred** to a follow-up ADR triggered by a real "many addressable skills, published" case — doing it now would widen this breaking change for a demand that has not appeared. Decision 4 records it as the explicit door.
- **Leave it and revisit at 1.0.** Rejected: the surface cost compounds with every new contributor and every publish-touching ADR. Pre-1.0 is exactly when removing an unused breaking-change-eligible mode is cheapest.
