# ADR 0041 — Dogfood textus in its own repo: a self-development store + MCP wiring

**Date:** 2026-05-31
**Status:** Accepted
**Refines:** [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (the MCP connection acts as `agent` and pins its root), [ADR 0038](./0038-runtime-artifacts-under-run-and-layout.md) (runtime artifacts under `.run/`; `role` is tracked config), [ADR 0036](./0036-transports-as-pure-framings.md) (MCP is one framing over the verb vocabulary)
**Touches:** [ADR 0015](./0015-agent-gate-mcp.md) (the agent gate is MCP-shaped), [ADR 0030](./0030-capability-based-roles.md) (capability roles), [`docs/how-to/agents-mcp.md`](../../how-to/agents-mcp.md) (the end-user Claude Code wiring guide), [`.textus/`](../../../.textus/) (the worked store this mirrors)

## Context

textus exists to wire a durable, multi-writer context store into Claude Code
and other MCP agents (`docs/how-to/agents-mcp.md`). The repo documents that integration
and ships a worked `.textus/` store — but **the textus repo did not run
textus on its own development.** A `.textus/` skeleton existed, uncommitted and
empty (only `.gitkeep`s); there was no `.mcp.json`, no projected `CLAUDE.md`. A
tool whose entire pitch is "wire me in for durable agent memory" was not wired
into the one repo where its maintainers and their agents do the most context-
heavy work — 41 ADRs, a dense convention surface, and a wire contract that moves
roughly weekly.

Two facts make the gap worth closing deliberately rather than by copy-paste:

- **The repo's own context is exactly textus's target case.** Decisions,
  conventions, and runbooks are canon that humans author and agents must read
  but not silently overwrite — the multi-writer problem textus enforces at the
  protocol level. Self-hosting also makes the MCP transport its own best
  regression net: `boot`/`pulse`/`propose` run against live code every session,
  and `ContractDrift`/`CursorExpired` (ADR 0040) fire in the maintainer's own
  loop the moment the contract moves.
- **"A Claude/MCP setup" is two different artifacts, and the question conflates
  them.** The `docs/how-to/agents-mcp.md` quickstart uses `command: "textus"`, which
  resolves to the *installed gem* — correct for an end user. For *developing
  textus*, that is precisely wrong: the agent's MCP server would be the last
  released gem, not the code under review. The self-development setup must drive
  the **working tree**.

## Decision

### 1. Commit a self-development store under `.textus/`

`.textus/` is committed (its `.run/` runtime tree stays git-ignored, ADR 0038).
The store is shaped to dogfood the full build/publish path, mirroring
`.textus/`: humans author `knowledge.project` + `knowledge.runbooks`
(canon), the agent keeps durable `scratchpad` notes and `propose`s, automation
`build`s an `artifacts.orientation` projection that publishes to `CLAUDE.md` and
`AGENTS.md` at the repo root. The role/capability split is the standard one
(ADR 0030): human `author`+`propose`, agent `propose`+`keep`, automation `build`.

`CLAUDE.md`/`AGENTS.md` are therefore **generated, not hand-edited** — the
orientation is a projection of the store (`inject_boot: true` folds in the live
boot contract), regenerated with `textus build`. Editing the root files by hand
is a mistake the header comment calls out.

### 2. The MCP wiring drives the working tree, not the gem

`.mcp.json` is committed with:

```json
{ "mcpServers": { "textus": {
  "command": "bundle",
  "args": ["exec", "exe/textus", "--root", ".textus", "mcp", "serve"]
} } }
```

`bundle exec exe/textus` binds the MCP server to the repo's working tree, so the
agent that helps develop textus runs the code under review. `--root .textus`
pins the store explicitly — the agent channel must not rely on cwd discovery
(ADR 0040 §2), and `bundle exec` already requires the project-root cwd to find
the `Gemfile`. The connection inherits the `agent` role default (ADR 0040 §2),
so it can `propose` and `keep` but not `accept` or `put` to canon: the gate the
docs promise is real here.

This is the deliberate inverse of the `docs/how-to/agents-mcp.md` quickstart, which
stays as written for end users (`command: "textus"`, the released gem). The two
configs are different artifacts for different audiences; neither replaces the
other. The guide gains a short pointer to this repo's `.mcp.json` as the live
self-development example.

### 3. Personal Claude settings stay local

`.claude/settings.json` / `.claude/settings.local.json` remain git-ignored
(permissions, statusline, enabled plugins are per-developer). Only the
project-shared contract — `.textus/`, `.mcp.json`, and the generated
orientation — is committed.

## Consequences

- **The integration the repo documents is now the integration the repo runs.**
  The claim in `docs/how-to/agents-mcp.md` is demonstrated in-tree; `.mcp.json` is a
  reviewable, copyable reference and a credibility signal.
- **MCP transport regressions surface in the maintainer's own loop.** Running
  `mcp serve` off the working tree every session is continuous dogfooding of the
  agent gate and the boot/pulse contract.
- **A new sync surface.** The self-dev store tracks a protocol that changes
  often; when the contract moves, `textus build` must be re-run and the store
  reconciled. Mitigation: drift is self-announcing (ADR 0040 error codes), and
  `CLAUDE.md`/`AGENTS.md` are derived, so a stale projection is a one-command fix,
  not a manual edit.
- **Contributors who don't use Claude/MCP are unaffected.** `.mcp.json` and
  `.textus/` are inert unless an MCP-aware agent opens the repo; nothing in the
  build or test path depends on them.

## Alternatives considered

- **Use the end-user config verbatim (`command: "textus"`).** Rejected: it binds
  the agent to the installed gem, so an agent developing textus would run stale
  released code, not the working tree — defeating the regression-net benefit and
  silently lying about what the agent is exercising.
- **Keep the setup local/uncommitted (developer-by-developer).** Rejected: the
  marketing and reference value is in it being *in-tree and reviewable*; an
  uncommitted setup is invisible to contributors and to readers of the guide.
- **Commit `role: agent` in `.textus/role` to gate the connection.** Rejected
  for the same reason as ADR 0040: `role` is tracked, shared config read by every
  transport, so it would also strip the human's own CLI of `author`/`accept`. The
  MCP `agent` default (ADR 0040 §2) already gates the connection without touching
  the human channel.
- **Hand-write `CLAUDE.md`/`AGENTS.md`.** Rejected: it would dogfood nothing and
  drift from the store. Generating them exercises the projection path that is
  textus's headline build feature.

## Open questions

- **Q1 — should this repo's store carry feeds/automation fetch entries?** The
  `feeds` (quarantine) zone exists but is unused here. A real fetch entry (e.g.
  pulling release notes or an upstream changelog) would dogfood the `fetch`
  path too. Deferred until there is a concrete external input worth caching.
- **Q2 — proposal flow in CI.** Should an automation actor open `proposals.*`
  entries from CI (e.g. a drift report) for a human to `accept`? Out of scope;
  noted as a natural next dogfooding step once the store has settled.
