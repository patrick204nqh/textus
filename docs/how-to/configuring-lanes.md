# Configuring lanes

> **How-to** · for integrators · **read when** you're declaring lanes, wiring workflows, or setting up produced entries
> **SSoT for** the lane-setup procedures (declare/rename lanes, workflow wiring, derived + publishing, worked example) · **reviewed** 2026-06 (v0.54)

How to shape your context: declare your own lanes, wire external data through workflows, wire derived data out through projections and publishing, and a full worked example.

For the exact lane, role, and entry semantics this guide builds on, see [`../reference/lanes.md`](../reference/lanes.md). For the wire protocol, see [`../../SPEC.md`](../../SPEC.md).

## Table of contents

1. [Declaring your own lanes](#declaring-your-own-lanes)
2. [Wiring produced entries — the workflow DSL](#wiring-produced-entries--the-workflow-dsl)
3. [Publishing](#publishing)
4. [Worked example](#worked-example)

---

## Declaring your own lanes

Edit `.textus/manifest.yaml` and add entries under `lanes:`. A lane declares only its `kind:` — write authority is derived from the kind, never listed per-lane:

```yaml
lanes:
  - { name: <lane-name>, kind: <canon|workspace|machine|queue|raw> }
```

### Declaring a lane's kind

Every lane declares its data-flow role with `kind:` — one of `canon`, `workspace`, `machine`, `queue`, `raw`:

```yaml
lanes:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace }
  - { name: artifacts,  kind: machine }
  - { name: proposals,  kind: queue }
  - { name: raw,        kind: raw }
```

`kind:` is required — a manifest with a kind-less lane is rejected at load. The kind is authoritative: `textus put` routes proposals to the lane declaring `kind: queue` (no name-based guessing). The kind fixes the capability a writer must hold — `canon`⇒`author`, `workspace`⇒`keep`, `machine`⇒`converge`, `queue`⇒`propose`, `raw`⇒`ingest`. This is a **bijection** (ADR 0091/0116): one kind maps to exactly one capability.

Rules: at most one `queue` lane, at most one `machine` lane, and (since `author` is the single trust anchor) at most one role may hold it.

### Renaming defaults

`knowledge`, `notebook`, etc. have no privileged status in the code. Rename freely — a lane carries only its `kind:`:

```yaml
lanes:
  - { name: self,     kind: canon }      # was knowledge
  - { name: scratch,  kind: workspace }  # was notebook
  - { name: outputs,  kind: machine }    # was artifacts
  - { name: review,   kind: queue }      # was proposals
```

### Adding new lanes

A multi-client layout might want a sharper split:

```yaml
lanes:
  - { name: knowledge,   kind: canon }
  - { name: research,    kind: canon }      # AI-assisted research notes — still author-gated
  - { name: deliverable, kind: canon }      # client-facing copy
  - { name: artifacts,   kind: machine }
```

### Tuning role capabilities

Role **names** are a closed set — `human`, `agent`, `automation` — but each role's **capabilities** are yours to tune. Assign any subset of the closed five-verb set (`author`, `propose`, `keep`, `converge`, `ingest`), subject to the one rule that at most one role may hold `author`:

```yaml
roles:
  - { name: human,      can: [author, propose, ingest] }
  - { name: agent,      can: [propose, keep, ingest] }
  - { name: automation, can: [converge, ingest] }
```

### Rules to keep in mind

- **Lane names must be unique.** Duplicates are caught by `textus doctor`.
- **Every entry must declare a lane that exists.** An entry pointing at an undeclared lane raises an error at load time.
- **A lane-kind with no capability holder is read-only at runtime** — if no declared role holds the verb a lane's kind requires, `put --as=anything` will be refused with `write_forbidden`.
- **There is no implicit role hierarchy.** If only `automation` holds `converge`, even a human running `put --as=human` against the `artifacts` lane is refused.
- **At most one role may hold `author`.** The trust anchor is singular.

---

## Wiring produced entries — the workflow DSL

Produced entries acquire their data via `Textus.workflow` blocks in `.textus/workflows/**/*.rb`. Each workflow matches a produced entry by key glob, then runs one or more named steps to acquire its data.

### Declaring a produced entry

```yaml
entries:
  - key: artifacts.skills
    lane: artifacts
    kind: produced
    format: json
    source: { from: external, command: "true", sources: [] }
    publish: [{ to: docs/reference/skills.md, template: feeds/skills.erb }]
```

### Writing the workflow

```ruby
# .textus/workflows/feeds/agentskills.rb
Textus.workflow "agentskills" do
  match "artifacts.skills"

  step :fetch do |_, _ctx|
    # acquire data from any source — HTTP, store reads, file reads, etc.
    skills = [{ "name" => "brainstorming", "description" => "..." }]
    { "content" => { "skills" => skills, "count" => skills.size } }
  end

  publish
end
```

`drain` discovers all workflow files, matches each to produced entries via `match`, runs the steps, and writes the result back to the entry's data path.

### Reading from the store inside a workflow

```ruby
Textus.workflow "orientation" do
  match "artifacts.orientation"

  step :build do |_, ctx|
    project_env = Textus::Action::Get.new(key: "knowledge.project")
                    .call(container: ctx.container, call: ctx.call)
    project = project_env&.meta || {}
    { "content" => { "name" => project["name"] } }
  end

  publish
end
```

### Retention rules

Accumulating lanes can self-prune via a `retention:` rule:

```yaml
rules:
  - match: proposals.**
    retention: { ttl: 30d, action: drop }      # delete aged proposals
  - match: artifacts.feeds.**
    retention: { ttl: 90d, action: archive }   # archive stale bytes
```

`textus drain --as=ROLE` performs the destructive sweep (Phase 2). `action: drop` deletes the leaf; `action: archive` moves it to `.textus/archive/`. Preview with `--dry-run`.

---

## Publishing

A produce entry's `publish:` list declares where its data is emitted after `drain` materialises it.

### To-target: single file

```yaml
publish:
  - { to: CLAUDE.md, template: docs/orientation.erb, inject_boot: true }
  - { to: AGENTS.md, template: docs/orientation.erb }
```

- `to:` — repo-relative destination path.
- `template:` — ERB template under `.textus/templates/`. The template receives the entry's `content` hash as local variables via `ERB#result_with_hash`.
- `inject_boot: true` — also injects a `boot` variable with the live orientation context.
- No `template:` — copies the data verbatim (json/yaml re-serialized without `_meta`).

### Tree-target: subtree mirror

For `nested:` knowledge entries that should publish a whole directory:

```yaml
- key: knowledge.how-to
  lane: knowledge
  nested: true
  publish: [{ tree: docs/how-to }]
```

`drain` walks the knowledge subtree and mirrors files to `docs/how-to/`, preserving relative layout. Unmanaged files in the target directory are never touched; textus-managed files that disappear from the source are pruned.

---

## Worked example

A repo that publishes `CLAUDE.md` from knowledge entries.

`.textus/manifest.yaml`:

```yaml
version: textus/4

roles:
  - { name: human,      can: [author, propose, ingest] }
  - { name: agent,      can: [propose, keep, ingest] }
  - { name: automation, can: [converge, ingest] }

lanes:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace, owner: agent }
  - { name: artifacts,  kind: machine }
  - { name: proposals,  kind: queue }
  - { name: raw,        kind: raw }

entries:
  - { key: knowledge.project, lane: knowledge, schema: project, owner: human:self, kind: leaf }

  - key: artifacts.orientation
    lane: artifacts
    kind: produced
    source: { from: external, command: "true", sources: [] }
    publish:
      - { to: CLAUDE.md,  template: docs/orientation.erb, inject_boot: true }
      - { to: AGENTS.md,  template: docs/orientation.erb }
```

`.textus/workflows/docs/orientation.rb`:

```ruby
Textus.workflow "orientation" do
  match "artifacts.orientation"

  step :build do |_, ctx|
    project_env = Textus::Action::Get.new(key: "knowledge.project")
                    .call(container: ctx.container, call: ctx.call)
    project = project_env&.meta || {}
    { "content" => { "name" => project["name"], "description" => project["description"] } }
  end

  publish
end
```

Day-to-day flow:

```sh
textus put knowledge.project --as=human < project.yaml   # edit project info
textus drain --as=automation                              # produce + publish CLAUDE.md
git diff CLAUDE.md                                        # review and commit
```

---

## Where to go from here

- [`../reference/lanes.md`](../reference/lanes.md) — the exact lane, role, and entry semantics
- [`../../SPEC.md`](../../SPEC.md) — the normative wire-protocol spec
- [`../../.textus/`](../../.textus/) — a complete worked example
