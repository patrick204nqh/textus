# ADR 0010 — Flat Operations API

**Date:** 2026-05-27
**Status:** Partially superseded by [ADR 0022](./0022-container-call-dispatcher.md) — the flat one-method-per-use-case ergonomics stand, but the `Operations` class described here is replaced by `Container` + `RoleScope` under the 0.27.0 architecture.
**Depends on:** [ADR 0004](./0004-operations-rename-and-store-facade-removal.md)

## Context

ADR 0004 landed `Textus::Operations` as the canonical entry point for
the application layer, grouping use cases under three namespace shells
— `Operations#reads`, `Operations#writes`, `Operations#refresh` —
that each returned a thin object exposing one method per use case. A
caller wanting to write an entry typed:

```ruby
ops.writes.put.call("working.notes.foo", body: "hi")
```

Three levels of indirection: the `Operations` facade, the `Writes`
shell, the `Put` use-case object, then `.call`. The shells held no
state of their own — they were containers, not collaborators. They
existed because the `lib/textus/application/{reads,writes,refresh}/`
directory layout mirrored them one-to-one, and the names had a soft
documentary value ("`writes.*` is everything that mutates").

In practice the namespacing was organisational, never contractual.
Embedders (the maintainer's own downstream projects included)
consistently typed the longer form once, stored the result, and used
it. Several embedders complained directly: "why three levels?" The
`.call` at the end was the part that drew the most fire — it read as
an internal-API leak rather than a clean public surface.

The cost of keeping the shells was paid every time someone read or
wrote textus-using code. The benefit — "the namespace tells you what
kind of operation this is" — was already encoded in the use-case
name itself (`put` reads as a write; `get` reads as a read).

## Decision

Flatten `Textus::Operations` to one public method per use case. Every
use case under `lib/textus/application/{reads,writes,refresh}/` gets
a directly-named method on `Operations`:

```ruby
ops.put(key, body: "hi")              # was: ops.writes.put.call(key, body: "hi")
ops.get(key)                          # was: ops.reads.get.call(key)
ops.get_or_refresh(key)               # was: ops.reads.get_or_refresh.call(key)
ops.refresh(key)                      # was: ops.refresh.worker.call(key)
ops.refresh_all(prefix:, zone:)       # was: ops.refresh.all.call(prefix:, zone:)
```

Internal use-case instances are memoized via `||=` on instance
variables — calling `ops.put` twice returns the same internal
`Application::Writes::Put` object, so the construction cost (which
wires `Context`, bus, manifest lookups) is paid once per
`Operations`.

`Operations#with_role(role)` returns a fresh `Operations` with a
fresh `Context` and no shared memoization — switching role mid-
session does not leak a memoized use-case object bound to the prior
role's `Context`.

The shell classes `Operations::Reads`, `Operations::Writes`, and
`Operations::Refresh` are deleted. References to them survive only
in v0.12.2 plan history and ADR 0004.

## Consequences

- **Public Ruby API breaks.** Embedders run a one-line sed:
  `ops.writes.put.call(...)` → `ops.put(...)`. The CHANGELOG ships
  the sed pattern.
- **`Operations` grows but stays small.** ~25 methods, each a
  one-liner that delegates to a memoized internal. Under ~100 lines
  total. Readable as a single file.
- **CLI internals unchanged.** Verbs already constructed `Operations`
  and called its methods. The translation from the prior three-level
  form to the flat form was mechanical.
- **Memoization is per-instance.** Two `Operations` (e.g., the
  original and one from `with_role`) hold their own use-case caches.
  No global state.
- **Wire format unchanged.** CLI JSON output byte-identical to
  v0.16.0; `textus/3` stays.

## Out of scope

- `Store::Reader` / `Store::Writer` port boundary — the infra
  decomposition is 0.18.0 work.
- Renaming `Application::Context` — the per-request object stays
  exactly as it was.
- Adding or removing any actual use cases. This is a surface
  reshape, not a capability change.

## Alternatives considered

- **Keep the shells, drop the `.call`.** Make `ops.writes.put(...)`
  invoke directly. Rejected: the three-level read survives, and the
  shell objects still hold no state. The win is partial.
- **Add the flat methods alongside the shells.** Rejected:
  permanent surface duplication, and embedders would split between
  the two for years. Pick one shape and commit.
- **Replace `Operations` with module-level functions
  (`Textus.put(store, key, ...)`).** Rejected: the `Context` and
  role binding are real state that wants to live on an object. A
  function-style surface would force every call to re-pass role and
  store, which is worse ergonomics, not better.
