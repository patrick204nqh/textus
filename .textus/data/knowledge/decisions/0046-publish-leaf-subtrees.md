# ADR 0046 — `publish_each` publishes a leaf's whole subtree; siblings are opaque attachments, never keys

**Date:** 2026-06-01
**Status:** Accepted · the "no third key" ruling is scoped to the index-*present* case by [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md)
**Touches:** [ADR 0007](./0007-envelope-data-class.md) (the build/publish split — publish is copy, not parse), [ADR 0042](./0042-native-ignore-patterns-for-entry-enumeration.md) (the shared `ignore` filter seam, evaluated above key-legality), [ADR 0044](./0044-system-actors-resolved-by-capability.md) (`build` runs as `actor_for("build")`).

> **Publish surface today (SPEC §4, §5.3).** Two mutually-exclusive keys, split on a real axis: `publish_to:` (a list of fixed repo paths — 1 stored file → N explicit destinations; leaf/derived/intake entries, `base.rb:82-101`) and `publish_each:` (one template — 1 *nested* entry → N leaves at derived paths; `nested.rb`, requires `nested: true`, `validators/publish_each.rb:15,18`). This ADR adds **no third key**: a multi-file artifact is a nested leaf, so it belongs to `publish_each`, and `publish_to` (single stored file → fixed paths) cannot express a tree anyway. Tree-vs-file is an *orthogonal sub-property* of the `publish_each` case, derived from `index_filename`.

## Context

A class of artifact we want the store to own is a **prose-heavy, multi-file unit**: a Claude Code Agent Skill is a directory —

```
zones/skills/my-skill/
  ├── SKILL.md       frontmatter + a large hand-authored body   ← the index
  ├── commands.md    sibling
  └── references/
        ├── foo.md   sibling
        └── bar.md   sibling
```

The store can model the directory today via a `nested` entry with `index_filename: SKILL.md`, and fan it out to a consumer path with `publish_each`. But publish sees **only the index file**.

`Resolver#enumerate_nested` globs `**/#{index_filename}` (`resolver.rb:75`) and keys each match by its *directory* (`resolver.rb:84`, `File.dirname`). With `index_filename: SKILL.md`, the glob matches `my-skill/SKILL.md` and nothing else — `commands.md` and `references/*` are never enumerated. `Nested#publish_via` (`nested.rb:40-66`) then copies the single `row[:path]` via `Ports::Publisher.publish`, which is `FileUtils.cp` (`publisher.rb:17`). The siblings are invisible to the manifest model and never reach the repo.

**The consequence:** a skill is a directory, and textus publishes one file of it. There is no way to publish a multi-file artifact tree as a unit. The author's only workaround is to cram the siblings into the index's frontmatter — abandoning the standard's "the file on disk is the editable unit."

The naive fix — glob `**/*` and make every file a key (`skills.my-skill.references.foo`) — is the wrong shape: `references/*` are not independently queryable store envelopes (frontmatter + body), promoting them pollutes the keyspace, and it breaks the key↔path bijection that `resolve` / `enumerate` rest on. The siblings are **payload**, not **entries**.

A separate, smaller asks (transform/inject *during* publish; an `--adopt` flag to bootstrap the sentinel over pre-existing files) are deliberately **out of scope** here — see Open questions. This ADR settles only the multi-file *unit* question, which is the actual blocker for owning this artifact class.

## Decision (proposed)

1. **The leaf directory is the unit; siblings are opaque attachments that never become keys.**
   Enumeration is **unchanged** — `**/#{index_filename}` still discovers leaves, and a leaf's key is still `File.dirname` of its index. A key still resolves to the index file (`resolver.rb:48-62`). The siblings ride along **at publish time only**; they are never enumerated, never addressable, never proposable. This is what keeps the bijection intact: we sidestep the data-model change by not promoting payload to entries.

