# textus documentation

> **Explanation** · for everyone · **read when** you're not sure which doc you need
> **SSoT for** the docs map + documentation conventions · **reviewed** 2026-05 (v0.30)

The protocol contract lives in [`../SPEC.md`](../SPEC.md). The friendly guides live here.

## Start here

| If you want to… | Read |
|---|---|
| See textus work in 5 commands | [`../examples/hello/`](../examples/hello/) |
| Wire textus into Claude Code / an MCP agent | [`agents-mcp.md`](agents-mcp.md) |
| Use textus as your project's context store | [`../examples/project/`](../examples/project/) |
| Author a Claude plugin backed by textus | [`../examples/claude-plugin/`](../examples/claude-plugin/) |

## Guides (how-to)

| Doc | What it does |
|---|---|
| [`agents-mcp.md`](agents-mcp.md) | Talk to a store as an agent: boot → pulse loop, MCP tools, Claude Code wiring |
| [`events.md`](events.md) | Write and test Ruby hooks |
| [`migrations.md`](migrations.md) | Restructure a store safely (rename keys/zones, bulk delete) |
| [`recipes/`](recipes/) | Task-shaped recipes (e.g. GitHub skill bundles) |

## Reference

| Doc | What it documents |
|---|---|
| [`../SPEC.md`](../SPEC.md) | The `textus/3` wire protocol — the normative contract |
| [`zones.md`](zones.md) | Zones, roles, entries, and data flow — the configuration model |
| [`conventions.md`](conventions.md) | Idiomatic key naming, schema, and runner integration |

## Internals (explanation)

| Doc | What it explains |
|---|---|
| [`architecture/README.md`](architecture/README.md) | How the Ruby implementation is laid out (layers, ports, paths) |
| [`architecture/decisions/`](architecture/decisions/) | ADRs — why each load-bearing decision was made |

## Doc conventions

These rules keep the docs consistent and cheap to maintain. Follow them when adding or editing docs.

1. **One genre per file (Diátaxis).** Every doc is exactly one of: **Tutorial** (teach by doing), **How-to** (help me do X), **Reference** (the facts), **Explanation** (the why). Don't mix genres in one file — split instead. New how-to lands in a guide or `recipes/`; new facts land in a reference doc; new rationale lands in an ADR.
2. **Header contract.** Every doc starts with its H1 followed by two header lines:
   ```markdown
   > **<Genre>** · for <audience> · **read when** <trigger>
   > **SSoT for** <facts this doc owns> · **reviewed** <YYYY-MM> (<version>)
   ```
   The `reviewed` stamp is the staleness signal — bump it when you revise the doc.
3. **Single Source of Truth.** Each fact has exactly one home (named in that doc's `SSoT for`). Everywhere else links to it instead of restating it.
4. **No deep code dumps.** Prefer tables, short snippets, and links. The normative wire details live in `SPEC.md`; guides link to it.
