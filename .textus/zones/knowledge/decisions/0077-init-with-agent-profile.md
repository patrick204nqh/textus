# ADR 0077 — `init --with-agent`: an opt-in profile that wires a fresh store to an agent

**Date:** 2026-06-03
**Status:** Accepted
**Refines:** [ADR 0041](./0041-dogfood-textus-in-its-own-repo.md) (textus dogfoods itself with a hand-authored self-development store + `.mcp.json` wiring — this generalizes that wiring into an opt-in scaffold any end user can ask `init` for, instead of copying it by hand).
**Touches:** [ADR 0073](./0073-surfaces-declare-external-projections.md) (`:cli`/`:mcp` are *external projections*; this ADR leans on the same framing to treat `CLAUDE.md`/`AGENTS.md`/`.mcp.json` as downstream projections of a vendor-neutral store, never canon), [ADR 0050](./0050-native-authoring-and-content-identical-adoption.md) (own multi-file artifacts by native authoring — the orientation projection is the native-authoring path applied to agent orientation), [ADR 0052](./0052-typed-publish-block.md) (the `publish:` block the orientation entry uses), [ADR 0070](./0070-content-addressed-build-artifacts.md) (the orientation rebuild is idempotent), [ADR 0076](./0076-build-gates-by-capability-actor-surface-to-mcp.md) (the companion decision that lets the agent rebuild the orientation this profile scaffolds, over MCP).

> **One sentence:** `textus init` produces a vendor-neutral store but leaves it *unwired* — to actually use it with an agent you must hand-author a `.mcp.json` and a `CLAUDE.md` projection — so this ADR adds an opt-in `--with-agent` profile that scaffolds the proven setup (a buildable `CLAUDE.md`/`AGENTS.md` orientation projection + a write-once starter `.mcp.json`), keeping the *default* `init` neutral while giving newcomers a batteries-included path, and accepting that under the flag `init` writes exactly one file outside `.textus/`.

## Context

`textus init` today scaffolds only the neutral store — `manifest.yaml`, the five zones, a sample intake hook, the derived `.gitignore` — all strictly inside `.textus/` (`lib/textus/init.rb`). That is the right *default*: the store is the durable, vendor-neutral artifact, and textus's whole thesis is that it "survives the session, the model, and the vendor."

But a freshly-init'd store is **inert to an agent**. Two things stand between `init` and a working agent session, and today both are manual:

1. **MCP wiring.** Nothing tells an agent harness how to reach the store. A user must hand-author a `.mcp.json` pointing at `textus … mcp serve` — exactly what textus itself did by hand in ADR 0041, and what every user currently copies from the README.
2. **Orientation.** The agent-readable `CLAUDE.md`/`AGENTS.md` that projects the store's `knowledge.*` into a session-start brief doesn't exist until someone builds it. The *proven* configuration for this — an `artifacts.orientation` derived entry with a projection template + reducer — already lives in `examples/project/.textus/`, but it is not reachable from `init`.

**The tension.** `CLAUDE.md`, `AGENTS.md`, and `.mcp.json` are vendor-shaped filenames. Does scaffolding them couple the store to a vendor and betray the neutrality thesis? **No — provided two conditions hold:** the files are (a) *opt-in*, not forced on the neutral default, and (b) *downstream projections*, not canon. ADR 0073 already names `:cli`/`:mcp` "external projections"; `CLAUDE.md`/`AGENTS.md` are derived artifacts — deletable, rebuildable, with the source of truth staying in `knowledge.*`. So shipping an opt-in *profile* of vendor projections is on-thesis; baking them into the *default* would not be. That distinction is the whole design.

## Decision

1. **Add `textus init --with-agent`, a pure additive superset of the default manifest.** With the flag, `init` appends (never replaces) three entries — `knowledge.project` and `knowledge.runbooks` (with their `project`/`runbook` schemas) and an `artifacts.orientation` derived entry that projects them, via a template + reducer, to `CLAUDE.md` and `AGENTS.md`. The entry, schemas, template, and reducer are copied **verbatim** from the proven `examples/project/.textus/` configuration. Every existing default-`init` entry is untouched, so the base path stays byte-identical.

