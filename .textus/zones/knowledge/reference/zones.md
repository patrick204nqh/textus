# Zones — reference

> **Reference** · for integrators · **read when** you need the exact zone, role, and entry semantics
> **SSoT for** zone semantics, what each capability *means*, entry fields, and doctor enforcement · **reviewed** 2026-06 (v0.43)

The *current-values* tables — the role→capability sets, the zone-kind↔capability bijection, and which roles write which zone-kinds — are projected from the live manifest into the generated [`authority.md`](authority.md) (ADR 0112). This doc owns their *meaning*; link there for the tables rather than restating them.

The exact semantics of textus zones: the roles and capabilities that govern who may write, the five default zones, the fields an entry declares, and what `textus doctor` enforces.

This is the configuration reference. For the wire protocol, see [`../../SPEC.md`](../../SPEC.md). For the setup procedures (declaring zones, wiring intake, derived entries), see [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md). For implementation internals, see [`../architecture/README.md`](../architecture/README.md).

> New here? Start with [Concepts](../explanation/concepts.md).

## Table of contents

1. [Roles and capabilities — who is allowed to write](#roles-and-capabilities--who-is-allowed-to-write)
2. [The four default zones](#the-four-default-zones) — `knowledge`, `notebook`, `artifacts`, `proposals`
3. [Defining entries](#defining-entries)
4. [Enforcement — what `textus doctor` checks](#enforcement--what-textus-doctor-checks)

---

## Roles and capabilities — who is allowed to write

A role is a name in the manifest that holds a set of **capabilities** — verbs from a closed four-element set. Write authority is *derived*: a role may write a zone iff it holds the capability the zone's kind requires (see [The four default zones](#the-four-default-zones)). **The current roles, their `can:` sets, and which zone-kinds each may write are the projected [`authority.md`](authority.md) tables** (generated from this manifest; never hand-maintained). What each role represents:

- **`human`** — a person at a terminal; the single trust anchor.
- **`agent`** — an autonomous agent: stages proposals and maintains its own `notebook` workspace.
- **`automation`** — scheduled or one-shot scripts: keep the one `machine` zone current — re-pull intake (`artifacts.feeds.*`) entries and produce derived (`artifacts.derived.*`) entries' data.

What each of the four capabilities **means** (the capability ↔ zone-kind mapping itself is the bijection projected into [`authority.md`](authority.md#lanes--the-zone-kind--capability-bijection)):

- **`author`** (writes `canon`) — authoring canonical truth; the **single trust anchor** (at most one role holds it).
- **`keep`** (writes `workspace`) — writing to an agent's own durable lane (`notebook`); bytes never auto-promote.
- **`propose`** (writes `queue`) — staging a proposal awaiting promotion.
- **`converge`** (writes `machine`) — keeping the one machine zone current: re-pulling intake entries (`artifacts.feeds.*`) and producing derived entries' data (`artifacts.derived.*`). Both are system-pushed by the `drain` sweep (ADR 0089/0091/0093).

Note: `accept` and `reject` are **transition verbs** (CLI commands), not capabilities. Both require the `author` capability. As of 0.35, `accept` also refuses a proposal whose `target_key` is not a `canon` zone (floor predicate `target_is_canon`, surfaced as `guard_failed`); `textus doctor`'s `proposal_targets` check flags queued proposals with non-canon or unresolvable targets.

Declare roles in the manifest with a `roles:` block; each names the capabilities it holds via `can:`:

```yaml
roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [converge] }
```

Two analogies that usually click for `automation` — both jobs belong to the one `converge` capability, because the `drain` sweep drives both:

- **the grocery shopper** — goes outside, brings raw ingredients home (into the `machine` zone, as intake entries under `artifacts.feeds.*`).
- **the chef** — takes ingredients already in the kitchen and cooks the meal (computing derived entries under `artifacts.derived.*` in the same `machine` zone).

Role names are the closed set `human`, `agent`, `automation`; what you customize is each role's `can:` capabilities — see [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md). Per-person/per-bot attribution uses the `owner:` field. Only one constraint is absolute: **at most one role may hold `author`** (the trust anchor).

---

## The four default zones

`textus init` scaffolds this manifest (Setup-1):

```yaml
roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [converge] }

zones:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace, owner: agent, desc: "agent's durable working memory" }
  - { name: artifacts,  kind: machine }
  - { name: proposals,  kind: queue }
```

`owner:` on a zone is **optional, informational** metadata — not enforced in 0.33.0 (owner-scoped enforcement is deferred). `desc:` is optional; the value surfaces as the `purpose` field in `textus boot` zone rows.

Write authority is **derived** — there is no `write_policy:`. Each zone declares only its `kind:`; the kind decides the required capability, and any role holding that capability may write. The kind→capability mapping is a **bijection** (ADR 0091): each zone-kind maps 1:1 to exactly one capability — the projected table is [`authority.md`](authority.md#lanes--the-zone-kind--capability-bijection). `machine` is the single kind requiring `converge`; the two-kind surjection (`quarantine` + `derived` → the converge capability) that ADR 0090 introduced is gone.

Crossing that bijection with the manifest's roles gives the default writers — the projected [`authority.md`](authority.md#roles-this-manifest) table. What each default zone is *for*, and how long its bytes live:

- **`knowledge`** (`canon`, written by `human`) — authored truth: identity (`knowledge.identity.*`), voice, decisions, network. Long-lived.
- **`notebook`** (`workspace`, written by `agent`) — the agent's own durable working memory. Bytes climb to `knowledge` only via propose→accept. Lives until promoted.
- **`artifacts`** (`machine`, written by `automation`) — the one machine-maintained zone: intake entries under `artifacts.feeds.*` are re-pulled by `textus drain --as=automation` (per their `source.ttl`); derived entries under `artifacts.derived.*` produce their data from projections. Never hand-edited; re-pulled/produced on `drain`.
- **`proposals`** (`queue`, written by `agent` + `human`) — AI proposals awaiting human review. Lives until `accept` or rejection.

These four are a **starter template**, not a closed set. Rename them, add to them, remove the ones you don't need — see [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md).

---

## Defining entries

Each entry is a key, a path under `zones/<zone>/`, and metadata:

```yaml
entries:
  - key: identity.self
    path: identity/self.md
    zone: identity
    schema: identity        # references .textus/schemas/identity.yaml
    owner: human:self
```

### Fields

| Field | Required | Meaning |
|-------|----------|---------|
| `key` | yes | Dotted identifier (`knowledge.identity.self`, `knowledge.notes.daily`). |
| `path` | yes | Relative path under `.textus/zones/`. |
| `zone` | yes | Must match a declared zone. |
| `schema` | no | YAML schema name. `null` means free-form. |
| `owner` | yes | `<role>:<actor>` — for audit and convention; not enforced. |
| `nested` | no | If `true`, the key prefix-matches subdirectories. `knowledge.notes.daily.2026-05-21` resolves under `knowledge/notes/`. |
| `format` | no | `markdown` \| `json` \| `yaml` \| `text`. Inferred from extension if omitted. |
| `source:` | no | How the entry acquires its **data** (ADR 0093/0094) — `from: handler` (intake, external fetch), `from: project` (in-process projection over store keys), or `from: command` (external build tool). Acquire-only: rendering is a publish concern. See [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md#wiring-data-out--derived-entries-and-publishing). |
| `publish:` | no | A **list** of publish targets (ADR 0052/0094). A to-target `{ to:, template?:, inject_boot?: }` emits the entry's data to a repo path — `template:` absent copies it verbatim (json/yaml re-serialized without `_meta`), present renders the data through the named Mustache template; `inject_boot: true` merges the `textus boot` payload into the render data (per target). A tree-target `{ tree: "dir" }` (for `nested:` entries) mirrors the entry's whole stored subtree to one target directory, preserving layout — path-driven, opaque payload, never keys (ADR 0047). Published artifacts are clean content — `_meta` provenance stays in the store. |
| `ignore:` | no | For `nested:` entries — a list of gitignore-style globs (e.g. `["**/node_modules/**"]`). Matching paths are excluded from enumeration **and** from `doctor`'s key checks. See [Nested entries](#nested-entries). |
| `events:` | no | Per-entry pub-sub bindings (e.g. run a shell command after this entry's `:entry_produced` event). |

The full schema lives in [`SPEC.md §4`](../../SPEC.md).

### Nested entries

A single entry can host an unbounded subtree:

```yaml
- key: knowledge.notes
  path: knowledge/notes
  zone: knowledge
  nested: true
```

That declaration covers `knowledge.notes.daily.2026-05-21`, `knowledge.notes.meetings.kickoff`, etc. — textus resolves the suffix as `/`-joined subdirectories under `knowledge/notes/`.

Real source trees often contain vendored or generated subtrees that ship their own index files — a `node_modules/` whose dependencies bundle `SKILL.md` files, or a `dist/` of generated output. Use `ignore:` to keep them out of the store entirely. The patterns are honoured consistently by enumeration (`list`, `publish`) and by `textus doctor`, so the store cannot `list` cleanly while `doctor` is red on the same paths:

```yaml
- key: skills
  path: skills
  zone: knowledge
  nested: true
  ignore:
    - "**/node_modules/**"
    - "**/dist/**"
```

Patterns match the file's path relative to the entry directory. A `**` globstar matches zero or more directory levels (so `**/node_modules/**` catches the subtree at any depth, including the store root); within a single path segment, `*` is anchored (it does not cross `/`) and `{a,b}` is alternation.

---

## Enforcement — what `textus doctor` checks

The manifest is declarative. `textus doctor` is the runtime check that the store still matches what it declares:

- Every entry's `zone:` references a declared zone
- Every entry file actually exists at its computed path
- Frontmatter `name:` matches the file basename
- Schemas exist for entries that reference one
- Hooks named by intake entries are registered
- Derived entries aren't stale relative to their sources
- No files exist under `.textus/zones/` that aren't declared

If doctor passes, your declared shape and your on-disk reality agree. If it fails, the error message names the entry and the rule that broke.

---

## Where to go from here

- [`../../SPEC.md`](../../SPEC.md) — the normative wire-protocol spec
- [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md) — the zone-setup procedures (declare/rename zones, intake wiring, derived + publishing, worked example)
- [`../architecture/README.md`](../architecture/README.md) — how the Ruby implementation is laid out
- [`conventions.md`](conventions.md) — store location, transport wrappers, multi-store patterns
- [`../../examples/project/`](../../examples/project/) — a complete worked example
