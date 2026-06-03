# ADR 0074 — The drift guard fingerprints the whole contract, not just the manifest

**Date:** 2026-06-03
**Status:** Accepted
**Refines:** [ADR 0036](./0036-transports-as-pure-framings.md) (one session value, one etag), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (role bound at `initialize` for the connection's lifetime)
**Touches:** [ADR 0012](./0012-explicit-hook-registration.md) (hooks load once at `Store#initialize`), [ADR 0025](./0025-boot-doctor-as-verbs-and-etag-via-port.md) / [ADR 0037](./0037-boot-pulse-derive-or-guard.md) (etag via the port; derive-or-guard)

## Context

`Session#check_etag!` fires on every MCP `tools/call`, raising `ContractDrift`
when the manifest fingerprint changed mid-session — the agent's cached `boot`
orientation is then stale and it must re-boot. But the fingerprint is
`Etag.for_file(manifest.yaml)` only.

Hooks (`.textus/hooks/**/*.rb`) and schemas (`.textus/schemas/**/*`) load once at
`Store#initialize` (ADR 0012) and are equally part of the contract the agent
booted against: a hook reshapes `transform_rows`, validates writes, audits
`entry_put`; a schema governs every `put`. Edit one of these in a long-lived MCP
subprocess and the running server keeps the stale behavior **and never raises
drift** — the declarative half of the contract is guarded, the executable half is
honor-system. This is the one way the contract can change silently, and it sits
directly under the audit/build path where silence is most expensive.

## Decision

The session fingerprint is a **composite digest over every orientation-bearing
file**: `manifest.yaml` + `hooks/**/*.rb` + `schemas/**/*`. Each file's etag is
taken through the `FileStore` port (ADR 0025); the composite is one
`Etag.for_bytes` digest over the sorted `path:etag` listing, so it is order-stable
and reuses the single sanctioned digest home (guarded by
`no_handrolled_manifest_etag_spec`).

The `Session` field `manifest_etag` is renamed `contract_etag` — in Ruby and in
the agent-facing `pulse` envelope key — because the name now lies if left as
`manifest_etag`. The drift message becomes "contract changed
(manifest/hooks/schemas)…". This is **breaking**: the `pulse` envelope key changes
and the Ruby `Session` field changes; enumerated in `CHANGELOG.md`.

The model stays "fail-and-reconnect," not "hot-reload": a contract edit raises
`ContractDrift` on the next call, and the connection re-boots — consistent with
ADR 0040 binding role for the connection's lifetime.

## Consequences

- A hook or schema edit in a live MCP session now surfaces as `ContractDrift` on
  the next `tools/call`, exactly as a manifest edit does. No more silent stale
  hooks under the audit path.
- `pulse`'s `manifest_etag` key is renamed `contract_etag` (breaking, wire).
- `Textus::Session#manifest_etag` / `MCP::Session#manifest_etag` is renamed
  `contract_etag` (breaking, Ruby embedders).
- `Etag.for_bytes` remains the only digest home; `Contract.etag` composes it.

## Alternatives considered

- **Keep `manifest_etag`, widen the meaning silently.** Rejected: the name and the
  drift message ("manifest changed") would lie for a hook edit. The project's
  derive-or-guard discipline prefers an honest, breaking rename.
- **Hot-reload hooks on change instead of failing.** Rejected: re-running
  `Loader#load_dir` mid-session re-enters arbitrary user code on a live
  connection and fights ADR 0040's lifetime binding. Re-boot is the existing,
  cheaper contract.
- **Watch the filesystem (inotify).** Rejected: the per-call digest is already the
  guard rhythm; a watcher adds a platform dependency for no extra safety.
