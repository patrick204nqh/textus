## 1. What textus is

A storage convention and JSON wire protocol for humans, agents, and automation to read and write structured project memory **deterministically**. It provides addressable dotted keys, schema validation, capability-based write gates, declarative data sources, and a list of publish targets that copy or render that data.

The storage lives in a `.textus/` directory at the project root. Each entry is a Markdown file with YAML frontmatter. A manifest binds dotted keys to subtrees, declares the capabilities each role holds, and declares each lane's kind — write authority for a lane is derived from the role's capabilities and the lane's kind. Schemas (also YAML) define what frontmatter shape each entry must have. Produced entries acquire their data via a declared `source:` (a pure projection over other entries, an external fetch, or an out-of-band workflow); that data is then optionally published to repo-relative paths — copied verbatim, or rendered through a per-target ERB template. The CLI surface (`textus get/put/list/where/schema/drain/...` `--output=json`) returns a versioned envelope any caller can parse without knowing Markdown.

You **shape your own memory structure** inside `.textus/`. The protocol manages how it's read, written, addressed, validated, gated, computed, and published. The contents are entirely yours.

### 1.1 Vocabulary axes

textus/4 names its concepts along six axes. Reviewers who internalize these can map any part of the spec to the right category:

- **Actor** — who is interacting: roles such as `human`, `agent`, `automation`, each holding a set of capabilities (`propose`, `author`, `keep`, `converge`).
- **Place** — where data lives: lanes such as `knowledge`, `notebook`, `raw`, `proposals`, `artifacts`.
- **Thing** — what is stored: entries, fields, keys.
- **Operation** — how you act on things: RPC and CLI verbs (`get`, `put`, `drain`, `serve`, `ingest`, …).
- **Event** — what gets fired after an operation: pub-sub events (`:entry_written`, `:entry_produced`, `:entry_published`, …).
- **Rule** — constraints declared in the top-level `rules:` array of the manifest.

### 1.2 The five layers

textus is organized as five composable layers. Each layer has a single responsibility; later layers build on earlier ones.

| Layer | Name | Responsibility |
|---|---|---|
| L1 | **Store** | Plain-file backend: `.textus/data/<lane>/...` with YAML frontmatter + Markdown body, addressed by dotted keys, schema-validated, etag-versioned. |
| L2 | **Sources** | Produced entries in the `artifacts` machine lane declare a `source:` block (`from: external` + a `Textus.workflow` block) that acquires their data on `drain`. textus *describes* sources; the workflow DSL acquires data and returns it to the store. |
| L3 | **Source** | An entry's `source:` *acquires* **data** — a pure in-process projection from store entries (select/pluck/sort/transform), an external fetch via a handler, or an out-of-band command. Acquire-only: rendering is not a source concern. No shell execution. |
| L4 | **Publish** | Emits a produced entry's data to repo-relative paths, declared via a **list** of `publish:` targets. A target with no `template:` copies the data verbatim (json/yaml re-serialized without `_meta`; other formats byte-copied); a target with a `template:` renders the data through it. A `{ tree: }` target mirrors a subtree (ADR 0047). Published artifacts are clean content — textus's `_meta` provenance stays in the store. A sentinel under `.textus/.run/sentinels/<target-rel-path>.textus-managed.json` (git-ignored runtime state) records the source, sha256, and `mode: "copy"`. |
| L5 | **Consumers** | Anything that reads the published files or calls the CLI — editors, LLM tools, MCP servers, CI jobs, dashboards. textus is agnostic about who consumes; the envelope is the contract. |
