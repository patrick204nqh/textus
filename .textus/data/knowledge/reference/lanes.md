# Lanes — reference

> **Reference** · for integrators · **read when** you need the exact lane, role, and entry semantics
> **SSoT for** lane semantics, what each capability *means*, entry fields, and doctor enforcement · **reviewed** 2026-06 (v0.54)

The *current-values* tables — the role→capability sets, the lane-kind↔capability bijection, and which roles write which lane-kinds — are projected from the live manifest into the generated [`authority.md`](authority.md) (ADR 0112). This doc owns their *meaning*; link there for the tables rather than restating them.

The exact semantics of textus lanes: the roles and capabilities that govern who may write, the five default lanes, the fields an entry declares, and what `textus doctor` enforces.

This is the configuration reference. For the wire protocol, see [`../../SPEC.md`](../../SPEC.md). For the setup procedures (declaring lanes, wiring workflows, produced entries), see [`../how-to/configuring-lanes.md`](../how-to/configuring-lanes.md). For implementation internals, see [`../architecture/README.md`](../architecture/README.md).

> New here? Start with [Concepts](../explanation/concepts.md).

## Table of contents

1. [Roles and capabilities — who is allowed to write](#roles-and-capabilities--who-is-allowed-to-write)
2. [The five default lanes](#the-five-default-lanes) — `knowledge`, `notebook`, `artifacts`, `proposals`, `raw`
3. [Defining entries](#defining-entries)
4. [Enforcement — what `textus doctor` checks](#enforcement--what-textus-doctor-checks)

---

## Roles and capabilities — who is allowed to write

A role is a name in the manifest that holds a set of **capabilities** — verbs from a closed five-element set. Write authority is *derived*: a role may write a lane iff it holds the capability the lane's kind requires (see [The five default lanes](#the-five-default-lanes)). **The current roles, their `can:` sets, and which lane-kinds each may write are the projected [`authority.md`](authority.md) tables** (generated from this manifest; never hand-maintained). What each role represents:

- **`human`** — a person at a terminal; the single trust anchor.
- **`agent`** — an autonomous agent: stages proposals, maintains its own `notebook` workspace, and can ingest external URLs.
- **`automation`** — scheduled or one-shot scripts: produce computed outputs in the `artifacts` machine lane via `drain`.

What each of the five capabilities **means** (the capability ↔ lane-kind mapping itself is the bijection projected into [`authority.md`](authority.md)):

- **`author`** (writes `canon`) — authoring canonical truth; the **single trust anchor** (at most one role holds it).
- **`keep`** (writes `workspace`) — writing to an agent's own durable lane (`notebook`); bytes never auto-promote.
- **`propose`** (writes `queue`) — staging a proposal awaiting promotion.
- **`converge`** (writes `machine`) — keeping the machine lane current: producing computed outputs via `drain` and the workflow DSL.
- **`ingest`** (writes `raw`) — write-once ingestion of external source material (URL bookmarks, files, binary assets).

Note: `accept` and `reject` are **transition verbs** (CLI commands), not capabilities. Both require the `author` capability.

Declare roles in the manifest with a `roles:` block; each names the capabilities it holds via `can:`:

```yaml
roles:
  - { name: human,      can: [author, propose, ingest] }
  - { name: agent,      can: [propose, keep, ingest] }
  - { name: automation, can: [converge, ingest] }
```

Role names are the closed set `human`, `agent`, `automation`; what you customize is each role's `can:` capabilities — see [`../how-to/configuring-lanes.md`](../how-to/configuring-lanes.md). Only one constraint is absolute: **at most one role may hold `author`** (the trust anchor).

---

## The five default lanes

`textus init` scaffolds this manifest (Setup-1):

```yaml
roles:
  - { name: human,      can: [author, propose, ingest] }
  - { name: agent,      can: [propose, keep, ingest] }
  - { name: automation, can: [converge, ingest] }

lanes:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace, owner: agent, desc: "agent's durable working memory" }
  - { name: artifacts,  kind: machine }
  - { name: proposals,  kind: queue }
  - { name: raw,        kind: raw }
```

`owner:` on a lane is **optional, informational** metadata. `desc:` is optional; the value surfaces as the `purpose` field in `textus boot` lane rows.

Write authority is **derived** — there is no `write_policy:`. Each lane declares only its `kind:`; the kind decides the required capability, and any role holding that capability may write. The kind→capability mapping is a **bijection** — the projected table is [`authority.md`](authority.md). What each default lane is *for*:

- **`knowledge`** (`canon`, written by `human`) — authored truth: identity, voice, decisions. Long-lived.
- **`notebook`** (`workspace`, written by `agent`) — the agent's own durable working memory. Bytes climb to `knowledge` only via propose→accept.
- **`artifacts`** (`machine`, written by `automation`) — computed outputs produced by `drain` and the workflow DSL. Never hand-edited.
- **`proposals`** (`queue`, written by `agent` + `human`) — proposals awaiting human review via `textus accept`.
- **`raw`** (`raw`, written by `human`, `agent`, `automation`) — write-once external source material: URL bookmarks, local files, binary assets. Each entry is immutable after creation.

These five are a **starter template**, not a closed set. Rename them, add to them, remove what you don't need — see [`../how-to/configuring-lanes.md`](../how-to/configuring-lanes.md).

---

## Defining entries

Each entry is a key, a path under `data/<lane>/`, and metadata:

```yaml
entries:
  - key: knowledge.identity.self
    lane: knowledge
    schema: identity        # references .textus/schemas/identity.yaml
    owner: human:self
    kind: leaf
```

### Fields

| Field | Required | Meaning |
|-------|----------|---------|
| `key` | yes | Dotted identifier (`knowledge.identity.self`, `knowledge.notes.daily`). |
| `lane` | yes | Must match a declared lane. |
| `schema` | no | YAML schema name. `null` means free-form. |
| `owner` | no | `<role>:<actor>` — for audit and convention; not enforced. |
| `nested` | no | If `true`, the key prefix-matches subdirectories. |
| `format` | no | `markdown` \| `json` \| `yaml` \| `text`. Inferred from extension if omitted. |
| `source:` | no | How the entry acquires its **data** — `from: external` + a `Textus.workflow` block. Acquire-only: rendering is a publish concern. See [`../how-to/configuring-lanes.md`](../how-to/configuring-lanes.md). |
| `publish:` | no | A **list** of publish targets. A to-target `{ to:, template?:, inject_boot?: }` emits the entry's data to a repo path. A tree-target `{ tree: "dir" }` mirrors an entire nested subtree. |
| `ignore:` | no | For `nested:` entries — gitignore-style globs. Matching paths are excluded from enumeration and doctor checks. |

The full schema lives in [`SPEC.md §4`](../../SPEC.md).

### Nested entries

A single entry can host an unbounded subtree:

```yaml
- key: knowledge.notes
  lane: knowledge
  nested: true
```

That declaration covers `knowledge.notes.daily.2026-05-21`, `knowledge.notes.meetings.kickoff`, etc.

---

## Enforcement — what `textus doctor` checks

The manifest is declarative. `textus doctor` is the runtime check that the store still matches what it declares:

- Every entry's `lane:` references a declared lane
- Every entry file actually exists at its computed path
- Frontmatter `name:` matches the file basename
- Schemas exist for entries that reference one
- Produced entries are not stale relative to their sources
- No files exist under `.textus/data/` that aren't declared

If doctor passes, your declared shape and your on-disk reality agree. If it fails, the error message names the entry and the rule that broke.

---

## Where to go from here

- [`../../SPEC.md`](../../SPEC.md) — the normative wire-protocol spec
- [`../how-to/configuring-lanes.md`](../how-to/configuring-lanes.md) — lane-setup procedures (declare/rename lanes, workflow wiring, produced entries, worked example)
- [`../architecture/README.md`](../architecture/README.md) — how the Ruby implementation is laid out
- [`conventions.md`](conventions.md) — store location, transport wrappers, multi-store patterns
