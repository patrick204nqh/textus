# Middleware Chain

Cross-cutting concerns (auth, timing, audit indexing) are composed as middleware wrapping the use-case execution.

## The Pattern

```ruby
middleware = [
  Dispatch::Middleware::Binder.new,    # Resolve Pending → contract
  Dispatch::Middleware::Trace.new,     # Record timing + metadata
  Dispatch::Middleware::Auth.new,      # Rule engine permission check
  Dispatch::Middleware::AuditIndex.new,# Index write ops, emit events
]
```

Middleware are composed in a chain (pipeline.rb:12-17):

```ruby
stack = @middleware.reverse.reduce(->(cmd, c) { execute(cmd, c) }) do |next_mw, mw|
  ->(cmd, c) { mw.call(container:, command: cmd, call: c, next_handler: next_mw) }
end
```

## Uniform Interface

Every middleware implements the same call signature:

```ruby
def call(container:, command:, call:, next_handler:)
  # before logic
  result = next_handler.call(command, call)
  # after logic
  result
end
```

## Why It Works

- **Pluggable:** Adding middleware = new class + one line in the middleware array. No existing code changes.
- **No Pipeline dependency:** Middleware receives `next_handler` as a callable, not as a Pipeline object. Excellent DIP.
- **Wrap everything:** Trace middleware wraps the entire chain including Auth and AuditIndex.

## Key Files

- `lib/textus/dispatch/pipeline.rb` — chain composition + execution
- `lib/textus/dispatch/middleware/base.rb` — abstract base class
- `lib/textus/dispatch/middleware/binder.rb` — resolves Pending
- `lib/textus/dispatch/middleware/trace.rb` — timing ring buffer
- `lib/textus/dispatch/middleware/auth.rb` — rule engine
- `lib/textus/dispatch/middleware/audit_index.rb` — audit + events
