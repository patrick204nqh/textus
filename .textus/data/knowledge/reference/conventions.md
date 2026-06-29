# Conventions

> **Reference** · for integrators · **read when** you're shaping a `.textus/` tree and want the idiomatic choices
> **SSoT for** idiomatic key naming, schema design, and automation integration · **reviewed** 2026-06 (v0.43)

Guidelines for shaping a `.textus/` tree, naming keys, organising schemas, and integrating with build automation. The spec ([`../../SPEC.md`](../../SPEC.md)) defines what's enforceable; this document captures what's *idiomatic*.

## Key naming

- **Segments are lowercase, kebab- or snake-case.** The grammar `^[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?$` is the hard limit. Prefer `acme-dashboard` over `acmedashboard` when there's a natural word break.
- **Lead with the lane in the key path.** `working.projects.acme.dashboard`, not `projects.acme.dashboard`. The lane prefix makes it obvious from the key alone whether a write will be accepted.
- **Mirror the directory structure.** If `working.projects.acme.dashboard` resolves to `working/projects/acme/dashboard.md`, do not invent shortcuts that diverge.
- **Don't pluralise the leaf.** `working.network.org.jane`, not `working.network.org.janes`. Pluralise the container, not the entry.

## Lane layout

Recommended top-level layout — the spec allows alternatives, but this is what tooling will default to:

```
.textus/
  manifest.yaml
  schemas/        # YAML schema definitions
  workflows/      # Textus.workflow DSL files for produced entry acquisition
  templates/      # ERB templates for publish rendering
  data/
    knowledge/    # authored truth: identity, voice, decisions — author-holders write
    scratchpad/     # agent's own durable lane (workspace) — keep-holders write
    proposals/    # AI proposals awaiting accept (propose)
    artifacts/    # computed outputs produced by drain — never edit by hand
    raw/          # write-once external source material (ingest)
```

Inside `knowledge/`, group by **domain** (identity, people, projects, decisions, runbooks), not by file type or date. `knowledge.identity.*` is the convention for slow-changing identity facts. Inside `artifacts/`, group by **producer** (`artifacts/catalogs/`, `artifacts/indexes/`) so it's clear which build job owns what.

## Schema design

- **One schema per entry type, not per directory.** `person.yaml`, `project.yaml`, `decision.yaml` — applied across multiple subtrees if the shape matches.
- **Required = "this entry is meaningless without it."** Everything else is `optional`. Resist the urge to mark organisational metadata (like `tags`) required.
- **Prefer `enum` over free-text** for low-cardinality fields (relationship type, status, severity). Agents are far better at picking from a list than at producing exact strings.
- **Cap string lengths** with `max:` where the field has a natural bound (names, summaries). Skip for prose body — bodies are not schema-validated, only frontmatter is.

## Owner strings

The `owner:` field in the manifest is **advisory metadata**, not an ACL. Use it to label *who's expected to write here*. The form is `<archetype>` or `<archetype>:<subject>`; the archetype must be one of `human`, `agent`, `automation` (validated at load — ADR 0045), and the subject is free-form:

- `human:network` — humans curate
- `agent:planner` — a specific named agent
- `automation:catalog-skills` — a specific build job

Tooling around `git blame` or audit logs may filter on owner; the gem itself only echoes it back in envelopes.

## Produced entries

A produced entry declares `source: { from: external, command: "true", sources: [] }` and a matching `Textus.workflow` block in `.textus/workflows/**/*.rb`. The `source:` acquires **data** — it never renders; rendering is a publish concern (below).

```yaml
- key: artifacts.feeds.skills
  lane: artifacts
  kind: produced
  format: json
  source: { from: external, command: "true", sources: [] }
  publish:
    - { to: docs/reference/skills.md, template: feeds/skills.erb }
```

The matching workflow block:

```ruby
# .textus/workflows/feeds/agentskills.rb
Textus.workflow "agentskills" do
  match "artifacts.feeds.skills"

  step :fetch do |_, _ctx|
    { "content" => { "skills" => [...], "count" => 1 } }
  end

  publish
end
```

`drain` discovers workflows, matches entries, runs the steps, and writes the result back to the entry's data path. Publishing then copies or renders each `publish:` target.

Age-based GC uses a `retention:` rule in the top-level `rules:` block:

```yaml
rules:
  - match: artifacts.feeds.**
    retention: { ttl: 90d, action: archive }
```

