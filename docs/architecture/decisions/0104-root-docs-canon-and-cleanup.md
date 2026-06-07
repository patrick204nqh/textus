# ADR 0104 — finish the root-doc canon move (CONTRIBUTING + SECURITY), clean up the drift

**Date:** 2026-06-08
**Status:** Accepted
**Refines:** [ADR 0103](./0103-root-readme-is-canon.md) (it brought the repo-root `README.md` under canon-publish; this ADR applies the same rule to the two remaining hand-edited front-door docs that carry drift-prone facts — `CONTRIBUTING.md` and `SECURITY.md` — and stops there).
**Touches:** [ADR 0081](./0081-docs-become-canon-published-out.md) (docs are canon authored under `.textus/zones/knowledge/` and published out — the model these two docs join), [ADR 0098](./0098-docs-ssot-cleanup.md) (its produce-vs-guard SSoT framing is the lens used here; this is more of the same DRY/SOLID cleanup), [ADR 0087](./0087-fold-build-into-reconcile.md) (`build` folded into `reconcile` — the stale `textus build` references this ADR clears were left behind by that fold), [ADR 0041](./0041-dogfood-textus-in-its-own-repo.md) (textus manages its own repo with textus — these were among the last hand-maintained docs outside that model).

> **One sentence:** ADR 0103 moved the repo-root `README.md` into canon but left the other hand-edited front-door docs out, so this ADR moves `CONTRIBUTING.md` and `SECURITY.md` to `.textus/zones/knowledge/` published verbatim back to root (same `publish: { to: <root path> }` pattern, with an invisible HTML-comment editor banner), and — because the move forces a read of each doc against the live contract — fixes two live drifts it surfaced (a stale `textus build` in the orientation template's top comment, shipping into `AGENTS.md`; a stale `build` verb in `SECURITY.md`'s role-gate scope list), de-duplicates the PR checklist (CONTRIBUTING now *defers* the mechanical gate to the single-owner PR template instead of restating it), and restores the curated ADR index, which had silently fallen five rows behind (0099–0103); it deliberately leaves `CODE_OF_CONDUCT.md`, `SPEC.md`, and `CHANGELOG.md` out, because canon-publishing them is ceremony for no SSoT gain.

## Context

ADR 0081 made every committed `docs/` file canon — authored under `.textus/zones/knowledge/` and published to its consumer path, never hand-edited at the destination. ADR 0103 closed the most-visible remaining gap by bringing the repo-root `README.md` into the same model.

That left a short tail of hand-edited tracked docs at the repo root: `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `SPEC.md`, `CHANGELOG.md`, and `.github/PULL_REQUEST_TEMPLATE.md`. A review of these through the ADR 0098 lens (produce where derivable, guard where prose embeds facts, otherwise canon-publish authored prose) found that they do **not** all earn the same treatment, and that two of them carried live drift:

1. **`CONTRIBUTING.md` and `SECURITY.md` are drift-prone prose.** Both are bespoke narrative (like the README — not projections), but both embed machine facts that rot: the test/hook commands and "sources of truth" list in CONTRIBUTING, and the role-gated verb list in SECURITY. They are the exact shape ADR 0103 handled.
2. **A stale `textus build` in the orientation template.** `.textus/templates/orientation.mustache`'s top HTML comment told editors to "edit the source … and run `textus build`" — but `build` was folded into `reconcile` (ADR 0087), and the template's own lower banner already says `reconcile`. The template produces both `CLAUDE.md` and `AGENTS.md`, so the stale instruction shipped into `AGENTS.md`.
3. **A stale `build` verb in `SECURITY.md`.** Its in-scope list cited "role-gate bypass on `put`, `delete`, `mv`, `accept`, or `build`" — `build` no longer exists, and `delete`/`mv` are loose generalizations of the real `key_delete`/`key_mv`/`zone_mv` verbs. The list hand-mirrors the contract with nothing stopping it from drifting (it already had).
4. **A duplicated PR checklist (DRY).** The pre-PR gate (tests · SPEC · CHANGELOG · rubocop · rspec) lived in **two** hand-maintained places — `CONTRIBUTING.md`'s "Commit and PR style" and `.github/PULL_REQUEST_TEMPLATE.md`'s checklist — free to drift apart.
5. **The curated ADR index had fallen behind.** `decisions/README.md` (the annotated reading guide, per ADR 0098) stopped at 0098; ADRs 0099–0103 had landed without their index rows (the `adr` runbook's "add index row" step was skipped). The produced `adr-log.md` status board still covered them, so CI did not catch it — but the *reading guide* drifted.

## Decision

1. **Move CONTRIBUTING + SECURITY into canon.** `git mv` each to `.textus/zones/knowledge/{contributing,security}.md` and add the manifest leaf entries:

   ```yaml
   - key: knowledge.contributing
     path: knowledge/contributing.md
     zone: knowledge
     schema: null
     owner: human:self
     kind: leaf
     publish:
       - { to: CONTRIBUTING.md }
   - key: knowledge.security
     path: knowledge/security.md
     zone: knowledge
     schema: null
     owner: human:self
     kind: leaf
     publish:
       - { to: SECURITY.md }
   ```

   `reconcile` copies each source verbatim to its repo-root path (markdown byte-copies as clean content, ADR 0094/0070; re-converged by the leaf-publish scope ADR 0103 added). Each source gets the invisible HTML-comment banner — `<!-- Generated from … — edit there, then run \`textus reconcile\`. Do not hand-edit … -->` — matching the README's quiet form.

