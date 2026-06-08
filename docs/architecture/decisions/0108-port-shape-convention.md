# ADR 0108 — two port shapes, named and documented (not converted)

**Date:** 2026-06-08
**Status:** Accepted
**Touches:** [ADR 0016](./0016-application-ports-value.md) (ports as the application's IO boundary), [ADR 0024](./0024-domain-purity-ports.md) (`FileStat`/`Clock` ports keep the domain pure — this ADR names *why* `Clock` is a module while `FileStore` is a class).

> **One sentence:** `lib/textus/ports/` holds two kinds of port — stateless modules (`Clock`, `Publisher`, `BuildLock`'s `self.with`) and instantiable classes (`FileStore`, `FileStat`, `AuditLog`, `SentinelStore`, the subscribers) — and a review flagged the mixed shapes as a cost ("a newcomer learns each port individually"); rather than mechanically converting the modules to objects (churn for no gain — `Clock` is already injected as data via `Call#now`), this **names the two sanctioned shapes and the rule that picks between them**, documents every port's shape inline, and adds a guard that a new port must declare a shape and say what it is.

## Context

The senior-architect review noted `ports/` mixed calling conventions: some ports
are `module X; module_function` (call `Clock.now`), others are `class X` you
instantiate (`FileStore.new(root)`). The friction is real but small — a reader
opening a port file has to work out, per file, whether to call the module or new
up an object.

The tempting fix is uniformity: convert everything to instantiable objects. That
is the wrong trade for textus. `Clock.now` is a pure function of nothing;
wrapping it in an object with no state adds a constructor and an injection point
that buys nothing — and time is **already** injected where it matters, as data
on `Call#now` (ADR 0024), not as a swapped-in fake clock. Forcing `Publisher`
and `BuildLock` into instances would be the same: ceremony with no payoff, the
kind of change-for-uniformity's-sake textus has repeatedly declined (cf. ADR
0104, "ceremony for no SSoT gain"). The mixed shapes are not an accident to
correct; they reflect a real distinction — **does this port carry collaborators
or not?**

## Decision

**Name the two sanctioned port shapes and the rule that selects them:**

1. **Stateless module** (`module X; module_function`) — when the port is a pure
   function of its arguments and holds no collaborators or config. `Clock`,
   `Publisher`, `BuildLock.with`. Callers that need to vary the behaviour pass
   data (e.g. a fixed time via `Call#now`), not a substitute object.
2. **Instantiable class** (`class X`) — when the port holds collaborators or
   config (a root path, size limits, a subscriber's bus). `FileStore`,
   `FileStat`, `AuditLog`, `SentinelStore`, the subscribers. Each store binds its
   own instance.

There is no third shape. A port that holds state is a class; a port that does
not is a module. The choice is a decision, made once per port and visible.

**Document every port inline.** Each port file carries a doc comment on its
declaration stating what it is and which shape it uses (and, for the modules,
why it needs no instance). The three that lacked one (`AuditLog`, `BuildLock`,
`Clock`) get it.

**Guard it.** `spec/conformance/architecture/port_shape_spec.rb` asserts every
`ports/**/*.rb` declares a class/module under `Ports` and carries a doc comment
on that declaration. A new port that ships undocumented — the actual "learn each
one individually" failure mode — fails CI.

## Consequences

- The newcomer cost is paid down without churn: the convention is written once
  (here), each port states its own shape, and the guard keeps new ports
  self-describing.
- No port changed shape; no call site moved. Behaviour is untouched.
- "Which shape should this new port be?" now has a written answer (stateful →
  class, stateless → module) instead of being copied from whichever port the
  author happened to read first.

## Alternatives considered

- **Convert all ports to instantiable objects** (the "uniform shape" the review
  sketched). **Rejected** — this is the churniest option for the least value:
  `Clock`/`Publisher`/`BuildLock` hold no state, time is already injected via
  `Call#now`, and the conversion would touch their call sites to gain symmetry
  and nothing else. Uniformity of *form* is not worth losing the signal that the
  shape currently carries (stateful vs not).
- **Leave it undocumented** (ADR only, no guard). Rejected: the failure mode is a
  *future* port shipping with no explanation, which a doc-only decision does not
  prevent. The guard is what keeps the convention true.
- **A `Port` base class / mixin to force one shape.** Rejected as the conversion
  in disguise, plus a layer of indirection over what are deliberately thin
  adapters.

No `SPEC.md` change — this is an internal convention + guard over the ports
layer; no wire contract, manifest grammar, or verb surface is affected.
