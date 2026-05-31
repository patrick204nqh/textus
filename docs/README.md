# textus documentation

> **Explanation** · for everyone · **read when** you're not sure which doc you need
> **SSoT for** the docs map + documentation conventions · **reviewed** 2026-05 (v0.31)

The protocol contract lives in [`../SPEC.md`](../SPEC.md). The friendly guides live here.

## Start here

| If you want to… | Read |
|---|---|
| See textus work end-to-end | [`../examples/project/`](../examples/project/) |
| Wire textus into Claude Code / an MCP agent | [`agents-mcp.md`](agents-mcp.md) |
| Use textus as your project's context store | [`../examples/project/`](../examples/project/) |

## Guides (how-to)

| Doc | What it does |
|---|---|
| [`agents-mcp.md`](agents-mcp.md) | Talk to a store as an agent: boot → pulse loop, MCP tools, Claude Code wiring |
| [`how-to/writing-hooks.md`](how-to/writing-hooks.md) | Write and test Ruby hooks |
| [`how-to/migrations.md`](how-to/migrations.md) | Restructure a store safely (rename keys/zones, bulk delete) |

## Reference

| Doc | What it documents |
|---|---|
| [`../SPEC.md`](../SPEC.md) | The `textus/3` wire protocol — the normative contract |
| [`reference/zones.md`](reference/zones.md) | Zones, roles, entries, and data flow — the configuration model |
| [`reference/conventions.md`](reference/conventions.md) | Idiomatic key naming, schema, and automation integration |

## Internals (explanation)

| Doc | What it explains |
|---|---|
| [`architecture/README.md`](architecture/README.md) | How the Ruby implementation is laid out (layers, ports, paths) |
| [`architecture/decisions/`](architecture/decisions/) | ADRs — why each load-bearing decision was made |

## Doc conventions

These rules keep the docs consistent and cheap to maintain. Follow them when adding or editing docs.

1. **One genre per file (Diátaxis).** Every doc is exactly one of: **Tutorial** (teach by doing), **How-to** (help me do X), **Reference** (the facts), **Explanation** (the why). Don't mix genres in one file — split instead. New how-to lands in a guide; new facts land in a reference doc; new rationale lands in an ADR.
2. **Header contract.** Every doc starts with its H1 followed by two header lines:
   ```markdown
   > **<Genre>** · for <audience> · **read when** <trigger>
   > **SSoT for** <facts this doc owns> · **reviewed** <YYYY-MM> (<version>)
   ```
   The `reviewed` stamp is the staleness signal — bump it when you revise the doc.
3. **Single Source of Truth.** Each fact has exactly one home (named in that doc's `SSoT for`). Everywhere else links to it instead of restating it.
4. **No deep code dumps.** Prefer tables, short snippets, and links. The normative wire details live in `SPEC.md`; guides link to it.
5. **Vocabulary canon.** The concept vocabulary is fixed by [ADR 0029](architecture/decisions/0029-concept-vocabulary.md): headline term is **coordination space**; the write-tracks are **lanes** in prose and **zones** in spec/code (the mapping is stated once, in the README); **three planes** is architecture-internal; *fabric* is etymology only. Don't reintroduce retired metaphors ("durable fabric", "shared workspace") as headline terms. The role model is **capability-based** per [ADR 0030](architecture/decisions/0030-capability-based-roles.md), extended by [ADR 0033](architecture/decisions/0033-complete-primitives-and-vocabulary.md) (renamed `accept`→`author`, added the fifth capability `keep`) and [ADR 0035](architecture/decisions/0035-proposal-target-zone-constraint.md): roles declare a `can:` set drawn from the closed five — `propose`, `author`, `keep`, `fetch`, `build` — and write authority is derived from capabilities × zone-kind; `automation` is the umbrella role (it replaced `runner`/`builder`). The role/capability model's SSoT is [`zones.md`](reference/zones.md) — link there rather than restating the set.
6. **Diagrams.** Use Mermaid for diagrams in docs (GitHub renders ```` ```mermaid ````); keep them small (≤ ~8 nodes) and put a one-line plain-text summary directly beneath each block as the no-render fallback. Reserve ASCII diagrams for output that must render in a terminal (CLI help, `textus boot`). Directory **trees** stay as plain text — they are listings, not diagrams.
