# ADR 0100 — `produce/` topology + de-fossilized names

**Date:** 2026-06-07
**Status:** Accepted
**Refines:** [ADR 0093](./0093-source-retention-over-one-reconcile-engine.md) (its "one reconcile engine" framing implied a single `produce/` home for all materialization concerns — the namespace scatter this ADR eliminates is residual pre-0093 layout), [ADR 0094](./0094-source-data-publish-render.md) (it established the acquire ÷ render split as the two acts of the produce pipeline — this ADR makes that split visible in the file tree rather than hiding it across three unrelated directories), [ADR 0095](./0095-collapse-produced-kind.md) (it merged `Entry::Derived` + `Entry::Intake` into one `Entry::Produced` class, establishing "produced" as the canonical produce concept — this ADR applies that same label to the pipeline that materializes produced entries).

> **One sentence:** the produce pipeline — *acquiring* intake data via handlers/fetch and *rendering* publish output — is currently scattered across `maintenance/`, `write/`, and `builder/` with fossilized `fetch_*` names left over from a pre-ADR-0094 era when "fetch" was the only produce path, so this ADR gathers it all under one `lib/textus/produce/` namespace split into `acquire/` (intake data) ÷ `render/` (publish output), renames every `fetch_*` / `FetchWorker` / `IntakeFetch` / `DataBuilder` constant to its honest `Produce::` equivalent, and keeps the verb surface, the manifest grammar, and every user-observable behavior **unchanged** — Zeitwerk derives constants from file paths, so moving the file is the rename.

## Context

ADR 0094 named the two acts of the produce pipeline:

- **Acquire** — bring bytes into the store: run a handler (`from: handler`), run a
  projection (`from: project`), or accept an out-of-band artifact (`from: command`).
- **Render** — emit stored bytes to a publish destination: copy, symlink, or format
  into the `publish:` paths.

Those two acts are the right decomposition. But the *code* did not grow up around
that decomposition — it grew up around an earlier "fetch only" model where `from:
handler` was the only produce path, and every class was named after fetching:

- `Write::FetchWorker` — the Sidekiq-style worker that enqueues an acquire job.
- `Write::IntakeFetch` — the handler that receives the acquire callback.
- `Write::FetchEvents` — the event bus wiring for acquire callbacks.
- `Write::PublishRenderer` — the render act, marooned in the same `write/` directory
  as the acquire classes despite being a separate concern.
- `Write::DataBuilder` / `Builder::Pipeline` — the projection runner, split across
  two unrelated directories.
- `Builder::Renderer::{Json,Yaml,Text}` — the serializers for projection output,
  hidden inside a generic `builder/` namespace.
