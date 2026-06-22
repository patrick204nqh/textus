---
name: '0119-architecture-deepening-phase-2'
uid: C05B465DE347449D
---

# ADR-0119: Architecture deepening — dry-monad actions, container split, geometry authority

## Status

Proposed

## Date

2026-06-22

## Context

The textus codebase had accumulated several structural weaknesses that made
the code harder to reason about and more brittle:

1. **Inconsistent error handling.** Actions returned a mix of bare values,
   `raise`d exceptions, and ad-hoc nil returns. Callers couldn't uniformly
   handle action results.

2. **Dual verb maps.** `Gate::VERB_ACTIONS` and `Action::VERBS` both mapped
   verb symbols to action classes but were independently maintained and
   silently drifting (24 vs 29 entries).

3. **Dry::Struct Container with optional fields.** A `LazyContainer` proxy
   existed solely to break the circular dependency between Gate and Container,
   adding indirection to the boot path.

4. **`root` and path logic scattered.** Container stored `root` alongside
   Geometry which also held it. Inline `File.join(root, ...)` patterns were
   duplicated across 99+ call sites.

5. **Unit test suite bloat.** `spec/unit/` contained 378 examples (17% of the
   suite) testing internal implementation details rather than contract
   behaviour, making refactoring costly.

## Decision

Apply five coordinated refactors:

### 1. Dry-monad result standardisation

Every action returns `Success(value)` or `Failure(code:, message:, details:)`.
A new `Value::Result.unwrap(result)` converts `Failure` to `ActionError`. All
30 action classes updated. Nil returns became `Failure(code: :not_found)`.

### 2. Delete Gate::VERB_ACTIONS

Gate reads `Textus::Action::VERBS.fetch(cmd.verb)` directly. Simplified
dispatch — no more `.map` / `results.length == 1` dance.

### 3. Container split — Infra/Coord via Data.define + remove LazyContainer

- **`Container::Infrastructure`**: `file_store`, `schemas`, `audit_log`,
  `job_store`, `geometry`
- **`Container::Coordination`**: `manifest`, `workflows`, `gate`,
  `compositor`

Top-level `Container` composes both and delegates all members.
`LazyContainer` deleted. Circular dependency broken by one-time
`wire_gate!` mutation during boot.

### 4. Geometry as sole path authority

`root` removed from Infrastructure. Container delegates `root` to
`geometry.root`. New methods: `schemas_dir`, `hooks_dir`. Key callers
converted to geometry methods.

### 5. Delete spec/unit/ + spec_layout.rb, add monadic matchers

52 files, 378 examples deleted. Added `be_success` / `be_failure` matchers
to `spec/support/matchers.rb`.

## Consequences

- Consistent error handling via monads — all actions return Success/Failure
- Single verb map — Gate reads Action::VERBS
- Linear boot path without LazyContainer
- Geometry is authoritative for all store paths
- 1824 remaining tests focus on contract behaviour

## Alternatives Considered

### Keep Dry::Struct for Container

`Data.define` is simpler, freezes by default, and the composition pattern is
more explicit than optional struct fields with `.with`.

### Inject components directly into Gate

Rather than passing the full Container to Gate, we could pass individual
components (manifest, compositor, etc.). Rejected because Gate dispatches to
30 actions that each need different container slices — the full container is
the pragmatic union.

### Tag spec/unit/ as volatile instead of deleting

The unit tests were already tagged `volatile` to allow exclusion from
contract-focused CI, but they still ran in the default suite and created
maintenance burden. Deleting them outright was simpler.
