# Architecture

How the reference Ruby implementation is organized. The wire protocol itself lives in [`../SPEC.md`](../SPEC.md); this document covers *how* the gem implements that spec.

## Layering

```
┌──────────────────────────────────────────────┐
│ exe/textus                                   │  thin shim: load lib, call CLI.run
├──────────────────────────────────────────────┤
│ Textus::CLI                                  │  argv parsing, JSON I/O, exit codes
├──────────────────────────────────────────────┤
│ Textus::Store                                │  verb implementations (get/put/list/…)
├───────────────┬───────────────┬──────────────┤
│ Manifest      │ Schema        │ Entry        │  parse/resolve, validate, (de)serialize
├───────────────┴───────────────┴──────────────┤
│ Etag · Errors · version                      │  primitives
└──────────────────────────────────────────────┘
```

Each layer talks only to the layer below it. `Store` is the only class that touches the filesystem for read/write; `Manifest` and `Schema` read at load time and are otherwise pure.

## Key resolution

`Manifest#resolve(key)` does **longest-prefix match** against `entries[].key`. The matched entry's `path:` is the base; if `nested: true`, remaining dotted segments become `/`-joined subdirectories under that path and a `.md` is appended.

Resolution is **path-only** — it does not check whether the file exists. Existence is the verb's concern: `get` raises `unknown_key` when the file is missing; `put` happily creates new files in nested entries.

## Frontmatter parsing

`Entry.parse` splits raw bytes on `---\n` boundaries and feeds the YAML chunk to `YAML.safe_load` (no aliases, restricted classes). Unknown top-level frontmatter keys are not rejected here — they are surfaced as warnings by `Schema#validate!`. This is the forward-compat rule from §6 of the spec.

The frontmatter `name:` field is enforced against the file basename inside `Store` (both on read and on write) so a misnamed file or a mistyped `name:` in `put` payload fails fast with `bad_frontmatter`.

## Zone enforcement

Three zones (`fixed`, `state`, `derived`) declared per-entry in the manifest. `Store#put` checks `ManifestEntry#agent_writable?` (true only for `state`) before doing anything else and raises `write_forbidden` otherwise. Zone semantics live in the manifest, not directory names — a project can rename `state/` to whatever it wants.

## ETag and concurrency

`Etag.for_bytes` returns `sha256:<hex>` over the raw file bytes. `put` accepts an optional `if_etag:` — if provided and the on-disk file's etag differs, `etag_mismatch` is raised. No locking, no temp-file-and-rename — the v1 spec leaves stronger guarantees to v1.x (§14 open question).

## Staleness (the dataflow oracle)

`Store#stale` walks every `zone: derived` entry that declares a `generator:` block, reads its `generated.at` frontmatter timestamp, and compares against each `generator.sources` entry's current mtime. Returns the offenders **and their declared `command`**; it does **not** execute anything. This is the core "dataflow oracle, not executor" boundary from §5.1 of the spec.

Sources are heuristically classified: a string matching the textus key grammar with no `/` is treated as a textus key (and enumerated via the manifest); anything else is treated as a repo-relative path.

## Errors → envelopes

All `Textus::Error` subclasses carry a stable error `code`, a `details` hash, and an `exit_code`. `CLI` catches them at the top level and emits the §8 error envelope on stdout; the exit code matches the §8 table. Errors are never written to stderr in `--format=json` mode — agents read stdout.

## What this implementation deliberately leaves out

- **No process spawning.** Even `stale` does not execute. Build runners do that.
- **No transport.** No HTTP server, no socket, no MCP server in this gem. Those are downstream wrappers (see [`./conventions.md`](./conventions.md)).
- **No indexes.** Listing walks the filesystem each time. Premature optimisation for v1.