- `Maintenance::Produce` / `Maintenance::Produce::AsyncRunner` — the engine that
  orchestrates the above, living in `maintenance/` (the reconcile verb's home)
  rather than alongside the pipeline it runs.

The `fetch_*` / `FetchWorker` / `IntakeFetch` names are **fossils**: they name
the intake-specific path of the acquire act but are used as entry points to a
pipeline that also handles projection and command sources. `Builder::Pipeline` and
`Builder::Renderer` carry a generic `builder/` prefix that says nothing about their
role. `Maintenance::Produce` is the engine buried in the wrong directory.

None of this is wrong at runtime — the behavior is correct. The cost is **reader
confusion**: to understand the produce pipeline, a reader must trace constants
across three namespaces (`maintenance/`, `write/`, `builder/`) and mentally
translate `FetchWorker` → "the thing that queues acquire jobs" and
`Builder::Pipeline` → "the projection runner". The ADR 0094 acquire ÷ render
split is the right map; the file tree should be that map.

## Decision

### 1. One `lib/textus/produce/` namespace

All produce-pipeline files move under `lib/textus/produce/`, split into:

```
lib/textus/produce/
  engine.rb                 # was Maintenance::Produce
  engine/
    async_runner.rb         # was Maintenance::Produce::AsyncRunner
  acquire/
    intake.rb               # was Write::FetchWorker
    handler.rb              # was Write::IntakeFetch
    projection.rb           # was Write::DataBuilder + Builder::Pipeline
    serializer/
      json.rb               # was Builder::Renderer::Json
      yaml.rb               # was Builder::Renderer::Yaml
      text.rb               # was Builder::Renderer::Text
  events.rb                 # was Write::FetchEvents
  render.rb                 # was Write::PublishRenderer
```

`Produce::Engine` orchestrates both acts. `Produce::Acquire::*` covers the intake
and projection paths (bringing bytes in). `Produce::Render` covers emit (pushing
bytes out). `Produce::Events` wires the async bus. The split is the ADR 0094
acquire ÷ render decomposition made visible in the file system.

### 2. Rename map

| New constant | Old constant |
|---|---|
| `Produce::Engine` | `Maintenance::Produce` |
| `Produce::Engine::AsyncRunner` | `Maintenance::Produce::AsyncRunner` |
| `Produce::Acquire::Intake` | `Write::FetchWorker` |
| `Produce::Acquire::Handler` | `Write::IntakeFetch` |
| `Produce::Events` | `Write::FetchEvents` |
| `Produce::Acquire::Projection` | `Write::DataBuilder` + `Builder::Pipeline` |
| `Produce::Acquire::Serializer::Json` | `Builder::Renderer::Json` |
| `Produce::Acquire::Serializer::Yaml` | `Builder::Renderer::Yaml` |
| `Produce::Acquire::Serializer::Text` | `Builder::Renderer::Text` |
| `Produce::Render` | `Write::PublishRenderer` |

`Write::DataBuilder` and `Builder::Pipeline` are merged into the single
`Produce::Acquire::Projection` — they were a split-site implementation of one
concept (run a `from: project` projection and serialize its output), now unified
under the honest name.

### 3. Zeitwerk — moving the file is the rename

textus uses Zeitwerk for constant autoloading. Zeitwerk derives constant names
from file paths: `lib/textus/produce/acquire/intake.rb` → `Produce::Acquire::Intake`.
No `autoload` declarations, no `require` calls, no constant aliases are needed.
Moving the file to the new path and updating all call sites is the complete rename.

### 4. No behavior change — verb surface and manifest grammar unchanged

This is a **pure mechanical move + rename**:

- The verb surface (`fetch`, `reconcile`, `get`, `pulse`, `doctor`, and all other
  CLI/MCP verbs) is **unchanged**.
- The manifest grammar (`source:`, `publish:`, `kind:`, `from:`, etc.) is
  **unchanged**.
- The wire protocol (envelope shapes, `_meta` keys, store layout) is **unchanged**.
- No migration hint is needed — nothing user-observable changes.

All call sites within `lib/` and `spec/` that reference the old constants are
updated in the same commit as the file moves.

## Consequences

- **The file tree matches the ADR 0094 mental model.** A reader following "acquire
  ÷ render" finds exactly two subdirectories under `produce/`; there is no `write/`
  or `builder/` to cross-reference.
- **Fossil names are retired.** `FetchWorker`, `IntakeFetch`, `FetchEvents`,
  `DataBuilder`, `Builder::Renderer` no longer exist; the honest names —
  `Intake`, `Handler`, `Events`, `Projection`, `Serializer` — make the role legible
  from the constant alone.
- **`Maintenance::Produce` is out of `maintenance/`.** The engine that runs the
  produce pipeline lives next to the pipeline, not inside the reconcile verb's home.
- **No user-observable change.** Verb surface, manifest grammar, wire protocol, and
  store layout are all frozen; this commit moves + renames constants, nothing more.
- **`Write::DataBuilder` + `Builder::Pipeline` merge.** Two files that implemented
  one concept (run-a-projection-and-serialize) become one class; the split was an
  artifact of the old directory layout, not a meaningful separation.

## Alternatives considered

- **Rename without moving (keep `write/` and `builder/`).**  Rejected: better
  constant names inside a misleading directory structure would be an improvement,
  but the directory structure is exactly where reader confusion starts. The
  acquire ÷ render split must be visible in the tree to be useful as a map.
- **Merge `acquire/` and `render/` — one flat `produce/` directory.** Rejected:
  acquire (bring bytes in) and render (push bytes out) are genuinely distinct
  acts with different triggering conditions and different callers; keeping them
  in named subdirectories preserves the ADR 0094 decomposition as a physical
  boundary, not just a comment.
- **Move only the engine (`Maintenance::Produce` → `Produce::Engine`), leave the
  rest.** Rejected: a tidy engine class pointing at fossilized workers in
  `write/FetchWorker` would be a partial cleanup that leaves the `fetch_*` fossils
  and the `builder/` scatter in place — net confusion gain is small, and the
  incomplete topology blocks a clean ADR 0094-aligned reading of the codebase.
