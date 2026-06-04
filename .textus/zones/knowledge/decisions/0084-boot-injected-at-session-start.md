# ADR 0084 — `boot` is delivered at session start via a SessionStart hook; textus ships the hook as a plugin

**Date:** 2026-06-04
**Status:** Accepted (ships 0.50.0)
**Touches:** [ADR 0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) and [ADR 0057](./0057-agent-legible-mcp-contracts.md) (the orientation payload this delivers), [ADR 0075](./0075-session-opened-connect-event.md) (the connect-time seam — that is textus's *internal* event; this is the *host's* session-start seam), [ADR 0077](./0077-init-with-agent-profile.md) (`init --with-agent` scaffolds the agent setup — the SessionStart hook is the natural next thing it could scaffold), [ADR 0083](./0083-contract-guard-writes-only-boot-self-heals.md) (delivery-at-start and mid-session recovery are complementary, not substitutes).

> **One sentence:** `boot` is the orientation a fresh agent needs (zones, schemas, write-flows, quickstart, contract etag), but today the agent only gets it if it *chooses* to call the tool — so orientation is best-effort; this ADR delivers `boot` deterministically at session start through a Claude Code **SessionStart hook** (`type: command`, shelling the CLI `boot` whose stdout becomes `additionalContext`), keeps the manifest as the *definition* of orientation and the hook as its *transport*, and proposes textus ship the hook from a plugin so installation auto-registers it — while leaving the agent-invokable `boot` tool in place for mid-session re-orientation.

## Context

`boot` returns the working model of a textus store: zones and their write authority, entries and flags, schemas, `write_flows`, `agent_quickstart`, and the `contract_etag` (ADR 0056/0057). A cold agent is only well-oriented once it has this. Today orientation is **pull**: the agent must decide to call the `boot` MCP tool. If it does not, it operates under-informed — guessing zone authority, missing the propose→accept flow, unaware of the contract etag. Orientation being optional makes it unreliable.

Claude Code (the primary host) exposes a `SessionStart` hook that fires on `startup`/`resume`/`clear`/`compact` and can inject text into the model's context *before the first prompt* via `hookSpecificOutput.additionalContext`. Two facts make this a clean fit:

- **`boot` is already on the `cli` surface** (`surfaces :cli, :mcp, :ruby`). A `type: command` hook can shell `textus boot` and pipe its stdout into `additionalContext` — no MCP round-trip, and each invocation is a fresh CLI process reading current on-disk state.
- **MCP has no "auto-run a tool at session start" mechanism.** MCP servers expose tools/resources the model must call. So a hook is the *only* way to make orientation push-based; there is no competing MCP feature to weigh it against.

This is distinct from ADR 0075's `session_opened` event: that is textus's own connect-time pub-sub seam for hooks *inside* the store. This ADR is about the *host* (Claude Code) injecting textus orientation into the *agent's* context at the host's session boundary.

## Decision

### 1. Orientation is delivered at session start by a SessionStart hook

A `SessionStart` hook of `type: command` runs `textus boot` (CLI) and emits its output as `additionalContext`:

```json
{
  "hooks": {
    "SessionStart": [
      { "type": "command", "command": "bundle exec exe/textus boot --lean" }
    ]
  }
}
```

The hook's stdout is wrapped by the host into:

```json
{ "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "<orientation>" } }
```

so the agent is oriented before it processes the first user turn — no tool call required.

### 2. The manifest defines orientation; the hook only transports it

The `.textus` manifest already *defines* what `boot` returns (zones, schemas, rules). The hook *delivers* it. We deliberately do **not** add an "inject on session start" flag to the manifest: that would couple textus's data model to one consumer (Claude Code). Keeping definition (manifest/`boot`) separate from delivery (host hook) lets the same `boot` feed a Claude hook, a CI step, or any other client without the store knowing who is asking.

### 3. `boot --lean` for repeated injection

SessionStart fires on `compact` and `resume`, not only `startup`. Injecting the full `boot` envelope on every compaction wastes context budget exactly when it is scarce. `boot` grows a `--lean` projection — `agent_quickstart` + the zone list + `contract_etag` — which is what a re-orienting agent needs without the full schema/entry dump. The hook uses `--lean`; an agent that wants the full contract calls the `boot` tool.

