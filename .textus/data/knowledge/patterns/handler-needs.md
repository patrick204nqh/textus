# Handler NEEDS (Interface Segregation)

ADR-0014: Explicit dependencies. ADR-0023: Uniform use-case shape. ADR-0125: Bounded use-case objects.

Every use case declares exactly the dependencies it needs — nothing more, nothing less.

## The Pattern

Each use case module declares a `NEEDS` array:

```ruby
module GraphEntry
  HANDLES = Dispatch::Contracts::GraphEntry
  NEEDS = %i[link_edge_store].freeze  # Only what this use case needs

  def self.call(command, call, deps)
    deps.link_edge_store  # Access only the declared fields
  end
end
```

The `HandlerResolver` (handler_resolver.rb:26-36) extracts exactly those fields:

```ruby
deps_hash = needs.to_h { |field| [field, ctx_hash[field]] }
dep_struct = Data.define(*needs).new(**deps_hash)
```

## Why It Works

- **Minimal surface:** No use case sees the full 12-field Infrastructure. GraphEntry gets only `link_edge_store`.
- **Explicit contract:** A use case's dependencies are visible at a glance — no hidden imports.
- **Testable:** Each use case can be tested with a minimal stub (just its declared fields).

## Dependency Size by Use Case

| Use Case | NEEDS count | Fields |
|----------|-------------|--------|
| GraphEntry | 1 | link_edge_store |
| RuleTrace | 1 | manifest |
| JobsAction | 1 | job_store |
| GetEntry | 3 | file_store, manifest, layout |
| PutEntry | 6 | file_store, manifest, schemas, audit_log, layout, event_bus |
| DrainStore | 7 | manifest, file_store, schemas, audit_log, job_store, layout, workflows |

## Key Files

- `lib/textus/dispatch/handler_resolver.rb` — NEEDS extraction + injection
- All `lib/textus/use_cases/*/*.rb` — each declares its own NEEDS
