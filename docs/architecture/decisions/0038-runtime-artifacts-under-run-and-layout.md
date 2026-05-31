# ADR 0038 — Runtime artifacts live under `.run/`; one `Layout` owns the map

**Date:** 2026-05-31
**Status:** Accepted
**Refines:** [ADR 0036](./0036-transports-as-pure-framings.md) (per-role cursor cache under `.state/`), [ADR 0025](./0025-boot-doctor-as-verbs-and-etag-via-port.md) (doctor as a verb that inspects the store on disk)

## Context

Textus is a gem that downstream repos adopt: `textus init` scaffolds a `.textus/`
directory, and the runtime then writes several files into it as it operates.
Today those files fall into two kinds that are never distinguished:

- **Authored config** — `manifest.yaml`, `schemas/`, `hooks/`, `templates/`,
  `sentinels/`, `zones/**`, `role`. Source. Tracked deliberately.
- **Runtime state** — disposable, machine- and run-local, regenerated on demand:
  - `.state/cursor.<role>` — per-role pulse cursor (`CursorStore`, ADR 0036)
  - `.locks/<key>.lock` — per-key fetch flock (`Ports::Fetch::Lock`)
  - `.build.lock` — build mutex (`Ports::BuildLock`)
  - `audit.log`, `audit.log.N`, `audit.log.N.meta.json` — append-only event
    ledger plus rotation sidecars (`Ports::AuditLog`); grows to
    `max_size`×`keep` (default **50 MB**)

Two problems compound:

1. **The path map is scattered.** Every artifact path is a hardcoded
   `File.join(root, "…")` literal spread across ~12 files (`audit_log.rb` alone
   owns 7). Nothing knows the full set, and nothing knows which paths are
   disposable. There is no place to ask "what does textus own, and what is safe
   to delete."

2. **Control is incomplete and not exported.** The only ignore rule is
   `.textus/.state/`, living in *textus's own* repo `.gitignore`.
   `audit.log*`, `.locks/`, and `.build.lock` are ignored nowhere — verified
   with `git check-ignore`. `textus init` writes no ignore file at all, so every
   consumer repo silently starts committing a 50 MB log and stray PID locks, and
   each must reverse-engineer the rules from textus internals. The boundary
   between authored and disposable is well-defined in code but never
   communicated to the only people who need it. A `.build.lock` has already
   leaked into `examples/claude-plugin/`.

These are the same drift class ADR 0037 named for boot: a fact (here, "this path
is disposable") that lives implicitly in N writers and must be hand-mirrored into
a `.gitignore`, with nothing failing when the mirror is wrong.

## Decision

1. **`Textus::Layout` is the single source of truth for the on-disk map.**
   One module enumerates every path under `root` and classifies each as `:config`
   or `:runtime`. Every writer and doctor check asks `Layout` for its path
   instead of hardcoding `File.join(root, …)`.

2. **All runtime state lives under one subtree, `.textus/.run/`.** The
   tracked/disposable boundary becomes a *directory* boundary — `/etc` vs `/var`:

   ```
   .textus/
     manifest.yaml  schemas/  hooks/  templates/  sentinels/  zones/  role
     .gitignore                      # emitted by init: one line -> .run/
     .run/                           # all runtime; ignored wholesale
       state/cursor.<role>
       locks/<key>.lock
       build.lock
       audit/audit.log[.N][.meta.json]
   ```

   A clean reset is `rm -rf .textus/.run`. A consumer glancing at the directory
   sees the boundary without reading docs.

3. **`init` emits `.textus/.gitignore`, derived from `Layout`.** Because all
   runtime is under `.run/`, the emitted ignore is a single line. It can never
   drift from reality because it is generated, not hand-kept. Textus's own repo
   `.gitignore` collapses to the `examples/**` mirror (or nothing).

4. **No backward-compatibility shim — this is a breaking change.** textus is
   pre-1.0 and does not maintain old on-disk layouts. A store created before
   0038 keeps its `audit.log`/`.state`/`.locks` at the root, which the new code
   simply ignores; the next write starts a fresh `.run/audit/audit.log`. There
   is deliberately **no auto-migration**: pre-0038 audit history is not carried
   forward. To upgrade a live store, move the old files under `.run/` by hand
   (`mkdir -p .textus/.run/audit && mv .textus/audit.log* .textus/.run/audit/`)
   or just delete them and re-init. We do not add code to silently relocate
   them, because compatibility code we'd never remove is worse than a one-line
   manual step taken once.

`archive/` (swept entries from `RetentionSweep`) is **not** runtime — it is
retained history the user may want to track — and stays at root, classified
`:config`/data.

## Consequences

- Control is one ignore line and one `rm -rf` target, shipped to every consumer
  automatically by `init`.
- The scatter collapses: adding or moving an artifact is a one-line `Layout`
  change; writers and the ignore file follow.
- A future `textus clean` verb and a doctor check ("runtime artifact committed")
  fall out for free — both just enumerate `Layout` runtime paths. (Deferred.)
- **Cost:** `audit.log`'s path moves, touching its readers, rotation logic, and
  doctor checks (`doctor/check/audit_log.rb`, `doctor/check/fetch_locks.rb`,
  `read/audit.rb`). This is the price of making the boundary physical rather than
  implicit.
- **Breaking:** live pre-0038 stores lose visibility of their old root-level
  `audit.log`/`.state`/`.locks` until moved by hand (see Decision §4). Accepted —
  textus is pre-1.0 and carries no legacy-layout code.

## Alternatives considered

- **Layout module, paths left in place (no `.run/`).** Centralizes code and lets
  `init` derive the ignore, but the emitted `.gitignore` stays a 4-pattern list
  and the tracked/disposable boundary remains implicit (interleaved at the
  `.textus/` top level). Lower migration cost, weaker standardization. Rejected:
  the recurring failure is humans misjudging which siblings are disposable; a
  directory boundary removes the judgement, four scattered patterns do not.
- **Keep hand-maintaining textus's repo `.gitignore`.** The status quo. Rejected:
  it does not reach consumers at all, and has already drifted (`.build.lock`).