### 4. textus ships the hook from a plugin (the packaging decision)

Two distribution channels exist, and the recommendation differs:

| Channel | Audience | Where the hook lives | Committed? |
|---|---|---|---|
| This repo (dogfooding) | textus developers | local `.claude/settings.json` `hooks.SessionStart` → `bundle exec exe/textus boot --lean` | **No** — `.claude/settings.json` is git-ignored in this repo (all Claude settings are kept local); each developer opts in locally |
| Shipped plugin | end users *and* this repo | the plugin's `hooks/hooks.json` (`textus boot --lean`), auto-discovered on install/enable | **Yes** — the only shareable delivery |

A wrinkle surfaced at implementation: this repo git-ignores `.claude/settings.json` (and `.claude/settings.local.json`) — Claude settings are deliberately local-only — so the dogfood hook **cannot** be a committed artifact. The committed, shareable mechanism is therefore the **plugin**, not a tracked settings file. The repo previously shipped textus *only* as an `.mcp.json` MCP-server entry; 0.50.0 adds a plugin (`.claude-plugin/plugin.json` + `hooks/hooks.json`) so enabling textus auto-registers the SessionStart hook. The `.mcp.json` analogy in earlier drafts was imperfect: `.mcp.json` is tracked, `.claude/settings.json` is not. The agent-invokable `boot` tool stays regardless — the hook is additive, not a replacement.

**SessionStart schema (verified):** `SessionStart` is an array of matcher-groups; each declares a `matcher` (`startup`/`resume`/`clear`/`compact`) and a nested `hooks` array. We register `startup`, `clear`, and `compact` (the cases where context is fresh or was lost); `resume` is skipped (context is preserved). Plain stdout from the command is injected as `additionalContext` — no JSON wrapper needed. `hooks/hooks.json` is auto-discovered at the plugin root (no `plugin.json` reference required).

### 5. Delivery and recovery are complementary (relation to ADR 0083)

The SessionStart hook solves *orientation at t=0*. ADR 0083's guard-exemption solves *re-orientation at t=N* after a mid-session contract change. They are different moments and both are wanted:

```
 SessionStart hook  → orientation at session start   (no agent action)
 boot (ADR 0083)    → re-orientation after drift      (agent calls it; it self-heals)
```

## Consequences

- **Orientation becomes deterministic, not best-effort.** Every session — including `compact`/`resume` — starts with the agent oriented, without relying on the model choosing to call a tool.
- **No new coupling.** The manifest stays consumer-agnostic; the hook is host-specific glue. Other hosts inject `boot` their own way.
- **A new packaging surface.** Shipping a plugin (not just an MCP entry) is new ground for textus and is the load-bearing open question — it adds a `plugin.json` + `hooks/hooks.json` to maintain. This ADR proposes it but flags it as the part most worth a deliberate yes/no before implementation.
- **`boot` grows a `--lean` mode.** A small, additive CLI/contract change; the full `boot` is unchanged.
- **Unverified host detail.** The `type: command` + `additionalContext` path is the documented, reliable mechanism. A `type: mcp_tool` SessionStart variant was floated during research but is **unverified** and explicitly not relied upon here.

## Alternatives considered

- **Leave `boot` pull-only (status quo).** Rejected: orientation that depends on the model deciding to call a tool is unreliable; the cost of a missed `boot` is an under-informed agent operating against rules it never read.
- **Inject via an MCP resource the agent `@`-mentions.** Rejected: still pull (the user/model must reference it), and it does not fire at session start.
- **Add an `inject_on_session_start` flag to the manifest.** Rejected: couples textus's data model to one host's session lifecycle. Delivery is the host's concern; the manifest should not know about Claude Code session events.
- **Always inject the full `boot` envelope.** Rejected: wasteful on `compact`/`resume` where context budget is tight. `--lean` is the right default for repeated injection; the full contract stays one tool call away.
- **Document a `.claude/settings.json` hook only; do not ship a plugin.** Viable as a first step (and is exactly what the dogfooding repo does), but it pushes per-user setup onto every consumer. Shipping the plugin is what makes orientation turnkey on install — hence the recommendation, with the packaging cost called out.
