# Architecture

How the reference Ruby implementation is organized. The wire protocol itself lives in [`../SPEC.md`](../SPEC.md); this document covers *how* the gem implements that spec.

The codebase is a flat graph of small modules under one CLI dispatcher, not a strict pyramid. The clusters below describe what each module exists for and which other modules it talks to.

## At a glance

```
exe/textus  →  Textus::CLI  ──┬──►  Store          (facade — delegates to Reader/Writer/Mover)
                              │       ├──►  Store::Reader  (get/list/where/uid/deps/published/stale/validate_all)
                              │       ├──►  Store::Writer  (put/delete/accept)
                              │       ├──►  Store::Mover   (mv)
                              │       └──►  Hooks::Dispatcher  (lifecycle publish/subscribe)
                              ├──►  Builder        (build verb — Pipeline + per-format renderers)
                              ├──►  Refresh        (refresh verb)
                              ├──►  Doctor         (doctor verb)
                              ├──►  Init           (init verb)
                              ├──►  Intro          (intro verb)
                              ├──►  MigrateKeys    (key migrate, key mv verbs)
                              ├──►  Schema::Tools  (schema init/diff/migrate verbs)
                              ├──►  Store::View    (read-only projection over Store::Reader)
                              └──►  Role           (role gate)
```

CLI is the single entry point. It parses argv and dispatches each verb to whichever module owns that capability — there is no single mediator below CLI.

## Module clusters

### 1. Request path — core read/write verbs

`Store` is a thin facade (~110 LOC) that holds `Manifest`, `Hooks::Registry`, `Hooks::Dispatcher`, and the lazy `Store::AuditLog`, then delegates verbs to a small set of focused collaborators:

- **`Store::Reader`** — owns `get`, `list`, `where`, `uid`, `deps`, `rdeps`, `published`, `schema_envelope`, `stale`, `validate_all`. The only module that reads working-store entry files.
- **`Store::Writer`** — owns `put`, `delete`, `accept`. Handles serialization, uid minting, etag check, role gate, audit append, and event publication. The only module that writes working-store entry files.
- **`Store::Mover`** — owns `mv` (same-zone rename) with uid preservation and one audit row.
- **`Store::Validator`** / **`Store::Staleness`** — back the `validate_all` / `stale` reads. Take explicit collaborators (`reader:`, `manifest:`, `audit_log:`, `schema_for:`) instead of the full store.

Shared value modules and primitives consumed by Reader/Writer/Mover:

- **`Textus::Key::Path`** — `Key::Path.resolve(manifest, mentry)` returns the absolute leaf path for a manifest entry. Single source for zone-path construction; used by `Manifest`, `Staleness`, `Builder`, and Writer.
- **`Textus::Envelope`** — `Envelope.build(...)` returns the canonical envelope hash (protocol, key, zone, owner, path, format, `_meta`, body, etag, schema_ref, uid, optional content). Single source for envelope shape across `get` and `put`.
- **`Manifest`** — parses `.textus/manifest.yaml`; resolves a dotted key to a path via longest-prefix match. `nested: true` entries treat unmatched suffix segments as `/`-joined subdirs, with `.md` appended. Resolution is path-only; existence is the verb's concern.
- **`Schema`** — loads YAML schema files; validates frontmatter shape and surfaces unknown-key warnings (the §6 forward-compat rule).
- **`Entry`** + format adapters (`entry/markdown.rb`, `entry/text.rb`, `entry/json.rb`, `entry/yaml.rb`) — splits raw bytes on `---\n`, feeds the YAML chunk to `YAML.safe_load` (no aliases, restricted classes). The frontmatter `name:` field is enforced against the file basename in Reader/Writer (on read and on write) — mismatch raises `bad_frontmatter`.
- **`Etag`** — `sha256:<hex>` over raw file bytes. `put` accepts optional `if_etag:`; mismatch raises `etag_mismatch`. No locking, no temp-file-and-rename — v1 leaves stronger guarantees to v1.x.
- **`Role`** — agent-vs-human gate. Writer checks `Manifest::Entry#zone_writers` before doing anything else; otherwise raises `write_forbidden`.
- **`Store::AuditLog`** — append-only NDJSON; every successful write emits one line.
- **`Proposal`** — `accept` verb flow for promoting a pending entry into its target zone.
- **`Dependencies`** — `deps`/`rdeps`/`published` verb backing; walks manifest declarations.

### 2. Build / publish pipeline

Separate from the request path. Owns derived-entry materialization and byte-copy publish. `Builder` orchestrates per-entry materialization through `Builder::Pipeline`, which runs an ordered step list and dispatches the rendering step to one of four format-specific renderers. Adding a new output format is a single-file change under `lib/textus/builder/renderer/`.

```
Builder ──► Pipeline ──► LoadSources ──► Project ──► Render (per-format) ──► Write ──► Publisher ──► (sentinel)
                                                          │
                                                          └──► Renderer::{Markdown, Text, Json, Yaml}
```

