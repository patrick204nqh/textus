# Handler Interface Convention

## Every handler accepts `ctx:` and `call:`

All verb handlers (in `Protocol::Handlers`, `Lanes::*::Handlers`) share a
uniform signature: the first two keyword arguments are always `ctx:` and
`call:`. `ctx:` provides read/write access to the store, manifest, and
infrastructure. `call:` carries the invocation context (role,
correlation_id, timestamp, dry_run flag).

```ruby
def get(key:, ctx:, call:)
  #                                      ^^^^
  # call: is part of the protocol contract. Gate always passes it.
  # Handlers that don't use it still declare it for interface uniformity.
end
```

This is enforced by `Gate#dispatch`, which always appends `call:` to the
handler invocation. Suppress RuboCop `Lint/UnusedMethodArgument` via
`.rubocop.yml` exclusion for handler files (not per-method inline).

## Read vs write handlers

**Write handlers** (`put`, `delete`, `move`, `propose`, `accept`,
`reject`) consume `call:` for audit-logging the role and correlation_id.

**Read handlers** (`get`, `list`, `where`, `uid`, `deps`, `rdeps`,
`graph`, `boot`, `schema_show`, `audit`, `blame`, `workflow_spec`,
`data_mv`, `diff`) do NOT use `call:` — but must still declare it for
interface consistency.

## Why not remove it

Gate dispatches via `handler.public_send(verb, **bound, ctx:, call:)`.
Removing `call:` from a handler signature would break dispatch. Two
dispatch paths (with/without `call:`) would add complexity for zero
benefit — the parameter is zero-cost at runtime.

## Verb args come from VerbRegistry

Each verb declares its accepted args via `ArgSpec` in `VerbRegistry`.
The Binder maps wire names to internal names. Additional parameters
(`dry_run:`, `if_etag:`) should only be declared when the handler
actually uses them. Remove dead ones (see commit `97abe966`).

---

See also: `knowledge.loop.judgment.engineering.0009-conventions`, commit `97abe966`
