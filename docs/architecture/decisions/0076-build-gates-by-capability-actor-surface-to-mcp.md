# ADR 0076 — `build` runs as the build actor, not the caller — surface it to MCP

**Date:** 2026-06-03
**Status:** Accepted
**Refines:** [ADR 0072](./0072-accept-reject-gate-by-capability.md) (deferred this exact question — "whether to surface `build` to MCP is a separate, open decision"; §4 + its last alternative split `build` out of the `accept`/`reject` authority argument precisely so it could be decided on its own grounds — this ADR decides it), [ADR 0061](./0061-build-publish-vocabulary.md) (`build` is the verb end to end; `Write::Build` / `RoleScope#build` — the use-case this ADR makes transport-uniform), [ADR 0030](./0030-capability-based-roles.md) (write authority = capabilities × zone-kind — `build` is the `automation`-held capability the verb self-elevates to).
**Touches:** [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the catalog derives from `surfaces`; this flips one list and removes one omit-list entry, no catalog code), [ADR 0036](./0036-transports-as-pure-framings.md) (one behaviour across transports — this *restores* that symmetry for `build`), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (connection role pinned at launch — the property that bounds the trust boundary), [ADR 0070](./0070-content-addressed-build-artifacts.md) (builds are content-addressed and idempotent — what bounds "heavy"), [ADR 0068](./0068-declarative-facets-dissolve-escape-hatches.md) (the `around:` resource mechanism the lock becomes), [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (the CLI verb thins back to a projection once its hand-coded logic moves into the contract).

> **One sentence:** `build` is CLI-only, but its CLI verb already ignores the caller's role and runs the materialization *as the manifest's `build`-capable actor* under a `BuildLock` — so the transport restriction is the only thing keeping an agent from triggering a recompute it has no authority to corrupt; this ADR lifts the actor-resolution and the lock out of the CLI verb into the shared `Write::Build` use-case (an `around :build_lock` resource), then surfaces `build` to MCP — making `build` transport-uniform, caller-agnostic, and serialized on **every** surface.

## Context

[ADR 0072](./0072-accept-reject-gate-by-capability.md) surfaced `accept`/`reject` to MCP and, in doing so, deliberately split `build` out of the same omit-list because the two were off MCP for *different* reasons:

- `accept`/`reject` — held off for **authority** (`author_held`, human-only).
- `build` — held off for **role-fit/steering**: it "carries no `author_held` floor; its gate is the `build` capability (automation's), and it is a heavy, schedule-driven materialization an interactive agent should not be steered toward. Whether to surface it to automation-role connections is open." (`spec/mcp_catalog_dispatcher_reconciliation_spec.rb:13-16`.)

This ADR settles that open question. Three facts about `build` as it stands today:

1. **`build` has no caller-capability gate at all.** It is *not* in `BaseGuards::BASE` (`lib/textus/domain/policy/base_guards.rb` lists `put`/`delete`/`mv`/`accept`/`reject`/`fetch` — not `build`). The materialization path — `Materializer` → `Ports::Publisher.publish` — is pure file I/O with no actor check. So there is no guard that would reject an `agent`-role caller; the only thing stopping one is transport-absence.

2. **The CLI verb already runs `build` as the build actor, not as the caller.** `cli/verb/build.rb` does `role = store.manifest.policy.actor_for("build")` and runs the writes under *that* role regardless of who invoked the CLI. So `build` is *already* caller-agnostic and self-elevating — that behaviour just happens to live in the CLI surface instead of the shared use-case.

3. **The `BuildLock` lives only in the CLI verb.** `cli/verb/build.rb:15` wraps the build in `Ports::BuildLock.with(root:)`. The shared `Write::Build#call` has no lock. So a build triggered through any *non-CLI* path (today: the Ruby API; tomorrow: MCP) would **skip the single-writer lock** and could collide with a concurrent CLI or background build — the real "heavy" risk ADR 0072 gestured at, and one the current arrangement does *not* actually protect against across transports.

The "steering" worry — *should an interactive agent be pointed at `build` at all?* — answers itself once you see what `build` **is**: a **pure, idempotent function of accepted canon**. It computes nothing new; it materializes the deterministic projection that already-accepted `knowledge.*` implies, content-addressed so a redundant build is a byte-equal no-op (ADR 0070). Triggering it grants the caller **no authority over content** — an agent cannot change canon via `build`, only recompute what a human already authored. And the companion profile ([ADR 0077](./0077-init-with-agent-profile.md)) makes the need concrete: an agent that edits `knowledge.*` and gets its proposal accepted leaves `CLAUDE.md`/`AGENTS.md` stale until a build runs. Forcing a terminal context-switch to run `textus build` breaks the single-transport loop — the same break ADR 0072 closed for `propose`→`accept`.

**Why surfacing is safe (ADR 0040), stated explicitly.** An MCP connection's role is resolved once at launch and cannot be re-selected per call. But `build` doesn't even consult the caller's role — it self-elevates to the `build` actor — so surfacing it widens nothing on the authority axis. The trust boundary is "who ran `textus mcp serve`," identical to the boundary already governing `put`/`delete`/`mv` over MCP.

## Decision

1. **Lift actor-resolution and the `BuildLock` from the CLI verb into the shared use-case.** `Write::Build#call` resolves `actor_for("build")` itself (raising a helpful error when no role holds `build`) and binds its `PublishContext`/reader to a `Call` for that build actor — so the materialization runs as the build actor on **every** surface, not just the CLI. The `BuildLock` becomes a registered `around :build_lock` contract resource (the ADR 0068 mechanism, mirroring `:cursor`), applied at the single `dispatch_bound` site every surface flows through. The CLI verb shrinks back to a thin projection (ADR 0063).

2. **Surface `build` to MCP.** Change its contract to `surfaces :cli, :mcp` and remove `build` from `MCP_CATALOG_INTENTIONALLY_OMITTED`. The catalog derives the tool (ADR 0039) — no catalog code, +1 MCP tool; `boot`'s `write_verbs` auto-advertises it.

3. **`build`'s authorization model is recorded as: transport-agnostic, caller-agnostic, self-elevating.** The only gate is that the manifest declares a role holding the `build` capability. There is no caller `author_held`/`build` floor, by design — `build` is mechanical recomputation, not authority over content. This is not new behaviour; it is the CLI verb's existing behaviour, now made explicit and uniform.

4. **Single-writer serialization now spans all transports.** Because the lock moved into the contract, a `build` over MCP and a concurrent `build` (or background materialization) over the CLI cannot both hold the lock — the second raises `BuildInProgress`. The cross-transport collision the CLI-only lock never covered is now covered.

## Consequences

- **The edit→accept→rebuild loop closes over one transport.** With ADR 0077's profile, an agent can propose a `knowledge.*` change, a human can `accept` it over the same MCP connection (ADR 0072), and then `build` to refresh `CLAUDE.md`/`AGENTS.md` — all without leaving the conversation. The `build` it triggers runs as `automation`, writes only derived projections, and is idempotent.

- **Safety posture is unchanged in substance; only legibility and the lock's reach improve.** No new authority is granted (`build` never gated the caller). The genuine *gain* is correctness: the single-writer lock now protects cross-transport, which it previously did not.

- **The MCP catalog grows by one** (`build`), derived not hand-maintained; the reconciliation spec asserts it is now exposed, and its omit-list comment loses the `build` paragraph.

- **`SPEC.md` (the *what*) gains `build` in the MCP tool set.** The contract surface changed, so SPEC.md's catalog listing is updated alongside the implementation.

- **One source of truth for build orchestration.** Actor-resolution + lock live in the use-case; the CLI verb, the Ruby API, and MCP all inherit identical behaviour — removing the latent bug that the Ruby API path already skipped the lock.

## Alternatives considered

- **Keep `build` CLI-only (ratify the status quo).** Rejected: the restriction is transport-absence reasoned on a steering axis, while `build` carries no authority an agent could abuse — it's a pure function of accepted canon (ADR 0070). It also leaves the real defect unaddressed: the lock only ever covered the CLI, so the Ruby API path is *already* unserialized. Ratifying CLI-only would re-decide to keep folklore over a fix.

- **Surface `build` but add a caller `build`-capability guard (gate the trigger, not just the actor).** Rejected: it would *reduce* function below today's CLI behaviour (where any CLI caller triggers a build that self-elevates) and defeat the stated intent that an agent/human can drive the recompute. Since `build` writes only deterministic projections of canon, gating *who may trigger* a recompute buys no safety — the content is already authorized by whoever accepted the canon.

- **Restrict `build` over MCP to `automation`-role connections only.** Rejected as the gate: it reintroduces per-call role reasoning that ADR 0040 deliberately removed (the connection role is pinned at launch; the agent can't self-select). The operator who launches the server already chose the trust boundary; layering a second connection-role check duplicates it on a coarser axis. Kept in the back pocket as a deployment-level posture for a hostile-multi-tenant model only — the same way ADR 0071/0072 hold confirm-token/kill-switch gates in reserve. textus is pre-1.0, single-trust-domain; YAGNI now.

- **Leave the lock in the CLI verb and add a second lock on the MCP path.** Rejected: two lock sites is exactly the duplication ADR 0063/0068 dissolve. One `around :build_lock` resource at the shared dispatch site is the single home, and it fixes the Ruby-API gap for free.