Full contract in [`../../SPEC.md` §5.2](../../SPEC.md).

## Freshness

A `get` is always a pure read (ADR 0089) — it never triggers a re-produce:

```sh
textus pulse --output=json       # `stale` lists entries past their ttl
textus drain --as=automation     # re-produces stale entries
```

See [`./lanes.md`](lanes.md) for lane semantics and [`../how-to/configuring-lanes.md`](../how-to/configuring-lanes.md) for setting up produced entries and workflows.

### Read vs. refresh

There is one public read operation, and it is pure (ADR 0089):

| Operation | Behaviour | Use for |
|-----------|-----------|---------|
| `ops.get` | A pure on-disk read annotated with a freshness verdict — it NEVER ingests, regardless of the entry's `action`. A stale `refresh` entry reads back stale until the next `drain`. | every caller — interactive reads, dashboards, scripts, and internal pipelines (materializer, projection, schema tooling, accept/reject/publish, uid, validator) |

Refreshing a stale entry is `drain`'s job (or a `hook run` event), never a read's — so no caller can accidentally trigger network I/O by reading.

## Body content

- **Bodies are Markdown.** Headings, lists, code fences — whatever a human or agent finds useful.
- **The schema does not validate the body.** If a field belongs in structured data, put it in frontmatter, not the body.
- **Keep entries short.** If a project entry hits 500 lines, it probably wants to be split into sub-entries (e.g. `working.projects.acme.dashboard` + `working.projects.acme.api`) rather than one mega-document.

## Concurrency

For multi-writer environments, **always pass `if_etag`** on `put`. The gem treats etag-less writes as last-writer-wins on purpose (single-writer scripts, fresh-file creation), but anything resembling a daemon or a long-running agent should round-trip the etag.

## Application layering

The application layer is organised around `Store` as the single dispatch module, `Container` as a capability record (`Data.define` composition of `Infrastructure` + `Coordination`), and a split envelope reader/writer. See [ADR 0119](../architecture/decisions/0119-architecture-deepening-phase-2.md) and [ADR 0120](../architecture/decisions/0120-unify-store-dispatch-paths.md).

- **`Manifest` is a composition record** (`Data.define(:data, :resolver, :policy, :rules)`). Reach individual concerns through the field accessors: `manifest.data.entries`, `manifest.policy.permission_for(lane)`, `manifest.resolver.resolve(key)`, `manifest.rules.for(key)`.
- **`Store` is the single dispatch module.** `Store` holds the `Container`, the active role, session state (cursor, propose_lane, contract_etag), and dispatches verbs through `method_missing`. Each verb call (`store.get(key: ...)`, `store.put(key:, meta:, body:)`) goes through `VerbRegistry`, binds inputs via `Dispatch::Binder`, routes through `Dispatch::Pipeline` (middleware chain: auth, cascade, audit), and reaches the handler. `Store#with_role(role)` returns a new `Store` bound to that role.
- **`Container` is a `Data.define` composition** of `Infrastructure` (`file_store`, `schemas`, `audit_log`, `job_store`, `geometry`) and `Coordination` (`manifest`, `workflows`, `pipeline`). Built in a single pass — no circular dependencies or lazy proxies.
- **Dispatch lives in `lib/textus/dispatch/`**: `Dispatch.dispatch` orchestrates verb dispatch, `Dispatch::Pipeline` runs middleware then invokes the handler, `Dispatch::Binder` handles input binding (wire format, CLI flags, session defaults). Auth predicates moved to `Manifest::Policy::Predicates`.
- **Write path is split**: `Store::Envelope::Reader` owns read/parse, and `Store::Envelope::Writer` owns put/delete/move + the audit-append invariant (every public method's final action is `@audit_log.append(...)`).
- **Handlers receive `container:`** and access I/O via `@container.pipeline.read/write/delete/move` and manifest config via `@container.manifest`.

The user-facing CLI surface, the wire envelope shape, and the protocol version (`textus/4`) are unchanged.

## Pairing with other tools

- **MCP servers**: a thin server that exposes `textus get` and `textus put` as tools is the recommended way to give Claude/agents access. Don't bake MCP into this gem.
- **Vector stores**: index `body` content into a vector store if you want fuzzy retrieval. `frontmatter` stays in textus as the source of truth for deterministic facts.
- **CI**: run `textus doctor` (the `generator_drift` check) or `textus pulse` (the `stale` list) in CI to catch drift between derived entries and their sources.
