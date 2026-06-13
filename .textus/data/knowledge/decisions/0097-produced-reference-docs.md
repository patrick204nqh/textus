# ADR 0097 — Reference docs become produced (projected/introspected, published out)

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0081](./0081-docs-become-canon-published-out.md) (made every committed `docs/` file canon prose, authored under `.textus/zones/knowledge/` and published verbatim — this ADR promotes the *machine-derivable* reference surfaces from hand-authored prose to **produced** entries while leaving the narrative docs exactly as 0081 left them), [ADR 0094](./0094-source-data-publish-render.md)/[ADR 0095](./0095-collapse-produced-kind.md) (the `source` produces data → `publish` renders split, and the single `produced` kind — this ADR is the first use of that machinery for *docs* rather than configs).
**Touches:** [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (its keyless `publish_tree` guarantee is preserved on the public surface; an opt-in `include_keyless` is added so projections may read keyless trees as *source* data), [ADR 0070](./0070-content-addressed-build-artifacts.md) (byte-stable idempotence holds — the produced docs are deterministic), [ADR 0093](./0093-source-retention-over-one-reconcile-engine.md) (these entries converge through the one `reconcile`/`Produce` engine like any other produced entry).

> **One sentence:** the reference docs that have a machine source of truth — the verb list, the schema/manifest reference, and the ADR log — graduate from hand-authored canon (ADR 0081) to `kind: produced` entries whose bytes `reconcile` makes from upstream (`from: handler` introspecting the live registry for verbs/schema; `from: project` over the ADR files for the log) and publishes to `docs/reference/`, a CI check fails the build when a `reconcile` would change a committed file, and the orientation (`CLAUDE.md`/`AGENTS.md`) is updated to tell agents to author upstream and never hand-edit the generated docs.

## Context

ADR 0081 made every committed `docs/` file canon: owned, attributed, drift-guarded, published verbatim from `.textus/zones/knowledge/`. That fixed *ownership* but not *toil* — the reference surfaces that document textus's own behavior (the CLI verb list, the schema/manifest grammar, the ADR log) are retyped by hand and drift the moment the code or the ADR set changes.

ADRs 0093–0095 had meanwhile built exactly the machinery to fix this: a `kind: produced` entry whose `source:` produces data (`from: project` over store entries, or `from: handler` via a registered Ruby hook) and whose `publish:` list renders that data — verbatim or through a template — to target paths, all converged by `reconcile`. It already drives `CLAUDE.md`, `AGENTS.md`, `.mcp.json`. This ADR extends it from generated *config* to generated *reference docs*.

One honesty constraint shaped the scope: **textus observes its own store, not your code.** Code lives outside the store's dependency graph, so "edit a verb → docs auto-regenerate" is not achievable for code-sourced docs — they refresh when `reconcile` runs, and a CI gate guarantees that happens before stale docs land. Only the ADR log, projected from the `knowledge.decisions` canon entries, is genuinely store-reactive.

Two premises from the original design were corrected during implementation:

1. `docs/architecture/README.md` is a hand-written **architecture overview** (layers, ports, paths), not an ADR table — converting it would destroy narrative prose. It stays hand-authored.
2. The real ADR log index, `docs/architecture/decisions/README.md`, is **curated**: its "Decision" column is a short hand-written description (not the ADR title), it pre-registers roadmap rows for unwritten ADRs, and it carries intro prose + a status legend. It is not byte-derivable, so it stays hand-authored too. Instead this ADR adds a **new** mechanically-generated `docs/reference/adr-log.md`.

## Decision

1. **Three reference surfaces become `kind: produced` entries in the `artifacts` (machine) zone** — produced entries are written by `reconcile` (capability `machine→reconcile`); a `canon` zone grants only `author`, so produced docs cannot live there.
   - `artifacts.derived.verbs` — `from: handler` (`verbs`); introspects the live `CLI::Verb` registry + Dispatcher contract → `docs/reference/verbs.md`.
   - `artifacts.derived.schema` — `from: handler` (`schema`); introspects the live schema cache (`Schemas#by_name`), emitting one field table per schema (type/required/maintained_by) → `docs/reference/schema.md`.
   - `artifacts.derived.adr-log` — `from: project` over `knowledge.decisions`, reshaped by the `adr_index_reducer` transform → `docs/reference/adr-log.md`. Number is taken from the filename (`NNNN-slug`); title/date/status are parsed from each ADR's markdown headers; relative links in the status text are flattened to label text so they don't break when rendered at `docs/reference/`.

2. **Source of truth is the live code registry, not `SPEC.md`.** The verb/schema docs introspect the running tool, so they always match its actual behavior. A spec-vs-code divergence is a separate concern, deliberately not folded in.

3. **Projections may read keyless `publish_tree` entries as source data.** `knowledge.decisions` is a keyless tree (ADR 0047): its files are never addressable keys on the public `list` surface. `Resolver#enumerate` gains an opt-in `include_keyless:` (default `false`), used only by the projection lister in `Write::DataBuilder`, so a `from: project` select can read those files as source without exposing them as store keys. ADR 0047's guarantee is unchanged on the public surface.

4. **The tree-mirror prune is told to spare the produced files.** `docs/reference/` is mirrored by the `knowledge.reference` nested entry, whose prune deletes the whole dir on rebuild but honors `ignore:`; it declares `ignore: ["**/verbs.md", "**/schema.md", "**/adr-log.md"]`. The `publish_tree_index_overlap` doctor check enforces this.

5. **A CI `docs freshness` job fails when `reconcile` is not a no-op.** Because code edits don't auto-trigger reconcile, CI runs `reconcile` and fails if any committed file changed — the same ergonomics as a "regenerate me" gate.

6. **The orientation teaches the rule.** `CLAUDE.md`/`AGENTS.md` (via `orientation.mustache`) now state that the three reference docs are generated — author upstream (the verb/schema code, or add an ADR) and run `reconcile`; never hand-edit them, as a hand-edit is clobbered on the next reconcile and flagged by `doctor`.

7. **No `SPEC.md` change.** Like ADR 0081, this is repo-local materialization: no wire field, hook event, or build-envelope field changes. The `include_keyless` option is an internal read-path seam, not part of the protocol.

## Consequences

- **Three reference surfaces stop drifting** — they are made from the source of truth, not retyped.
- **The ADR log is always complete and fresh** — every ADR (incl. legacy headers without the "ADR" prefix and the malformed 0001 heading) appears, because the number comes from the filename.
- **CI guarantees freshness** for the code-sourced docs; drift is a red PR.
- **Agents are told the rule up front**, so the new producedness is discoverable, not a trap.
- **A small read-path seam now exists** (`include_keyless`) that future projections over keyless trees can reuse.
- **Narrative stays human** — the architecture overview and the curated ADR decisions log are deliberately untouched; this ADR does not pretend prose is mechanically derivable.

## Alternatives considered

- **Convert `docs/architecture/README.md` to a produced ADR table.** Rejected — it is an architecture overview, not an ADR list; producing over it would delete hand-written prose.
- **Produce the curated `decisions/README.md` byte-for-byte.** Rejected — its "Decision" column is curated, it carries roadmap rows for unwritten ADRs, and it has hand-authored prose; it is not derivable without losing the curation. An additive `docs/reference/adr-log.md` gives an always-fresh mechanical listing without fighting the curated index.
- **Project verb/schema from `SPEC.md`.** Rejected for now — it would require a machine-parseable `SPEC.md` and would hide spec-vs-code divergence in the docs. Introspecting the live registry keeps the docs honest about what the tool does.
- **An LLM transform to also generate the narrative prose.** Rejected — non-deterministic output breaks the byte-stable idempotence invariant (ADR 0070) and the CI no-op gate. Narrative stays hand-authored.
