# ADR 0072 — `accept`/`reject` gate by capability, not by transport — surface them to MCP

**Date:** 2026-06-03
**Status:** Accepted
**Refines:** [ADR 0030](./0030-capability-based-roles.md) (write authority = capabilities × zone-kind — this ADR makes `accept`/`reject`'s authority lean on that model alone), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the MCP catalog is derived from per-verb contracts and guarded by a reconciliation spec — this flips two `surfaces` lists and edits the omit-list, no catalog code), [ADR 0036](./0036-transports-as-pure-framings.md) (one verb vocabulary, one behaviour across transports — this *restores* that symmetry for the promotion verbs), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (an MCP connection's role is pinned at launch and the agent cannot self-select it per call — the property that makes this safe).
**Touches:** [ADR 0045](./0045-close-role-name-set.md) (the closed role set `{human, agent, automation}` is unchanged — `author` is a *capability*, not a new role), [ADR 0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) / [ADR 0071](./0071-dry-run-is-opt-in.md) (sibling decisions that relocated safety from transport/default folklore to legible, contract-grounded gates). Surfaced by the #161 integration review (F7).

> **One sentence:** `propose` is on MCP but `accept`/`reject` are CLI-only, so the propose→accept governance loop can't close over one transport — yet `accept`/`reject` already carry a closed-floor `author_held` guard, so the CLI-only restriction is a *redundant second gate reasoned on the wrong axis* (transport, when the system's grain is capability); this ADR surfaces both verbs to MCP and lets `author_held` be the single gate, so the human checkpoint is enforced by **who holds `author`**, not by **which wire the call arrives on**.

## Context

The #161 review (F7) asked whether the human checkpoint should be *role-gated* on MCP rather than *absent* from it. Investigating the code, the checkpoint is already role-gated — twice over, once redundantly:

1. **`accept`/`reject` carry a closed-floor capability guard.** `BaseGuards::BASE` lists `accept: %w[author_held target_is_canon]` and `reject: %w[author_held]` (`lib/textus/domain/policy/base_guards.rb:16-17`). `author_held` evaluates the *acting role's* capabilities on **every** call regardless of surface (`lib/textus/domain/policy/predicates/author_held.rb`). Under the default capability map only `human` holds `author` (`agent` is precisely "holds `propose`, not `author`" — `lib/textus/manifest/policy.rb:32-34`). So an `agent`-role caller is already rejected with `GuardFailed`.

2. **They are *also* held off MCP entirely.** Both declare `surfaces :cli, :ruby` (`lib/textus/write/accept.rb:8`, `reject.rb:8`) and sit in the reconciliation guard's omit-list (`spec/mcp_catalog_dispatcher_reconciliation_spec.rb:14`), so the catalog never advertises them.

The transport-absence (2) is therefore a **redundant second gate** layered over the capability gate (1) — and the omit-list comment justifies it on the wrong axis: *"internal/maintenance/CLI-only operations an agent should not be steered toward."* That is a *steering/transport* argument, but the system models promotion authority by *capability*. The two never met: nobody recorded that `author_held` already blocks the agent, so an integrator (F7) couldn't tell whether CLI-only was a deliberate governance stance or an unexamined default. It was the latter — a decision made by parking, at the wrong altitude (a test's omit-list), reasoned on the wrong axis.

**The omit-list also conflates two unrelated rationales.** It groups `accept reject build` under one phrase, but:

- `accept`/`reject` are off MCP for **authority** — human-by-`author_held`.
- `build` is off MCP for **role-fit/steering** — it carries *no* `author_held` floor; its gate is the `build` capability, held by `automation` (`lib/textus/write/build.rb:17`, ADR 0030/0061). Nothing about `build` is human-only; it is mechanical materialization an agent or automation could legitimately drive.

Lumping them hid that these are different questions. This ADR settles only the authority one.

**Why surfacing is safe (ADR 0040).** An MCP connection's role is resolved **once at launch** (`lib/textus/cli/verb/mcp_serve.rb:15`, `default: AGENT`) and the whole connection acts as that single role — *"the acting role IS the resolved connection role"* (`lib/textus/mcp/server.rb`). The agent on the far end of stdio cannot assert or change its role per request; it inherits whatever role the operator launched the server as. So the trust boundary is **"who runs `textus mcp serve`,"** and it is identical to the boundary that already governs `put`/`delete`/`mv` over MCP. Surfacing `accept`/`reject` does not widen it.

## Decision

1. **Surface `accept` and `reject` to MCP.** Change both to `surfaces :cli, :ruby, :mcp` and remove `accept reject` from `MCP_CATALOG_INTENTIONALLY_OMITTED`. The catalog derives them (ADR 0039) — no catalog code, +2 MCP tools. The reconciliation spec asserts they are now exposed.

2. **`author_held` is the single gate, unchanged.** The default capability map keeps `human` as the sole `author`. An `agent`-role MCP connection calling `accept`/`reject` is rejected with `GuardFailed` ("role 'agent' lacks the 'author' capability"). The checkpoint moves from *transport-absence* to *capability* — where the system already models it.

3. **The connection-role-at-launch property (ADR 0040) is the safety hinge, stated explicitly.** To promote over MCP, the operator must launch the connection as a role that holds `author` (`--as=human`, `TEXTUS_ROLE=human`, or `.textus/role`). The agent cannot self-escalate. So "accept over MCP" is always a deliberate operator act — the same chain that authorizes every other write, not a new mechanism.

