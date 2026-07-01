# Unified Dispatch

Every verb call — whether from CLI, MCP, or internal — converges through a single `method_missing` on Store.

## The Pattern

```ruby
store.get(key: "foo")       # CLI verb, hand-authored
store.put(key: "bar", ...)  # MCP tool call
store.boot                  # Internal use case
```

All of these route through `Store#method_missing` (store.rb:56-68):

```ruby
def method_missing(name, *args, **kwargs)
  return super unless DOMAIN_VERBS.include?(name)
  spec = VerbRegistry.for(name)
  pending = Dispatch::Binder.command(spec, kwargs)
  call_obj = Value::Call.build(role:, correlation_id:)
  @ctx.pipeline.dispatch(pending, call: call_obj)
end
```

## Why It Works

- **Open for extension:** Adding a new verb requires only: contract + use case + VerbSpec registration. No new dispatch methods.
- **Closed for modification:** The dispatch path never changes — all verbs flow through the same pipeline.
- **Single convergence point:** CLI, MCP, and Doctor checks all hit the same `method_missing`.

## Key Files

- `lib/textus/store.rb` — method_missing entry point
- `lib/textus/dispatch/pipeline.rb` — middleware chain execution
- `lib/textus/dispatch/middleware/binder.rb` — resolves Pending → contract instance
- `lib/textus/dispatch/handler_resolver.rb` — discovers use cases, injects deps
