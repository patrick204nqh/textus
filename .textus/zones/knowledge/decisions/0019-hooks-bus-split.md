# ADR 0019 — Split Hooks::Bus into EventBus and RpcRegistry

**Date:** 2026-05-28
**Status:** Accepted
**Depends on:** [ADR 0013](./0013-port-extraction-store-as-root.md), [ADR 0016](./0016-application-ports-value.md)

## Context

`Textus::Hooks::Bus` conflates two responsibilities:

1. **Event publication** — `bus.publish(name, data)` broadcasts events to
   subscribers (hooks listening on `Textus.hook :event_name`).
2. **RPC invocation** — `bus.rpc_callable(hook_name)` retrieves a registered
   callable (e.g. `validate`, `resolve_intake`, `transform_rows`) and invokes
   it with kwargs.

Today, the same object serves both. This forces every hook author to think
about "the bus" as a monolith, and it confuses port contracts: the
`Application::Ports` struct carries both `event_bus` and `rpc_registry` as
aliases pointing to the same object.

This is a leak in the abstraction. The two patterns should be separate
concepts. Additionally, the `Ports` struct will soon carry more collaborators
(ADR 0020 split them into read/write/hook capability records), and mixing
concerns in a single bus object makes capability narrowing harder.

## Decision

Split `Textus::Hooks::Bus` into two collaborators:

1. **`Textus::Hooks::EventBus`** — pubsub only. Public methods:
   - `publish(event_name, data = {})` — broadcasts to all listeners
   - (internal) `register_listener(event_name, callable)` — used by boot

2. **`Textus::Hooks::RpcRegistry`** — named callable registry. Public methods:
   - `invoke(hook_name, ctx:, **kwargs)` — fetches and calls a registered
     callable; embeds the "inject kwargs from ports" pattern internally
   - (internal) `register(hook_name, callable)` — used by boot

Remove the `Textus::Hooks::Bus` constant entirely. Update `Ports` to carry
`events: EventBus` and `rpc: RpcRegistry` as separate fields. The two objects
are still instantiated at `Store` boot and composed into a single `Ports`
value, but they are conceptually distinct.

### RPC invocation plumbing

Today, hook callables declare `store:` or `ports:` as a kwarg, and the
invoker supplies it:

```ruby
# Before
bus.rpc_callable(hook_name).call(store: ports, rows: rows, ...)
```

The split moves this injection into `RpcRegistry#invoke`:

```ruby
# After
rpc.invoke(hook_name, ctx: context, rows: rows, ...)
# RpcRegistry#invoke internally does:
# callable.call(ctx: context, caps: write_caps, rows: rows, ...)
```

The kwarg name changes from `store:` → `ports:` (ADR 0016) and later to
`caps:` (ADR 0020). The public hook DSL will reflect this progression.

## Consequences

**Positive**

- Hook authors and maintainers see `events` (pubsub) and `rpc` (callables)
  as separate concepts. Hook registration functions gain clarity: "I'm
  listening to events" vs. "I'm providing an RPC callable".
- Capability records (ADR 0020) can carry `HookCaps(events, rpc)` without
  mixing pubsub and invocation logic.
- The bus object is no longer a watering hole where unrelated concerns meet.
- `Operations` and use cases can declare `needs rpc for X` vs.
  `listens to events Y` as separate concerns.

**Negative**

- Code that references `Textus::Hooks::Bus` directly (e.g. tests, hooks,
  integration code) must change to use the two new constants.
- Any hook author who cached a reference to the bus breaks. The fixture
  pattern in tests changes.

**Neutral**

- No wire-format change. Protocol remains `textus/3`.
- Gem version bumps; landing in 0.26.0.

## Alternatives considered

**Keep Bus, add two methods `as_event_bus` and `as_rpc_registry`.** Avoids
breaking tests, but perpetuates the confusion in the mental model. Half-measure.

**Split only EventBus, keep RPC on Bus.** Incomplete. The split is equally
justified for both.

**Carve them out during ADR 0020's capability records split.** We could, but
the bus split is independent and clarifies the contract *now*, making ADR
0020's reasoning clearer.
