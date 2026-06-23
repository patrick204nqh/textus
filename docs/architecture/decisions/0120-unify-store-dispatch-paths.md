---
name: '0120-unify-store-dispatch-paths'
uid: 73D74CA486A29351
---

# ADR-0120: Unify dispatch paths — Store as the single dispatch module

## Status

Proposed

## Date

2026-06-22

## Context

The textus store had accumulated four dispatch paths — code paths that invoke the same handlers through different entry points:

1. **`Store#dispatch(spec:, inputs:, ...)`** — used by `Surface::CLI::Runner`, CLI escape-hatch verbs (get, put, doctor), and `Surface::Projector`. Goes through `Bus.dispatch` → `Bus::Pipeline` → `HandlerRegistry` → handler.

2. **`RoleScope#verb(args)`** — injected by the `define_method` loop in `textus.rb`. Used by `Surface::MCP::Server` and `Schema::Tools`. Also goes through `Bus.dispatch`.

3. **`Store#verb(role:, ...)`** — also injected by the `define_method` loop. Delegates to `Store#as(role).verb(...)`, which goes through `RoleScope`. So this path adds one hop of indirection on top of path 2.

4. **`ReadModel` / `CommandModel`** — exclusively instanced by `Store#query` and `Store#command`. Both methods had **zero callers** outside their own definitions at the time of this ADR. Dead code.

A reader needed to understand four different invocation patterns to trace how a user action reaches a handler. The `define_method` injection in `textus.rb` was code-as-configuration — load-time metaprogramming that made the dispatch surface implicit rather than explicit.

## Decision

Fold all dispatch into a single `Store` interface using `method_missing`, and delete the dead/duplicate modules:

### 1. Store becomes the single dispatch module

`Store` holds `container`, `role`, `correlation_id`, `dry_run`, and session state (cursor, propose_lane, contract_etag). Dispatch is unified under `method_missing`:

- `store.verb(**inputs)` — single entry point for all verbs
- Kwargs only — no positional args accepted
- `method_missing` resolves verb from `VerbRegistry`, binds inputs via `Bus::Binder`, constructs `Call`, dispatches through `Bus::Pipeline`

### 2. Delete `RoleScope`

Its identity fields (role, correlation_id, dry_run) move to `Store`. The `Store#with_role(role)` method returns a new `Store` bound to the given role with a fresh session. Callers that did `store.as(role).get(key)` change to `store.with_role(role).get(key:)` or pass `role:` per-call.

### 3. Delete `ReadModel` and `CommandModel`

Both are dead code. Their query logic was already duplicated in handlers; whatever remains is folded into `Store` as private helpers or dropped.

### 4. Delete `Store#dispatch`

The `Store#dispatch` method was a thin wrapper around `Bus.dispatch`. Its callers (CLI Runner, get/put/doctor verbs, Projector) are updated to use the unified `Store#verb(**inputs)` surface.

### 5. Replace define_method loop with method_missing

The `define_method` loop in `textus.rb` is removed. `Store#method_missing` and `Store#respond_to_missing?` are defined on `Store`, keyed off `VerbRegistry`:

```ruby
def method_missing(name, *args, **kwargs)
  spec = VerbRegistry.for(name)
  raise NoMethodError, "unknown verb: #{name}" unless spec || !args.empty?
  # positional args are refused — kwargs only
  # look up spec, bind inputs, build Call, dispatch through pipeline
end
```

### 6. Session lives on Store

The `Dry::Struct::Session` value object is folded into `Store`. `Store#with_role(role)` computes cursor, propose_lane, and contract_etag. `Store#advance_cursor(new_cursor)` returns a new Store with the advanced cursor (immutable). `Store#check_etag!(observed)` raises `ContractDrift` on mismatch.

## Consequences

**Positive**

- One dispatch path: `store.verb(**inputs)` → `Bus::Pipeline` → handler. Full stop.
- No dead code — ReadModel, CommandModel, RoleScope removed.
- No load-time metaprogramming — method_missing is explicit and debuggable.
- Session management moves closer to the Store it operates on.

**Negative**

- Regression risk on every caller that dispatches a verb. All call sites in CLI Runner, CLI escape-hatch verbs, Projector, MCP Server, and Schema Tools must be updated.
- `method_missing` is slightly less discoverable than defined methods for tooling (IDE go-to-definition). `respond_to_missing?` mitigates `respond_to?` checks.

**Neutral**

- Callers that currently pass `role:` as a keyword arg on `store.verb(role:, ...)` continue to work (method_missing passes it through to `Bus.dispatch`).
- Wire format unchanged. Protocol version unchanged.

## Alternatives Considered

### Keep define_method loop

The current approach works. Replacing it with `method_missing` was a deliberate choice to make the dispatch surface explicit and testable — method_missing can be tested with `assert_respond_to` and has a single `respond_to_missing?` gate rather than N `define_method` calls.

### Keep RoleScope as a wrapper

RoleScope could be kept as a role-carrier that delegates to Store rather than carrying its own dispatch. This would avoid changing MCP server and Schema Tools callers. Rejected because the delegation layer adds no value once `Store` itself carries role state — `store.with_role(role).verb(args)` is as clear as `store.as(role).verb(args)`.
