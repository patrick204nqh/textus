---
name: adr
description: Add an Architecture Decision Record for a load-bearing decision.
---

1. Copy the shape of a recent ADR (header block: Date, Status, Refines/Touches
   cross-links). Number it next in sequence and author the new `NNNN-*.md`
   under `.textus/data/knowledge/decisions/`.
2. Capture Context → Decision → Consequences → Alternatives considered. ADRs are
   immutable once accepted; later decisions update the old `Status:` line to
   point forward rather than rewriting it.
3. Add the index row in `.textus/data/knowledge/decisions/README.md`.
4. Writing the ADR (a canon write) materializes `knowledge.decisions` reactively
   and publishes it to `docs/architecture/decisions/` — no explicit build step.
   `bundle exec exe/textus drain` is the manual full pass if you ever need to
   force a rematerialize.
5. If the decision changes the wire contract, reflect it in `SPEC.md` too —
   the ADR is the *why*, `SPEC.md` is the *what*.
