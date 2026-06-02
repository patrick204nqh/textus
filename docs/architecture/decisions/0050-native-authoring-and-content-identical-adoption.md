# ADR 0050 — Own multi-file artifacts by native in-store authoring; migrate by content-identical adoption

**Date:** 2026-06-02
**Status:** Accepted · native authoring now rides **`publish_tree`** alone — `publish_each` was removed by [ADR 0051](./0051-remove-publish-each.md) (the index-present `publish_each` references below are historical)
**Touches:** [ADR 0046](./0046-publish-leaf-subtrees.md) (`publish_each` whole-leaf subtree — the publish mechanism native authoring rides on), [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (`publish_tree` mirror), [ADR 0042](./0042-native-ignore-patterns-for-entry-enumeration.md) (the `ignore` seam), and the sentinel/clobber contract (`SPEC.md` §491, `ports/publisher.rb:36`). Resolves the *direction* of issue #132 (textus as a generator for prose-heavy, multi-file artifacts such as Agent Skills).

> **One sentence:** textus already publishes a multi-file artifact authored in its **native shape** (ADR 0046/0047) — the only thing standing between "I have skills on disk" and "textus owns them" is the clobber guard refusing a *byte-identical* first publish, so this ADR picks native authoring over a structured-derive stack and closes the migration gap by letting an identical publish **adopt** instead of refuse.

## Context

Issue #132 asks textus to own prose-heavy, multi-file artifacts (the motivating case: Claude Code **Agent Skills** — `SKILL.md` + `commands.md` + `references/*` + `scripts/*`). Its four sub-gaps split on one axis the issue itself names:

> *"if skills are authored in their native shape in the store, [whole-leaf publish] alone unblocks ownership — [`include_body`] and [publish-time transform] only matter if you want to **derive** `SKILL.md` from structured store data."*

So there are two ways to own the artifact, and they want very different amounts of machinery:

| Model | What the store holds | Publish path | Extra machinery needed |
|---|---|---|---|
| **Native authoring** | the artifact's real files (`SKILL.md` is hand-authored markdown) | ADR 0046 whole-leaf `publish_each` (or 0047 `publish_tree`) — already shipped | **none** for rendering |
| **Derive from structure** | a structured skilldef; `SKILL.md` is rendered | derived entry + sibling mirror | #1 `include_body`, maybe #2a publish-time transform, a 5th `IndexPlusTree` mode |

The derive model is the one the issue's open items (#1, #2a) and ADR 0049's Q2 (`IndexPlusTree`) build toward. But it is a large, mostly-**permanent** surface: a new manifest opt-in, a new hook event, and a new publish mode — justified only if you actually have structured source data that needs templating.

Native authoring needs **nothing new to render or publish** — ADR 0046/0047 already copy a leaf's whole subtree, layout-preserved, ignore-filtered, with per-file sentinels and prune-on-rebuild. The single friction is **migration**: real skills already exist on disk (at the very path textus would publish to), so the first publish trips the clobber guard:

```
ports/publisher.rb:36  refuse_if_unmanaged → raise "refusing to clobber unmanaged file"
```

The guard (`SPEC.md` §491) exists to protect a human-authored file textus did not create. But it refuses on **existence alone** — even when the target's bytes are *already identical* to the source about to be published (exactly the state migration produces: copy files into `zones/…`, publish them back to where they already live). The sentinel already records the target's `sha256` (`sentinel_store.rb` `write!`), so the guard *has* the information to tell "identical, nothing at risk" from "divergent human edit" — it just doesn't use it. The blanket refusal is broader than the guard's actual purpose.

## Decision

1. **textus owns prose-heavy, multi-file artifacts by native in-store authoring.** The artifact's real files live under `zones/<path>/…` in their consumer shape; ADR 0046 whole-leaf `publish_each` (index-present leaves) and ADR 0047 `publish_tree` (key-less mirror) publish them unchanged. No structured-skilldef indirection is introduced. This is the recommended and supported way to make textus the source of truth for Agent Skills.

2. **A content-identical publish adopts instead of refusing.** `Ports::Publisher.publish` adopts an unmanaged regular-file target — writes the sentinel and proceeds with the (no-op-content) copy — **iff** the target's bytes equal the source's. It still **refuses** when:
   - the unmanaged target's content **differs** from the source (a genuine human artifact — the guard's true job), or
   - the target is an unmanaged **symlink** (unchanged from today).

   This narrows `SPEC.md` §491 from *"refuses to clobber a destination that is not either missing or marked as managed"* to *"…not either missing, marked as managed, **or byte-identical to the source being published (adopted into management)**."* No new manifest key, CLI flag, hook event, wire field, or build-envelope field — an adopted file flows through the existing `published_leaves` path like any publish.

