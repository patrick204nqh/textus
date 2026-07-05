# Unified Dispatch

ADR-0132: Replaced `store.entry(:get, key:)` with `session.get(key:)` via `method_missing`.

Every verb call — whether from CLI, MCP, or internal — converges through `Protocol::Session#method_missing`.

## The Pattern

```ruby
session.get(key: "foo")       # CLI verb
session.put(key: "bar", ...)  # MCP tool call
session.boot                  # Internal use case
```

All of these route through `Protocol::Session#method_missing`:

```ruby
def method_missing(name, *args, **kwargs)
  return super unless VerbRegistry.for(name)
  @bridge.dispatch(name, **kwargs)
end
```

The `Bridge` delegates to `Gate.dispatch`, which:
1. Looks up the verb spec from `VerbRegistry`
2. Authorizes the write via `Manifest::Policy`
3. Binds arguments via `Protocol::Binder`
4. Resolves the handler (`Protocol::Handlers::Read`/`Write`/`System` or lane-specific)
5. Dispatches with `ctx:` and `call:`

## Why It Works

- **Open for extension:** Adding a new verb requires only: VerbSpec registration + handler method.
- **Closed for modification:** The dispatch path never changes — all verbs flow through `Gate#dispatch`.
- **Single convergence point:** CLI, MCP, and Doctor checks all hit the same `method_missing`.

## Key Files

- `lib/textus/protocol/session.rb` — method_missing entry point
- `lib/textus/protocol/gate.rb` — dispatch hub (lookup → authorize → bind → handler)
- `lib/textus/protocol/binder.rb` — validates and binds keyword args
- `lib/textus/protocol/handlers/` — verb handler modules (Read, Write, System)
