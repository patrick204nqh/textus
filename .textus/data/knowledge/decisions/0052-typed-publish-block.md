# ADR 0052 — Fold `publish_to`/`publish_tree` into one typed `publish:` block

**Date:** 2026-06-02
**Status:** Accepted (ships 0.43.0)
**Touches:** [ADR 0049](./0049-publish-modes-as-sum-type.md) (the internal `Publish::*` sum type this surface now mirrors — unchanged by this ADR), [ADR 0051](./0051-remove-publish-each.md) (collapsed publish to two modes, making a clean pair possible; this is its option-b *namespace* without the third mode), [ADR 0046](./0046-publish-leaf-subtrees.md) / [ADR 0047](./0047-publish-tree-keyless-subtree-mirror.md) (introduced `publish_to`-family and `publish_tree` — the two keys folded here).

> **One sentence:** after ADR 0051 left exactly two publish modes, the two top-level keys `publish_to:` and `publish_tree:` become one typed `publish:` block (`to:` xor `tree:`) so the manifest surface mirrors the ADR 0049 internal sum type and a future third mode gets a namespace instead of a third top-level key — a deliberately *ergonomic* change, not a structural-correctness one.

## Context

ADR 0049 re-cut the publish internals into a resolved sum type (`None` / `ToPaths` / `Tree`, plus the now-removed `Each*`). ADR 0051 removed `publish_each`, leaving the external surface at two top-level keys:

| Key | Value | Mode |
|---|---|---|
| `publish_to:` | list of repo paths | `ToPaths` — 1 stored file → N fixed paths |
| `publish_tree:` | one directory | `Tree` — whole entry subtree → 1 dir, keyless |

Two flat sibling keys for what is internally a sum type is a mild surface smell: nothing groups them, exclusivity reads as two unrelated optional keys rather than "pick one publish mode," and a third mode (the deferred ADR 0051 option-b / ADR 0049 Q2 `IndexPlusTree`) would add a *third* top-level key crosscutting the first two.

This was weighed and explicitly **not** done as a *rename* (`publish_file`/`publish_dir`): that pairing forces both modes onto a single file-vs-dir axis, which mischaracterises `publish_to` (its defining trait is the **list of N destinations**, not its file-ness) and drops the meaning `tree` carries over `dir` (recursive mirror, layout preserved). The namespace, not a rename, is the right grouping.

## Decision

Replace the two top-level keys with one typed `publish:` block. **Breaking change, no backward compatibility** — a manifest using flat `publish_to:`/`publish_tree:` fails at load with a migration-pointing error.

```yaml
publish:
  to: [CLAUDE.md, .ai/instructions.md]   # ToPaths — file fan-out
# xor
publish:
  tree: skills                           # Tree — subtree mirror
```

1. **Surface-only.** The ADR 0049 sum type and every mode (`ToPaths`, `Tree`, `None`), `Derived#publish_via`, `Write::Publish`, the `:file_published` event, the `{ built:, published_leaves:, pruned: }` envelope, and the internal `entry.publish_to` (Array) / `entry.publish_tree` (String) readers are **unchanged**. The parser sources those readers from the block — `publish_to ← publish.to`, `publish_tree ← publish.tree` — so the change is concentrated at the YAML→entry boundary.

2. **Exclusivity stays a guard, honestly.** A `publish:` hash can carry both `to:` and `tree:`, so this does **not** make "exactly one mode" structural. `Publish.resolve`'s single mutual-exclusivity check (ADR 0049) remains the one enforcement point; only its message changes (`publish.to and publish.tree are mutually exclusive`). The win is grouping and extensibility, not a new invariant — recorded plainly so the next reader does not over-credit it.

3. **Fail loudly at load.** `Schema` drops `publish_to`/`publish_tree` from the allowed entry keys (so they are rejected) and intercepts each with a migration message (`publish_to was replaced by the publish: block in 0.43.0 (ADR 0052) — use publish: { to: [...] }`, and the `tree` analogue). `Schema` also validates the block's shape: `publish` must be a Hash whose only keys are `to`/`tree`. `publish.tree` still requires `nested: true` (validators/publish.rb).

4. **One key.** `ENTRY_KEYS` gains `publish` and loses the two flat keys; a new `PUBLISH_KEYS = %w[to tree]` bounds the block. Per the `adr` runbook step 4, `SPEC.md` §4/§5.3 are updated in the same change.

## Consequences

- **The manifest surface mirrors the code.** One `publish:` key resolves to one `Publish::*` mode; the YAML now reads like the sum type it has been internally since ADR 0049.
- **A third mode has a home.** ADR 0051 option-b (lift `index_filename ⊥ publish_tree` so enumeration and publish compose) or ADR 0049 Q2 `IndexPlusTree` becomes a new sub-key under `publish:`, not a third top-level key — which is the whole reason to pay the break now rather than after a third key already shipped flat.
- **Breaking change on the workhorse.** `publish_to` is the only mode with real usage (dogfood, examples, every derived/intake entry). Migration is mechanical and surfaced at load with the exact replacement; pre-1.0 and consistent with the `publish_each` break one version prior. Recorded in `CHANGELOG.md`.
- **No correctness gain — stated outright.** Exclusivity is still a runtime guard; this is grouping and extensibility only. A reader expecting "both can't be set anymore" would be wrong, so the ADR and the resolver comment say so.
- **Rollback is a single-commit revert.** Surface-only; nothing internal entangles.

## Alternatives considered

- **Rename to `publish_file`/`publish_dir`.** Rejected: forces both modes onto a file-vs-dir axis that hides `publish_to`'s list-of-N-destinations semantics and `tree`'s recursive-mirror meaning; same blast radius as the block for less clarity.
- **Tagged union `publish: { mode: tree, target: … }`.** Rejected: would make exclusivity structural, but `target`'s type changes per mode (list vs string) and the discriminator is noise; `{ to: } | { tree: }` is cleaner and the residual guard is one line.
- **Dual-support (accept the block *and* the flat keys, deprecate later).** Rejected: textus does clean pre-1.0 breaks (cf. `publish_each`); carrying two code paths and a deprecation window buys little for a single-maintainer store.
- **Defer until a third mode actually returns.** The honest minimal option — the internal cleanup is already done and two flat keys are fine. Rejected *here* only because doing it now means one break instead of two (the third key never ships flat) and the maintainer accepted the breaking change; recorded as the considered-cheaper path not taken.
- **Leave the two flat keys (status quo).** Valid; the smell is mild. Rejected for the same one-break-not-two reason, with eyes open that the gain is ergonomic.