2. **The default `init` (no flag) is unchanged and stays vendor-neutral.** Batteries are opt-in. The boundary between "create a durable store" and "wire it to a vendor" stays explicit — a user who wants the neutral core gets exactly that.

3. **Write a starter `.mcp.json` once, at the project root — the one file `init` writes outside `.textus/`.** It is *write-once / never-clobber*: if a `.mcp.json` already exists, `init` leaves it untouched and reports `skipped`. It is **not** a derived artifact, by necessity: an agent needs `.mcp.json` to reach textus *before* any `build` could run, so "rebuild it" is incoherent (a bootstrap circularity). Like `manifest.yaml`, `init` owns the first write and the user owns the file thereafter.

4. **The `.mcp.json` command form assumes a gem-installed `textus` on `PATH`; no install autodetection.** Because the invocation is install-specific (gem vs. bundler vs. plugin), the scaffold writes the common gem form and the user adjusts — consistent with "user-owned after the first write." (The textus repo keeps its own hand-authored `bundle exec` form, ADR 0041.)

5. **Publish targets are `CLAUDE.md` + `AGENTS.md`** — the proven cross-vendor pair (`AGENTS.md` is the emerging cross-vendor convention; `CLAUDE.md` for Claude Code) — not a single `AGENT.md`.

## Consequences

- **A newcomer is one command from a working agent loop.** `textus init --with-agent`, author `knowledge.project` + a runbook, and they have a connectable MCP server *and* a buildable orientation — no hand-wiring. Paired with ADR 0076, the agent can edit `knowledge.*` and rebuild its own `CLAUDE.md`/`AGENTS.md` entirely over MCP.

- **`init`'s write surface widens by exactly one file outside `.textus/`** (`.mcp.json`), and only under the flag, and only when absent. The default path's invariant — *`init` writes only inside `.textus/`* — still holds. This is the load-bearing change worth recording: `init` is no longer purely store-local when `--with-agent` is set.

- **The profile is a snapshot of `examples/project`.** The scaffolded files are verbatim copies; if the example config evolves, the `init` scaffold and the example can drift. The example remains the source of truth; keeping the copies verbatim makes the drift mechanical to reconcile.

- **No new vendor coupling in the neutral core.** Users who never pass `--with-agent` get a store with zero vendor-shaped files — the neutrality guarantee is intact for the default.

## Alternatives considered

- **Bake the agent setup into the default `init` (no flag).** Rejected: it couples the neutral core to vendor-shaped files for every user, including those who don't want them — directly against the store-survives-the-vendor thesis. The opt-in flag keeps the default honest while still offering batteries.

- **A separate `textus adopt` / `wire <vendor>` verb.** Rejected *for now*: a new verb plus per-vendor parameterization is more surface than the single-flag profile needs, and the 90% case is one vendor (Claude Code / the `AGENTS.md` convention). The per-vendor `adopt` path stays open for when a second concrete vendor target justifies the structure — this ADR doesn't preclude it.

- **Generate `.mcp.json` as a derived `build` artifact.** Rejected: the bootstrap circularity — you'd need the MCP wiring to run the build that produces the MCP wiring. Write-once-at-init sidesteps it cleanly, and the file being user-owned afterward matches how install-specific the invocation is.

- **Scaffold a single `AGENT.md`.** Rejected in favour of the proven `CLAUDE.md` + `AGENTS.md` pair, which is what `examples/project` already builds and what current harnesses read.

- **A minimal orientation that projects only `knowledge.identity` (avoid the extra schemas/entries).** Rejected: it would require authoring a *new* reducer + template instead of copying the battle-tested ones, trading two tiny schema files for novel, unproven scaffold code. The verbatim-copy path is lower-risk and keeps the example as the single source of truth.
