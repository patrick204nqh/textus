# Pipeline Context and Data.define Convention

## Context objects are immutable

Write pipeline steps communicate via immutable context objects defined as
`Data.define`. Each step receives `(ctx, deps)`, reads from `ctx`, and
returns `ctx.with(updated_field:)` — never mutates in place.

```ruby
DeleteContext = Data.define(:key, :if_etag, :path, :etag_before) do
  def with(**attrs) = self.class.new(**to_h, **attrs)
end
```

## Rules for Data.define fields

- Every field MUST be read by at least one step in the pipeline. Fields
  that are set at construction but never consumed are dead weight.
  Remove them (see commit `97abe966` for examples).
- Use `Data.define` (or `::Data.define` when inside a namespace where
  `Data` is shadowed) — never `Struct`.
- The `with` helper method is standard on all pipeline contexts.

## WriteDeps pattern

Infrastructure dependencies follow the same pattern:

```ruby
WriteDeps = Data.define(:file_system, :manifest, :store, :call, :reader, :layout, :workflow_registry)
```

Deps are constructed once at pipeline entry and passed unchanged through
every step. Steps access deps by name — no positional arguments.

## Step shape

Every pipeline step is a module with a single `.call(ctx, deps)` method:

```ruby
module ResolvePath
  def self.call(ctx, deps)
    path = deps.manifest.resolver.resolve(ctx.key).path
    ctx.with(path:)
  end
end
```

Steps are composed as an ordered array and reduced:

```ruby
STEPS = [ResolvePath, AssertExists, CheckEtag, ...].freeze
STEPS.reduce(initial_ctx) { |c, step| step.call(c, deps) }
```

## What doesn't belong in a context

- Business logic (belongs in the step module)
- I/O (belongs in deps — file_system, manifest, store)
- Transient state like timers or caches (belongs in deps or infrastructure)

---

See also: `knowledge.loop.judgment.engineering.0009-conventions`, commit `97abe966`
