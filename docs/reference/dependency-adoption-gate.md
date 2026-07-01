<!-- Maintained by hand. This file defines the dependency admission policy referenced by contributor conventions. -->

# Dependency Adoption Gate

A new runtime dependency is accepted only if it passes all checks below.

1. It sits behind a dependency adapter module under `Textus::DependencyAdapters`.
2. The adapter publishes a small interface owned by textus.
3. The call sites depend on the adapter interface at seams (ports, surfaces, runners), not directly on gem classes.
4. Tests prove behavior at the adapter interface and seam boundary.
5. An exit path is documented (replacement or removal strategy).

## Checklist

- Need cannot be met by Ruby stdlib or existing dependency adapters.
- Adapter API is minimal and use-case scoped (no kitchen-sink wrapper).
- Runtime code references adapter methods, not vendor constants/classes.
- Unit spec covers adapter published interface.
- Integration/conformance spec covers the seam using that adapter.
- Upgrade/removal notes are written in ADR/PR context.

## Runtime-Critical Dependencies

The following are adapter-first and should remain behind stable interfaces:

- `mcp` (protocol server/tool construction)
- `sqlite3` (database connection)
- `concurrent-ruby` (futures and coordination primitives)

## Why This Gate Exists

This gate keeps vendor churn localized, reduces replacement cost, and preserves deep module boundaries.