3. **Defer the derive stack.** Issue #132's #1 (`include_body`), #2a (publish-time transform/inject hook), and a future `IndexPlusTree` 5th publish mode (ADR 0049 Q2) are **explicitly not built here**. They are revisited only when a concrete structured-generation need appears — not on spec. ADR 0049 already made `IndexPlusTree` *cheap* to add later; that cheapness is the reason it can wait.

## Consequences

- **Native-authoring migration "just works."** Copy an existing skill tree into `zones/…` and publish: identical targets are adopted (sentinel written, file untouched), so a repo already carrying the skills onboards without a manual delete-then-publish dance and without a new flag to remember.
- **The guard gets *narrower and safer*, not weaker.** It now fires only on the genuinely dangerous state — an unmanaged target whose content **differs** from what textus would write. A coincidental byte-match is, by definition, not a human edit at risk. The blast radius of a bad publish shrinks.
- **No new permanent surface.** The change is ~3 lines in `refuse_if_unmanaged` reusing the `sha256` the sentinel already stores. Nothing is added to the manifest grammar, the `textus/3` wire contract, the hook catalog, or the build envelope — so there is nothing to deprecate if the derive model is chosen later.
- **`SPEC.md` §491 changes** (a normative safety-contract refinement). Per the `adr` runbook step 4, this ADR updates `SPEC.md`; it is the *why*, `SPEC.md` is the *what*. No protocol-version bump — publish is repo-local materialization, not a wire change.
- **Adoption is silent by default.** An adopted file is reported in `published_leaves` exactly like a normal publish; there is no separate "adopted" signal. If observability proves necessary, `doctor`/`status` is the place for it (see Open questions), not a new event.
- **The derive path stays open and cheap.** Choosing native authoring now forecloses nothing: ADR 0049's sum type makes `IndexPlusTree` a one-class addition, and #1/#2a remain well-scoped if a real generation case arrives.

## Alternatives considered

- **An explicit `--adopt` flag on build/publish (issue #132's #3 proposal).** Rejected as the primary mechanism. It is broader and *less* safe than content-match adoption: a blanket "adopt whatever is there" can silently overwrite a **divergent** human file (the exact thing the guard protects). It also adds CLI surface the user must remember to use for the common, safe case. A flag of this shape is better reserved as a *future* escape hatch for the **divergent** case only (see Open questions), and only once someone actually hits it.
- **Build the derive stack now (#1 `include_body` → #2a transform → `IndexPlusTree`).** Rejected for this issue. It is the right design *if* you want `SKILL.md` derived from structured data, but it is large, mostly-permanent surface justified only by a concrete need that does not yet exist. Native authoring delivers ownership today with zero new rendering machinery. Deferring is cheap precisely because ADR 0049 made the 5th mode cheap to add.
- **Leave the guard as-is; document delete-then-publish.** Rejected. The guard's blanket refusal is broader than its purpose, and the manual workaround is exactly the migration friction that blocks adopting textus for an existing skill repo — the practical thing #132 is about.
- **Adopt on content-match but emit a new `:file_adopted` event / `adopted:` envelope array.** Rejected for v1 as unnecessary surface. An adopted file already appears in `published_leaves`; a dedicated signal is a new contract for a marginal observability gain. Revisit via `doctor` if needed.

## Open questions

- **Q1 — a divergent-content override.** When an unmanaged target *differs* from the source, the guard still (correctly) refuses. If a real workflow needs "yes, overwrite my different file and manage it from now on," that is a deliberate, destructive action deserving an explicit, confirmed `--adopt`/`--force` escape hatch — distinct from the silent content-match adoption decided here. Deferred until a concrete case demands it.
- **Q2 — observability of silent adoption.** Adoption is invisible beyond the file gaining a sentinel. If "which files were adopted on this build?" becomes a real question (e.g. for migration audits), surface it through `doctor`/`status`, not a new build-time event — keeping the publish envelope and hook catalog stable.
- **Q3 — when does the derive model become worth it?** This ADR bets native authoring covers the motivating cases. The trigger to revisit #1/#2a/`IndexPlusTree` is a skill corpus that genuinely shares generated structure (many skills, shared partials, computed frontmatter) — at which point ADR 0049's sum type makes the addition incremental.
