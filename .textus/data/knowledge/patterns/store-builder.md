# Store Builder

Dependency container construction is extracted into its own class so Store stays a thin facade.

## The Pattern

Instead of Store building its own dependencies:

```ruby
# Bad: Store does discovery, session management, AND context building
class Store
  def initialize(root, ...)
    @ctx = build_ctx(root)  # 50 lines of concretions
  end
end
```

The Builder handles construction:

```ruby
# Good: Store delegates to Builder
class Store
  def initialize(root, ...)
    @ctx = Store::Builder.new.call(root)
  end
end
```

## Builder Responsibilities

The Builder (builder.rb) handles: Manifest loading, Port instantiation (Store, FileStore, AuditLog, Clock), Schema registry, Link edge store, Workflow loading, Event bus + cascade subscribers, Freshness evaluation, Trace buffer, Middleware wiring, Pipeline construction.

## Why It Works

- **SRP:** Store owns session + dispatch. Builder owns construction.
- **DIP:** Builder is extracted but still ultimately depends on concretions. The next step is a DI container.
- **Testable:** Store can be tested with a mock Infrastructure instead of building the full graph.

## Key Files

- `lib/textus/store/builder.rb` — the Builder
- `lib/textus/store.rb` — thin facade using Builder
- `lib/textus/store/infrastructure.rb` — the Data.define container
