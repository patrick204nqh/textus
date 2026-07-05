# ADR 0068 — Declarative `source:`/`coerce:`/`cli_stdin`/`around:`/`cli_default:` dissolve the acquisition & wrapper escape hatches

**Date:** 2026-06-03
**Status:** Accepted (ships 0.45.0)
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (the generated/escape-hatch split), [ADR 0065](./0065-finish-cli-response-shrink-escape-hatches.md) (finished the output-only hatches; explicitly deferred acquisition, stateful, and surface-default hatches).
**Touches:** [ADR 0066](./0066-one-binder-required-is-a-surface-policy.md) (single bind+dispatch site), [ADR 0067](./0067-per-surface-views.md) (views), [ADR 0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) (the surface-divergent `dry_run` default this makes legible).

> **One sentence:** ADR 0065 left a population of CLI verbs hand-authored for *input acquisition* (stdin, file reads), *coercion*, *stateful wrappers* (lock, cursor), *surface-divergent defaults*, and *multi-dispatch overloads*; this ADR gives the contract a declarative facet for each, dissolving those hatches so the population drops from 18 to 7 — the irreducible behavioral floor.

## Context

After ADR 0065, `HAND_AUTHORED_VERBS` still held verbs that escaped for reasons the contract could not yet express:

| reason | verbs | new facet |
|---|---|---|
| stdin JSON envelope | `propose` | `cli_stdin :json` |
| read a flag/positional as a file path | `migrate`, `rule_lint` | `arg … source: :file` |
| coerce a raw string | `audit` (`since` → Time) | `arg … coerce: ->(s){…}` |
| stateful wrapper | `pulse` (cursor), `build` (lock) | `around :name` |
| CLI default ≠ agent default | `zone_mv`, `migrate`, `key_*_prefix` | `arg … cli_default:` |
| one command, two verbs | `key delete`/`key mv` `--prefix` | first-class split commands |

## Decision

Five declarative facets, all consumed at the single dispatch site (ADR 0066):

- **`arg … source: :file`** — the CLI reads the arg's value as a path → file contents (`Contract::Sources.acquire`). MCP receives typed JSON, so it never runs there.
- **`arg … coerce: callable`** — the CLI applies the callable to the raw value before binding.
- **`cli_stdin :json`** — the CLI parses a stdin JSON envelope, distributing keys to args by wire-name (`Sources.from_stdin`). An empty stream yields `{}`, so a required arg surfaces as a clean missing-arg error. The `--stdin` flag becomes a vestigial no-op.
- **`around :name`** — a registered `Contract::Around` resource wraps `dispatch_bound`, adjusting inputs before and post-processing the result after. `session:` is threaded through so a session-aware resource can defer to the session's own state. `Resources::Cursor` reads/persists the file cursor for sessionless (CLI/Ruby) dispatch and defers to the session cursor (`session_default: :cursor`) on MCP.
- **`arg … cli_default:`** — the CLI default when it diverges from the agent default. It drives both the bound value (`apply_cli_defaults`) and boolean flag *polarity* (`effective_default`): `zone_mv`/`migrate`/`key_*_prefix` get a `--dry-run` flag (apply by default, plan on demand) while agents plan by default. The ADR 0060 divergence is now legible in the contract, not hidden in a hand class.

The `key delete`/`key mv` `--prefix` overloads split into first-class generated commands: `key delete-prefix` and `key mv-prefix` (**breaking**: `key delete --prefix P` → `key delete-prefix P`).

## Remaining behavioral floor (7 verbs)

These escape because their CLI behavior is genuine behavior, not a projection:

- **`put`** — IntakeFetch read-through orchestration.
- **`get`** — raises `UnknownKey` with resolver *suggestions*; a CLI-only affordance the agent surface deliberately omits (it returns `nil`). Moving this into the use-case would change the MCP contract (ADR 0060's graceful-nil), so `get` stays whole.
- **`build`** — the CLI auto-resolves the **build-capability actor role** (not the `--as` role) and serializes under `BuildLock`. `around:` covers the lock, but the role resolution is policy, not a projection, so `build` stays hand-authored rather than splitting its behavior.
- **`fetch` / `fetch_all`** — worker verbs (background intake), not request/response.
- **`boot` / `doctor`** — composite reports assembled outside the contract.

A reconciliation guard (`contract_facets_reconciliation_spec`) asserts every `around:` names a registered resource, every `cli_stdin` mode is supported, and every default view tolerates the uniform call.

## Consequences

- Eight hand-classes deleted (`propose`, `migrate`, `rule_lint`, `audit`, `zone_mv`, `pulse`, `key_delete`, `mv`); `HAND_AUTHORED_VERBS` shrinks 18 → 7.
- Fixed a latent `Runner.coerce` bug: `when Integer` used `===` (instance-of), so `Integer`-typed flags never coerced; now compared by equality.
- **Breaking** (pre-1.0): the `view` DSL replaces `response`/`cli_response`; `blame`/`zone_mv`/`migrate`/`key_*_prefix` gain positional `#call` signatures; `key delete --prefix`/`key mv --prefix` become `key delete-prefix`/`key mv-prefix`.
