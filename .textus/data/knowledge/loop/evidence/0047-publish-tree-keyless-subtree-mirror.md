# ADR 0047 — `publish_tree`: a key-less subtree mirror for a derived-index leaf

**Date:** 2026-06-02
**Status:** Accepted (ships 0.41.0)
**Touches:** [ADR 0046](./0046-publish-leaf-subtrees.md) (whole-leaf `publish_each`; scopes its "no third key" ruling to the index-*present* case — see Decision 1), [ADR 0042](./0042-native-ignore-patterns-for-entry-enumeration.md) (the shared `ignore` filter seam), [ADR 0007](./0007-envelope-data-class.md) (publish is copy, not parse), [ADR 0044](./0044-system-actors-resolved-by-capability.md) (`build` runs as `actor_for("build")`). Resolves issue #132 item #4.

> **Publish surface after this ADR (SPEC §4, §5.3).** Three keys, pairwise mutually exclusive, split on a real axis:
> - `publish_to:` — 1 stored file → N fixed repo paths (leaf/derived/intake; `base.rb:80-101`, `derived.rb:22-41`).
> - `publish_each:` — **key-driven** fan-out: 1 nested entry → N leaves at *templated* paths, one leaf per enumerated key (`nested.rb:40-63`; requires `nested: true`).
> - `publish_tree:` — **path-driven** mirror: 1 nested entry's directory subtree → 1 target directory, layout preserved, **no keys involved** (this ADR).
>
> ADR 0046 rejected "a third publish key" — but that ruling was explicitly scoped to the case where `index_filename` *already determines the unit* (an index file is in-store). `publish_tree` addresses the case ADR 0046 did not reach: the index is **derived/absent**, so there is no key to enumerate and `publish_each` has nothing to iterate. The precondition for 0046's rejection is absent. See Decision 1 and the supersession note appended to 0046's Alternatives.

## Context

Issue #132 wants the store to own a **prose-heavy, multi-file artifact** — a Claude Code Agent Skill, which is a directory:

```
zones/skills/my-skill/
  ├── SKILL.md        frontmatter + a large hand-authored body   ← the index
  ├── commands.md     sibling
  ├── references/
  │     ├── foo.md    sibling
  │     └── bar.md    sibling
  └── scripts/
        └── build.py  sibling (NOT markdown)
```

ADR 0046 (shipped 0.40.0) lets the store own this **when `SKILL.md` is authored natively in-store**: a `nested` entry with `index_filename: SKILL.md` + `publish_each` copies the whole leaf subtree as a unit. That fully closes ownership for the *native-shape* path, and it is the recommended default.

