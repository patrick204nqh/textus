# ADR 0082 — Normalize the key-verb family stem (`key_mv`/`key_delete`) and remove the `migrate` orchestrator

**Date:** 2026-06-04
**Status:** Accepted
**Refines:** [ADR 0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) (added single-key `mv`/`delete` as the MCP cousins of the bulk `key_mv_prefix`/`key_delete_prefix` — this ADR completes that pairing by giving all four a shared `key_` stem), [ADR 0058](./0058-one-verb-name-across-surfaces.md) (one verb name across CLI/MCP/Ruby — the discipline this rename keeps, since the CLI leaf `key mv`/`key delete` is unchanged while the wire/verb name gains the stem).
**Touches:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP catalog is derived from the verb contracts; removing `migrate` shrinks it and renaming changes two tool ids — the reconciliation guard enforces the new surface), [ADR 0031](./0031-unified-guard.md) (the guard transition vocabulary keyed by verb symbol — `mv`/`delete` become `key_mv`/`key_delete`), [ADR 0071](./0071-dry-run-is-opt-in.md) (the bulk verbs keep their `dry_run` preview), the audit-log verb-string contract (SPEC §11) and the `:entry_renamed` hook event (SPEC §16).

> **One sentence:** textus's key-mutation surface names the same operation four inconsistent ways — single-key `mv`/`delete` carry no object prefix, bulk `key_mv_prefix`/`key_delete_prefix` do, and `migrate` is a non-transactional YAML orchestrator whose every op is already individually callable; this ADR removes `migrate` and renames `mv`→`key_mv` / `delete`→`key_delete` **everywhere the token is load-bearing** (verb/tool id, guard transition, audit verb string, hook payload, manifest `guard:` key) so the family reads `key_mv` / `key_mv_prefix` / `key_delete` / `key_delete_prefix`, with `zone_mv` left alone as the distinct zone-scoped operation — a breaking manifest + audit + MCP-surface change.

## Context

The verb surface for mutating keys grew in two layers (ADR 0060 added the single-key cousins after the bulk ops already existed), and the names never reconciled. Three frictions, all at the **wire/verb-name layer** — the CLI is already clean (`key {mv,delete,mv-prefix,delete-prefix}` is a tidy noun-grouped grammar):

1. **The object prefix appears for bulk but vanishes for single.** `mv` / `delete` carry no `key_` stem; `key_mv_prefix` / `key_delete_prefix` do. In the derived MCP catalog (ADR 0039) `mv` and `key_mv_prefix` don't read as the same family — the single/bulk relationship is invisible.

