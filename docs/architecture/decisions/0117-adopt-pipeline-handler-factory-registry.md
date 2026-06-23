---
_meta:
  title: "Adopt Pipeline HandlerFactoryRegistry + Adapter"
  authors: [patrick]
  status: accepted
  date: 2026-06-23
---

Decision: we replace the Pipeline::Builder composition seam with a
HandlerFactoryRegistry + Pipeline::Adapter seam.

Context
- Two small composition seams were explored to improve locality and
  testability of Dispatch::Pipeline: a Builder (register then build)
  and a Registry+Adapter (register factories then adapt to a Pipeline).

Decision
- The codebase now uses HandlerFactoryRegistry + Pipeline::Adapter as
  the single composition seam for Dispatch::Pipeline. The Builder
  implementation was removed.

Consequences
- Composition is expressed as a registry of factories. The Adapter is
  the single place responsible for turning that registry into an
  executable Dispatch::Pipeline.
- Tests remain green (1486 examples, 0 failures, 4 pending).
- The registry is easier to inspect and swap in tests and at runtime
  if required; it also simplifies the container wiring.

Rationale
- The registry+adapter separates concerns: factories are data, adapter
  is the translator into runtime handlers. This improves inspectability
  and makes factories first-class.
