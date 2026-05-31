# Zones — reference

> **Reference** · for integrators · **read when** you need the exact zone, role, and entry semantics
> **SSoT for** zone semantics, the role/capability model, entry fields, and doctor enforcement · **reviewed** 2026-05 (v0.38)

The exact semantics of textus zones: the roles and capabilities that govern who may write, the five default zones, the fields an entry declares, and what `textus doctor` enforces.

This is the configuration reference. For the wire protocol, see [`../../SPEC.md`](../../SPEC.md). For the setup procedures (declaring zones, wiring intake, derived entries), see [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md). For implementation internals, see [`../architecture/README.md`](../architecture/README.md).

> New here? Start with [Concepts](../explanation/concepts.md).

## Table of contents

1. [Roles and capabilities — who is allowed to write](#roles-and-capabilities--who-is-allowed-to-write)
2. [The five default zones](#the-five-default-zones) — `knowledge`, `notebook`, `feeds`, `proposals`, `artifacts`
3. [Defining entries](#defining-entries)
4. [Enforcement — what `textus doctor` checks](#enforcement--what-textus-doctor-checks)

---

## Roles and capabilities — who is allowed to write

A role is a name in the manifest that holds a set of **capabilities** — verbs from a closed five-element set. Write authority is *derived*: a role may write a zone iff it holds the capability the zone's kind requires (see [The five default zones](#the-five-default-zones)). The default mapping, applied when the manifest omits a `roles:` block:

| Role | Capabilities (`can`) | What it represents |
|------|----------------------|--------------------|
| `human` | `[author, propose]` | A person at a terminal; the single trust anchor. |
| `agent` | `[propose, keep]` | An autonomous agent: stages proposals and maintains its own `notebook` workspace. |
| `automation` | `[fetch, build]` | Scheduled or one-shot scripts: pull external sources in, materialize derived outputs. |

The five capabilities:

| Capability | Authorizes writes to zone-kind | What it represents |
|------------|--------------------------------|--------------------|
| `author` | `canon` | Authoring canonical truth — the **single trust anchor** (at most one role holds it). |
| `keep` | `workspace` | Writing to an agent's own durable lane (`notebook`). Bytes never auto-promote. |
| `propose` | `queue` | Staging a proposal awaiting promotion. |
| `fetch` | `quarantine` | Pulling external bytes in. |
| `build` | `derived` | Computing outputs from other zones. |

Note: `accept` and `reject` are **transition verbs** (CLI commands), not capabilities. Both require the `author` capability. As of 0.35, `accept` also refuses a proposal whose `target_key` is not a `canon` zone (floor predicate `target_is_canon`, surfaced as `guard_failed`); `textus doctor`'s `proposal_targets` check flags queued proposals with non-canon or unresolvable targets.

Declare roles in the manifest with a `roles:` block; each names the capabilities it holds via `can:`:

```yaml
roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [fetch, build] }
```

Two analogies that usually click for `automation`:

- **`fetch` is the grocery shopper** — goes outside, brings raw ingredients home (into `feeds`).
- **`build` is the chef** — takes ingredients already in the kitchen and cooks the meal (into `artifacts`).

You can also invent your own role names (`reviewer`, `import-bot`, `compiler`) and hand them whichever capabilities fit — see [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md). Only one constraint is absolute: **at most one role may hold `author`** (the trust anchor).

---

## The five default zones

`textus init` scaffolds this manifest (Setup-1):

```yaml
roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [fetch, build] }

zones:
  - { name: knowledge,  kind: canon }
  - { name: notebook,   kind: workspace, owner: agent, desc: "agent's durable working memory" }
  - { name: feeds,      kind: quarantine }
  - { name: proposals,  kind: queue }
  - { name: artifacts,  kind: derived }
```

`owner:` on a zone is **optional, informational** metadata — not enforced in 0.33.0 (owner-scoped enforcement is deferred). `desc:` is optional; the value surfaces as the `purpose` field in `textus boot` zone rows.

Write authority is **derived** — there is no `write_policy:`. Each zone declares only its `kind:`; the kind decides the required capability, and any role holding that capability may write. The kind→verb mapping is closed:

| Zone `kind` | Required capability | Meaning |
|-------------|---------------------|---------|
| `canon` | `author` | Authored truth — only the trust anchor writes directly. |
| `workspace` | `keep` | Agent's own durable lane; bytes never auto-promote. |
| `quarantine` | `fetch` | External bytes pending validation. |
| `queue` | `propose` | Proposals awaiting promotion. |
| `derived` | `build` | Computed from other zones. |

Crossing that table with the default role mapping gives the default writers:

| Zone | `kind` | Required capability | Writable by (default) | Purpose / lifetime |
|------|--------|---------------------|-----------------------|--------------------|
| `knowledge` | `canon` | `author` | `human` | Authored truth: identity (`knowledge.identity.*`), voice, decisions, network. (Long-lived.) |
| `notebook` | `workspace` | `keep` | `agent` | Agent's own durable working memory. Bytes climb to `knowledge` only via propose→accept. (Until promoted.) |
| `feeds` | `quarantine` | `fetch` | `automation` | Declared external inputs, fetched via `textus fetch KEY --as=automation`; never edited by hand. (Fetched on demand.) |
| `proposals` | `queue` | `propose` | `agent`, `human` | AI proposals awaiting human review. (Until `accept` or rejection.) |
| `artifacts` | `derived` | `build` | `automation` | Build-computed outputs. Materialized from projections; never hand-edited. (Recomputed every build.) |

These five are a **starter template**, not a closed set. Rename them, add to them, remove the ones you don't need — see [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md).

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
| `intake:` | no | Declares this is an intake entry. See [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md#wiring-data-in--intake-and-resolve_intake-hooks). |
| `compute:` | no | Declares this is a derived entry (`kind: projection` computes from store entries; `kind: external` tracks an outside build tool). See [`../how-to/configuring-zones.md`](../how-to/configuring-zones.md#wiring-data-out--derived-entries-and-publishing). |
| `template:` | no | Mustache template name under `.textus/templates/`. Required for markdown/text derived entries; optional for JSON/YAML. |
| `inject_boot:` | no | When `true` on a derived entry, the `textus boot` payload is merged into the projection data so templates can reference it. |
| `publish_to:` | no | List of external paths to byte-copy the built file to. |
| `publish_each:` | no | For `nested:` entries — pattern like `"skills/{basename}/SKILL.md"` that publishes each child file to its own external path. |
| `events:` | no | Per-entry pub-sub bindings (e.g. run a shell command after this entry's `:build` event). |

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
