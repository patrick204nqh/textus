# ADR 0103 — the root README is canon, published out

**Date:** 2026-06-08
**Status:** Accepted
**Refines:** [ADR 0081](./0081-docs-become-canon-published-out.md) (it made the documentation set canon authored under `.textus/zones/knowledge/` and published to `docs/` — this ADR applies the same rule to the one front-door doc 0081 left out: the repo-root `README.md`).
**Touches:** [ADR 0041](./0041-dogfood-textus-in-its-own-repo.md) (textus manages its own repo with textus — the root README was the last hand-maintained doc outside that model), [ADR 0094](./0094-source-data-publish-render.md) (its "publish renders clean content" rule is why the markdown README byte-copies with no `_meta` injected), [ADR 0070](./0070-content-addressed-build-artifacts.md) (the publish writes a content-addressed sentinel for `README.md` like any other target).

> **One sentence:** `docs/README.md` and `docs/architecture/README.md` are already canon authored under `.textus/zones/knowledge/` and published out (ADR 0081), but the repo-root `README.md` — the project's most-visible doc — was still hand-edited in place, so this ADR moves it to `.textus/zones/knowledge/readme.md` and publishes it verbatim to `README.md` (`publish: { to: README.md }`), making `reconcile` keep the front door fresh and `doctor` flag any hand-edit, with an invisible HTML-comment banner pointing editors at the source.

## Context

ADR 0081 established that documentation is **canon**: authored under `.textus/zones/knowledge/`, published to its consumer path, and never hand-edited at the destination. ADR 0097/0098 then split the derivable docs (produced) from the prose docs (authored canon + drift guard). The repo dogfoods textus on itself (ADR 0041): its `knowledge.docs-index` publishes to `docs/README.md`, `knowledge.architecture-index` to `docs/architecture/README.md`, the reference docs are produced, and the ADRs publish to `docs/architecture/decisions/`.

The one doc outside the model was the **repo-root `README.md`** — the GitHub landing page. It was a plain tracked file, hand-edited directly (most recently a manual refresh for the current zone/produce vocabulary). Being the front door, it is exactly the doc most worth keeping inside the trust model: drift there is the most visible.

This is verbatim-publish prose, not a projection — the README is ~90% bespoke narrative (the mermaid, the trust-quadrant ASCII, the prose). It is the same shape as `docs/README.md`, just published to repo root instead of under `docs/`.

## Decision

1. **Move the source into canon.** `git mv README.md .textus/zones/knowledge/readme.md`. Add the manifest entry:

   ```yaml
   - key: knowledge.readme
     path: knowledge/readme.md
     zone: knowledge
     schema: null
     owner: human:self
     kind: leaf
     publish:
       - { to: README.md }
   ```

   `reconcile` copies the source verbatim to the repo-root `README.md` (publish targets are repo-root-relative; markdown byte-copies as clean content, ADR 0094/0070). The published file stays tracked, so the gem's README and the GitHub landing page are unchanged byte-for-byte.

2. **Point editors at the source.** Prepend an HTML comment to the source — `<!-- Generated from .textus/zones/knowledge/readme.md — edit there, then run `textus reconcile`. Do not hand-edit README.md. -->`. It is invisible on the GitHub-rendered landing page (keeping it clean) but visible to anyone who opens the file to edit it. (The `docs/` READMEs use a visible blockquote banner; the front page earns the quieter form.)

3. **Make `reconcile` converge it.** `reconcile`'s produce scope selected only `derived? || publish_tree` — authored *leaf* `publish.to` entries (`docs/README.md`, the architecture index, and now the root README) were published *reactively on write* but never re-converged by the sweep, so a source edit without a write left the published copy stale. Add `|| !e.publish_to.empty?` to the scope; the produce engine already publishes a canon leaf through the same `publish_via` path, idempotently (writes only on content change). This closes a latent gap for the *existing* leaf docs too — landing this surfaced and fixed a stale `docs/architecture/README.md` (its source had been edited without a re-publish).

4. **Drift is caught, not assumed.** With (3), `README.md` joins the truly converged set: a hand-edit is clobbered on the next `reconcile` and caught by the CI "reconcile is a no-op" check — the same guarantee the produced docs have. The link-checker scans the published `README.md` (its `Dir["**/*.md"]` glob skips the dot-dir source), so root-relative links keep resolving.

## Consequences

- **The front door can't silently rot.** Editing flows through `.textus/zones/knowledge/readme.md` + `reconcile`, exactly like every other doc; `doctor` enforces it.
- **The dogfooding story is complete.** Every doc in the repo — root README included — is now textus-managed canon (ADR 0041/0081). The README *is* the demo.
- **One workflow change.** Contributors must edit the source, not `README.md`. The HTML-comment banner and `doctor`'s drift flag make the redirect discoverable; CONTRIBUTING/orientation already say "author upstream, never hand-edit the published copy."
- **No template, no projection.** This is a verbatim copy of authored prose. The README does *not* become a Mustache projection — that was rejected in ADR 0102 (90% bespoke prose; templating badges/mermaid is fragile for no benefit). The README may still *defer* to produced docs (e.g. the proposed produced `events.md`) by linking to them.

## Alternatives considered

- **Keep `README.md` hand-edited at root.** Rejected: it leaves the most-visible doc as the sole exception to ADR 0081, and the manual refresh that prompted this showed it drifts like any hand-maintained doc. Canon + publish is the established answer.
- **A visible "generated" blockquote banner (as `docs/README.md` uses).** Rejected for the *front page* specifically — a prominent "this file is generated" banner above the fold is noise for first-time visitors. The invisible HTML comment serves editors without taxing readers. (Internal `docs/` pages keep the visible banner; their audience is contributors.)
- **Make the README a produced projection.** Rejected (see ADR 0102): the README is overwhelmingly bespoke narrative; only small data tables are derivable, and those should be *linked* from produced docs, not inlined via a fragile whole-file template.
