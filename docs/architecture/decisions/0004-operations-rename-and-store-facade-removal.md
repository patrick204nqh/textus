# ADR 0004 — Operations rename + Store facade removal (v0.12.2)

> **Note:** Superseded by [ADR 0010](0010-flat-operations-api.md) for the public Operations surface. The `Operations#reads` / `#writes` / `#refresh` accessors described below were removed in v0.17.0 in favour of one flat method per use case.

**Status:** Proposed
**Date:** 2026-05-26
**Depends on:** [ADR 0002 — textus/3 vocabulary redesign](0002-textus-3-vocabulary-redesign.md), [ADR 0003 — Legacy Sweep](0003-legacy-sweep.md)

## Context

ADR 0002 introduced a layered architecture: `domain/`, `application/`, `infra/`,
with `Composition` as the factory module that wires `Application::Context` to
`Application::Reads::*` / `Application::Writes::*` / `Application::Refresh::*`
use-cases. ADR 0003 deleted the textus/2 compatibility shims.

What survived both sweeps:

1. **`Store` is still a god-object facade.** `Store#put`, `#get`, `#delete`,
   `#accept`, `#reject`, `#mv` each rebuild a `Context` and dispatch through
   `Composition` (or in `#mv`'s case, instantiate `Mover` directly — the one
   inconsistency). `Writer#put` is a second shim explicitly labelled
   `# Backward-compat shim — orchestration now lives in Application::Writes::Put`
   (`lib/textus/store/writer.rb:14`). Three doors to the same operation.
2. **`Composition` is named for a design pattern, not a thing.** Thirteen
   sibling factory methods (`writes_put`, `writes_delete`, `reads_get`,
   `reads_freshness`, …) in a flat namespace. The structure is implicit in
   the method names; new readers ask "composition of what?".
3. **CLI verbs and specs hold `(store, ctx)` pairs.** Every verb does
   `ctx = Composition.context(store, role: ...)` then
   `Composition.writes_put(ctx).call(...)`. The context isn't reusable across
   calls in a request — it's recreated each time even when a single verb
   does multiple operations.
4. **The test suite carries shim-era weight.** Specs for the `Store#*` facade,
   the `Writer#put` shim, and the legacy `Composition.writes_put` flat
   naming overlap with specs that exercise the same path through the
   Application use-cases directly.

`Composition` is internal (not referenced from SPEC.md, not part of the
public API documented in README/docs). Renaming it is a free move
post-ADR 0003 — the textus/2 cutover already established that internal
vocabulary changes ride the next minor bump.

## Decision

1. **Introduce `Textus::Operations`** as the single canonical entrypoint
   for invoking application use-cases against a store. Group by kind
   (`ops.writes.put`, `ops.reads.get`, `ops.refresh.worker`) so the
   structure mirrors `lib/textus/application/{writes,reads,refresh}/`.
2. **Delete `Textus::Composition` entirely.** No alias, no deprecation
   warning. v0.12.x is internal-API season; the cost of dragging
   `Composition` along is greater than the cost of one mechanical rename.
3. **Delete `Store#put / #get / #delete / #accept / #reject / #mv`** and
   the `Writer#put` shim. CLI verbs and specs go through `Operations` directly:
   ```ruby
   ops = Textus::Operations.for(store, role: "agent")
   ops.writes.put.call("working.notes.foo", body: "...")
   ops.reads.get.call("working.notes.foo")
   ```
4. **Promote `Mover` to `Application::Writes::Mv`** so every CLI verb maps
   1:1 to an Application use-case. The existing `Store::Mover` class is
   kept as a private collaborator (pure I/O) — the new use-case wraps it
   and publishes the event.
5. **Audit and prune `spec/`.** Each removed surface (`Store#put`,
   `Writer#put`, `Composition.*`) drops the specs that exclusively
   exercised it via that surface. Specs that test underlying behavior get
   rewritten to call through `Operations` once, not three times. Stale
   spec helpers (factories that build legacy-shaped Contexts, fixtures
   for compat code paths) are deleted.
