---
uid: 58874e878de2be3a
---
ADR-0102: Produced event catalog. ADR-0110: Job queue and drain/serve.

# TriggerCatalog Pattern

Centralize trigger and action vocabulary in one module, then make all producers and validators depend on that module instead of repeating string literals.

## Context

Reactive behavior (planner, manifest policy checks, cascade subscriber, and event-to-job bridges) was using duplicated trigger/action strings. That made drift easy:

- one place could introduce a new token,
- another could reject it,
- and tests had to infer the canonical set indirectly.

## Pattern

Create a single vocabulary module (`Textus::Manifest::TriggerCatalog`) that provides:

- the canonical trigger/action constants,
- validation helpers (reject unknown trigger tokens early),
- one import point for all reactive orchestration code.

Then wire every trigger-aware collaborator through it:

- planner validation,
- manifest react policy,
- cascade subscriber checks,
- dispatch/event bridges that emit trigger-driving events.

## Why this works

- **Single source of truth**: token changes happen in one place.
- **Fail-fast behavior**: invalid trigger vocabulary is rejected at boundaries.
- **Safer evolution**: adding/removing trigger tokens becomes explicit and reviewable.
- **Lower cognitive load**: no cross-file grep to discover "what are valid triggers?".

## Implementation cues

- Keep token definitions declarative and close together.
- Validate as close to input/manifest boundaries as possible.
- Keep runtime emission sites thin; they should reference catalog terms, not invent terms.
- Back with unit tests that assert unknown tokens are rejected.

## Trade-offs

- Adds one more module dependency for reactive components.
- Requires touching multiple call sites when introducing the catalog initially.

The trade-off is worth it because vocabulary drift in reactive systems causes subtle production behavior differences that are difficult to trace.
