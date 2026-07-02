---
name: '0120-atomic-canon-composed-artifacts'
uid: ''
refines: knowledge.architecture.conventions
---

# ADR-0120: Atomic canon + composed artifacts

## Status

Proposed

## Date

2026-06-30

## Context

The textus knowledge layer mixes two kinds of content: (1) stable intent —
goals, rules, decisions — that humans author and own; and (2) derived
descriptions — architecture docs, API references, how-to guides — that
describe what the system currently does and drift with every development loop.

Hand-maintaining derived docs creates a documentation tax each development
loop: humans update content that is fully derivable from the live system.
This violates Golden Rule 5 ("automation runs the boring loops") and burdens
canon with content that doesn't belong there.

The `design/invariants.md` monolith (12 golden rules + evolution rules + north
star in one LOCKED file) exemplifies the problem: a single file is edited to
change one rule, making rule changes non-atomic and history noisy.

## Decision

**Canon is the lighthouse.** The knowledge lane holds only three families:

1. `knowledge.goals.*` — one entry per goal (north star, strength model, …)
2. `knowledge.rules.*` — one entry per rule (each golden rule, each evolution rule)
3. `knowledge.decisions.*` — ADRs (already atomic; unchanged)

Everything else is a generated artifact in the artifacts lane, produced by
`drain` workflows from canon atoms and live system state (boot output,
contracts, manifest):

```
artifacts.design.invariants     assembled from knowledge.goals.* + knowledge.rules.*
artifacts.architecture.index    generated from boot output
artifacts.how-to.*              generated from boot output + contract data
artifacts.reference.*           generated from boot output
artifacts.cookbook.*            generated from boot output + template
artifacts.explanation.concepts  assembled from goal/rule atoms + boot output
```

Artifact keys mirror the knowledge key structure. The lane (`artifacts` vs
`knowledge`) declares authority; the rest of the key is the semantic address.

Templates live as ERB files in `.textus/templates/`, tracked by git alongside
workflow Ruby files. Changing a doc's format means committing a new template,
not touching any canon entry.

## Consequences

- Canon entries are atomic: one concept per entry, independent history
- Human touch points per development loop shrink to: edit a goal/rule/ADR atom
- `drain` regenerates all downstream artifacts; `rdeps` tracks dependencies
- Doc format changes are template commits; no canon churn
- The `design/invariants.md` monolith is deleted from canon (decomposed into atoms)
- Architecture, how-to, reference, cookbook, explanation docs become artifacts
