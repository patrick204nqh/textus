# ADR 0024 — Domain purity via FileStat/Clock ports

**Date:** 2026-05-29
**Status:** Accepted
**Refines:** [ADR 0013](./0013-port-extraction-store-as-root.md), [ADR 0016](./0016-application-ports-value.md)

## Context

`ARCHITECTURE.md` states that the domain layer has zero direct File/Dir/Time.now
I/O — all outbound I/O is mediated through ports. As of 0.28.0 that rule was
aspirational, not enforced. Three clusters of domain code violated it:

1. **`Domain::Staleness::{IntakeCheck,GeneratorCheck}`** called `File.read`,
   `Dir.glob`, `File.mtime`, and `Time.now` directly. This made TTL and
   generator-staleness logic impossible to unit-test without a real filesystem
   and a live clock.

2. **`Domain::Sentinel`** had class-level persistence methods (`write!`, `load`,
   `sentinel_path`, `SUFFIX`, `DIR`) plus `orphan?` / `drift?` predicates that
   interrogated the disk directly. The value object and the I/O adapter were
   fused into one class.

3. **`Call.build`** called bare `Time.now`, so request-timestamp provenance
   bypassed the `Ports::Clock` that existed for exactly this purpose.

The 0.28.0 ADR audit noted an Interface Segregation Problem: `Ports::FileStore`
mixed read queries with write operations, but there was no read-only query port
for domain code to depend on.

None of this was caught mechanically — no spec enforced the "no direct I/O in
`lib/textus/domain/`" rule.

## Decision

1. **New read-only port `Textus::Ports::Storage::FileStat`** (methods:
   `exists?`, `directory?`, `read`, `mtime`, `glob`) serves as the narrow query
   interface that pure domain logic depends on. It is kept deliberately separate
   from the write-side `Ports::Storage::FileStore` (ISP — closes the 0.28.0
   audit note).

2. **Inject `file_stat:` and `clock:` into staleness checks** instead of
   touching the disk or clock directly:
   - `Domain::Staleness#initialize(manifest:, file_stat:, clock:)`
   - `Domain::Staleness::IntakeCheck#initialize(manifest:, file_stat:, clock:)` —
     uses `@file_stat` for reads and `@clock.now` for TTL (replacing `Time.now`).
   - `Domain::Staleness::GeneratorCheck#initialize(manifest:, file_stat:)` — takes
     `file_stat` only. `GeneratorCheck` compares source mtimes against an entry's
     stored `generated.at` timestamp; it never consults wall-clock now, so
     injecting a clock would be a dead dependency. We inject only what each unit
     actually depends on.

3. **Split `Domain::Sentinel` into a pure value object and a persistence adapter.**
   `Domain::Sentinel` becomes a pure value object carrying target/source/sha256/mode
   and two predicates (`orphan?(file_stat)` / `drift?(file_stat)`) that now accept
   the read-only port as an argument rather than touching the disk themselves. All
   persistence and path-layout logic (the former `write!` / `load` / `sentinel_path`
   class methods plus `SUFFIX` / `DIR` constants) moves to a new adapter
   `Ports::SentinelStore`. On-disk JSON shape and path layout are byte-identical —
   no wire change.

4. **Route freshness clock provenance through `Ports::Clock`.** The request
   timestamp in `Call.build` now comes from `Ports::Clock.now` instead of bare
   `Time.now`. `Freshness::Evaluator`'s `now:` constructor signature is unchanged;
   the change is at the call site that feeds it.

5. **Invariant guard spec `spec/domain_purity_spec.rb`** scans
   `lib/textus/domain/**/*.rb` and fails the build if any file performs direct
   filesystem or clock I/O. The spec permits pure path-math (`File.join`,
   `File.dirname`, `File.basename`, `File.expand_path`, `File.absolute_path?`,
   `File.split`, `File.extname`), `Digest` hashing of injected bytes, and
   `Time.parse` of stored strings — none of these constitute outbound I/O.
   It forbids `IO.*`, `FileUtils`, `Dir.`/`Dir[`, `Pathname`, shell execution,
   and `Time.now`/`Time.new`.

## Consequences

**Breaking — Ruby API only.** `Domain::Staleness`, `IntakeCheck`, and
`GeneratorCheck` constructors gain required `file_stat:` (and where applicable
`clock:`) kwargs. `Domain::Sentinel`'s persistence class methods and path
constants move to `Ports::SentinelStore`; callers that called `Sentinel.write!`
or `Sentinel.load` must switch to the adapter. `Sentinel#orphan?` and
`Sentinel#drift?` now require a `file_stat` argument. Wire format (`textus/3`)
and CLI verb signatures are unchanged.

**Domain is now unit-testable without a filesystem.** Staleness logic is
exercised with fakes over tmp dirs or purely in-memory stubs. A fake clock
proves TTL logic deterministically. `Sentinel` value-object tests need no disk
at all.

**ISP improved.** `FileStat` (read-only query) is distinct from `FileStore`
(write-side). Domain code that only reads cannot accidentally call write
operations through the same port.

**Invariant is mechanically enforced.** `domain_purity_spec.rb` prevents
regression silently accruing the way the 0.28.0 violations did.

**Accepted `Metrics/MethodLength` (Rule 2) exceptions.** `GeneratorCheck#stale_reason`
(~7 lines) and `IntakeCheck#rows_for` (~6 lines) intentionally exceed the 5-line
guideline. Both are flat staleness guard-chains kept at one level of abstraction;
decomposing further would require check-object polymorphism not warranted at this
scale. This is a deliberate decision per "break the rule with good reason" — the
methods are longer than five lines but contain no nested abstraction layers.

## Alternatives considered

**Extend `FileStore` to add query methods.** Rejected: mixing write operations
with read queries on the same port violates ISP. Callers that only read would
depend on an interface that exposes mutation — the exact problem the 0.28.0 audit
flagged.

**Relocate all of `Sentinel` into the ports layer.** Rejected: the value
(target/source/sha256/mode) and the orphan/drift semantics — "does this sentinel
describe a path that no longer exists?" — are genuinely domain concerns. Only the
persistence mechanism (path layout, JSON serialisation) belongs in a port. Moving
the whole class would push business logic into the infrastructure layer.
