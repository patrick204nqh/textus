# ADR 0022 — Container + Call + Dispatcher

**Date:** 2026-05-29
**Status:** Accepted
**Depends on:** [ADR 0016](./0016-application-ports-value.md), [ADR 0020](./0020-capability-records.md), [ADR 0021](./0021-session-and-module-use-cases.md)
**Supersedes (in part):** [ADR 0020](./0020-capability-records.md), [ADR 0021](./0021-session-and-module-use-cases.md)

## Context

0.26.0 landed three structural moves in close succession:

- ADR 0020 split capabilities into `ReadCaps`, `WriteCaps`, `HookCaps`.
- ADR 0021 introduced `Session` + a `UseCase` registry + module-function
  use cases.
- ADR 0018 carved `Manifest` with an `@manifest` back-reference on each
  entry so helpers like `zone_writers` could resolve policy.

In practice these shapes have rubbed against each other:

1. **Three Caps records, mostly identical.** `ReadCaps`, `WriteCaps`, and
   `HookCaps` are advisory-only in Ruby — there is no enforcement at the
   call site. They share most fields. The split exists to document intent,
   not to constrain behavior. Three records, three constructors, three
   places to update when a port is added.

2. **`Session` is three things.** It is a per-call value (role,
   correlation_id, dry_run), a lazy container of wired ports, *and* a
   verb dispatcher generated via `define_method` from the
   `UseCase.registry`. Three responsibilities, one class.

3. **Module-function use cases come with ceremony.** ~30 use cases each
   look like:

   ```ruby
   module Textus::Application::Write::Put
     def self.call(ctx:, caps:, key:, rows:, dry_run: false)
       Impl.new(ctx: ctx, caps: caps).call(key: key, rows: rows, dry_run: dry_run)
     end

     class Impl
       def initialize(ctx:, caps:); ...; end
       def call(key:, rows:, dry_run:); ...; end
     end
   end
   ```

   Two layers per use case. The outer module exists only to satisfy the
   registry's `respond_to?(:call)` contract.

4. **`PublishContext` is a 12-field struct.** Most fields are derivable
   from a Caps record + a Context. The struct exists so the publish path
   can pass one argument; the cost is twelve coupled accessors.

5. **`Manifest::Entry::Base#@manifest`.** Entries hold a back-reference
   to their manifest, set via `instance_variable_set` during build, so
   that `zone_writers` and friends can look up policy. This is invisible
   coupling — the entry is no longer a value.

The smell is consistent: indirection layers added one at a time, each
defensible on its own, now compounding.

## Decision

Collapse the four shapes into three plain values plus one static table.

1. **`Textus::Container`** — single 8-field `Data` record replacing the
   three Caps. Fields: `manifest`, `file_store`, `schemas`, `root`,
   `audit_log`, `events`, `rpc`, `authorizer`. Constructed once at
   `Store` boot.

2. **`Textus::Call`** — immutable per-invocation value replacing
   `Application::Context`. Same shape, new name. Carries `role`,
   `correlation_id`, `dry_run`, etc.

3. **`Textus::Dispatcher::VERBS`** — static frozen hash mapping verbs to
   use-case classes. Replaces the runtime `UseCase.register(...)`
   registry and the `define_method` loop in `Session`.

4. **Plain-class use cases.** Each use case is now a single class with
   the conventional shape:

   ```ruby
   class Textus::Write::Put
     def initialize(container:, call:); @container = container; @call = call; end
     def call(key:, rows:, dry_run: false); ...; end
   end
   ```

   No outer module, no `Impl`, no factory method. The class *is* the
   use case.

5. **`Store#put` / `Store#as(role)` / `RoleScope`.** Public API replaces
   `Session`. `store.put(key, ...)` is the verb call. `store.as(role)`
   returns a `RoleScope` — a thin value that holds a role and forwards
   verb calls to the store. No metaprogramming, no per-store
   `define_method` loop.

Along with these moves, four pieces of bookkeeping:

- **`Application::*` namespace flattened to top-level.** `Write::*`,
  `Read::*`, `Maintenance::*`, `Projection`, `Envelope::IO::*` now live
  directly under `Textus::`. The `Application` namespace added no
  information.
- **`Infra::*` renamed to `Ports::*`.** Matches the vocabulary in
  ADR 0013 and ADR 0016 — these are port adapters, not infrastructure.
- **Manifest back-reference dropped.** `Entry::Base#zone_writers`,
  `#in_generator_zone?`, `#in_proposal_zone?` now take an explicit
  `policy:` argument. Entries become true values.
- **`PublishContext` shrunk to `(container, call, reader)`.** Other
  fields are derived via accessors. Twelve attributes become three.

## Consequences

**Breaking — Ruby API.** This is a major Ruby-API break. Migration is
mechanical:

| Old | New |
|-----|-----|
| `store.session(role: r).put(...)` | `store.as(r).put(...)` or `store.put(..., role: r)` |
| `Textus::Application::Write::Foo` | `Textus::Write::Foo` |
| `Textus::Application::Read::Foo` | `Textus::Read::Foo` |
| `Textus::Application::Maintenance::Foo` | `Textus::Maintenance::Foo` |
| `Textus::Application::Envelope::Reader\|Writer` | `Textus::Envelope::IO::Reader\|Writer` |
| `Textus::Application::Projection` | `Textus::Projection` |
| `Textus::Application::Context` | `Textus::Call` |
| `Textus::Application::{ReadCaps,WriteCaps,HookCaps,Caps}` | `Textus::Container` |
| `Textus::Application::UseCase` | `Textus::Dispatcher` |
| `Textus::Infra::Foo` | `Textus::Ports::Foo` |

Hook RPC callables (`:resolve_intake`, `:transform_rows`, `:validate`)
now receive `caps: <Container>` instead of `caps: <WriteCaps>`. Field
names are preserved, so handlers reading `caps.manifest`, `caps.events`,
etc. continue to work — the type narrows but the surface does not
shift.

**Wire format unchanged.** Protocol remains `textus/3`. CLI verb
signatures unchanged. No on-disk format changes.

**~600 LOC removed net.** Across ~60 files. Most of the loss is the
disappearance of the inner `Impl` class per use case, the three Caps
constructors, the `Session#define_method` loop, the
`UseCase.register` calls, and nine `PublishContext` accessors.

**Migration path is mechanical.** Find/replace covers all rename
breaks. The two semantic moves — `session(role:)` → `as(role)` and the
Manifest helper signature — surface as clear `NoMethodError` /
`ArgumentError` at boot.

## Alternatives considered

**Keep the Caps split for type-clarity.** Each verb would continue to
declare its power level via the Caps type it receives. Rejected: the
split was advisory in Ruby (no enforcement), and the documentation
value did not outweigh the carrying cost of three records.

**Keep `Session` as a thin facade.** Drop the registry, drop the
`define_method`, keep `Session` as `RoleScope`-equivalent under the
existing name. Rejected: the verb-dispatch + cache + value-bag triple
was the core smell. Keeping the name kept the temptation to re-grow
the responsibilities.

**Single class with all three roles (Container, Call, Dispatcher).**
Rejected: that is exactly what `Session` already was. The point is
the separation.