2. **`migrate` is conceptual weight with no unique capability.** It loads a YAML plan and dispatches each op to `key_mv_prefix` / `key_delete_prefix` / `zone_mv` in sequence. It is **not transactional** (`maintenance/migrate.rb` concatenates each op's Plan; a mid-plan failure leaves earlier ops applied — no rollback), so it provides no atomicity the primitives lack. Its only value is "one YAML file instead of N CLI calls," and it introduces a second input format (a plan DSL) nothing else on the surface uses. It is also on MCP, so it enlarges the agent catalog for zero added power.

3. **`mv` means rename, not move.** All three (`mv`, `key_mv_prefix`, `zone_mv`) refuse cross-zone/format changes — they rename in place. The Unix-`mv` idiom is idiomatic enough to keep, but it is worth recording that the operation is a rename.

The cost of fixing (1) is higher than it looks, and that cost is the crux of this ADR: `mv` and `delete` are **not just tool names**. They are the symbols the guard system keys transitions on (`guard_for(:mv, …)`, and the manifest `guard: { mv: [...] }` block, SPEC §guards), the verb strings written to the audit log (SPEC §audit — `mv` additionally carries `from_key`/`to_key`/`uid` structural fields), and the `:entry_renamed` hook event's verb. A half-rename (tool id only, tokens left as `mv`) would make the tool id diverge from its own transition/audit/hook token — strictly worse than the cosmetic drift it set out to fix. So the rename is all-or-nothing.

## Decision

**1. Remove `migrate`.** Delete `lib/textus/maintenance/migrate.rb`, its dispatcher registration, and its specs. The three ops it orchestrated (`key_mv_prefix`, `key_delete_prefix`, `zone_mv`) remain individually callable on every surface. No replacement; batching a reorg is now N explicit calls, each of which already supports `dry_run` (ADR 0071).

**2. Rename `mv`→`key_mv` and `delete`→`key_delete`, completely.** Every load-bearing occurrence of the token moves:

| Site | Before | After |
|------|--------|-------|
| Verb / MCP tool id | `mv`, `delete` | `key_mv`, `key_delete` |
| Guard transition symbol | `:mv`, `:delete` | `:key_mv`, `:key_delete` |
| Manifest `guard:` key | `guard: { mv: … }` | `guard: { key_mv: … }` |
| Audit-log verb string | `"mv"`, `"delete"` | `"key_mv"`, `"key_delete"` |
| `:entry_renamed` hook verb | `mv` | `key_mv` |
| Use-case class + file | `Write::Mv` / `mv.rb`, `Write::Delete` / `delete.rb` | `Write::KeyMv` / `key_mv.rb`, `Write::KeyDelete` / `key_delete.rb` |
| CLI leaf | `key mv`, `key delete` | **unchanged** |

The CLI surface is preserved: the leaf stays `key mv` / `key delete` (set explicitly so it does not track the verb symbol). The result is one coherent family — `key_mv` / `key_mv_prefix` / `key_delete` / `key_delete_prefix` — sharing the object-first `key_` stem, with the bulk variants distinguished by the honest `_prefix` scope suffix.

The use-case **classes and their files** move too, to keep the codebase's `verb == class == file` convention intact — the bulk cousins already follow it (`KeyMvPrefix` / `key_mv_prefix.rb`), and Zeitwerk requires the file to match the constant. So `Write::Mv`→`Write::KeyMv` (`mv.rb`→`key_mv.rb`) and `Write::Delete`→`Write::KeyDelete` (`delete.rb`→`key_delete.rb`); the integration spec mirrors follow.

**3. `zone_mv` is unchanged.** It operates on a zone, not keys; the noun-first `zone_` stem already disambiguates it, and its transition/audit identity is independent. The bare `mv` token survives only inside `zone_mv`, which is correct — that is a different operation.

**4. Read-side `uid` (`key uid`) is out of scope.** It is CLI/Ruby-only (not on MCP) and not part of the write transition/audit/guard vocabulary, so it carries none of the family's load-bearing tokens.

We chose the **object-first stem** (`key_mv`) over the verb-first scope form (`mv` / `mv_prefix`, leaving the tokens untouched — the cheaper "B′" alternative below) because the object (`key` vs `zone`) is the real discriminator on this surface, and aligning single with bulk on `key_` makes the family legible in the derived catalog. We accepted the higher blast radius deliberately.

## Consequences

- **Breaking: manifests.** Any `guard: { mv: … }` / `guard: { delete: … }` block must be renamed to `key_mv` / `key_delete`. textus's own dogfooded manifest keys no guard on these transitions, so the dogfood store is unaffected; external manifests are. `doctor` should flag an unknown transition key (follow-up). No auto-migrator ships — consistent with textus not shipping data migrators (SPEC §migration ethos); the rename is a documented breaking step in `CHANGELOG.md` with a version bump.
- **Breaking: MCP tool ids.** `mv`→`key_mv`, `delete`→`key_delete`, and `migrate` is gone. Agents/clients pinned to the old ids must update. The catalog reconciliation guard (ADR 0039) enforces the new surface.
- **Audit log is append-only across the rename.** Historical rows keep their `mv`/`delete` verb strings; new rows are `key_mv`/`key_delete`. Readers/analytics that match on the verb string must accept both. SPEC §audit is updated to list the new strings and note the discontinuity.
- **CLI is unchanged.** `key mv` / `key delete` / `key mv-prefix` / `key delete-prefix` / `zone mv` all keep their human-facing spelling — no operator relearning.
- **Surface shrinks by one verb.** The MCP/CLI catalog loses `migrate`; one fewer concept, one fewer input format (the YAML plan DSL).
- **No wire-protocol version change.** This renames identifiers and removes a verb; it does not change the envelope shape, transport framing, or `textus/N` number. SPEC edits are to the verb/guard/audit/hook prose, not the protocol version.

## Alternatives considered

- **A — Remove `migrate` only; leave the names.** Lowest risk, zero token churn, but leaves the single/bulk family illegible in the catalog. Rejected: the user explicitly wanted the family normalized, and the cosmetic drift is the thing worth fixing.
- **B′ — Scope-suffix, tokens untouched.** Rename only the two bulk verbs (`key_mv_prefix`→`mv_prefix`, `key_delete_prefix`→`delete_prefix`) so the family shares the *verb* stem (`mv`/`mv_prefix`) while `mv`/`delete` — and therefore all guard/audit/hook/manifest tokens — stay put. Much cheaper and non-breaking. Rejected because the bare bulk names (`mv_prefix`, `delete_prefix`) lose the explicit `key` object that disambiguates them from `zone_mv`, and the object-first family was judged the clearer end state. This was a close call; B′ is the fallback if the breaking cost proves unacceptable in practice.
- **C — Semantic rename (`zone_rename`, `key_rename_prefix`).** Says what it does, but abandons the Unix-`mv` idiom the whole CLI leans on and splits from `key mv`. Rejected: trades one inconsistency for a worse one.
