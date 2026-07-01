---
uid: c7c0c58b8ad41100
---
# ADR-0125: Bounded Use-Case Objects

## Status
Proposed

## Date
2026-07-01

## Context
The textus use-case layer (e.g., UseCases::EntryRead, UseCases::EntryWrite) has evolved into a set of "God Modules". These modules use internal if/elsif dispatchers to handle multiple unrelated contracts. 

This causes:
1. Dependency Bloat: Each module requires a union of all dependencies needed by all its actions.
2. Poor Locality: Understanding one action requires scanning a large file containing many unrelated actions.
3. AI Friction: Agents must load large files to make small changes, increasing token cost and the risk of unrelated regressions.

## Decision
We will transition from "God Modules" to Bounded Use-Case Objects.

1. One Class Per Contract: Every Dispatch::Contract will be handled by a dedicated class (e.g., UseCases::Read::GetEntry).
2. Uniform Interface: Every use-case class will implement self.call(command, call, deps).
3. Isolated Dependencies: Dependencies will be scoped to the specific use-case class, eliminating module-level dependency bloat.
4. Direct Dispatch: The Gate or Dispatcher will resolve the use-case class directly from the contract map, removing internal dispatch logic.

## Consequences
- Positive: Increased locality and AI-legibility.
- Positive: Narrower dependency graphs per action.
- Positive: Easier to test use cases in isolation.
- Negative: Increased number of files in the lib/textus/use_cases/ directory.
- Negative: Initial refactoring effort to split existing modules.
