# ADR 0115: Role Trust Model — Asserted Identities, Ambient Authority

**Status:** Accepted
**Date:** 2026-06-14
**Context:** Auth consolidation PR (security audit finding F8)

## Context

Textus defines three role archetypes — `human`, `agent`, `automation` — each with a declared capability set in the manifest. Role claims are validated only for membership in the closed set `Role::NAMES`; they are not cryptographically verified.

## Decision

The three roles are **asserted identities**, not authenticated credentials. The security boundary is process-level: whoever can execute `textus` or open a stdio MCP connection has ambient read/write access to the store root on the host filesystem. Asserting a role beyond one's actual authority is already equivalent to editing the files directly — no privilege is gained beyond what filesystem access already grants.

This is the correct model for local single-machine deployments (a developer's workstation, a CI runner, a single-user server). It is **not appropriate** for network-accessible transports.

## Consequences

1. **Local deployment (stdio MCP, CLI):** Role assertions are accepted at face value. The Gate enforces *capability* constraints (can this role write this lane?), not *identity* constraints (is this really a human?).

2. **Network transport (MCP over HTTP, remote proxy):** Role assertions MUST be bound to transport-level credentials before reaching `Gate`. This binding is out of scope for this ADR and requires a dedicated design. Any MCP server exposing textus over a network without credential binding is operating outside the supported security model.

3. **`textus doctor`** will warn if a `.mcp.json` at the project root references a non-stdio transport without a documented credential binding comment.

## Alternatives Rejected

- **Per-request cryptographic signing:** Heavy operational overhead for the local use case; deferred to the network-transport ADR.
- **OS user → role mapping:** Fragile (CI runners share users), unnecessary for local deploys.
