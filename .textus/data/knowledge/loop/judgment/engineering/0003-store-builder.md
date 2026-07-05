# Store Builder

ADR-0014: Explicit dependencies. The container builder was extracted from Store into its own class.

Dependency construction is extracted into `Protocol::Builder` so dispatchers stay thin facades.

## The Pattern

The Builder chains three phases:

```ruby
class Protocol::Builder
  def call(root)
    infra = Builder::Infrastructure.call(root)   # Database, FileSystem, Layout
    domain = Builder::Domain.call(infra)          # Manifest, Schemas, Workflows
    Builder::Runtime.call(infra, domain)          # StoreEngine, Gate, Container
  end
end
```

Each phase produces a `Components` Data.define struct passed to the next phase.

## Builder Responsibilities

| Phase | Produces | What it wires |
|-------|----------|---------------|
| Infrastructure | `Components(database, file_system, store, layout)` | SQLite, file I/O, path layout |
| Domain | `Components(manifest, schemas, workflows, workflow_registry)` | Config, validation, workflow definitions |
| Runtime | `Components(store_engine, gate, container)` | All together |

## Why It Works

- **SRP:** Session owns dispatch. Builder owns construction.
- **Testable:** Session can be tested with a mock container instead of building the full graph.
- **Linear boot:** No circular dependencies — infra → domain → runtime is a strict DAG.

## Key Files

- `lib/textus/protocol/builder.rb` — orchestrator
- `lib/textus/protocol/builder/infrastructure.rb` — infra layer
- `lib/textus/protocol/builder/domain.rb` — domain layer
- `lib/textus/protocol/builder/runtime.rb` — runtime layer
