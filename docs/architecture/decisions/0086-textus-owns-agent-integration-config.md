# ADR 0086 — textus owns agent-integration config: consolidate the plugin manifest, fold MCP + hook into it, keep `init` as the no-plugin fallback

**Date:** 2026-06-04
**Status:** Proposed
**Refines:** [ADR 0077](./0077-init-with-agent-profile.md) (`init --with-agent` scaffolds a write-once `.mcp.json` — this ADR positions that as the no-plugin fallback and adds the plugin as the primary, fuller delivery).
**Touches:** [ADR 0084](./0084-boot-injected-at-session-start.md) (ships the plugin with an inline SessionStart hook — this ADR generalizes "fold setup into the manifest" to the MCP server too), [ADR 0070](./0070-content-addressed-build-artifacts.md) (content-addressed build artifacts — `.mcp.json`/`plugin.json` join that class for the self-shipped repo), [ADR 0081](./0081-docs-become-canon-published-out.md) (canon-published-out — the same projection mechanism), [ADR 0050](./0050-native-authoring-and-content-identical-adoption.md) (content-identical adoption — the zero-diff migration path).

> **One sentence:** textus's agent-integration config — the plugin manifest (`.claude-plugin/plugin.json`, inline `hooks` + `mcpServers`), the MCP-server registration (`.mcp.json`), and the lean orientation they deliver (`boot --lean`) — is authored ad hoc across files that don't share a source; this ADR has textus *manage* it the way it manages `CLAUDE.md` (ADR 0081): **one canon definition of "the textus agent integration" → `textus build` projects it into both `.mcp.json` and `.claude-plugin/plugin.json` as content-addressed build artifacts** (version stamped from `Textus::VERSION`, so drift is impossible by construction) — *for the repo that owns its config, textus itself*; downstream consumer repos keep `init --with-agent`'s **write-once** `.mcp.json` (bootstrapping + don't-clobber-the-user, per ADR 0077). The split is by *ownership*, not by file.

## Context

As of 0.50.0 (ADR 0084) the textus repo ships a Claude Code plugin: a self-contained `.claude-plugin/plugin.json` whose inline `hooks` registers a `SessionStart` → `boot --lean` orientation. Separately, ADR 0077's `init --with-agent` writes a **write-once** `.mcp.json` (the MCP-server wiring) — `init.rb` literally `return "skipped" if File.exist?`. These are two disconnected mechanisms for the same goal — *wire an agent to a textus store* — and a third file, the plugin manifest, now overlaps the same territory.

Two structural facts shape the decision:

