# ADR 0080 — Spec suite: a three-category physical split (unit / integration / conformance) over the lib mirror

**Date:** 2026-06-04
**Status:** Accepted
**Touches:** the spec-layout guard convention (`spec/support/spec_layout.rb` + `spec/spec_layout_spec.rb`, introduced as test infrastructure on 2026-06-03) — this ADR keeps the lib-mirror rule but **re-anchors it below a category segment**, so the guard is rewritten, not retired.

> **One sentence:** the 271-file spec suite mirrors `lib/textus/` flat at the spec root, which conflates three kinds of test (isolated unit, store-backed integration, cross-surface conformance) into one undifferentiated tree with no way to run them separately and no shared foundation for the boilerplate they each repeat; this ADR moves every spec under one of **`spec/unit` · `spec/integration` · `spec/conformance`**, keeps the lib-mirror *inside* each category, derives an `:unit`/`:integration`/`:conformance` RSpec tag from the spec's location (so the categories are runnable, not just visual), and stands up a shared-context / shared-examples / verifying-double foundation that later phases delete the duplicated setup into — staged so the full suite stays green at every step.

## Context

The suite (271 files, ~1942 examples) mirrors the `lib/textus/` namespace at the spec root, and a guard
(`SpecLayout`) enforces that mirror for every constant-described spec. That guard is good and stays — but the
flat layout has three costs:

- **No separation of test kinds.** ~80 specs test one class in isolation (no filesystem), ~165 are store-backed
  integration (real tmpdir, manifests, multi-component), and ~110 describe a *string* (CLI contract, MCP catalog,
  boot reconciliation — cross-surface conformance). They are interleaved, so there is no `--tag unit` fast lane
  and no way to reason about the suite by kind.
- **No shared foundation.** Exactly one shared context (`textus_store_fixture`) and zero shared examples exist.
  The same setup recurs by hand: the `intake_store` + `resolve_intake` hook heredoc (~15×), the CLI
  `StringIO`-triple + `CLI.run` (~10×), and per-verb re-assertions of audit-row / guard-failure / event-fired.
- **Ad-hoc fakes.** The read/get path fakes its collaborator with anonymous `Class.new { def execute(*) … }`
  objects — normal doubles that pass even if `FetchOrchestrator`'s interface changes.

The conformance specs already describe *strings* and are therefore **exempt** from the mirror guard today, which
means the layout already half-acknowledges the three-way distinction — it just isn't physical or runnable.

## Decision

### 1. Three physical categories, lib-mirror inside each

```
spec/{unit,integration,conformance}/<lib-namespace mirror>/…_spec.rb
spec/support/{contexts,examples,matchers.rb,doubles.rb,spec_layout.rb}
```

Classification is deterministic, applied top-down: a **string-described** spec → `conformance/`; else a spec
that touches `Store` / `Dir.mktmpdir` / the store fixture → `integration/`; else → `unit/`.

### 2. The category is the tag (single source = location)

`spec_helper` derives metadata from the path (`define_derived_metadata(file_path: %r{/spec/unit/}) …`), so
`rspec --tag unit` partitions the suite with **no hand-maintained tags**. Location *is* the classification.

### 3. The guard is re-anchored, not retired

`SpecLayout` gains `categorized_placement_error`: the first dir segment must be a known category, and the
existing mirror rule applies to the remainder. Post-move the live sweep switches to it, and it additionally
enforces that a `unit/` spec stays pure, a `conformance/` spec is string-described, and no spec sits at the
spec root. A misfiled `git mv` then fails CI — which is what makes a 271-file move mechanical and safe.

### 4. A shared foundation, adopted gradually

Shared contexts (`"intake doc"`, `"cli invocation"`), shared examples (`"an audited write"`, `"a correlated
write"`, `"a guarded action"`, `"an event-emitting action"`), and a verifying-double helper (`stub_orchestrator`
→ `instance_double(FetchOrchestrator)`) are built first; specs adopt them per-subsystem afterwards. SimpleCov
(opt-in, `COVERAGE=1`) is added so the later removal of low-value specs is **coverage-backed evidence**, not
judgement. Baseline at adoption: **line 93.43 % (4935/5282), branch 75.65 % (1137/1503)**.

### 5. Staged, green at every step

Foundation lands with no file moves (Phase 0); the move runs in per-subsystem batches behind the guard
(Phase 1); deduplication onto the foundation (Phase 2), a `rubocop-rspec` style-guide ratchet (Phase 3), and
evidence-gated cleanup (Phase 4) follow. Each step keeps `rspec` and `rubocop` green.

## Consequences

- **A runnable taxonomy.** `--tag unit` gives a fast pure lane; integration and conformance are separable for CI.
- **Churn is real but mechanical.** ~271 files move; the rewritten guard turns "moved correctly" into a CI check,
  and the move PRs carry no logic edits, so they review fast.
- **The mirror convention strengthens.** The unit-purity and conformance-string invariants the guard now asserts
  were previously unwritten; the split makes them enforced.
- **A deliberate style deviation is preserved.** `RSpec/DescribedClass` and `RSpec/SpecFilePathFormat` stay
  disabled — the house style uses full `Textus::` constant paths and string-described conformance specs on
  purpose; the style-guide ratchet (Phase 3) does not reverse that.
- **Coverage gates the cleanup.** Phases 2/4 must not drop the SimpleCov baseline; removals cite evidence.

## Alternatives considered

- **Metadata tags only, keep the flat tree.** Lower churn — `--tag unit` works without moving a file. Rejected
  *for this ADR* because the directory remains undifferentiated and the conformance specs stay mixed into the
  mirror; the physical split was the chosen appetite. (The derived-tag mechanism is kept regardless, so the
  fast lane exists either way — the split adds the physical separation on top.)
- **Big-bang restructure in one PR.** Rejected: 271 moves + dedup + lint in one diff is unreviewable and risks a
  red suite mid-flight. The staged plan keeps every step green.
- **Adopt FakeFS to speed unit specs.** Rejected: real-tmpdir IO is fast enough (~8 s full suite) and faithful;
  mocking the filesystem would trade fidelity for speed the suite doesn't need.
- **One `spec/conformance` carve-out only (hybrid), keep the rest flat + tagged.** Rejected as half-measure: it
  separates the string-described specs but leaves unit and integration interleaved, so the unit-purity boundary
  stays unenforced.