This ADR addresses the **derive path** (#132 items #1 + #4): rendering `SKILL.md` from a structured skilldef rather than authoring it. The moment `SKILL.md` is *derived*, it is removed from the source tree — and that breaks every existing publish mode for the **sibling** files:

- **Whole-leaf `publish_each`** keys off `**/<index_filename>` (`resolver.rb:81`); remove the in-store `SKILL.md` and zero leaves are found, so the siblings never publish.
- **File-leaf `publish_each`** (drop `index_filename`) routes each file through `publish_target_for` → key segments and `resolver.rb:101-106` drops any file whose name isn't a legal segment `[a-z0-9][a-z0-9-]*`. The agentskills-mandated `README.md` (→ `README`) is dropped; `scripts/build.py` is invisible because nested enumeration is **format-scoped** to one `nested_glob` (`resolver.rb:76`, `nested_glob(entry.format)`); and every surviving sibling is **promoted to an addressable key** — exactly the keyspace pollution ADR 0046 Decision 1 rejected.

The shape of the problem: publishing the siblings of a derived-index leaf is a **pure-payload directory mirror** — copy a tree of opaque files to a target dir, preserving layout, with sentinels + `ignore` + prune — and it has **no key/envelope semantics at all**. `publish_each` cannot express this because it is *fundamentally* key-driven: it iterates `resolver.enumerate` rows (`nested.rb:45`), and the siblings in ADR 0046 only ride along *because a leaf key (the index) exists to anchor them*. Remove the index and there is nothing to iterate.

The derived `SKILL.md` itself is **not** the blocker: it is a `derived` entry with `publish_to: <literal path>`, which works today (`derived.rb:22-41`). The blocker is the siblings.

## Decision (proposed)

1. **Add `publish_tree:` — a key-less, path-driven subtree mirror — as a third pairwise-exclusive publish key.** It applies to a `nested` entry and copies the entry's directory subtree (`zones/<path>/**`) to one target directory, preserving relative layout verbatim (case and extension preserved). It does **not** consult the resolver, creates **no keys**, and addresses **no envelopes** — files under it are opaque payload, never proposable/guardable/queryable. This is the inverse of `publish_each`: where `publish_each` says *"iterate the keys, render each to a templated path,"* `publish_tree` says *"mirror the paths; key semantics never enter."*

   ```yaml
   skills:
     path: skills
     kind: nested
     publish_tree: "~/.claude/skills"            # ONE target dir; no template vars
     ignore: ["*.tmp", ".DS_Store", "SKILL.md"]  # exclude the DERIVED index (Decision 4)
   ```

   - **No `index_filename`** — there is no in-store index (it's derived); that is the whole point.
   - **No template variables** — `publish_tree` is a single dir→dir mapping, not a per-leaf template. `{leaf}/{basename}/{key}/{ext}` are meaningless here; their presence is a **validation error** (derive-or-guard, ADR 0037/0039).

2. **`publish_tree` reuses the existing publish machinery; it only severs the key-enumeration step.** Mechanically it is `Nested#publish_subtree` (`nested.rb:72-89`) **lifted off the leaf and rooted at the entry base**, with the `resolver.enumerate` call deleted:

   ```
   base   = zones/<path>
   target = <publish_tree>
   for src in Dir.glob(base/**/*, FNM_DOTMATCH) where File.file?(src):
       rel = src - base
       skip if ignored?(rel)                          # ADR 0042 seam, reused
       dst = File.join(target, rel)                   # layout mirrored 1:1
       Ports::Publisher.publish(src, dst, store_root) # per-file sentinel (ADR 0046 D3)
       emit :file_published
   prune: managed-but-no-longer-produced files under target  # ADR 0046 D4 delete path
   ```

   - **Per-file sentinels** — identical to `publish_each` and `publish_to`; the `refuse_if_unmanaged` clobber guard (`publisher.rb:31-36`) stays meaningful per sibling.
   - **`ignore` (ADR 0042)** — reused unchanged. This makes `ignore` a *third* consumer of the seam (enumeration, whole-leaf publish, now tree mirror), further validating it as a shared filter.
   - **Mixed file types ride freely** — the mirror walks `**/*` by real path, not a format glob, so `*.md` + `scripts/*.py` + `*.json` all publish. (This is the concrete thing file-leaf `publish_each` cannot do.)

3. **Prune is whole-target, bounded only by the sentinel invariant.** `publish_each`'s prune is per-leaf and deliberately bounded (`prune_orphans`, `nested.rb:94`). `publish_tree` has no leaf, so its prune reconciles the **entire target tree**: any file under the target whose sentinel marks it textus-managed but which the current source no longer produces is deleted (file + sentinel). **Unmanaged files are never touched** (the inverse of the clobber guard) — a human file dropped into the target survives. This is a wider blast radius than `publish_each`; the sentinel invariant ("only ever delete files textus provably owns") remains the *sole* safety boundary, and as with ADR 0046 Decision 6 it reports rather than prompts (build stays automatable; `doctor` offers the dry-run pre-flight).

4. **The derived index and the sibling mirror are two cooperating entries over one target — and they must not fight over the index file.** The complete derive-path design composes:

   ```
   skilldef (structured, in-store)
     └─ #1 include_body → template
        derived entry  ── publish_to: "~/.claude/skills/my-skill/SKILL.md"   ← INDEX

   zones/skills/<skill>/{commands.md, references/*, scripts/*.py, …}
        nested entry   ── publish_tree: "~/.claude/skills"                    ← SIBLINGS
                          ignore: ["SKILL.md"]                               ← REQUIRED
   ```

   Because both write into `~/.claude/skills/<skill>/`, the `publish_tree` entry **must `ignore` the index filename**, or its whole-target prune (Decision 3) would delete the `SKILL.md` the `derived` entry just wrote (the `derived` entry's sentinel is the *derived* entry's, and the source set the tree walk produces never includes `SKILL.md`, so prune would classify it as orphaned-managed). The validator **requires** that a `publish_tree` entry whose target overlaps a derived entry's `publish_to` carries that index name in `ignore` — surfaced at validate/`doctor` time, never as a silent deletion. (This coordination cost is the strongest argument for the future unification in Open questions.)

5. **`publish_tree` requires `nested: true` and is pairwise-exclusive with `publish_to` and `publish_each`.** It joins the existing exclusivity rule (`validators/publish_each.rb:18`). An entry declares exactly one publish mode. `index_filename` + `publish_tree` together is a **validation error**: `index_filename` declares "a leaf is a directory anchored by an in-store index," which is precisely the premise `publish_tree` negates.

## Consequences

- **The store can own a multi-file artifact whose index is *derived*.** Combined with #132 item #1 (`include_body`), a structured skilldef renders `SKILL.md` via `publish_to` while its real sibling tree mirrors via `publish_tree` — closing the last gap in issue #132's derive path.
- **No `textus/N` wire change.** Publish is repo-local materialization; `publish_tree` adds a manifest key, not a protocol change. Per the `adr` runbook step 4, `SPEC.md` §4 gains the `publish_tree` semantics (subtree mirror, ignore, whole-target prune, per-file sentinel, the index-`ignore` requirement of Decision 4) at ship time; the *why* is here.
- **The publish surface grows from two keys to three.** Accepted because the third key expresses a capability the other two structurally cannot (key-less path mirror), not a restatement of an existing one. ADR 0046's "no third key" is amended, not contradicted: its rejection was scoped to the index-present case (see the supersession note appended to 0046).
- **Publish's delete path widens.** ADR 0046 gave publish its first prune (per-leaf). `publish_tree` prunes a whole target tree. The blast radius is larger but the boundary is unchanged — the sentinel invariant. The dedicated spec must prove: author a tree with two siblings, build, remove one sibling from the store, rebuild, assert the stale copy *and* its sentinel are gone while a hand-placed unmanaged file in the target survives; and assert a `publish_tree` whose target overlaps a derived `publish_to` without `ignore`-ing the index is rejected at validation (Decision 4).
- **`ignore` (ADR 0042) gains a third consumer**, confirming it as a general filter seam rather than enumeration-specific.
- **Opacity is enforced in every path, not just the Publisher** (added 0.43.0). "No keys" must hold in `doctor` and the resolver too, or a mirror carrying non-key-legal filenames (uppercase `SKILL.md`, `README`) trips `key.illegal` and red-gates commits. The resolved mode answers `Publish::Mode#keyless?` (true only for `Tree`); `doctor`'s `IllegalKeys` and `Resolver#enumerate_nested` consult it and skip key-walking a keyless mirror. The Publisher already honored opacity; this closes the two paths that still treated `publish_tree` files as enumerable.
- **`build` is unchanged in actor terms** — tree mirror + prune run inside `actor_for("build")` (ADR 0044); no new actor, no new capability.

## Alternatives considered

- **Make `index_filename` optional for directory-leaf `publish_each`; infer a leaf by directory depth/structure** (issue #132, #4 first option). Rejected: this is the "infer the unit from structure" fragility ADR 0046 Decision 2 and its Alternatives already rejected for the template string, now reintroduced at the enumeration level. It also reopens the keyspace question — a terminal directory with no index has no envelope, so what is its key? Deriving a leaf from depth is exactly the implicit magic textus avoids.
- **Coerce file-leaf `publish_each` into mirroring the siblings.** Rejected: it "almost works" only for a lowercase, markdown-only sibling set, and does so by (a) promoting every sibling to an addressable key (the pollution 0046 D1 rejected), (b) dropping mandated uppercase files like `README.md` via key-legality (`resolver.rb:101-106`), and (c) ignoring non-markdown files (`scripts/*.py`) because nested enumeration is format-scoped. Three model violations to fake a directory mirror.
- **Extend `publish_each` with a `tree: true` sub-flag instead of a new key.** Rejected: `publish_each` is defined by per-key fan-out to templated paths; a "no keys, no template, one target" mode under the same key would mean two incompatible semantics behind one name, decided by a flag — worse than a distinct key with a distinct contract. The names should track the axis (key-driven vs path-driven).
- **One sentinel per target directory** (instead of per file). Rejected for the same reason ADR 0046 D3 rejected it: it coarsens the clobber guard so a hand-added file inside the target could be silently clobbered or block the whole mirror. Per-file keeps the guard precise.
- **No prune; warn-only via `doctor`.** Rejected for the same reason as ADR 0046 D4/Alternatives: the explicit ask is a consumer tree faithful to the source, and a derived skill tree makes rename/remove drift routine. Whole-leaf *rename/removal* orphans remain a `doctor` concern (consistent with 0046 D7).
- **Leave it (native shape only).** Valid, and the recommended default for anyone who does not need to *derive* `SKILL.md`: ADR 0046 already closes ownership for natively-authored skills, and then `publish_tree`, item #1, and item #2b are all unnecessary. This ADR is **only** for the derive path; if the derive path is not pursued, do not build `publish_tree`.

## Open questions

- **Q1 — unify the derived index and the sibling mirror into one entry.** Decision 4 splits one artifact across a `derived` entry (`publish_to` the index) and a `nested` entry (`publish_tree` the siblings) that share a target and must coordinate via `ignore`. A single entry that declares both "derive the index here" and "mirror the siblings around it" would remove the coordination footgun and the two-sources-of-truth risk. Deferred: it is a larger model change; the two-entry composition is sufficient to unblock #132 and is fully guarded (Decision 4's validator). Revisit if the coordination proves error-prone in practice.
- **Q2 — transform/inject during publish (#132 item #2b).** Still open and orthogonal: injecting a shared partial into `SKILL.md` at publish time needs a new `transform_file` hook threaded through `publish_via` (not the `transform_rows` seam; see ADR 0046 Q2). `publish_tree` is byte-copy like all publish (ADR 0007). Note: #2b on top of natively-authored `SKILL.md` may deliver most of the derive path's value without `publish_tree` or item #1 at all — weigh before building this.
- **Q3 — `--adopt` bootstrap (#132 item #3).** First `publish_tree` over a pre-existing on-disk skill tree hits `refusing to clobber unmanaged file` (`publisher.rb:35`) per sibling. An explicit `--adopt` (write sentinels for pre-existing targets after one-time confirmation, gated through `actor_for("build")`) is the natural migration path for an existing tree. Complementary; its own ADR.
