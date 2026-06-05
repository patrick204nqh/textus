# ADR 0083 — The contract-drift guard applies to writes only; `boot` and reads bypass it

**Date:** 2026-06-04
**Status:** Accepted (ships 0.50.0)
**Refines:** [ADR 0074](./0074-contract-etag-drift-guard.md) (the contract-etag drift guard — this ADR narrows *which* verbs the guard gates and fixes the self-referential recovery path it left).
**Touches:** [ADR 0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) (`boot` is the orientation handshake — this ADR makes it the verb that *establishes* the contract etag), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (the MCP connection is long-lived — the guard's failure mode bites mid-session), [ADR 0062](./0062-one-get-read-through.md) (reads are read-through; this ADR keeps reads ungated so a stale-contract read still returns on-disk truth).

> **One sentence:** ADR 0074's drift guard fingerprints the whole contract and refuses *every* verb on a mid-session manifest/hook/schema change — including `boot`, whose error message says "re-run boot" — so the documented recovery path is a dead end that only an MCP-server restart escapes; this ADR narrows the guard to **write verbs only**, makes `boot` (and pure reads) bypass it, and makes a `boot` call *re-arm* the guard by refreshing the session's cached contract etag — turning "re-run boot" into a recovery that actually works, mirroring how per-entry `if_etag` guards writes (not reads) one level down.

## Context

ADR 0074 introduced a contract-drift guard: the session caches a `contract_etag` (a composite hash of `manifest.yaml` + `hooks/**` + `schemas/**`), and if the on-disk contract changes mid-session the next call raises `ContractDrift` instead of silently acting on stale behavior. The intent is sound and consistent with textus's optimistic-concurrency DNA — it is the contract-level analog of the per-entry `if_etag` check.

The guard is implemented at the dispatch layer and currently fires on **every** verb. That produces a defect observed in practice: after editing a schema file mid-session (e.g. adding `maintained_by:` to a field), every subsequent MCP call returns

```
contract changed (manifest/hooks/schemas were <old>, now <new>); re-run boot
```

— and `boot` itself returns the same error, because `boot` is gated by the same check. The recovery instruction names a verb that cannot run. The only escape is restarting the MCP server process, which is a poor failure mode for a tool whose entire pitch is *surviving the session*.

Two observations sharpen the fix:

1. **`boot` is the re-orientation verb.** Its whole job is to read the current contract from disk and hand it back. Gating it on the contract being unchanged is contradictory — it is the one verb that *should* run precisely when the contract changed.
2. **A stale read is low-harm; a stale write is the hazard.** The guard exists so a writer does not act against rules it has not seen. A pure read (`get`/`list`/`where`/`pulse`) against a changed contract returns on-disk truth either way — there is nothing to corrupt. Gating reads buys no safety and worsens the failure mode.

## Decision

### 1. The guard gates mutating verbs only

The `ContractDrift` check runs for every MCP verb that is **not a pure read** — the `Write::` family (`put`, `propose`, `accept`, `reject`, `build`, `key_mv`, `key_delete`) plus the destructive `Maintenance::` verbs (`tend`, `zone_mv`, `key_mv_prefix`, `key_delete_prefix`). Pure reads and `boot` are never gated.

Implementation derives the set as the complement of the MCP read catalog (`unless Catalog.read_verbs.include?(name)`) rather than the `Write::`-only `write_verbs` — keying on `write_verbs` would silently leave the destructive `Maintenance::` verbs un-gated. The lone read-only `Maintenance::` verb, `rule_lint` (a candidate-manifest diff that performs no store write), is therefore also gated; that is harmless and arguably correct — linting against a drifted live manifest should re-orient first — and it keeps the predicate a clean "reads bypass, everything else enforces" with no per-verb hardcoding.

```
 verb class           contract-drift guard
 ──────────           ────────────────────
 boot                 BYPASS — reloads from disk, returns fresh contract + etag
 reads (get, list,    BYPASS — on-disk truth; a stale read corrupts nothing
   where, pulse,
   deps, rdeps, …)
 writes (put, build,  ENFORCE — refuse on drift; the writer must re-orient first
   key_*, …) +
   destructive
   Maintenance::
   (tend, zone_mv,
   key_*_prefix)
```

### 2. `boot` establishes — and re-arms — the contract etag

`boot` is unconditionally exempt, reloads the contract from disk, and writes the fresh etag back into the session. It is the contract-level analog of `get` returning an entry etag that a later `put --if_etag` is checked against:

```
get KEY        → returns entry etag    → put KEY --if_etag=<etag>   (entry concurrency)
boot           → returns contract_etag → writes checked against it   (contract concurrency)
```

Because a `boot` call resyncs the session's cached etag, "re-run boot" becomes a real recovery: after `boot`, subsequent writes are checked against the *current* contract, not the stale one. The wire format is unchanged — `contract_etag` is already present in `boot`/`pulse` responses (ADR 0074); only *who checks it* changes.

### 3. Reads remain ungated

`get`, `list`, `where`, `pulse`, `deps`, `rdeps`, `rule_explain`, `schema_show`, `capabilities` never raise `ContractDrift`. They return current on-disk state. `pulse` continues to surface `contract_etag` so a client can *detect* drift cheaply and choose to `boot`, without being *blocked* by it.

## Consequences

- **The recovery path works.** "Re-run boot" resolves the condition instead of looping. No server restart required for a mid-session contract edit — the common case during local development and dogfooding.
- **Writes stay safe.** The protection ADR 0074 wanted — a writer never acts against rules it has not seen — is preserved exactly, because writes still enforce the guard.
- **Reads stay available during drift.** An agent mid-session can still read state and `pulse` after a contract edit; it is refused only if it tries to *write* without re-orienting.
- **One concurrency model, two altitudes.** Contract-level optimistic concurrency (`boot` issues the etag, writes check it) now mirrors entry-level concurrency (`get` issues the etag, `put` checks it). The mental model is uniform.
- **Behavioral change to ADR 0074, not the wire.** The etag composition and the `contract_etag` field are unchanged; this narrows the *enforcement surface* and exempts `boot`. SPEC's drift-guard wording is updated when this ships.

## Alternatives considered

- **Keep gating every verb; just exempt `boot` (minimal patch).** Rejected as insufficient on its own — exempting `boot` fixes the deadlock, but continuing to gate pure reads still blocks an agent from observing state during drift for no safety benefit. The write-only boundary is the principled line, and exempting `boot` falls out of it.
- **Hot-reload the contract on every call (no guard at all).** The server stats the contract files each call and silently adopts changes. Rejected: it throws away ADR 0074's deliberate "you changed the rules underneath me, acknowledge it before writing" property, and adds per-call I/O. The guard's value is making drift *explicit* for writers.
- **Auto-`boot` on drift (silently re-orient, then proceed).** Rejected: it hides a contract change from the caller at the exact moment a writer most needs to know the rules moved. Re-orientation should be an observable act (`boot`), not a silent side effect of a write.
- **Make `boot` gated but special-cased to "always succeed."** This is the chosen behavior, framed precisely: `boot` is not "gated but exempt," it is *outside* the guard because it is the verb that issues the etag the guard checks. Framing it as an establishment verb (not an exempted one) is what keeps the model coherent.