4. **`build` stays omitted — but for its own, corrected reason.** Split the omit-list so `accept`/`reject` are gone and `build`'s entry carries its *true* rationale (automation-driven materialization, a steering/role-fit choice — not authority). Whether to surface `build` to `automation`-role MCP connections is a separate, deferred decision, no longer prejudged by an authority argument that never applied to it.

## Consequences

- **The propose→accept loop closes over one transport.** A human (or a reviewer-capable role) driving a `human`-role MCP connection can review and promote in the same place the proposal surfaced — no context-switch to a terminal. This is the F7 ask, granted by capability rather than by relaxing the gate.

- **The coordination loop, now legible end-to-end (the DX answer):**
  1. **Agent proposes** (`propose`, MCP) → writes into the `queue` zone, auto-prefixed (`lib/textus/write/propose.rb`).
  2. **Anyone discovers it.** `pulse` surfaces `pending_review` — the queue-zone keys — on every surface (`lib/textus/read/pulse.rb:34,59-67`, already `:cli, :ruby, :mcp`). The human polling `pulse` (or `list <queue_zone>`) sees the proposal waiting.
  3. **Reviewer inspects.** `get <queue.key>` reads the proposal's `_meta.proposal` block (`target_key`, `action`) and body.
  4. **Reviewer decides.** `accept`/`reject` — **now available on the same transport** — promote into `target_key` or discard.
  Feedback is **pull-based via the `pulse` cursor**: on `accept` the `:proposal_accepted` event fires (`accept.rb:43`), the queue key leaves `pending_review`, and the target appears in `pulse.changed`; the proposing agent polling `pulse` sees the round-trip close. `reject` fires `:proposal_rejected` (`reject.rb:43`) and the key simply disappears from `pending_review`.

- **Safety posture is unchanged in substance.** Same `author_held` gate, now the *only* gate instead of gate-plus-transport-absence. Default-`agent` MCP still cannot promote. The change is in *legibility*, not in *who can do what*.

- **MCP catalog grows by two** (`accept`, `reject`), derived not hand-maintained; `boot`'s `write_verbs` (catalog-derived, ADR 0056/0057) auto-advertises them, so an agent learns the verbs exist and learns from a `GuardFailed` that it lacks the authority — the boundary is self-documenting.

## Open questions / deliberately out of scope

This ADR relocates **authority**; it does not add a **signal**. Two DX gaps remain, named here so they aren't lost, each its own future decision:

- **No push/notification primitive — the loop is poll-based.** The human must poll `pulse`/`list` to *discover* a pending proposal, and the agent must poll `pulse` to learn its proposal landed. There is no "a proposal awaits you" / "your proposal was accepted" push. The `:proposal_accepted` / `:proposal_rejected` events already exist as the substrate; a notification hook, or a `boot`-surfaced "you have N pending" count, could build on them. Deferred to its own ADR — this one only makes the *act* reachable, not *proactive*.

- **`reject` carries no reason payload.** `reject(pending_key)` discards and emits an event with no operator-supplied "why" (`reject.rb:48` returns only `rejected`/`target_key`). For a real human↔agent loop the proposer benefits from a rejection reason so it can revise rather than re-propose blindly. Adding an optional `reason:` arg threaded into the `:proposal_rejected` event is a small, separable follow-up.

## Alternatives considered

- **Keep `accept`/`reject` CLI-only (ratify the status quo).** Rejected: transport-absence is redundant with the `author_held` floor and reasoned on the wrong axis (steering, when authority is the real gate). It bends "transports are pure framings" (ADR 0036) the same way ADR 0060's `cli_default` split did — and it blocks the single-transport governance loop F7 wants. Ratifying it would mean *re-deciding* to keep folklore where a capability gate already exists.

- **An env kill-switch (`TEXTUS_ALLOW_ACCEPT=1`) to enable accept on MCP.** Rejected as the *gate*. It duplicates the capability model with a coarser, process-global axis: it answers "does this process permit accept at all," never "*who* may accept," so two gates must agree and the finer one already says everything. It re-bends ADR 0036/0071 (the same verb behaving differently by an out-of-band toggle is `cli_default` relocated to an env var), and it is folklore safety — "protection you must remember to leave off" — the exact weakness ADR 0071 §3 rejected. `TEXTUS_ROLE` / `--as` / `.textus/role` *already is* the operator-level toggle (launch the connection as an `author`-holding role) and it **composes** with the model instead of standing beside it. A deployment-level kill-switch is kept in the back pocket — as belt-and-suspenders defense-in-depth for a hostile-multi-tenant threat model only — exactly as ADR 0060/0071 keep the confirm-token gate: the named escalation if the simple thing ever proves too sharp. textus is pre-1.0, single-trust-domain; YAGNI for now.

- **Add a dedicated `reviewer` role to the closed set.** Rejected: `NAMES` is deliberately closed to `{human, agent, automation}` (ADR 0045) with capabilities left open. "May accept" is already expressed by *holding the `author` capability*; a deployment that wants a non-human reviewer grants `author` to a role it already has, no vocabulary growth required. Enlarging the closed set to solve F7 would trade a one-line surface change for a structural one.

- **Surface `build` in the same stroke.** Rejected here: `build` is off MCP for role-fit, not authority, and deserves its own reasoning (automation-driven, potentially heavy, schedule- not conversation-shaped). Folding it in would repeat the omit-list's original sin of conflating two rationales. Corrected its omit-list reason instead; left the surfacing question open.
