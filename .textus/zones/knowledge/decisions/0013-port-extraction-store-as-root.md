# ADR 0013 — Port extraction: Store as composition root

**Date:** 2026-05-27
**Status:** Partially superseded by [ADR 0022](./0022-container-call-dispatcher.md) (`Infra::*` renamed to `Ports::*`; `Application::Writes::EnvelopeIO` flattened to `Envelope::IO`). The composition-root role of `Store` is unchanged.
**Depends on:** [ADR 0005](./0005-store-facade-final-removal.md), [ADR 0006](./0006-format-strategy-extraction.md), [ADR 0007](./0007-envelope-data-class.md)

## Context

ADRs 0004 and 0005 collapsed the `Store` facade for embedders: the
public surface became `Operations`, and direct `store.get` /
`store.list` / `store.put` calls went away. What remained inside
`Store` were two classes whose names suggested infrastructure but
whose bodies were application code:

- **`Store::Reader`** — serialized envelope reads, name-match guards,
  schema awareness, dependency graph traversal, publication filters,
  staleness predicates. None of this is I/O; all of it is
  coordination over an envelope vocabulary.
- **`Store::Writer`** — serialize, UID inject, name-match against the
  manifest, schema validate, etag negotiate, audit append, event
  publish, then `File.write`. Six application steps and one syscall
  bundled behind a name that suggested it just put bytes on disk.

ADR 0006 had already extracted the per-format strategies that
`Reader`/`Writer` used to serialize envelopes. ADR 0007 had typed
the envelope itself. The remaining seam was the I/O port: a
properly narrow contract that says *bytes in, bytes out* and
nothing else, so the orchestration above it can live where it
already belongs — `Application::*`.

Three pressures forced the issue:

1. **The `Store::*` namespace was lying.** `Reader`/`Writer`
   suggested infra; the code was application. New contributors had
   to read the bodies to understand the layering, because the names
   did not tell them.
2. **Non-file storage backends were not possible.** Anyone who
   wanted S3 or SQLite would have had to subclass two classes that
   mixed I/O with application coordination, copying the
   coordination wholesale. The narrow port unlocks that.
3. **Write-path duplication.** `Put`, `Delete`, and `Mv` each
   reached through `store.writer` for the same six-step pipeline.
   Lifting the pipeline into a named collaborator
   (`EnvelopeIO`) made the duplication visible and removable.

## Decision

Introduce a true I/O port and lift the orchestration into the
application layer. Reshape `Store` into a composition root.

**`Textus::Infra::Storage::FileStore`** is the port. Its surface
is bytes only:

```ruby
class Infra::Storage::FileStore
  def read(relpath)          # → String (bytes) or raises NotFound
  def write(relpath, bytes)  # → etag
  def delete(relpath)        # → bool
  def exists?(relpath)       # → bool
  def etag(relpath)          # → String
end
```

No envelope knowledge. No schema knowledge. No manifest. No
events. A future `S3Store` or `SqliteStore` implements this
contract and nothing else.

**`Textus::Application::Writes::EnvelopeIO`** is the lifted
write pipeline. Given a built envelope, it serializes, validates,
negotiates etag, writes via the port, appends to the audit log,
and publishes the event. `Put`, `Delete`, and `Mv` collaborate
with it via constructor injection (`envelope_io:`).

**`Textus::Schemas`** replaces `Store#schema_for`. An eager-loading
cache built once at boot from the `_schemas/**` zone; reads no
longer touch `Store` for schema lookup.

**Read use cases lose the `Reader` indirection.** `Reads::Get`,
`Reads::List`, `Reads::Where`, `Reads::Stale`, `Reads::Deps`,
`Reads::Validator`, etc., read directly from `file_store`,
`manifest`, and `schemas`. The path is `Operations → use case
→ ports`.

**`Store::Reader` and `Store::Writer` are deleted.**

**`Store::AuditLog`, `Store::Sentinel`, `Store::Staleness`,
`Store::Validator`** move to the layers they belong to —
`Infra::AuditLog`, `Domain::Sentinel`, `Domain::Staleness`,
`Application::Reads::Validator`. The `Store::*` namespace stops
being a catch-all.

**`Store` becomes a composition root.** Its job is to construct
and expose collaborators: `manifest`, `schemas`, `file_store`,
`audit_log`, `bus`, `registry`, `root`. Plus `load_hooks` and
`operations` — both thin delegations to dedicated collaborators
(`Hooks::Loader`, `Operations.for(self)`).

## Consequences

- **Public Ruby API breaks** for embedders that reached through
  `store.reader.*` / `store.writer.*` / `store.schema_for`, plus
  the four `Store::*` renames. The CHANGELOG ships the full
  migration table; it's mechanical. CLI behavior is unchanged.
- **Non-file storage backends are possible.** Not delivered.
  `Infra::Storage::FileStore` is the only implementation in-tree.
  A consumer who needs S3 implements the five-method contract.
- **Write-path duplication is gone.** `Put`, `Delete`, and `Mv`
  share `EnvelopeIO` instead of each reimplementing the
  pipeline through `Store::Writer`.
- **Read paths are flatter.** One fewer indirection between
  `Operations` and the ports.
- **The layering names tell the truth.** `Infra::*` is I/O,
  `Domain::*` is vocabulary, `Application::*` is coordination.
  Names match contents.
- **Wire format and audit log NDJSON are unchanged.** Stores
  written by 0.17.0 round-trip through 0.18.0 byte-for-byte.

## Out of scope

- **Non-file storage backends.** The extraction *enables* them;
  this release does not ship one. A future ADR will accompany the
  first real backend (likely SQLite for testing, or S3 for cloud
  embedders).
- **Schema engine replacement.** `Schemas` is a cache around the
  existing per-format validators. Swapping JSON Schema for
  another engine is a separate decision.
- **Sub-typing `Envelope#meta`.** The `meta` hash stays untyped
  in this release. ADR 0007 typed the envelope; further
  refinement waits for a real need.
- **1.0 freeze.** Public-surface stability is still a goal, not a
  guarantee. The breaking changes here are justified by the
  layering payoff.

## Alternatives considered

- **Keep `Store::Reader`/`Writer`, rename them.** Rejected: the
  problem wasn't the name, it was that two classes were doing six
  application steps each. Renaming wouldn't have removed the
  duplication across `Put`/`Delete`/`Mv` or made non-file
  backends possible.
- **Make `FileStore` envelope-aware (read returns parsed
  envelopes).** Rejected: that reintroduces the exact mixing the
  port extraction is meant to remove. A future `S3Store` would
  have to re-implement parsing. Bytes-only is the contract.
- **Lift orchestration into `Operations` directly, skip
  `EnvelopeIO`.** Rejected: `Operations` is the public API
  surface. The write pipeline is a coherent named collaborator;
  inlining it into seven methods on `Operations` would make
  `Operations` the new god class.
- **Lazy schema loading via `Store#schema_for`.** Rejected: the
  on-demand path required `Store` to know about schemas, which
  kept `Store` participating in reads. Eager-loading via
  `Schemas` lets `Store` stop knowing.
