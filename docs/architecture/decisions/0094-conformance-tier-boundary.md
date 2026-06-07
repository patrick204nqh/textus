# ADR 0094 — Does the conformance tier earn a distinct category?

**Date:** 2026-06-07
**Status:** Proposed
**Revisits:** [ADR 0080](./0080-spec-suite-three-category-split.md) — the three-category physical split (`unit`/`integration`/`conformance`) and the location-derived RSpec tag. · [ADR 0092](./0092-spec-suite-churn-resistance.md) — the churn-resistance invariants and the `SpecLayout` guard whose `string_described?` heuristic is the mechanical signal in question.

> **One sentence:** ADR 0080 classifies a spec into a tier **mechanically** — string-described ⇒ conformance, else store-touching ⇒ integration, else unit — so "conformance" today means "describes a string," a *syntactic* signal (`SpecLayout.string_described?`), not the *semantic* "cross-surface contract test" the name implies; the just-completed consolidation pass surfaced enough evidence of this mismatch (shared lib namespaces across `integration/` and `conformance/`, store-backed specs filed as conformance, zero misfiled constant-described specs) to ask whether the conformance tier should be **redefined**, **collapsed**, or **left as-is** — this ADR records the evidence and three options and leaves the choice for human ratification.

## Context

ADR 0080 split the suite into `spec/{unit,integration,conformance}/`, kept the `lib/textus/` mirror inside each category, and derived the `:unit`/`:integration`/`:conformance` tag from the spec's location. ADR 0092 finished 0080's cleanup, added the "conformance asserts contract, not fixture spelling" invariant, and installed the `SpecLayout` retired-token guard. Neither ADR examined *what makes a spec conformance* — they took the tier as given.

The classification is mechanical, not semantic. The guard's signal is one regex:

```ruby
def string_described?(source) = source.match?(/^\s*RSpec\.describe\s+["']/)
```

A spec is conformance iff its `RSpec.describe` argument is a **string** rather than a `Textus::` constant. Store-touching-else-unit decides the other two. Nothing in the boundary asks whether the spec proves a *cross-surface contract* (CLI/MCP/boot parity, doctor structural checks, docs-links resolution) — the meaning the word "conformance" carries everywhere else in this repo.

Four pieces of evidence say the syntactic signal and the semantic intent have drifted apart:

1. **The same lib namespaces appear in both tiers.** `cli`, `mcp`, `doctor`, `domain`, `envelope`, `hooks`, `key`, `manifest`, `read`, `write`, and `ports` each have subdirs under **both** `spec/integration/` and `spec/conformance/`. The tier is not separating subsystems; it is separating *how the example happens to be described*.

2. **Most conformance specs stand up a real Store / tmpdir** — the very signal that defines integration. They are classified conformance only because they describe a string. By the integration definition (store-touching) they would qualify as integration; the string-describe override wins.

3. **The consolidation found zero loose conformance files that describe a `Textus::` constant.** Nothing is *obviously* misfiled under 0080's own rule — and that is precisely the point. "Nothing is misfiled" only means "every file in `conformance/` describes a string," which is the mechanical rule restated, not evidence that each file is a cross-surface contract test.

4. **The name oversells the tier.** "Conformance" reads as "the contract is honored across surfaces." In practice it means "string-described." A reader using the directory as a semantic map is misled.

This question was *raised by*, not *resolved by*, the consolidation pass that just landed. That pass grouped the conformance tier into subdirs (`boot/`, `init/`, `contract/`, `source/`, `publish/`) and folded the rest into existing `mcp/`, `manifest/`, `write/`, and `cli/` subdirs; loose root files dropped **67 → 19**, total conformance files **124 → 97**, with **zero coverage loss**. Consolidation made the tier *legible* — and legibility made the mechanical-vs-semantic gap visible enough to write down. This ADR is the "ADR later" half of that work: it changes no spec or lib code.

## Decision

No decision yet — **Proposed for human ratification.** Three options, with trade-offs, no winner picked:

### (a) Keep three tiers, sharpen the definition

Redefine "conformance" to mean **cross-surface contract**: CLI/MCP/boot parity, doctor structural checks, docs-links resolution, manifest-rejection hints — the specs that prove a behavior holds *across* surfaces rather than exercising one component against a store. Reclassify store-but-not-cross-surface specs **down to `integration/`**. The guard's `string_described?` heuristic is replaced by an **explicit signal** (a tag or location convention that means "this is a contract test"), so the tier stops being an artifact of describe-argument syntax.

- **Pro:** lower churn than (b); the tier finally means what its name says; the guard asserts an intentional signal, not a syntactic accident.
- **Con:** requires an explicit-signal mechanism to replace the regex, and a one-time reclassification of the store-backed-but-not-cross-surface specs (a directory move with the usual coverage gate); "cross-surface" needs a crisp, guardable definition or it drifts again.

### (b) Collapse to two tiers

Drop `conformance/` as a **physical** tier. Keep `spec/unit/` + `spec/integration/`, and mark cross-surface specs with a **`:conformance` tag** (an attribute on the example) instead of a directory. The fast/slow and unit/integration partitions survive; "conformance" becomes a queryable facet, not a location.

- **Pro:** one fewer structural concept; highest legibility win; a spec can be *both* integration and conformance without the directory forcing an either/or.
- **Con:** **reverses ADR 0080's physical split** (which deliberately chose location-derived tags over hand-maintained metadata) and carries the largest churn (~97-file move). Needs its own coverage-gated move plan and a follow-up implementation ADR; the tag must be derivable or it reintroduces the hand-maintained-metadata cost 0080 rejected.

### (c) Status quo

Keep the mechanical split. Accept that, in this repo, **"conformance" == "string-described."** Document the equivalence so no reader expects more, and move on.

- **Pro:** zero churn; the suite stays green untouched; the `SpecLayout` guard is unchanged.
- **Con:** the concept stays fuzzy; the directory remains a poor semantic map; the next reader re-discovers the gap this ADR records.

## Consequences

- Whichever option is ratified, the change **must stay coverage-gated** (the ADR 0080 / 0092 discipline: a spec moves or is retired only on coverage evidence, and `rspec`/`rubocop` stay green at every step). No tier change rides an uncovered move.
- **(b) specifically requires a follow-up implementation plan / ADR** — it is a ~97-file physical move that reverses 0080's location-derived design and cannot be done as a side effect of this proposal.
- **(a)** requires defining and guarding an explicit "cross-surface" signal to replace `string_described?`; the definition is the load-bearing work, not the move.
- **(c)** ships nothing but the written-down equivalence; the cost is paid by every future reader.
- This ADR is the **"ADR later"** half of the conformance-consolidation pass (loose root `67 → 19`, total `124 → 97`, zero coverage loss; new subdirs `boot/`, `init/`, `contract/`, `source/`, `publish/`, plus folds into `mcp/`, `manifest/`, `write/`, `cli/`). That pass made the tier legible; this ADR records the boundary question it exposed. No spec or lib code changes here.

## Alternatives considered

- **Pick a winner now.** Rejected for this draft: the choice trades off churn (zero / one reclassification / ~97-file move) against concept clarity, and the cost of (b) in particular warrants explicit human ratification rather than an author's call. Recording the options with honest trade-offs is the deliverable; the decision is deferred.
- **Treat it as a 0092 follow-up edit rather than a new ADR.** Rejected: 0092 is Accepted and its scope was *coupling and Phase-4 retirement*, not the tier's semantic identity. The boundary question is a distinct, load-bearing decision and earns its own (Proposed) record, in the house style where a revisiting ADR references — not rewrites — its predecessors.
