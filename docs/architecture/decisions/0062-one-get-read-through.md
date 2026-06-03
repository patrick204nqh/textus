# ADR 0062 — One `get`: unify the public read verb on read-through; keep `Read::GetEntry` as the internal pure primitive

**Date:** 2026-06-03
**Status:** Accepted (ships 0.44.0)
**Refines:** [ADR 0058](./0058-one-verb-name-across-surfaces.md) (one name per verb across surfaces — this removes the last *behaviour* mismatch still hiding under a matched name: the CLI `get` command secretly upgraded to read-through while MCP/Ruby `get` was a pure read), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the contract verb is the `Dispatcher::VERBS` key is the use-case method is the class name — moving the `get` contract onto the read-through class realigns all four after a layer-down naming defect).
**Touches:** [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (the MCP connection acts as the agent — the agent's `get` now performs a policy-bounded fetch-on-stale instead of a pure read), [ADR 0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) (which set the agent's read default to a *pure* read for `get`; this **supersedes that specific stance** — the agent's pure reads are now internal-only, reachable through `Read::GetEntry`, never as a public verb).

> **One sentence:** the public `get` verb meant two different things — a pure on-disk read on MCP and Ruby, but a secret read-through on the CLI (which dispatched a separate `get_or_fetch` verb) — so this unifies `get` on **read-through everywhere** (return the freshest obtainable envelope, fetching on stale per the entry's fetch rule, degrading to a pure read when the key has no fetch rule), drops the now-redundant `get_or_fetch` verb, and keeps the orchestrator-free pure read as an **unexposed** primitive (`Read::GetEntry`) for the ~9 internal callers that must never trigger a fetch mid-write or mid-hook.

> **Amendment (2026-06-03, same 0.44.0 PR):** the two-class split this ADR
> introduced (`Read::Get` read-through + `Read::GetEntry` pure) is collapsed
> into **one** `Read::Get#call(key, fetch: false)`. The fetch behavior is a
> single flag, not a class fork: the **method** default is `fetch: false` (the
> safe default for the ~9 in-process callers that must read persisted truth and
> never fetch — they construct `Read::Get` directly), while the **public verb**
> is read-through because the contract declares `arg :fetch, default: true`,
> injected on every verb surface by both `RoleScope` and `MCP::Catalog.map_args`
> (a new contract literal-default feature). `Read::GetEntry` is removed; the
> orchestrator is built lazily, so a pure call still never touches threads/
> forks/locks. `get` also gains an optional wire `fetch` flag (CLI `--no-fetch`,
> MCP `{fetch:false}`) for an explicit cheap pure read. Rationale: one read
> path with centralized fetch control, safe-by-default for machinery — the
> single-path model the two classes were only approximating.

**Amendment consequences:**
- **One read class.** `Read::Get#call(key, fetch: false)` is the single read path. `Read::GetEntry` is removed.
- **`fetch` flag on the wire.** The MCP `get` tool now advertises an optional `fetch` property (default `true`); `required` stays `["key"]`. The CLI gains `--no-fetch` for an explicit pure read.
- **Contract literal-defaults are a reusable protocol feature.** `Arg#default` is honored identically by `RoleScope` (Ruby/CLI path) and `MCP::Catalog.map_args` (MCP path) — the two verb-dispatch chokepoints inject the contract's declared default for any absent kwarg.

## Context

`get` is the single thing every caller — human, agent, automation — calls "read." But under one name it carried two behaviours:

- **MCP and Ruby `get`** dispatched the pure primitive (then named `Read::Get`, since renamed to `Read::GetEntry` — see the Decision): it read the on-disk bytes, annotated a freshness verdict, and returned — never fetching.
- **CLI `get`** dispatched a *second* verb, `get_or_fetch` (the read-through class), which ran the same pure read and then, on a stale verdict, handed off to the fetch orchestrator per the entry's `on_stale` policy.

So an operator typing `textus get` got current data; an agent calling the `get` tool got whatever happened to be on disk, however stale — same name, two contracts. This is exactly the defect ADR 0058 set out to kill (one verb, one name, one meaning across surfaces), surviving one layer down: the *names* matched but the *behaviour* did not, because two verbs sat behind them.

The load-bearing reason the split exists at all is real and must be preserved. A read-through `get` builds a fetch orchestrator, and a fetch fires lifecycle events → hooks → which may themselves read. A hook (or a materializer, or the validator) doing read-through could loop `fetch → event → hook → fetch`. So a large set of internal callers must read *purely* — they need the on-disk envelope with a freshness verdict and nothing more. Today ~9 such call-sites depend on the orchestrator-free primitive: `accept`, `reject`, `publish`, the materializer/projection, `uid`, `validate_all`/the validator, schema/tools (inspect + migrate), and the hook context. The split between a pure primitive and a read-through composition is correct. The inconsistency was never the split — it was the *secret CLI upgrade* sitting under a verb whose other surfaces meant something else.

A senior-architect consult on the fix surfaced a second, subtler instance of the same smell. The read-through class was named `GetOrFetch` and owned `verb :get`. A class named `GetOrFetch` owning `verb :get` is the ADR 0058 naming defect one layer down inside the codebase: every other verb in textus already follows class-name = verb (`Write::Put` owns `:put`, `Read::Where` owns `:where`, …), and only `get` would have broken that. So the verb-owning read-through class is named **`Read::Get`** and the pure primitive is **`Read::GetEntry`**. This is an internal rename — it changes no wire contract by itself; the verb token, args, and response are identical.

## Decision

1. **One public read verb, read-through.** `verb :get` is owned by **`Read::Get`** (`surfaces :cli, :ruby, :mcp`). `get` returns the freshest *obtainable* envelope: it runs the pure read, and on a stale verdict consults the entry's fetch rule and hands off to the fetch orchestrator per `on_stale` (`warn`/`sync`/`timed_sync`, §6). When the key has **no** fetch rule, read-through **degrades to a pure read** — byte-identical to the old pure `get`.
2. **Drop the `get_or_fetch` verb.** There is now a single public path; `get_or_fetch` is removed from the dispatcher and is no longer a method on any surface. Explicit `fetch` / `fetch_all` remain for *forced* and *bulk* refresh — they are a different intent (refresh now, regardless of freshness) and stay distinct verbs.
3. **The pure read is an unexposed class.** `Read::GetEntry` carries **no contract** — it is not a verb, has no `:mcp`/`:cli`/`:ruby` surface, and is reachable only in-process by direct construction. It is the orchestrator-free primitive: read the on-disk envelope, annotate freshness, never fetch.
4. **Internal callers that must stay pure construct `Read::GetEntry` directly** — `accept`, `reject`, `publish`, the materializer/projection, `uid`, the validator, schema/tools, and the hook context. This preserves their current behaviour (they already read purely) and structurally forecloses the `fetch → event → hook → fetch` reentrancy: a hook simply cannot reach the read-through verb.
5. **Class-name = verb, end to end (the consult's call).** The verb-owning read-through class is `Read::Get`; the pure primitive is `Read::GetEntry`. Naming the read-through class `GetOrFetch` while it owned `verb :get` would have re-introduced the ADR 0058 smell inside the library. This rename is internal — **no wire-contract change follows from the rename itself.**

## Consequences

- **One read verb, one meaning.** The thing an operator types as `get` and the thing an agent calls as the `get` tool are now the same contract: read-through. The CLI's secret `get_or_fetch` upgrade is gone, folded into the one verb.
- **The agent's `get` returns the freshest obtainable envelope.** On MCP, `get` now performs a policy-bounded fetch-on-stale (bounded by the entry's `on_stale` budget) instead of a pure on-disk read. This is the deliberate supersession of ADR 0060's "agent reads default to pure" stance for `get` — the agent's pure read is no longer a public verb.
- **Pure reads are in-process only.** No surface can request the orchestrator-free read; it is reachable solely by the internal callers that must not fetch. The reentrancy hazard is closed by construction, not by convention.
- **No catalog growth, no new wire shape.** The MCP tool count is unchanged (`get_or_fetch` was never surfaced); `get`'s args and response are identical. The `Read::Get`/`Read::GetEntry` naming is an internal rename with no protocol effect.
- **`fetch`/`fetch_all` keep a distinct job.** Read-through is "give me current data, fetching only if stale"; `fetch`/`fetch_all` are "refresh now." Keeping them separate avoids overloading `get` with a force-refresh mode.

## Alternatives considered

- **Surface both `get` and `get_or_fetch`.** Rejected: two public names for the one operation every user calls "read." The whole point of unification is that an operator and an agent reach for the same verb and get the same contract; a second public name re-creates the divergence under a different label.
- **Document the split as intentional / keep the `GetOrFetch` class name owning `verb :get`.** Rejected: a class named `GetOrFetch` owning `verb :get` is the ADR 0058 class-name/verb mismatch one layer down — every other verb already satisfies class-name = verb, and `get` would be the lone exception. The fix is to name the read-through class `Read::Get` and the pure primitive `Read::GetEntry`, not to enshrine the mismatch.
- **A strategy-injection facade** (one `Read::Get` class taking `strategy: :pure | :read_through`). Rejected: it hides a collaborator behind a kwarg and adds a `strategy: :pure` footgun an internal caller could forget to pass (re-opening the reentrancy hazard a default would mask). The two-class composition — a pure primitive `GetEntry` composed by a read-through `Get` — is already the clean shape; only the names were wrong, and renaming is cheaper and safer than introducing a mode parameter.
