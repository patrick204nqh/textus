---
uid: f29f4200b556a3f0
---
ADR-0013: Port extraction. ADR-0016: Application ports/value. ADR-0024: Domain purity/ports.

# Dependency Adapters and Interfaces

Wrap external runtime dependencies behind small adapter modules, and depend on those adapters at seams. Keep the adapter API minimal and focused on the exact calls the module needs.

## Context

As textus grows, direct calls to third-party gems (`mcp`, `sqlite3`, `concurrent-ruby`, etc.) scattered across domains make upgrades and behavior changes risky.

Without an adapter boundary:

- third-party API details leak into core modules,
- tests become tightly coupled to vendor behavior,
- replacing or hardening a dependency requires broad edits.

## Pattern

For each external runtime dependency used by core code:

1. Create a dedicated adapter in `Textus::DependencyAdapters`.
2. Expose only the tiny published interface needed by current call sites.
3. Inject or reference that adapter at seam modules (ports, surfaces, runners).
4. Keep domain logic dependent on the adapter contract, not the vendor API.

## Existing examples in textus

- `McpAdapter` wraps MCP server/tool constructors.
- `SqliteAdapter` wraps SQLite connection construction.
- `ConcurrencyAdapter` wraps futures/zip-futures primitives.

Adoption points:

- `Surface::MCP::Server` and `Surface::MCP::Catalog` use `McpAdapter`.
- `Port::Store` uses `SqliteAdapter`.
- `Workflow::Runner` uses `ConcurrencyAdapter`.

## Interface guidance

- Treat each adapter's public methods as the stable interface.
- Keep method names descriptive and vendor-agnostic where practical.
- Avoid pass-through "kitchen sink" wrappers that mirror entire gems.
- Add adapter methods only when a concrete caller needs them.

## Testing guidance

- Add unit specs that assert the adapter exposes only published methods.
- Add seam-level integration specs proving the caller works through the adapter.
- Avoid asserting vendor internals in domain tests.

## Dependency adoption gate

Before adding a new runtime dependency:

- confirm stdlib / existing adapter cannot solve the need,
- define adapter surface first,
- add a published-interface test for the adapter,
- wire usage through seam modules (not deep domain code),
- document why the dependency exists and its replacement cost.

## Trade-offs

- Small upfront wrapper cost.
- One more indirection when reading code.

This is intentional: it buys safer upgrades, better testability, and clearer module boundaries over time.
