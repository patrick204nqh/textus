# Architecture

How the reference Ruby implementation is organized. The wire protocol itself lives in [`../SPEC.md`](../SPEC.md); this document covers *how* the gem implements that spec.

The codebase is a flat graph of small modules under one CLI dispatcher, not a strict pyramid. The clusters below describe what each module exists for and which other modules it talks to.

## At a glance

```
exe/textus  →  Textus::CLI  ──┬──►  Store          (verb impl: get/put/list/stale/refresh/accept/…)
                              ├──►  Builder        (build verb)
                              ├──►  Refresh        (refresh verb)
                              ├──►  Doctor         (doctor verb)
                              ├──►  Init           (init verb)
                              ├──►  Intro          (intro verb)
                              ├──►  MigrateKeys    (migrate-keys, mv verbs)
                              ├──►  SchemaTools    (schema-init/diff/migrate verbs)
                              ├──►  StoreView      (read-only projection over Store)
                              └──►  Role           (role gate)
```

CLI is the single entry point. It parses argv and dispatches each verb to whichever module owns that capability — there is no single mediator below CLI.

## Module clusters

### 1. Request path — core read/write verbs

`Store` (617 LOC) owns the `get`, `put`, `list`, `delete`, `stale`, and proposal-acceptance verbs. It is the largest module and the only one that touches the working-store filesystem for primary read/write. It uses:

- **`Manifest`** — parses `.textus/manifest.yaml`; resolves a dotted key to a path via longest-prefix match. `nested: true` entries treat unmatched suffix segments as `/`-joined subdirs, with `.md` appended. Resolution is path-only; existence is the verb's concern.
- **`Schema`** — loads YAML schema files; validates frontmatter shape and surfaces unknown-key warnings (the §6 forward-compat rule).
- **`Entry`** + format adapters (`entry/markdown.rb`, `entry/text.rb`, `entry/json.rb`, `entry/yaml.rb`) — splits raw bytes on `---\n`, feeds the YAML chunk to `YAML.safe_load` (no aliases, restricted classes). The frontmatter `name:` field is enforced against the file basename inside `Store` (on read and on write) — mismatch raises `bad_frontmatter`.
- **`Etag`** — `sha256:<hex>` over raw file bytes. `put` accepts optional `if_etag:`; mismatch raises `etag_mismatch`. No locking, no temp-file-and-rename — v1 leaves stronger guarantees to v1.x.
- **`Role`** — agent-vs-human gate. `Store#put` checks `ManifestEntry#agent_writable?` (true only for `state`) before doing anything else; otherwise raises `write_forbidden`.
- **`AuditLog`** — append-only NDJSON; every successful write emits one line.
- **`Proposal`** — `accept` verb flow for promoting a pending entry into its target zone.
- **`Dependencies`** — `deps`/`rdeps`/`published` verb backing; walks manifest declarations.

### 2. Build / publish pipeline

Separate from the request path. Owns derived-entry materialization and byte-copy publish.

```
Builder ──► Projection ──► Mustache ──► Entry  ──► Publisher ──► (sentinel)
```

- **`Builder`** — iterates `zone: derived` entries, materializes each by running its declared template + projection, parses the rendered output back through `Entry`, and hands the bytes to `Publisher`.
- **`Projection`** — collects rows from manifest-declared source keys, applies optional reducer, sorts and positions. Pure data shaping.
- **`Mustache`** — minimal mustache renderer for templates in `.textus/templates/`.
- **`Publisher`** — byte-copy from store path to external target path. Refuses to overwrite unmanaged targets; writes a sentinel in `.textus/sentinels/` to track managed targets.

### 3. Extension surface

Declared in the manifest, loaded on demand, dispatched by `Store` and `Refresh`.

- **`Extensions`** — declarative manifest schema for action/reducer/hook/doctor_check extensions.
- **`ExtensionRegistry`** — loads one `.rb` per extension from `.textus/extensions/`, registers callables under their declared names.
- **`BuiltinActions`** — ships built-in actions (e.g. json, csv, ical-events, rss) available without user extensions.
- **`Refresh`** — `refresh` verb: looks up the action for a key, invokes it, normalizes the result by declared format, writes through `Store` with an etag check.

### 4. Operational tooling

First-class CLI verbs that don't fit the read/write/build axes. Read-mostly; side modules off CLI.

- **`Doctor`** — `doctor` verb: validates manifest, schemas, extensions, and (via `MigrateKeys`) suggests key migrations. Talks to Manifest/Schema/Entry/ExtensionRegistry directly.
- **`MigrateKeys`** — `migrate-keys` and `mv` verbs; computes renames against the manifest.
- **`SchemaTools`** — `schema-init`, `schema-diff`, `schema-migrate` verbs.
- **`Init`** — `init` verb: scaffolds `.textus/` with the five zone directories, baseline schemas, empty audit log, starter manifest.
- **`Intro`** — `intro` verb: emits the human/agent-facing onboarding payload.
- **`StoreView`** — read-only projection over `Store` for code that should not mutate.
- **`KeyDistance`** — Levenshtein-ish suggestion for `did-you-mean` on unknown keys.

### 5. Primitives

- **`Errors`** — `Textus::Error` subclasses, each carrying a stable `code`, a `details` hash, and an `exit_code`. `CLI` catches them at the top level and emits the §8 error envelope on stdout. In `--format=json` mode, errors are **never** written to stderr — agents read stdout.
- **`version`** — gem semver string (independent of the wire protocol `textus/1`).

## Invariants

- **CLI is the only entry point.** No public API surface guarantees outside the verbs CLI exposes.
- **Manifest is pure.** Reads at load, no mutation.
- **Store is the only module that writes to working-store entry files.** Init, MigrateKeys, Publisher, Builder, AuditLog write to **other** parts of `.textus/` (scaffolding, sentinels, audit log, derived targets) — they do not edit existing entry files behind Store's back.
- **`name:` frontmatter matches file basename.** Enforced on read and write.
- **Zone semantics live in the manifest, not in directory names.** A project may rename `state/` to anything; the manifest declares which zone each entry belongs to.
- **`stale` does not execute anything.** It walks `zone: derived` entries with a `generator:` block, compares `generated.at` against source mtimes, and returns offenders **plus their declared `command`**. Build runners execute. This is the §5.1 "dataflow oracle, not executor" boundary.

## What this implementation deliberately leaves out

- **No process spawning.** Even `stale` does not execute. Build runners do that.
- **No transport.** No HTTP server, no socket, no MCP server in this gem. Those are downstream wrappers (see [`./conventions.md`](./conventions.md)).
- **No indexes.** Listing walks the filesystem each time. Premature optimisation for v1.
- **No locking.** Etag is advisory; concurrent writers can still race. Left to v1.x (§14 open question).
