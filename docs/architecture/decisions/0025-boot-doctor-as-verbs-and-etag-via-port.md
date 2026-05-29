# ADR 0025 — Boot/Doctor as dispatched verbs + manifest etag via FileStore port

**Date:** 2026-05-29
**Status:** Accepted
**Refines:** [ADR 0022](./0022-container-call-dispatcher.md), [ADR 0023](./0023-uniform-use-case-shape.md), [ADR 0024](./0024-domain-purity-ports.md)

## Context

Two seams survived the 0.29.0 domain-purity pass:

1. **`Boot` and `Doctor` bypassed the verb dispatcher.** ADR 0023 established a
   single use-case shape — a class on `(container:, call:)` with `#call`, looked
   up in `Dispatcher::VERBS`. `Boot` and `Doctor` instead exposed
   `run_via(container:, role:)` where `role:` was dead (rubocop-disabled). This
   forced a second dispatch path: two hand-written methods on `RoleScope`
   (`#boot`, `#doctor`) outside the `VERBS.each_key` loop, plus call sites in
   Pulse, Materializer, the CLI verbs, and the MCP boot tool that each
   constructed the call by hand.

2. **`manifest_etag` was hand-rolled in two places.** `Read::Pulse` and
   `MCP::Server` both computed `Digest::SHA256.hexdigest(File.read(manifest))`
   directly — raw filesystem I/O and a private digest in the application and
   interface layers, duplicated, and producing a bare hex string inconsistent
   with every other etag in the system (envelope etags are `sha256:`-prefixed
   via `Etag.for_bytes`). The 0.24 domain-purity guard only scans
   `lib/textus/domain/`, so neither leak was caught mechanically.

## Decision

1. **Keep `Textus::Boot` / `Textus::Doctor` as report-builder libraries** (all
   constants, helpers, and the `Doctor::Check::*` namespace unchanged), but
   rename their entry point from `run_via(container:, role:)` to a role-free
   `build(container:, ...)`. The acting role is irrelevant to a read-only
   orientation/health report, so the dead parameter is removed rather than
   threaded through.

2. **Add `Read::Boot` and `Read::Doctor` use cases** on the uniform
   `(container:, call:)` shape, each delegating to its library `build`. Register
   `boot:` and `doctor:` in `Dispatcher::VERBS`. `store.boot` / `store.doctor`
   and `store.as(role).boot` now dispatch through the single `VERBS` loop.

3. **Delete the `RoleScope#boot` / `#doctor` special cases.** The dispatcher
   loop defines them. One invocation path, not two.

4. **Compute `manifest_etag` through `FileStore#etag`** in both `Read::Pulse`
   and `MCP::Server`. The value is now the system-standard `sha256:`-prefixed
   token. The MCP drift-message snippet strips the prefix before slicing so the
   short id stays meaningful.

5. **Guard spec `spec/no_handrolled_manifest_etag_spec.rb`** fails the build if
   `Digest::SHA256.hexdigest(File.read(...))` reappears anywhere in `lib/` (the
   `Etag` helper itself is exempt — it is the sanctioned home for the digest).
   `lib/textus/ports/sentinel_store.rb` is also exempt because its `sha256`
   field is a bare-hex content-integrity checksum stored in the sentinel JSON
   wire format and compared bare on read-back in `Sentinel#drift?` — prefixing
   it would break existing sentinel files (out of scope).

## Consequences

**Breaking — Ruby API only.** `Textus::Boot.run_via` → `Textus::Boot.build`
(drops `role:`); `Textus::Doctor.run_via` → `Textus::Doctor.build` (drops
`role:`, keeps `checks:`). `RoleScope#boot` / `#doctor` are gone but
`store.boot` / `store.doctor` / `store.as(role).boot` are unchanged surface.

**Behavioural — `manifest_etag` format.** The `manifest_etag` field in `pulse`
output and the MCP session drift token change from bare 64-char hex to
`sha256:<hex>`. The token is opaque (compared for equality, never parsed);
within-session drift detection is unaffected because both sides recompute it
identically.

**Wire format (`textus/3`) and CLI verb signatures are unchanged.**

**One dispatch path.** The "uniform use-case shape" invariant (ADR 0023) is now
true rather than mostly-true; two `rubocop:disable Lint/UnusedMethodArgument`
sites disappear.

## Alternatives considered

**Move `Textus::Doctor` wholesale into `Read::Doctor`.** Rejected: the
`Doctor::Check::*` namespace (~15 check classes + specs) and the `CHECKS` /
`ALL_CHECKS` / `DOCTOR_CHECK_TIMEOUT_SECONDS` constants hang off `Textus::Doctor`.
Relocating the module would force a large, mechanical namespace migration for no
behavioural gain. Keeping the library and adding a thin use-case wrapper mirrors
how `Read::Get` composes `Domain::Freshness::Evaluator`.

**Preserve the bare-hex `manifest_etag` by stripping the port's prefix.**
Rejected: the prefix is the convention everywhere else; stripping it to preserve
a one-off format would re-introduce special-case code to avoid a cosmetic
change to an opaque token.

**Extend the 0.24 purity guard to all of `lib/`.** Rejected for this release:
legitimate port-mediated and CLI-argument file reads (`migrate`, `rule_lint`,
template loading, audit-log globbing) live throughout `read/`, `write/`, and
`cli/`; a blanket ban would demand unrelated refactors. The targeted
hand-rolled-etag guard closes the specific regression class without that scope.