6. **No backward compatibility.** v0.12.2 is a hard break for any external
   consumer that depended on `Store#put` or `Composition.writes_put`. The
   CHANGELOG calls this out under "Breaking changes." No `respond_to?`
   guards, no soft alias, no deprecation period.

## Consequences

**Smaller production code.** Net reduction:
- `lib/textus/composition.rb` deleted (~70 LOC)
- Store facade methods deleted (~50 LOC)
- `Writer#put` shim deleted (~10 LOC)
- `Operations` + nested namespaces added (~100 LOC)
- `Application::Writes::Mv` added (~30 LOC), `Mover` slimmed (~10 LOC saved)

Estimated net: −10 to +20 LOC in `lib/`. The win isn't LOC, it's that
there's one door per operation and the layer boundary is enforceable
by grep (`rg "store\.(put|get|delete|accept|reject|mv)\b" lib/ spec/`
should return zero hits post-merge).

**Spec suite shrinks.** Target: −300 to −500 LOC across `spec/` after the
audit pass. Specifically:
- `spec/store_spec.rb` loses cases that duplicate `spec/put_spec.rb` /
  `spec/get_spec.rb` (testing the facade *and* the underlying use-case).
- `spec/mv_spec.rb` consolidates with whatever `Application::Writes::Mv`
  introduces — no separate Mover-direct test.
- Helper modules in `spec/spec_helper.rb` that built compat-era contexts
  are removed.

**Sharper failure modes.** Calling `store.put(...)` raises `NoMethodError`
immediately. No silent fallback, no "did you mean" hint — the symbol is
just gone. This is intentional: v0.12.2 readers should not need to
mentally trace which surface they're looking at.

**One CLI-verb rewrite pass.** ~30 verb files change from
`Composition.x(ctx).call` to `ops.kind.x.call`. Mechanical; the resolved
role and context construction collapse into one `ops = Operations.for(...)`
line at the top of `#call`.

**Documentation churn.** README and `docs/conventions.md` don't reference
`Composition` (verified). SPEC.md doesn't either. The only doc change is
this ADR plus a CHANGELOG entry.

## Alternatives considered

- **Option A — keep `Composition`, do nothing.** Rejected: the cleanup is
  exactly the kind of internal-vocabulary work that becomes more
  expensive the longer it waits. Post-ADR 0003 the codebase is small
  enough that this is a 1-PR job.
- **Option C — keep `Composition` name, restructure to grouped factories
  (`Composition.writes(ctx).put`).** Rejected: same structural benefit
  as `Operations` without the discoverability win. If we're touching
  every call site, fixing the name is free.
- **Keep `Store#put` etc. as one-line forwarders to `Operations`.**
  Rejected: that's exactly the shim shape ADR 0003 spent a release
  deleting. The convenience-of-`store.put(key, body)` argument is real
  but small — three extra characters at the call site (`ops.writes.put`
  vs `store.put`) is not worth a second canonical entrypoint.
- **Deprecate `Composition` for one minor release before deletion.**
  Rejected: deprecation cycles are for *public* APIs. `Composition`
  is internal; deleting it on the next bump is consistent with how
  internal renames have been handled (manifest schema changes, hook
  event names, etc.). No third-party code in the wild calls it.
- **Promote `Mover` to use-case in a follow-up PR.** Rejected: leaving
  it inconsistent for one release is exactly the half-state ADR 0002
  warned against. Same PR or nothing.

## Out-of-scope

- Splitting `Manifest::Entry` (260 LOC, the largest file) — listed in the
  architecture review as a medium-ROI follow-up; deferred to its own ADR.
- Consolidating freshness/staleness across four directories — same.
- Renaming `Composition` was raised as part of the textus/3 vocabulary
  sweep (ADR 0002) but deferred; this ADR closes that thread.
