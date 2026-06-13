# 0005 — Store facade final removal (Phase 1 completion)

**Date:** 2026-05-26
**Status:** Accepted
**Supersedes:** 0004 (for the remaining `Store` surface)

## Context

After ADR 0004 (v0.12.2) we still had two parallel facades:
- `Textus::Store` delegated `list`, `where`, `deps`, `rdeps`, `published`,
  `stale`, `validate_all`, `uid`, `schema_envelope` to its internal `Reader`.
- `Textus::Store::Writer` retained orchestration methods (`delete`, `accept`,
  `reject`) that built `Application::Context` instances inline.
- `Textus::Store::Mover` did full orchestration (validation, audit, events)
  from the infrastructure layer.
- `Textus::Store#fire_event` constructed a context to publish hook events.

This kept the "two ways to do the same thing" problem alive: callers could
reach either through `store.<method>` or `Operations.for(store)...` and
choose differently from file to file.

## Decision

1. Delete the read delegators on `Store`. Every public read flows through
   `Operations.reads.<name>` (new `Application::Reads::*` use cases).
2. Delete `Writer#delete`, `#accept`, `#reject`. The corresponding
   `Application::Writes::*` classes are the only orchestrators.
3. Move `Store::Mover` into `Application::Writes::Mv`. Delete the file.
4. Replace `Store#fire_event` with `Application::Context.system(store)`
   for the rare "infrastructure needs to publish a hook event" path.

## Consequences

- `Store` becomes pure infrastructure: filesystem layout, manifest load,
  hook registry, schema cache. No use-case orchestration.
- `Operations` is the single public entry point. Tests and CLI verbs all
  go through it.
- Breaking changes ship in v0.12.4 with no deprecation aliases — same
  cadence as 0.12.0–0.12.3.
- Phases 2–4 (format-strategy extraction, `Manifest::Entry` split,
  `Build`/`Publish` separation, envelope `Data.define`) remain for later
  versions. This ADR closes Phase 1 only.

## Update (2026-05-26, v0.14.0)

Phases 2, 3, 4 from this ADR's "Out of scope" section are now complete:

- **Phase 2** (format-strategy extraction) — shipped in v0.13.0, ADR 0006.
- **Phase 3** (`Manifest::Entry` split) — shipped in v0.13.1.
- **Phase 4** (Build/Publish split + Envelope `Data.define`) — shipped in
  v0.14.0, ADR 0007.

The four-phase cleanup arc from the original v0.12.4 tech-debt review is
closed.
