# ADR 0017 — Split EnvelopeIO into Reader and Writer

**Date:** 2026-05-28
**Status:** Partially superseded by [ADR 0022](./0022-container-call-dispatcher.md) — the Reader/Writer split shipped, but lives at `Envelope::IO::Reader` / `Envelope::IO::Writer` rather than the `Application::Writes::Envelope*` names proposed here.
**Depends on:** [ADR 0013](./0013-port-extraction-store-as-root.md), [ADR 0016](./0016-application-ports-value.md)

## Context

`Application::Writes::EnvelopeIO` was introduced by ADR 0013 to lift
the orchestration that previously lived inside `Store::Writer`. It
landed in one class because `Put`, `Delete`, and `Mv` shared the
serialize → uid-inject → name-check → schema-validate → etag-check
→ file-write → audit-append pipeline, and pulling it out broke the
duplication.

That was the right first move. One release later, the class has
accreted more:

```
EnvelopeIO (166 LOC)
├── read_envelope(key)            → read path
├── existing_uid_for(mentry, path) → read path
├── write(key, …)                 → write path
├── delete(key, …)                → write path
├── move(from, to, …)             → write path
├── ensure_uid(…)                 → write helper
├── enforce_name_match!(…)        → write helper
├── serialize_for_put(…)          → write helper
└── exists?(path)                 → leak
```

Four problems:

1. **The name lies.** "EnvelopeIO" reads as "envelope I/O" — bytes
   in, bytes out — but two-thirds of the body is application
   coordination (etag negotiation, schema validation, uid
   reconciliation, audit append).
2. **Reads and writes share nothing.** `read_envelope` and
   `existing_uid_for` exist only because `Mv` and `EnvelopeIO`'s own
   `write` need pre-write inspection. They are pure-read paths.
   The unified class forces read callers to depend on the entire
   write-side surface.
3. **Constructor noise.** Every write use case (`Put`, `Delete`,
   `Mv`, plus `Refresh::Worker` and `Refresh::All` transitively)
   constructs a 5-arg `EnvelopeIO`. ADR 0016 will fold this into
   `Operations` wiring; the split lets each use case ask only for
   the half it needs.
4. **Audit row ownership is murky.** Each write helper appends its
   own audit row from inside `EnvelopeIO`. That logic is tightly
   coupled to the write code path. The split surfaces it as a
   first-class concern of the writer; the reader has no business
   touching `audit_log`.

## Decision

Replace `Application::Writes::EnvelopeIO` with two narrower
collaborators in the same namespace:

### `Application::Writes::EnvelopeReader`

```ruby
class Application::Writes::EnvelopeReader
  def initialize(file_store:, manifest:)
    @file_store = file_store
    @manifest   = manifest
  end

  def read(key)            # → Envelope | nil
  def existing_uid(key)    # → String | nil   (used by Mv)
  def exists?(key)         # → bool           (was exists?(path) — now key-shaped)
end
```

Read-only. No schemas, no audit log, no etag negotiation. Used by
`Mv` for pre-move inspection and by any future read-side caller
that needs a low-level envelope parse without the public
`Reads::Get` freshness rollup.

### `Application::Writes::EnvelopeWriter`

```ruby
class Application::Writes::EnvelopeWriter
  def initialize(file_store:, manifest:, schemas:, audit_log:, ctx:)
    …
  end

  def put(key, mentry:, payload:, if_etag: nil)   # → Envelope (writes + audits)
  def delete(key, mentry:, if_etag: nil)          # → nil      (writes + audits)
  def move(from_key:, to_key:, new_mentry:, if_etag: nil)  # → Envelope (writes + audits)
end
```

Each method owns one verb end-to-end: validate → serialize →
etag-check → write bytes → append audit row. The audit append is
the **last** step inside each method, on the same code path as the
write — no possibility of a write succeeding without an audit row.

### Construction

`Operations` builds both once per call:

```ruby
def envelope_reader
  @envelope_reader ||= Application::Writes::EnvelopeReader.new(
    file_store: @ports.file_store, manifest: @ports.manifest,
  )
end

def envelope_writer
  @envelope_writer ||= Application::Writes::EnvelopeWriter.new(
    file_store: @ports.file_store, manifest: @ports.manifest,
    schemas: @ports.schemas, audit_log: @ports.audit_log, ctx: @ctx,
  )
end
```

`Put` and `Delete` take `writer:`. `Mv` takes both `reader:` and
`writer:` (it inspects pre-move state before writing).

### Migration of the shared helpers

| Old (`EnvelopeIO` private)  | New home                                                |
|------------------------------|---------------------------------------------------------|
| `serialize_for_put`         | `EnvelopeWriter` private                                |
| `ensure_uid`                | `EnvelopeWriter` private                                |
| `enforce_name_match!`       | `EnvelopeWriter` private                                |
| `existing_uid_for(m, path)` | `EnvelopeReader#existing_uid(key)` (key, not path)      |
| `exists?(path)`             | `EnvelopeReader#exists?(key)` — callers pass keys       |

The path-shaped `exists?` was only ever called by `Reads::Get`
internals that already had a key; the key-shaped version closes the
abstraction cleanly.

## Consequences

**Positive**

- Each new class is ~80 LOC of one-shape code: `EnvelopeReader` does
  parsing only; `EnvelopeWriter` does write+audit only.
- Audit rows become unmissable: every public method on
  `EnvelopeWriter` ends with `@audit_log.append(…)`.
- `Mv` becomes a readable two-step orchestration: inspect via reader,
  rewrite via writer.
- Sets up cleaner backends: read-only consumers (a future
  `textus inspect` or schema-validator pipeline) can carry a
  `EnvelopeReader` without ever instantiating audit-log machinery.

**Negative**

- Two new files instead of one. Net LOC drops slightly because the
  shared instance variables were duplicated anyway; the readability
  win is the point.
- Tests that mocked `EnvelopeIO` must split into reader/writer
  doubles. Most existing specs use real instances and won't change.

**Neutral**

- No public surface change for `Operations` callers. The split is
  entirely internal to `Application::Writes::*`.
- No wire-format change. Bumps with 0.25.1 alongside ADRs 0016, 0018.

## Alternatives considered

**Leave it as `EnvelopeIO` and rename the class to `EnvelopePipeline`.**
Cheaper, but doesn't address the read/write coupling — the
constructor still demands write-side dependencies for read calls.

**Push `audit_log.append` up into `Put/Delete/Mv` directly, leaving
`EnvelopeIO` purely as bytes+schema.** Tempting symmetry, rejected:
appending audit at the use-case layer means each writer must
remember to do it, and the failure mode (write succeeds, audit row
forgotten) is exactly the corruption ADR 0013 was trying to make
impossible.
