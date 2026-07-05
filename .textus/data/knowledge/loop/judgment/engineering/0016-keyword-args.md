# Keyword-Arg Convention for StoreEngine

## All StoreEngine public methods use keyword args exclusively

`StoreEngine` (`lib/textus/protocol/store_engine.rb`) exposes all public
operations via keyword-only arguments. No positional arguments are accepted.

```ruby
def read(key:)
def put(key:, meta:, body:, content: nil, if_etag: nil, call:)
def delete(key:, call:)
def move(from_key:, to_key:, call:)
def resolve(key:)
def exists?(key:)
def mentry_for(key:)
```

This includes its delegate pipeline modules (`PutPipeline`, `DeletePipeline`,
`MovePipeline`) whose `deps.reader` calls also use keyword args.

## Why

- **Consistency** — every StoreEngine method accepts the same pattern. No
  guessing whether a new operation takes positional or keyword args.
- **Explicit** — `read(key: ...)` is self-documenting at the call site.
- **Extensible** — adding optional parameters never breaks existing callers.
- **Matches handler convention** — protocol handlers also use all-keyword args.

## What to watch for

### Pipelines call `deps.reader`

Pipeline steps receive a `deps` struct whose `reader` is a `StoreEngine`.
Calls must use keyword args:

```ruby
deps.reader.read(key: ctx.key)   # yes
deps.reader.read(ctx.key)        # no
```

### Workflow Runner Context#read

Internally creates a StoreEngine and calls `.read(key:)`:

```ruby
def read(key) = StoreEngine.new(...).read(key:)
```

### Workflow Publisher

Passes a keyword-aware proc rather than `method(:read)`:

```ruby
reader: ->(key:) { @store_engine.read(key:) }  # good
reader: @store_engine.method(:read)              # bad
```

### PublishContext.reader.call

Must use keyword args:

```ruby
pctx.reader.call(key: entry.key)  # good
pctx.reader.call(entry.key)       # bad
```

## Files owning the contract

- `lib/textus/protocol/store_engine.rb`
- `lib/textus/protocol/store_engine/put_pipeline.rb`
- `lib/textus/protocol/store_engine/delete_pipeline.rb`
- `lib/textus/protocol/store_engine/move_pipeline.rb`

## Related

- `knowledge.loop.judgment.engineering.0013-handler-interface`
- `knowledge.loop.judgment.engineering.0009-conventions`
