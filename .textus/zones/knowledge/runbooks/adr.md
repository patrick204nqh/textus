---
name: adr
description: Add an Architecture Decision Record for a load-bearing decision.
---

1. Copy the shape of a recent ADR (header block: Date, Status, Refines/Touches
   cross-links). Number it next in sequence under
   `docs/architecture/decisions/`.
2. Capture Context → Decision → Consequences → Alternatives considered. ADRs are
   immutable once accepted; later decisions update the old `Status:` line to
   point forward rather than rewriting it.
3. Add the index row in `docs/architecture/decisions/README.md`.
4. If the decision changes the wire contract, reflect it in `SPEC.md` too —
   the ADR is the *why*, `SPEC.md` is the *what*.
