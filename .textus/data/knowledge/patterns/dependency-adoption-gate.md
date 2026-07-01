---
uid: 329cc7dce4d093f5
---
# Dependency Adoption Gate

Adopt new runtime dependencies only through a strict adapter-first gate.

## Gate

A dependency passes only when all are true:

1. It is wrapped by a `Textus::DependencyAdapters::*` module.
2. The adapter publishes a small textus-owned interface.
3. Runtime call sites depend on adapter methods at seams, not gem classes in domain modules.
4. Tests verify adapter interface and seam behavior.
5. An exit path (replacement/removal strategy) is documented.

## Checklist

- Confirm stdlib or existing adapters cannot satisfy the need.
- Add the minimal adapter API required by concrete callers.
- Route usage through seam modules (ports, surfaces, runners).
- Add unit coverage for the adapter's published surface.
- Add integration/conformance coverage for the seam.
- Record rationale and rollback path in ADR/PR context.

## Why

This gate keeps vendor churn localized and preserves deep module boundaries while lowering long-term replacement cost.