- **`Builder`** — iterates `zone: derived` entries, hands each to `Pipeline.run`, then handles `Publisher` copy-out and fires the `:build` event. Holds no format-specific logic.
- **`Builder::Pipeline`** — `Pipeline.run(store:, mentry:, template_loader:)` is the orchestrator: runs the projection, merges `intro` if `inject_intro: true`, dispatches to the matching renderer, writes the bytes to the derived path.
- **`Builder::InjectMeta`** — builds the `_meta` block (`generated_at`, `from`, `template`, `reduce`) and threads it onto JSON/YAML content as the first key per SPEC §6 ordering.
- **`Builder::Renderer::{Markdown,Text,Json,Yaml}`** — one class per format, inheriting `Builder::Renderer`. Receives a template-loader lambda and `(mentry:, data:)`; returns rendered bytes. Markdown/Text always require a template; JSON/YAML optionally accept one (otherwise default-shape the projection rows).
- **`Projection`** — collects rows from manifest-declared source keys, applies optional reducer, sorts and positions. Pure data shaping.
- **`Mustache`** — minimal mustache renderer for templates in `.textus/templates/`.
- **`Publisher`** — byte-copy from store path to external target path. Refuses to overwrite unmanaged targets; writes a sentinel in `.textus/sentinels/` to track managed targets.

### 3. Extension surface

Declared in the manifest, loaded on demand, dispatched by `Store` and `Refresh`.

- **`Hooks::Registry`** — loads one `.rb` per hook from `.textus/hooks/`, registers callables under their `(event, name)`. Single source of truth via the `EVENTS` table (rpc vs pubsub, arg shape, failure semantics). For pub-sub events it also forwards registrations to the `Hooks::Dispatcher`.
- **`Hooks::Dispatcher`** — first-class pub/sub for lifecycle events (`:put`, `:delete`, `:refresh`, `:build`, `:accept`). Owns the 2-second per-handler timeout and the audit-on-failure middleware (raising handlers do not abort the write; they produce an `event_error` audit row). Embedded callers can `store.dispatcher.subscribe(:put, :name) { ... }` outside `.textus/hooks/`.
- **`Hooks::Builtin`** — ships built-in `:fetch` hooks (e.g. json, csv, ical-events, rss) available without user-supplied hooks.
- **`Refresh`** — `refresh` verb: looks up the `:fetch` hook for a key, invokes it, normalizes the result by declared format, writes through `Store::Writer` with an etag check.

### 4. Operational tooling

First-class CLI verbs that don't fit the read/write/build axes. Read-mostly; side modules off CLI.

- **`Doctor`** — `doctor` verb: orchestrator that runs 9 builtin checks under `Doctor::Check::*`. Talks to Manifest/Schema/Entry/Hooks::Registry directly.
- **`Doctor::Check`** — explicit base class for doctor checks. Each of the 9 builtin checks is its own file under `lib/textus/doctor/check/`.
- **`MigrateKeys`** — `key migrate` and `key mv` verbs; computes renames against the manifest.
- **`Schema::Tools`** — `schema init`, `schema diff`, `schema migrate` verbs.
- **`Init`** — `init` verb: scaffolds `.textus/` with the five zone directories, baseline schemas, empty audit log, starter manifest.
- **`Intro`** — `intro` verb: emits the human/agent-facing onboarding payload.
- **`Store::View`** — read-only projection over `Store::Reader` for hook code that should not mutate.
- **`Key::Distance`** — Levenshtein-ish suggestion for `did-you-mean` on unknown keys.

### 5. Primitives

- **`Errors`** — `Textus::Error` subclasses, each carrying a stable `code`, a `details` hash, and an `exit_code`. `CLI` catches them at the top level and emits the §8 error envelope on stdout. In `--format=json` mode, errors are **never** written to stderr — agents read stdout.
- **`version`** — gem semver string (independent of the wire protocol `textus/2`).

## Invariants

- **CLI is the only entry point.** No public API surface guarantees outside the verbs CLI exposes.
- **Manifest is pure.** Reads at load, no mutation.
- **Store::Writer is the only module that writes to working-store entry files.** Reader reads them; Mover moves them within a zone. Init, MigrateKeys, Publisher, Builder, AuditLog write to **other** parts of `.textus/` (scaffolding, sentinels, audit log, derived targets) — they do not edit existing entry files behind the Store facade's back.
- **`name:` frontmatter matches file basename.** Enforced on read and write.
- **Zone semantics live in the manifest, not in directory names.** A project may rename `state/` to anything; the manifest declares which zone each entry belongs to.
- **`stale` does not execute anything.** It walks `zone: derived` entries with a `generator:` block, compares `generated.at` against source mtimes, and returns offenders **plus their declared `command`**. Build runners execute. This is the §5.1 "dataflow oracle, not executor" boundary.

## What this implementation deliberately leaves out

- **No process spawning.** Even `stale` does not execute. Build runners do that.
- **No transport.** No HTTP server, no socket, no MCP server in this gem. Those are downstream wrappers (see [`./conventions.md`](./conventions.md)).
- **No indexes.** Listing walks the filesystem each time. Premature optimisation for v1.
- **No locking.** Etag is advisory; concurrent writers can still race. Left to v1.x (§14 open question).