2. **No new key — the publish *unit* is derived from the entry's shape, which `index_filename` already declares.**
   The leaf's shape is intrinsic to the entry, not the publish directive, so `publish_each` stays a single scalar template and publishes *whatever the leaf is*:

   ```yaml
   skills:
     path: skills
     kind: nested
     index_filename: SKILL.md                    # ← this already says "a leaf IS a directory"
     publish_each: "~/.claude/skills/{leaf}"     # → directory target; copies the whole leaf subtree
     ignore: ["*.tmp", ".DS_Store"]              # reuses the ADR 0042 ignore seam
   ```

   - **entry *without* `index_filename`** → a leaf is a *file* → `publish_each` names a file. **Unchanged** byte-for-byte from today.
   - **entry *with* `index_filename`** → a leaf is a *directory* → `publish_each` names a directory; `Nested#publish_via` walks the leaf directory (`File.dirname(index_path)`), applies the entry's existing `ignore` filter (`nested.rb:14`, `ignored?` — ADR 0042), and copies each surviving file to `<target_dir>/<rel>`, preserving in-leaf layout.

   The mode is taken from `index_filename`, **never inferred from the template string** (which can't distinguish a dir from an extensionless file) — so nothing is silently reinterpreted. This is derive-or-guard (ADR 0037/0039): the `{basename}`/`{ext}` vars (`nested.rb:36`) are meaningless for a directory target and their use in a directory-leaf template is a **validation error**; the validator **also rejects** (a) a directory-leaf template whose final path segment is the `index_filename` (the likely-mistaken `.../{leaf}/SKILL.md` shape that would otherwise copy the subtree into a dir literally named `SKILL.md/`), and (b) a final segment carrying any file extension (e.g. `.../{leaf}.md` or `.../{leaf}/foo.md`) — which would otherwise copy the subtree into a directory literally named `skill.md/`. Publish does not re-declare a shape the entry already owns.

3. **Per-file sentinels.** Each copied file gets its own sentinel via `SentinelStore` exactly as a single-file publish does today (`publisher.rb:18`). One sentinel per leaf-directory was considered and rejected: per-file keeps the `refuse_if_unmanaged` clobber guard (`publisher.rb:21-25`) meaningful for every sibling, and is consistent with the existing model. No change to `Ports::Publisher`'s contract — `publish_via` calls it once per file.

4. **Prune stale managed files on build.** Publish today never deletes, so a renamed/removed sibling would leave a stale copy in the consumer tree — and multi-file makes this drift routine (rename `references/foo.md → bar.md` and the old copy lingers). On each tree publish, after copying the current source set, textus prunes any file under the leaf's target whose **sentinel marks it as textus-managed but which the current source no longer produces**. Changed files are simply overwritten by the copy (status quo); orphaned-managed files are deleted (file + sentinel). **Unmanaged files — no sentinel — are never deleted** (the inverse of the clobber guard): a human file dropped into the consumer dir is left untouched. Pruning is scoped to the leaf currently being built.

5. **Shallowest index wins; leaves do not nest.** A `SKILL.md` appearing *inside* another leaf's subtree (e.g. `my-skill/references/SKILL.md`) is **payload of the parent leaf**, not a second leaf. Enumeration claims the shallowest index per branch and treats everything beneath it as that leaf's attachments. This removes the `**/#{index_filename}` double-match ambiguity and matches the artifact's real shape (a skill is not a tree of skills).

6. **Prune does not prompt; it reports.** `build` never blocks on a confirmation (it must stay automatable). Instead the build envelope grows the intended/applied prunes per leaf, and `doctor` offers a dry-run pre-flight ("these N managed files would be pruned"). The sentinel invariant — only ever delete files textus provably owns — is the safety boundary, not an interactive prompt. (Resolves former Q1.)

7. **Whole-leaf orphans are `doctor`'s job, not `build`'s.** Per-leaf prune (Decision 4) reconciles *within* a still-existing leaf. Renaming or deleting an entire leaf orphans its whole target directory, which a per-entry build won't revisit — reconciling that is a `doctor` drift check (consistent with its existing checks), keeping `build` per-entry and fast. `build` does not scan globally. (Resolves former Q3.)

## Consequences

- The store can own a multi-file artifact as a single addressable unit. The skill author keeps the standard shape — `SKILL.md` and its siblings are real files on disk — with no frontmatter-blob workaround.
- **No new manifest key and no `textus/N` wire change** — the publish unit is derived from the existing `index_filename`, and publish is repo-local materialization. Per the `adr` runbook step 4, `SPEC.md` §4 gets the directory-leaf `publish_each` semantics (subtree copy, ignore, prune, per-file sentinel) at ship time; the *why* is recorded here.
- **Publish gains a delete path** for the first time (prune). It is bounded by the sentinel invariant: textus only ever deletes files it provably owns. Worth a dedicated spec — author a leaf with two siblings, build, remove one sibling from the store, rebuild, assert the stale copy *and* its sentinel are gone while an unmanaged sibling placed by hand survives.
- `build` runs as `actor_for("build")` (ADR 0044); tree publish and its prune are part of that single capability — no new actor, no new capability.
- The `ignore` seam (ADR 0042) gains a second consumer (publish-tree filtering) beyond enumeration, validating it as a *shared* filter rather than an enumeration-only one.
- **Behaviour change (deliberate, accepted).** An entry with `index_filename` + `publish_each` whose leaf directories contain siblings previously published *only the index file*; it now publishes the whole subtree. This breaks **no correct usage** — the affected behaviour is either (a) the dropped-siblings defect this ADR fixes (the author wants the new output), or (b) a template that names the index file (`.../{leaf}/SKILL.md`), which the validator now **rejects loudly** with a fix-the-template message rather than silently copying the tree into a directory named after the index. Per derive-or-guard, the change is surfaced at validate/`doctor` time, never as a silently-different copy. Acceptable pre-1.0 (0.39.x); record in `CHANGELOG.md` as a breaking change with the one-line migration (drop the trailing index filename — or any file extension — from the directory-leaf template).

## Alternatives considered

- **Every file is an entry** (`**/*` → keys). Rejected: pollutes the keyspace with non-queryable payload, breaks the key↔path bijection, and makes `references/foo.md` proposable/guardable for no benefit. This is the heavy "data-model change" version; Decision 1 exists precisely to avoid it.
- **One sentinel per leaf directory.** Rejected (Decision 3): coarsens the clobber guard — a hand-added sibling inside a managed leaf dir could be silently clobbered or, conversely, block the whole leaf. Per-file keeps the guard precise.
- **No pruning; leave stale files, let `doctor` warn.** Rejected (Decision 4): the explicit ask was that build keep the consumer tree faithful to the source. Drift-by-default is the failure mode multi-file introduces; a warn-only posture pushes cleanup onto the human for the common rename case. (Whole-leaf *rename* orphans are still a doctor concern — see Q3.)
- **Infer dir-vs-file from the template string** (e.g. trailing `/`, or absence of `{basename}`/`{ext}`). Rejected: implicit and fragile — a `.../{leaf}` template can't be distinguished from an extensionless file. Deriving the mode from `index_filename` (Decision 2) is unambiguous, since the entry already declares whether a leaf is a directory.
- **A distinct `publish_tree` key** (a directory target separate from `publish_each`). Rejected: it adds a third top-level publish key crosscutting the existing two (`publish_to`, `publish_each`) to express what `index_filename` already determines. Deriving the mode keeps the surface at two keys (see the publish-surface note in the header). **Scope note (ADR 0047):** this rejection holds only while the index is *in-store* — `index_filename` then determines the unit. When the index is *derived* (absent from the store), there is no key to enumerate and `publish_each` has nothing to iterate; that case is genuinely distinct and is settled by [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md), which adds `publish_tree` for the index-absent path only.
- **Leave it (status quo).** Rejected: this is the load-bearing gap — without it the store cannot own the artifact class at all, and the alternatives (frontmatter blob, single-file-only) defeat the reason to manage skills in textus.

## Open questions

Deferred to their own ADRs; out of scope here (this ADR settles only the multi-file *unit*).

- **Q2 — transform/inject during publish.** Publish is byte-copy (ADR 0007); injecting a shared partial into `SKILL.md` at publish time would need a *new* hook event (e.g. `transform_file`) threaded through `publish_via` — it is **not** the existing `transform_rows` seam, which lives in `Projection` and which `publish_each` leaves never traverse. (If skills are authored consumer-shaped in the store, Q2 is not needed at all.)
- **Q4 — `--adopt` bootstrap.** First publish over pre-existing skill files hits `refusing to clobber unmanaged file` (`publisher.rb:25`) and currently forces a manual delete. An explicit `--adopt` (write the sentinel for a pre-existing target after one-time confirmation, gated through `actor_for("build")`) is the natural migration path for a *tree* of existing files. Complementary to this ADR.
