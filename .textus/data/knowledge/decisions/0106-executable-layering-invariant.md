# ADR 0106 — the layering is executable, not just intended

**Date:** 2026-06-08
**Status:** Accepted
**Touches:** [ADR 0016](./0016-application-ports-value.md) (established the ports/value layering — domain logic reaches the outside only through ports; this ADR makes the inward-dependency direction a build-time guard rather than a convention), [ADR 0022](./0022-container-call-dispatcher.md) / [ADR 0023](./0023-uniform-use-case-shape.md) (the use-case layer above the domain — `Read`/`Write`/`Maintenance`/`Produce` — that the domain must not reach up into).

> **One sentence:** textus is hexagonal (surfaces → use cases → domain → ports → adapters) and the dependencies *do* flow inward today, but that was an unenforced convention — `ls` cannot see it and nothing failed if a `domain/` file reached up into a use case; this ADR makes the load-bearing rule **executable** with a conformance guard (`domain/` must not reference `Read`/`Write`/`Maintenance`/`Produce`/`CLI`/`MCP`) and writes the layer map down in `lib/textus/ARCHITECTURE.md`, so the structure stops being tribal knowledge that rots.

## Context

The codebase has a clear hexagonal shape:

```
surfaces (cli/ mcp/) → use cases (read/ write/ maintenance/ produce/)
  → domain (pure) → ports (interfaces) → adapters (filesystem/git)
```

Dependencies flow inward: a use case may call the domain and ports; the domain
is pure and depends on nothing above it. This is real — an audit confirms
`lib/textus/domain/**` references only inward primitives (`Textus` errors,
`Key`, `Projection`, `Ports`, `Manifest`, `Domain` itself) and **zero**
use-case or surface namespaces.

But the rule lived nowhere. A newcomer reading `ls lib/textus/` sees a flat list
of directories with no indication that `domain/` is special, that IO is confined
to `ports/`, or which way dependencies are allowed to point. And nothing stopped
the drift: a `domain/` class that did `Textus::Write::Put.new(...)` to "just
trigger a rebuild" would compile, pass its own unit test, and quietly invert the
architecture. The first such edit is the cheap one to catch; the tenth, after
the pattern looks normal, is the expensive one. The invariant being *currently
true* is exactly why now — while there is nothing to fix — is the right time to
nail it down.

## Decision

**1. The inward-dependency rule is enforced by a conformance spec.**
`spec/conformance/architecture/layering_spec.rb` asserts that no file under
`lib/textus/domain/` references `Textus::Read::`, `::Write::`, `::Maintenance::`,
`::Produce::`, `::CLI::`, or `::MCP::`. A violation fails CI with the offending
files named and the remedy stated (invert the dependency, or move the logic up
into the use-case layer that owns the orchestration).

**2. The layer map is written down** in `lib/textus/ARCHITECTURE.md`: the
inward-flow diagram, the layer/responsibility table, and the one enforced rule,
pointing at the spec as the enforcement and this ADR as the why.

**3. Scope is deliberately the one defensible rule, not a full matrix.** The
guard encodes "domain does not reach up" — the load-bearing, already-true
invariant — not a speculative N×N table of which layer may import which. Start
with the rule that actually matters and that the code already honors; widen only
if a real violation pattern emerges.

## Consequences

- A future edit that makes the domain reach up into a use case or surface fails
  CI immediately, with a message naming the file — the architecture's most
  important rule is now a build failure, not a code-review hope.
- The structure is discoverable: `ARCHITECTURE.md` answers "what are these
  directories and which way do they depend?" without spelunking.
- The guard is cheap (reads the `domain/` tree, ~7 examples) and lives beside the
  other conformance guards (routing bijection, docs coverage), consistent with
  textus's "make the invariant executable" culture (cf. ADR 0105).

## Alternatives considered

- **A custom RuboCop cop.** Rejected: a cop is more machinery (a cop class,
  config wiring) than a six-line spec, and the rule is a conformance property
  that belongs with the other conformance specs, not a style lint.
- **A full layer-dependency matrix** (assert every layer's allowed imports).
  Rejected as over-fitting: it would encode rules the code does not yet need and
  invite bikeshedding over edges that never occur. The domain-inward rule is the
  one with teeth; the rest is YAGNI.
- **Leave it as documentation only** (`ARCHITECTURE.md` with no spec). Rejected:
  unenforced architecture docs are the thing that rots. The doc states the rule;
  the spec keeps it true.

No `SPEC.md` change — this is an internal-structure guard, not a wire-contract
change.