1. **Plugin manifests can carry the MCP server too.** `plugin.json` accepts an inline `mcpServers` object (paths via `${CLAUDE_PLUGIN_ROOT}`). So a single plugin install can register *both* the MCP server *and* the SessionStart hook — "one enable, fully wired." Today the MCP wiring lives only in a hand-/`init`-authored `.mcp.json`.
2. **The managed-file class depends on *ownership*, not on the file.** textus has two: regenerated **build artifacts** (`CLAUDE.md`, `docs/` — textus-owned, byte-stable, clobbered on rebuild; ADR 0070/0081) and **write-once scaffolds** (`.mcp.json` — seeded once, then user-owned; ADR 0077). The earlier draft of this ADR put all integration config in the write-once class. That was too coarse: a file textus *authors for itself* (this repo's own `.mcp.json` + plugin manifest) is textus-owned and belongs in the build-artifact class; a file textus *scaffolds for a consumer* is the consumer's and belongs in the write-once class. The same filename (`.mcp.json`) lands in different classes depending on who owns it.

3. **Bootstrapping forces write-once downstream.** A fresh consumer store must be wired the moment `init --with-agent` runs — before any `build`, before any canon exists to project from. So downstream `.mcp.json` *must* be an immediate write-once scaffold; it cannot be a build artifact. Only a repo where textus is already present and owns its config (textus itself) can manage these via `build`.

## Decision (proposed)

1. **One canon definition of "the textus agent integration."** A single canon source describes the integration: the MCP-server launch command, and the `SessionStart` hook config. It is the source of truth both projections derive from.

2. **`textus build` projects it into both files as content-addressed build artifacts — for the textus repo itself.** A derived entry computes and `publish`es:
   - `.claude-plugin/plugin.json` — inline `hooks` (ADR 0084) + inline `mcpServers`, `version` stamped from `Textus::VERSION` at build time.
   - `.mcp.json` — the MCP-server entry (this repo's working-tree command).

   Both publish to repo-root paths exactly like `CLAUDE.md`/`AGENTS.md` (ADR 0081), are sentinel-managed and byte-stable (ADR 0070), and are never hand-edited. Because the build is content-addressed, embedding `Textus::VERSION` carries no idempotence hazard — the bytes change only on a real version bump (no `generated_at` churn). Release flow: bump `version.rb` → `textus build` → both files regenerate → commit.

3. **Downstream consumers keep `init --with-agent`'s write-once `.mcp.json`.** Rationale (§Context 3): a fresh store must wire on `init` without a build, and a build must never clobber a *consumer's* customized config (ADR 0077 stands). `init` may also grow a write-once plugin-manifest scaffold for consumers who want the full setup. Build-artifact management is opt-in and only natural for a repo that owns its config.

4. **Drift is solved by construction, not by a check.** Because `plugin.json` is *generated* with `Textus::VERSION` embedded, its version can never drift off the gem version — superseding the earlier draft's proposed `doctor version-match check` (which only made sense while the file was hand-authored). A `doctor` check that inline-hook/command verbs exist in the contract may still be worthwhile as a generic guard.

5. **Migration is zero-diff (ADR 0050).** The generated `.mcp.json` and `plugin.json` are made byte-identical to the current hand-authored files at 0.50.0, so adopting the build path is a content-identical republish — the same move ADR 0081 used to make `docs/` canon. Shipping 0.50.0 hand-authored wastes nothing.

## Consequences

- **One source, two projections.** The MCP command + hook config live once in canon; `build` keeps `.mcp.json` and `.claude-plugin/plugin.json` consistent and version-synced. DRY across the two files that previously drifted independently.
- **textus dogfoods its own build/publish for its own agent wiring** — the same projection that produces `CLAUDE.md` now produces its MCP + plugin config. Strong dogfood signal.
- **Drift can't happen.** Version is stamped from `Textus::VERSION`; no hand-maintenance, no check needed.
- **Downstream is unaffected.** Consumers still get an immediate, customizable, write-once `.mcp.json` from `init`; their files are never clobbered by a textus build.
- **`.mcp.json` + plugin manifest join the sentinel-managed published set** (like `CLAUDE.md`) — they show in `published`, are pruned/repaired by the build, and must not be hand-edited in this repo.
- **Scope to settle before accepting:** the exact canon shape (a `knowledge` entry vs. a manifest block) for the integration definition; whether a JSON build artifact needs a templateless computed-publish path (orientation uses mustache→markdown; JSON is better produced by a reducer returning the structure); and whether the dogfood repo also consumes its own plugin or keeps the tracked `.claude/settings.json` hook.

## Alternatives considered

- **Validate-only; never regenerate (the earlier draft of this ADR).** Rejected for the self-shipped repo: textus *authors* these files, so regeneration is the point — it keeps version and config in sync and removes two hand-maintained files. Validate-only leaves drift possible and the files hand-edited. (Validation is retained as a secondary guard, not the primary mechanism.)
- **Make *all* `.mcp.json` build artifacts, including downstream.** Rejected: breaks bootstrapping (a fresh store has nothing to build from) and clobbers consumer customization (ADR 0077). The build-artifact treatment is scoped to repos that own their config.
- **Keep both files hand-authored (the 0.50.0 state).** Fine as a shipping state, but leaves version drift and two disconnected files; this ADR is the path off that.
- **A top-level `hooks/`/`commands/` plugin layout (the spec default).** Rejected: pollutes the gem repo root. Inline `hooks`/`mcpServers` in the manifest keep the plugin a self-contained, separate concern.
- **Keep MCP wiring only in `.mcp.json`; plugin carries only the hook.** Viable (it's the 0.50.0 state) but leaves two disconnected setup mechanisms. Folding `mcpServers` into the plugin gives "one enable, fully wired" and is the point of shipping a plugin at all.
- **Leave the config hand-authored, no `doctor` validation.** Rejected: `plugin.json` `version` silently drifting off the gem version is a real failure mode; cheap validation prevents it without textus owning the file.
- **A top-level `hooks/`/`commands/` plugin layout (the spec default).** Rejected: it pollutes the gem repo root with plugin files. Inline `hooks`/`mcpServers` in the manifest keeps the plugin a self-contained, separate concern.