2. **Fix the orientation-template drift.** Change the top comment in `orientation.mustache` from `textus build` to `textus reconcile`. This converges `AGENTS.md` on the next `reconcile`.

3. **Fix and de-couple the SECURITY verb list.** Drop the stale `build`; rewrite the bullet to name the gated write verbs by their real names and *defer to the produced contract* — "(`put`, `key_delete`, `key_mv`, `zone_mv`, `accept`, `reject`, … — see `docs/reference/verbs.md` for the current contract)". The doc now points at the SSoT instead of hand-copying it. **No conformance guard is added** for this list (unlike `events`/`zones`/`mcp`): SECURITY's enumeration is illustrative prose, not a strict 1:1 projection, so a token guard would be fragile and noisy — deferring to `verbs.md` is the proportionate fix (the same YAGNI call ADR 0098 made about not adding a render-logic layer).

4. **De-duplicate the PR checklist.** `CONTRIBUTING.md` stops restating the mechanical gate; its "Commit and PR style" now says the **PR template's checklist is the gate** (and keeps the prose guidance the template can't carry — conventional prefixes, one logical change per PR, name the cost). The PR template is the single owner of the checkbox attestation.

5. **Restore the curated index.** Add reading-guide rows 0099–0104 to `decisions/README.md`, bringing it level with the ADR set again.

6. **Stop here.** `CODE_OF_CONDUCT.md` (inert Contributor Covenant boilerplate, externally versioned, zero embedded facts), `SPEC.md` (it *is* a source of truth — authored, not derived; sourcing it from elsewhere would invert the dependency), and `CHANGELOG.md` (append-only, partly release-tool-managed, a different lifecycle) stay as plain tracked files. Canon-publishing them buys no single-sourcing.

7. **No `SPEC.md` change.** Repo-local materialization and doc moves; no wire-contract change.

## Consequences

- **The drift-prone front-door docs can't silently rot.** Editing CONTRIBUTING/SECURITY flows through the store + `reconcile`, exactly like the README and all of `docs/`; `doctor` flags a hand-edit and the CI no-op gate catches it.
- **Two live wrong instructions are gone** — `AGENTS.md` no longer tells agents to run a removed verb, and SECURITY no longer advertises a gate on a verb that doesn't exist.
- **One owner for the PR gate.** The checklist lives in the PR template; CONTRIBUTING explains the *why* and links. No two-copy drift.
- **The reading guide is current** — and the gap exposed a process smell: the `adr` runbook's manual "add index row" step is skippable with no CI backstop. Left as-is for now (the board is the status SSoT); a guard asserting the curated index covers every ADR is a reasonable future follow-on, not taken here.
- **The dogfooding tail is short and intentional.** Every drift-prone doc is now textus-managed canon; the three left out are left out *on purpose*, with the reason recorded — not by omission.

## Alternatives considered

- **Canon-publish everything, including CODE_OF_CONDUCT / SPEC / CHANGELOG (full dogfooding purity).** Rejected: the Covenant is inert boilerplate (no facts to drift), `SPEC.md` is itself a SSoT (don't source a source-of-truth from elsewhere), and the CHANGELOG has a distinct append/release lifecycle. Moving them adds a banner and a manifest row for zero single-sourcing benefit — ceremony, not DRY. ADR 0041 dogfooding is served by managing what *drifts*, not by maximizing file count under `.textus/`.
- **Add a conformance guard for SECURITY's verb list (mirror the events/zones/mcp guards).** Rejected: those docs carry genuine 1:1 projection *tables*; SECURITY's list is illustrative prose mixing real verbs with families (`delete`/`mv`). A token-exact guard would force machine spellings into security prose or flag legitimate generalizations. Deferring to `verbs.md` removes the duplication without the fragile guard.
- **Move the PR template into canon too.** Rejected as out of proportion: GitHub reads it from `.github/PULL_REQUEST_TEMPLATE.md`, and once CONTRIBUTING defers to it the duplication is already gone. It is not drift-prone as the sole owner; a banner + manifest row earns nothing.
- **Leave CONTRIBUTING/SECURITY hand-edited at root.** Rejected: they are the same shape as the README (bespoke prose embedding facts that drift), and the two stale `build` references are proof they drift like any hand-maintained doc. ADR 0103 already settled that canon + publish is the answer for front-door prose.
