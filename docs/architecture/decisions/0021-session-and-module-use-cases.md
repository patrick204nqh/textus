# ADR 0021 — Session + module-function use-cases

**Date:** 2026-05-28
**Status:** Partially superseded by [ADR 0022](./0022-container-call-dispatcher.md) — the per-call `Session` is replaced by `RoleScope` under the 0.27.0 architecture; the use-case shape was refined by [ADR 0023](./0023-uniform-use-case-shape.md).
**Depends on:** [ADR 0013](./0013-port-extraction-store-as-root.md), [ADR 0016](./0016-application-ports-value.md), [ADR 0020](./0020-capability-records.md)

## Context

`Textus::Operations` exists to vend use cases. Today it is 182 lines of
boilerplate:

```ruby
class Operations
  def self.for(store, ...)
    # ... wiring ...
    new(ctx: ctx, ports: ports)
  end

  def initialize(ctx:, ports:, ...)
    @ctx = ctx
    @ports = ports
  end

  def put(key:, rows:, dry_run: false)
    Application::Writes::Put.new(
      ctx: @ctx, ports: @ports, envelope_io: ..., hook_context: ...
    ).call(key: key, rows: rows, dry_run: dry_run)
  end

  def delete(key:, reason:)
    Application::Writes::Delete.new(
      ctx: @ctx, ports: @ports, envelope_io: ..., hook_context: ...
    ).call(key: key, reason: reason)
  end

  # ... move, get, patch, etc. ...
end
```

Each method follows the same pattern: instantiate a use-case class, pass fixed
collaborators (context, ports, derived adapters), call it. This is pure
dispatch.

Three concrete costs:

1. **Repetition.** Six verbs, six factory methods, six nearly-identical lines
   of wiring. Adding a new use case means adding another method.
2. **Maintainability.** The collaborators are line-noise. The actual
   responsibility — "invoke the appropriate use-case class for this verb" —
   is obscured.
3. **Subclassing temptation.** Because `Operations` is a class, user code
   sometimes subclasses it to override a verb or add logging. This breaks
   when we change the constructor (as happened in ADR 0016). A function-based
   interface makes subclassing a non-option.

ADR 0020 carved capabilities into three records. Now that each use case
declares its power level, we can systematize this.

## Decision

Rename `Textus::Operations` to `Textus::Session` to better reflect that it
represents a call context (role, correlation ID, dry-run mode, etc.) living
for the duration of a request.

Replace the class with a **registry + generator** pattern:

1. Each use case is defined as a module with a `call(ctx:, caps:, **args)`
   method:

   ```ruby
   module Textus::Application::Write::Put
     def self.call(ctx:, caps:, key:, rows:, dry_run: false)
       # use case logic
     end
   end
   ```

2. Use cases are registered in a central registry at boot:

   ```ruby
   Textus::Application::UseCase.register(:put, Write::Put)
   Textus::Application::UseCase.register(:delete, Write::Delete)
   Textus::Application::UseCase.register(:move, Write::Move)
   Textus::Application::UseCase.register(:get, Read::Get)
   # ...
   ```

3. `Session` is built at `Store` boot and holds the three capability objects:

   ```ruby
   class Session
     def initialize(read_caps:, write_caps:, hook_caps:)
       @read_caps  = read_caps
       @write_caps = write_caps
       @hook_caps  = hook_caps
     end

     # Generate a method for each registered use case
     UseCase.registry.each do |verb, use_case_module|
       define_method(verb) do |ctx:, **args|
         caps = determine_caps(use_case_module)  # ReadCaps or WriteCaps
         use_case_module.call(ctx: ctx, caps: caps, **args)
       end
     end
   end
   ```

   For example, calling `session.put(ctx: ctx, key: "x", rows: [...])` looks
   up the `:put` use case from the registry, determines that it needs
   `WriteCaps`, and invokes it.

4. `Store#session(role:)` returns a `Session` instance scoped to that role:

   ```ruby
   session = store.session(role: Role::OWNER)
   result = session.put(ctx: ctx, key: "x", rows: [...])
   ```

   No factory method `Operations.for(store, ...)` — just ask the store for
   its session.

### Hook callables no longer take `operations: self`

Today, hook callables (e.g. `validate`, `transform_rows`) receive `operations:`
so they can delegate to other use cases:

```ruby
# Old
Textus.hook :validate do |store:, operations:, rows:|
  # call operations.transform_rows(...)
end
```

With module-based use cases and the registry, hooks receive the hook
capabilities and can invoke use cases directly:

```ruby
# New
Textus.hook :validate do |ctx:, caps:, rows:|
  # cap.rpc.invoke(:transform_rows, ctx: ctx, rows: rows, ...)
end
```

The indirection through `operations` is gone. Hooks are pure functions of
their inputs.

## Consequences

**Positive**

- `Session` shrinks from 182 lines of repeated factory methods to ~30 lines of
  generic wiring + the registry definition.
- Adding a new use case is mechanical: define the module, register it. No need
  to touch `Session` itself.
- Use cases are now standalone modules. They have no coupling to `Session`,
  making them easier to test and compose.
- `Store` is the composition root. Callers ask for a session; they don't
  construct `Operations` directly.
- Subclassing `Operations` to override verbs is no longer possible. The
  registry is the single point of extension.
- The hook contract is cleaner. Hooks don't carry a reference to `operations`;
  they use the RPC registry directly.

**Negative**

- Any code that subclassed `Operations` breaks. The pattern is no longer
  supported.
- Use-case constructors are gone. Use cases are now module singletons with a
  `call` method. Tests that instantiate use-case classes need refactoring.
- The `define_method` loop to generate session methods is metaprogramming.
  Some readers may find it harder to trace.
- Hook callables that currently declare `operations: self` must update to
  declare `caps:` and use `caps.rpc.invoke(...)`.

**Neutral**

- No wire-format change. Protocol remains `textus/3`.
- Gem version bumps; landing in 0.26.0.
- The public verb signatures (`session.put(ctx: ctx, key: "x", ...)`) are
  unchanged.

## Alternatives considered

**Keep Operations, simplify with `method_missing`.** `method_missing` on
undefined verbs could check the registry and dispatch. Requires dynamism at
call time and still leaves the factory methods.

**Use singleton methods on a module instead of a class.** Avoids the
metaprogramming, but loses the natural composition root (`store.session`).

**Use Dry::Container or similar DI framework.** Overkill for this use case.
We need exactly one registry and one generator. A hand-rolled solution is
simpler.

**Keep use-case classes, remove subclassing via frozen class.** Doesn't solve
the repetition or the maintenance burden. The boilerplate stays.
