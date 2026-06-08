# ADR 0111 — rename the `reconcile` capability/lane token to `converge`; drop the dead `:reconcile_failed` event

**Date:** 2026-06-08
**Status:** Accepted
**Amends:** [ADR 0110](./0110-job-queue-and-drain-serve.md) — reverses its deliberate choice to *keep* the `reconcile` capability/lane token. 0110 hard-renamed the **verb** to `drain`/`serve` but left the **capability** named `reconcile` to bound blast radius; this ADR finishes the rename so one vocabulary survives.

> **One sentence:** the machine-zone write capability is renamed `reconcile` → **`converge`** — matching `Produce::Engine.converge` (the operation) and reading as *what `drain` runs once and `serve` runs on a loop* — and the declared-but-never-emitted `:reconcile_failed` event is deleted; both are breaking, with no back-compat alias.

## Context

ADR 0110 split convergence into the `drain`/`serve` **verbs** but kept the
**capability/lane token** `reconcile` (`can: [reconcile]`, `actor_for("reconcile")`,
the `machine → reconcile` bijection in `Schema::Vocabulary::LANES`, the
`:reconcile` write transition). That left a dual vocabulary: a manifest declares
`can: [reconcile]`, but there is no `reconcile` command to grep for — only
`drain`/`serve`. Newcomers trip on the mismatch. The operation itself is already
called `converge` in code (`Produce::Engine.converge`), so the capability had a
third name for the same idea.

A second, smaller debt surfaced in the same audit: `:reconcile_failed` was
declared in the hooks catalog (and the `init` scaffold + `events.md`) as the
destructive counterpart to `:produce_failed`, but **nothing ever emitted it** —
in the job-queue model a failed destructive `sweep` dead-letters (and surfaces
via `jobs`), it does not publish an event. It was vestigial from the old
synchronous `reconcile` result-hash path.

## Decision

**(a) Rename the capability/transition token `reconcile` → `converge`,
everywhere, with no alias.** This is one coordination token used in three code
registers, all renamed together:
- the lane bijection `Schema::Vocabulary::LANES["machine"]` (`machine → converge`),
  hence `Schema::CAPABILITIES`;
- the default role mapping (`automation → [converge]`) and every `can: [converge]`
  declaration;
- `Policy#actor_for("converge")`, the `build_actor_call` error/hint, the
  `BaseGuards` floor key, and the `:converge` write transition in `Acquire::Intake`.

The three **verbs** (`drain`, `serve`, `jobs`) and the `Produce::Engine.converge`
method are unchanged — they already read correctly against `converge` as the
capability ("the authority to converge the machine lane", which `drain` exercises
once and `serve` on a loop).

**(b) Delete the dead `:reconcile_failed` event.** Removed from
`Hooks::Catalog`, the `init` hooks-README scaffold, and the canon event docs. Not
renamed to `:converge_failed` — re-introducing a destructive-failure signal (if
wanted) is follow-up feature work; the honest state today is that destructive
failures dead-letter, so the catalog should not advertise an event that never
fires.

## Consequences

- **Breaking, no migration shim** (per the project's "no maintain old version"
  stance). Existing manifests with `can: [reconcile]` must change to
  `can: [converge]`; a stale token now fails at load with
  `unknown capability 'reconcile'`. `owner: automation:reconcile` becomes
  `automation:converge`.
- **Historical ADRs are untouched.** 0079/0087/0090/0091/0093/0110 keep their
  `reconcile` wording (and slugs like `0087-fold-build-into-reconcile`) as the
  record of what was decided then; only living canon (how-to/reference/explanation)
  moves to `converge`. The ADR 0090 *folded-into* hint and its spec now read
  `'converge'`.
- **Doc-rot swept in the same pass.** Comments/error strings that named the
  retired `reconcile` *verb* now say `drain`/`serve`; comments naming the
  *operation* say `converge`. The transitional `reconcile_drain_parity_spec` and
  the permanently-empty `CLI_RECONCILE_EXEMPT` constant are removed, and the
  duplicated worker builder in `drain`/`serve` is collapsed into `Worker.for`.
- No `SPEC.md` change (capability vocabulary is manifest/code surface, already
  governed by ADR 0030/0091).
