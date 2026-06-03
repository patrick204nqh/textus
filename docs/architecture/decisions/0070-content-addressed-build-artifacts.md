# ADR 0070 — Built artifacts are content-addressed: no `generated_at` in the tracked output

**Date:** 2026-06-03
**Status:** Accepted
**Touches:** [ADR 0038](./0038-runtime-artifacts-under-run-and-layout.md) (the tracked/runtime boundary — this ADR removes the last volatile field from a *tracked* artifact, and re-opens whether **sentinels** belong on the runtime side; see Consequences + Open question), [ADR 0050](./0050-native-authoring-and-content-identical-adoption.md) (content-identical adoption — determinism is what makes adoption reliable across a clone), [ADR 0024](./0024-domain-purity-ports.md) (`FreshWithin` is a domain predicate). Surfaced by the #161 integration review (F1 — the "highest leverage" item).

> **One sentence:** textus stamped a fresh `generated_at` into every built artifact and then carried a whole `IdempotentWrite` module to *un*-stamp it on rebuild — so this ADR removes the timestamp from the tracked output entirely, making artifacts content-addressed (a rebuild on unchanged sources is a byte-for-byte no-op) and deleting the guard that existed only to reverse textus's own side effect.

## Context

Every built artifact carried a build timestamp in its tracked bytes: `_meta.generated_at` for json/yaml (via `Builder::InjectMeta`), `_meta.generated.at` for markdown (via `Renderer::Markdown`), and `generated_at` in the projection payload. Because that value changes on every build, two layers of compensation grew around it:

1. **`Builder::IdempotentWrite`** parsed the old and new bytes, extracted both timestamps, and rewrote the fresh one back to the prior value purely to decide "did anything *real* change?" A guard whose entire job is to reverse a side effect textus itself just produced is a sign the side effect is in the wrong place.
2. **The publish step churned regardless.** `Ports::Publisher.publish` does an unconditional `cp` to every `publish:` target, so each re-stamp produced a 1-line diff in the published copy (`AGENTS.md`, `CLAUDE.md`) on every `build`.

The #161 integration also observed `sentinel.drift` warnings after an ordinary `git` revert: because the timestamp lived inside the *tracked* artifact, a revert could restore one file but not its pair, and the sha-based drift check fired on the skew. Every symptom traces to one root: **a volatile field living inside a content-addressed, git-tracked artifact.**

A clarifying distinction the review surfaced: the `generated.at` that `Domain::Staleness::GeneratorCheck` reads (SPEC §5.2) is written by **external** build tools (`rake`, `just`, …) for `compute: { kind: external }` entries — textus does not produce it. textus's own builder only stamps `generated_at` on `compute: { kind: projection }` (textus-built) entries. The two sets are disjoint, so removing textus's stamp does not touch the external-generator staleness convention.

## Decision

1. **The builder stamps no `generated_at`.** `InjectMeta` injects only deterministic provenance (`from`/`reduce`/`template`); `Renderer::Markdown`'s frontmatter carries only `generated.from`; `Projection#run`'s payload drops `generated_at`. A built artifact is now a pure function of its sources, template, and manifest — content-addressed.

2. **Delete `Builder::IdempotentWrite`.** With deterministic output, idempotency is plain byte-equality: `write_if_changed` skips the write iff the new bytes equal the on-disk bytes, for every format. No timestamp extraction, no rewrite, no `BadFrontmatter` rescue.

3. **`FreshWithin` no longer falls back to `generated_at`.** Its write-timestamp chain is `checked_at || last_fetched_at`. Fetch-freshness is a fetch concept; leaning on build-generation time conflated two clocks, and that field no longer exists in the artifact anyway.

4. **SPEC.md updated** (per the `adr` runbook): the `_meta` injected-key order drops `generated_at` (§5.5); the projection-build fixture (§13) states the output is content-addressed. The §5.2 *external* `generated.at` convention is unchanged.

## Consequences

- **Rebuilds are no-ops; publish `cp` is a content no-op; the `sentinel.drift` warning class collapses.** A deterministic artifact reproduces byte-for-byte, so `build` writes nothing when sources are unchanged, the published copy's bytes don't move, and a `git` revert restores bytes whose sha still matches the sentinel. "Is this diff real?" is answered by the diff itself.
- **`IdempotentWrite` and its tests are gone** — less surface, one fewer parse-and-rewrite path, no format-specific timestamp dig.
- **One-time churn on upgrade.** The first `build` after this change rewrites each artifact once to drop the timestamp line (and refreshes its sentinel sha); steady state is silent thereafter. The repo's own dogfooded artifacts are regenerated in the same commit.
- **Determinism is the precondition that makes ADR 0050 adoption reliable.** A freshly-cloned, textus-managed file now equals a fresh build byte-for-byte, so content-identical adoption always succeeds for an unmodified managed file — which in turn makes it *safe* to treat sentinels as regenerable runtime state rather than tracked source (see Open question).
- **No protocol bump.** This narrows what the builder writes, not the wire contract; `textus/3` is unchanged.

## Open question

- **Should sentinels move to the runtime side (`.run/`, git-ignored)?** ADR 0038 classified `sentinels/` as `:config` ("tracked deliberately"), but a sentinel is machine-generated (the published target's sha), not authored source — it was bucketed with `manifest.yaml`/`schemas/` more by location than by nature. Tracking it was also partly *forced*: before this ADR, a clone's `AGENTS.md` could differ from a fresh build by exactly the timestamp, so adoption would fail and the clobber guard refuse — tracking the sentinel papered over that. Determinism removes that constraint: a fresh build re-adopts the unmodified managed file and rewrites the sentinel. So git-ignoring sentinels (relocating them under `.run/sentinels/`, superseding ADR 0038's sentinel classification) is now *safe* and would kill the tracked-sentinel churn outright. It is deliberately **scoped out of this ADR** — it touches the publish/adopt/doctor paths and `git rm --cache`s currently-tracked files, and warrants its own diff — but this ADR is the enabler and records the direction.

## Alternatives considered

- **Keep `generated_at`, keep `IdempotentWrite`.** The status quo. Rejected: a guard that exists solely to undo textus's own stamp is accidental complexity, and it never covered the publish `cp` or the revert-skew drift — the timestamp-in-tracked-artifact root cause defeats it from two directions.
- **Move `generated_at` into a git-ignored build-state sidecar under `.run/` (key → {generated_at, content_sha}).** Considered as the home for the displaced timestamp. Rejected as unnecessary: the only in-tree readers were `IdempotentWrite` (deleted — byte-equality replaces it) and `FreshWithin`'s fallback (dropped). `GeneratorCheck` reads the *external* tools' `generated.at`, not textus's. With no reader left, a sidecar would store a value nothing consumes.
- **Stamp `generated_at` only when content changes.** Rejected: it still puts a volatile field in the tracked artifact (so the cp still churns when content does change for unrelated reasons) and keeps the parse-old-bytes machinery. Content-addressing is the simpler invariant.
