# ADR 0008 — Freshness and Resolution value objects

**Date:** 2026-05-26
**Status:** Accepted
**Depends on:** [ADR 0007](./0007-envelope-data-class.md)

## Context

ADR 0007 typed the `Envelope` itself but stopped short of two adjacent
hashes/tuples that still carried structural meaning by convention:

1. **`Envelope#freshness`** was a string-keyed `Hash` with `"stale"`,
   `"stale_reason"`, `"refreshing"`, and (on failed refresh) a
   `"refresh_error"` key merged in. Callers reached into the hash by
   string key. Typos returned `nil`. There was no signal of which keys
   were always present vs. conditional.

2. **`Manifest#resolve(key)`** returned a three-tuple `[entry, path,
   remaining]`. Twelve-plus call sites destructured the array with
   patterns like `mentry, = manifest.resolve(key)` (entry only), `_,
   path, = manifest.resolve(key)` (path only), and `mentry, path,
   remaining = manifest.resolve(key)`. The shape was a convention
   enforced by the surrounding code, not by the return type.

Both are gem-internal types — they do not appear on the wire — and so
typing them carries no wire-format cost.

## Decision

**Part A.** Replace the freshness hash with a `Data.define` value
object:

```ruby
module Textus
  module Domain
    Freshness = Data.define(
      :stale, :refreshing, :reason, :refresh_error,
      :checked_at, :ttl_remaining_ms,
    ) do
      def to_h_for_wire
        h = { "stale" => stale, "stale_reason" => reason, "refreshing" => refreshing }
        h["refresh_error"] = refresh_error unless refresh_error.nil?
        h
      end
    end
  end
end
```

`Envelope#freshness` now returns `Freshness | nil`. `Envelope#stale?` /
`#refreshing?` delegate to the value object. `Envelope#to_h_for_wire`
flattens via `freshness&.to_h_for_wire&.each` instead of the prior
`Hash#each`.

The renamed `:reason` field (was `"stale_reason"` on the hash) is
mapped back to `"stale_reason"` by `to_h_for_wire`, so CLI JSON output
is byte-identical. The new gem-side fields (`:checked_at`,
`:ttl_remaining_ms`) are deliberately omitted from the wire in this
release.

**Part B.** Replace the resolve tuple with a `Data.define` value:

```ruby
module Textus
  class Manifest
    Resolution = Data.define(:entry, :path, :remaining)
  end
end
```

`Manifest#resolve` now returns a `Resolution`. All call sites updated
to field access (`res = manifest.resolve(key); res.entry`). Single-field
cases collapse to a one-liner: `path = manifest.resolve(key).path`.

## Consequences

- **Public Ruby API breaks.** Embedders that touched `env.freshness`
  hash-style or destructured `manifest.resolve` must update. CHANGELOG
  documents both with concrete migration snippets.
- **Wire format unchanged.** `textus/3`; CLI JSON output byte-identical.
- **`Domain::Freshness::{Evaluator,Verdict,Policy}` namespace** — these
  pre-existed as a nested module. To host the new `Freshness =
  Data.define` constant in the same `Textus::Domain::Freshness`
  namespace, the parent file (`lib/textus/domain/freshness.rb`) now
  defines `Freshness` as a class (a `Data.define` returns a `Class`),
  and the nested files reopen with `class Freshness`. Eager-load
  ordering (parent before children) is provided by `Zeitwerk.eager_load`.
- **`Domain::Freshness::Evaluator` still returns `Verdict`, not
  `Freshness`.** Keeping evaluator → Verdict → Freshness as a layered
  translation preserves the policy-decision/envelope-annotation
  distinction. `Application::Reads::Get` does the Verdict→Freshness
  translation.

## Alternatives considered

- **`Struct` instead of `Data.define`.** Rejected: `Data.define`
  enforces immutability, which is the right default for value objects
  that flow through the read pipeline.
- **Pattern-match destructuring at call sites.** Rejected for
  `Resolution`: the codebase doesn't use pattern matching as an
  established idiom, and inline attribute access is clearer for the
  three-attribute case.
- **Lift `Resolution` into the public hexagonal-ports API.** Deferred:
  it stays inside `Manifest` for now. If a future port (e.g., a
  remote manifest backend) needs to return resolutions, the value
  object is already in shape to move.
