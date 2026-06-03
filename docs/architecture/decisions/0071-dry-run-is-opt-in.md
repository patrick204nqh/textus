# ADR 0071 — `dry_run` is an opt-in preview, not a default — verbs apply by default on every surface

**Date:** 2026-06-03
**Status:** Accepted
**Reverses:** [ADR 0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) decision §2 (default-dry-run on the four bulk-destructive verbs). The other half of ADR 0060 — surfacing `deps`/`rdeps`/`where` to MCP so an agent *can* look before it leaps — stands unchanged.
**Touches:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the contract `default:` feeds the MCP binder; this only flips a default value, no catalog code), [ADR 0036](./0036-transports-as-pure-framings.md) (one verb vocabulary, one behaviour across transports — this ADR *restores* that symmetry, which 0060's per-surface `default`/`cli_default` split had bent). Surfaced by the #161 integration review (F6).

> **One sentence:** ADR 0060 made the four bulk-destructive verbs (`zone_mv`, `key_mv_prefix`, `key_delete_prefix`, `migrate`) *plan* by default and apply only when an agent remembered to pass `dry_run: false` — this ADR reverses that: a verb is an action, so it **applies by default**, and `dry_run` becomes a uniform opt-in preview (`dry_run: true` / `--dry-run`) on every surface.

## Context

ADR 0060 fixed a real agent-safety asymmetry, and its primary fix — surfacing the blast-radius reads (`deps`/`rdeps`/`where`) to MCP — was correct and stays. But its *secondary* fix, flipping `dry_run` to default-`true` on the four bulk verbs, has not aged well:

1. **A verb is an action; planning is the exception.** "Call `key_delete_prefix` and nothing is deleted" is surprising — the default outcome of invoking a destructive verb is *not the thing the verb names*. The agent (or Ruby caller) that wants to act must now pass `dry_run: false` to make a verb do what it says, which is the inverse of every other verb in the surface (`put`, `delete`, `mv`, `build` all act on call).

2. **It bent "transports are pure framings" (ADR 0036).** To keep the CLI usable, 0060 left `cli_default: false` while the agent default was `true` — so the *same verb* planned-by-default for an agent but applied-by-default on the CLI. ADR 0060 itself rejected per-surface defaults (its alternative §3) as a violation of ADR 0036, then reintroduced exactly that split through `default`/`cli_default`. The split is defensible but surprising, and the #161 review flagged it as the kind of behaviour an integrator can only learn by reading arg docs.

3. **The guardrail it bought is weaker than it looks.** The protection was "a forgotten flag returns a Plan instead of mutating" — but an agent that ignores the returned Plan and immediately retries with `dry_run: false` is no safer, and a deliberate caller just carries the flag everywhere. The durable safety win of 0060 was the *eyes* (`rdeps` on MCP), not the execute-gate.

## Decision

1. **`dry_run` defaults to `false` on all four verbs — they apply by default.** Flip both the contract `default:` and the `#call` keyword default from `true` to `false` in `ZoneMv`, `KeyMvPrefix`, `KeyDeletePrefix`, and `Migrate`. Drop the now-redundant `cli_default: false` (the agent default and the CLI default are the same value again).

2. **`dry_run: true` (`--dry-run` on the CLI) is the uniform opt-in preview.** Pass it to get a `Plan` without mutating; omit it to act. One default, one behaviour, every surface — restoring ADR 0036 symmetry. The arg descriptions are rewritten to state the new default ("defaults to false, so omitting it applies immediately").

3. **The blast-radius reads stay on MCP.** `deps`/`rdeps`/`where` remain MCP-surfaced (ADR 0060 §1). "Look before you leap" is still available to an agent — it is now a *choice the agent makes* (read first, or pass `dry_run: true`), not a default it must override to get work done.

## Consequences

- **Behavioural change (breaking) for MCP/Ruby callers of the four bulk verbs** that relied on ADR 0060's `dry_run: true` default: omitting `dry_run` now **mutates**. This is the reversal's whole point. textus is pre-1.0; no shim. The maintenance specs already pass `dry_run` explicitly, so they pin the new behaviour directly.
- **CLI behaviour is unchanged** — `--dry-run` was already opt-in (`cli_default: false`), so operators see no difference. Only the agent/Ruby default moves, back into parity with the CLI.
- **The per-surface `default`/`cli_default` divergence on these verbs disappears**, restoring "one verb, one behaviour across transports" (ADR 0036).
- **The `capabilities` projection (#161 F4) makes the default legible.** Each arg now reports a single `default: false` with no `cli_default`, so the behaviour is machine-readable and assertable in CI rather than folklore — which is the durable replacement for "the default protects you."
- **Net safety posture:** the agent keeps the *eyes* (graph-reads on MCP) and loses the *execute-gate*. Given the gate's weakness (Consequences-era observation above) and the surprise of action-verbs-that-don't-act, this is judged the better trade. If a stronger guardrail is ever wanted, ADR 0060's rejected **confirm-token gate** (a plan hash that execution must echo) remains the principled option — it gates execution without making the *default* a no-op.

## Alternatives considered

- **Keep ADR 0060's default-dry-run.** Rejected — the status quo this ADR exists to change. Action-verbs that plan-by-default are surprising, and the per-surface split bends ADR 0036.
- **Default `false` for Ruby/CLI but keep `true` for MCP only.** Rejected for the same reason ADR 0060's own alternative §3 was rejected: it splits one verb's behaviour by transport. The whole point of this ADR is to *remove* that split, not relocate it.
- **Confirm-token gate instead of a plain default.** Not adopted now (no demonstrated need), but explicitly kept as the preferred future guardrail if default-apply proves too sharp — it protects execution without neutering the default.
