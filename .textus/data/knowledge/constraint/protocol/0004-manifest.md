## 4. Manifest

The manifest declares: (a) which roles exist and the capabilities each holds, (b) which lanes exist and each lane's `kind:`, (c) the key-to-subtree mapping, (d) the schema applied to entries in each subtree, and (e) the owner string recorded in writes. Write authority is **derived** — a role may write a lane iff it holds the capability the lane's kind requires (§5).

```yaml
# .textus/manifest.yaml
version: textus/4

roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose] }
  - { name: automation, can: [converge] }

lanes:
  - name: knowledge
    kind: canon
  - name: scratchpad
    kind: workspace
    owner: agent              # optional, informational — agent's own lane
    desc: "agent's durable working memory; bytes climb to knowledge only via propose→accept"
  - name: proposals
    kind: queue
  - name: artifacts
    kind: machine            # machine-maintained: external inputs (artifacts.feeds.*) + computed outputs (artifacts.derived.*)

entries:
  - key: knowledge.identity.self
    path: data/knowledge/identity/self.md
    lane: knowledge
    schema: identity

  - key: knowledge.network.org
    path: data/knowledge/network/org
    lane: knowledge
    schema: person
    owner: human:network
    nested: true

  - key: artifacts.catalogs.people
    path: data/artifacts/catalogs/people.md
    lane: artifacts
    schema: null
    owner: automation:converge

rules:
  - match: artifacts.feeds.**
    retention: { ttl: 6h, action: archive }

audit:
  max_size: 10485760   # bytes before rotating (default: 10 485 760 = 10 MiB)
  keep: 5              # rotated files to retain (default: 5)
```

Zone names are conventional — write authority comes from each lane's declared `kind:` crossed with the capabilities roles hold (§5); rename lanes freely.

**Key grammar:** dotted segments matching `/^[a-z0-9][a-z0-9-]*$/`. Segments are joined by `.`. A key has at most 8 segments; each segment is at most 64 characters. Segments MUST NOT contain dots, slashes, uppercase letters, or underscores. Example: `working.projects.acme.dashboard`. Enforcement points: manifest load (rejects illegal `key:` declarations and illegal nested file/directory names), `put` (rejects illegal keys before any write), `enumerate` (filters and warns on illegal filenames).

**Per-entry `format:`** an entry MAY declare `format:` to be one of `markdown` (default), `json`, `yaml`, or `text`. The `format` controls the on-disk shape and which path extension is required:

| `format`   | Path extension              | `template:`           | `schema:` |
|------------|-----------------------------|------------------------|-----------|
| `markdown` | `.md` (or appended if absent) | required for produced | optional  |
| `json`     | `.json` required            | optional (escape hatch) | optional (top-level keys) |
| `yaml`     | `.yaml` or `.yml` required  | optional (escape hatch) | optional (top-level keys) |
| `text`     | `.txt` or no extension      | required for produced | MUST be null |

For `nested: true`, the recursive glob matches the format's extension (markdown→`**/*.md`, json→`**/*.json`, yaml→`**/*.{yaml,yml}`, text→`**/*.txt`). All files under one nested entry share one format and one schema. Each matching file is enumerated as its own key, with the key segments derived from the path relative to the entry (extension stripped). A nested entry that instead mirrors a whole directory of files to a consumer path — without enumerating any of them as keys — uses a `{ tree: }` publish target (below); its files are opaque payload. (The former `index_filename:` directory-keyed enumeration was removed in 0.43.0 — ADR 0053.)

**The `publish:` list (ADR 0052, ADR 0094).** Publishing is configured by a `publish:` **list** of targets; each element is exactly one of a to-target `{ to:, template?:, inject_boot?: }` (file emit, §5.3) or a tree-target `{ tree: }` (subtree mirror, below). The legacy *map* forms (`publish: { to: [...] }`, `publish: { tree: ... }`) and the older top-level `publish_to:` / `publish_tree:` keys are rejected at load with a migration message — `publish:` is a list, and a mirror is a `{ tree: }` element of it.

**Subtree mirror (a `{ tree: }` target).** A nested manifest entry MAY include a `{ tree: "dir" }` target to mirror its entire stored subtree (`data/<lane>/**`) to a single target directory, preserving relative layout (case and extension preserved). It is **path-driven, not key-driven**: no keys are enumerated, no template variables are interpreted, and the mirrored files are opaque payload (never addressable). The entry's `ignore:` globs (§4, ADR 0042) filter the walk; each mirrored file gets its own sentinel; and on every drain the whole target directory is pruned of textus-managed files the current source no longer produces (unmanaged files are never touched). When a `{ tree: }` target directory overlaps another entry's `{ to: }` target (e.g. a derived `SKILL.md` written into the mirrored dir), the mirroring entry **must** `ignore:` that filename or prune will delete it — `doctor` flags this as `publish.tree_index_overlap`. See ADR 0047.

```yaml
- key: knowledge.skills
  path: data/knowledge/skills
  lane: knowledge
  schema: skill
  nested: true
  publish:
    - { tree: "skills" }
  ignore: ["*.tmp", ".DS_Store"]
```

**Lookup rule:** to resolve a key, find the entry with the longest `key:` prefix that matches. If that entry has `nested: true`, the remaining segments map to subdirectories under its `path`. Otherwise the key must equal an entry exactly. The resolved filesystem path is `<.textus root>/<entry.path>[/<remaining>...].md` — manifest `path:` values include the `data/` prefix (e.g. `data/knowledge/network/org`).
