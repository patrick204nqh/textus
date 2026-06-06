# ADR 0092 — Finish ADR 0080's cleanup: couple conformance to contract, not fixture spelling

**Date:** 2026-06-06
**Status:** Accepted
**Refines:** [ADR 0080](./0080-spec-suite-three-category-split.md) — executes its deferred **Phase 4** (evidence-gated retirement of low-value specs) and adds the churn-resistance invariant 0080's foundation implied but never enforced. The three-category split, location-derived tags, shared foundation, and `SpecLayout` guard all stand.

> **One sentence:** the suite is already fast (9.5 s / 2073 examples), so the cost it imposes is not runtime but **churn** — the reconcile-era sweep (ADRs 0087→0091) renamed and deleted a cascade of concepts (`build`, `tend`, the fetch read-through, `ingest`, the `quarantine`/`derived` zone-kinds, the `upkeep` `on:` tag), and each rename rippled through dozens of conformance specs that hard-code incidental structure as string literals; this ADR fixes the *coupling* (one fixture vocabulary owns zone-kind/namespace spelling, enforced by the `SpecLayout` guard) and runs 0080's deferred coverage-gated retirement, rather than reducing the suite for a speed problem it does not have.

## Context

ADR 0080 split the 271-file suite into `spec/{unit,integration,conformance}/`, derived the category tag from location, and stood up a shared foundation (contexts, examples, matchers, the `SpecLayout` guard, opt-in SimpleCov). Its **Phase 4 — "low-value specs are retired on coverage evidence" — never ran.**

Two things since then raised the cost of that gap:

1. **The reconcile-era sweep (0087→0091)** deleted or renamed `build`, `tend`, the `get` read-through, the `ingest` capability, the `quarantine`/`derived` zone-kinds, and the `upkeep` `on:` tag. Each was a breaking vocabulary change.

2. **Conformance specs hard-code incidental structure.** Renaming the `quarantine` zone-kind to `machine` (ADR 0091) touched ~30 conformance specs on this branch — not because their *behavior* changed, but because they spelled the literal `"quarantine"` in their bodies. The behavior under test (a verb is gated, an event fires, a kind is rejected) was unchanged; only the fixture spelling moved.

A measurement settles the framing. The full suite runs in **9.52 s for 2073 examples**; ADR 0080 already recorded ~8 s. Runtime is not a problem, so the suite must not be cut to chase one — that trades real coverage for an imaginary win. The honest cost is **maintenance churn and reading noise**, and the honest fix is *decoupling*, plus the small, evidence-gated retirement 0080 deferred.

Most specs that *mention* the swept concepts earn their keep: they test live behavior (intake entries are now `artifacts.feeds.*` under the one `machine` zone; the fetch mechanism still runs) or they are deliberate **absence guards** (`no_dead_verbs`, `upkeep_kinds`, `capabilities_schema`, `lanes`) that assert a deleted concept stays deleted. The genuinely-dead set is a handful, not a large fraction.

## Decision

### 1. Runtime is not a goal of this work

The suite is not reduced for speed. The target is **churn-resistance and legibility**. Stated normatively so a future pass does not delete coverage in the name of a fast suite that is already fast. A spec is retired only on the Phase-4 coverage gate below — never on a wall-clock argument.

### 2. One fixture vocabulary owns incidental structure

Zone names, zone **kinds** (`machine`, `canon`, `workspace`, `queue`), and key namespaces (`feeds.*`, `artifacts.derived.*`) are spelled in `spec/support/` **once** — `fixtures.rb` is the home that already exists (the `KIND_ZONE` map, `intake_store`, the machine-zone presets). Specs reference the vocabulary; they do not re-spell the literals. The next zone-kind rename then touches one file, not thirty.

### 3. Conformance asserts the contract, not the spelling

A conformance spec proves a behavior or contract — a verb is absent, a role is gated, an event fires, a manifest is rejected with a hint. When it must name structure, it pulls the name from the fixture vocabulary (§2). A conformance spec must not depend on the *spelling* of a zone-kind it is not the dedicated guard for.

### 4. The invariant is enforced, not just documented

`SpecLayout` (the guard 0080 rewrote to make misfiled specs fail CI) gains a **retired-token scan**: a denylist of zone-kind tokens that a sweep has *removed from the vocabulary* (today `quarantine`; it grows by one entry each time a kind is retired) may not appear in a spec body outside `spec/support/`, with the dedicated kind-guard specs (`lanes`, `capabilities_schema`, `schema`) — which assert those tokens are *rejected* — as the explicit allow-list.

The scan is deliberately a **denylist of dead tokens, not a ban on all kind literals**. Live kinds (`machine`, `canon`, `workspace`, `queue`) are spelled freely: inline `store_from_manifest` fixtures legitimately write `kind: machine`, and `derived` remains a live *entry-kind* word (`entry.derived?`, `artifacts.derived.*`). Banning those would break valid specs and is not the goal. The guard's job is narrow and decisive: a retired token never creeps back, and the next straggler after a rename fails CI instead of lingering. Without §4, §2 and §3 are aspiration.

### 5. Phase 4 runs, coverage-gated

With `COVERAGE=1` baselined against ADR 0080's numbers (line 93.43 %, branch 75.65 %), a spec is deleted only when it (a) tests a concept the sweep removed **and** (b) drops **zero** unique line/branch coverage. Each removal cites its coverage delta. Absence guards are retained by definition — they cover the rejection path. The expected yield is a handful of files, not a large cut.

### Sequencing

Each step keeps `rspec` and `rubocop` green, mirroring 0080's discipline:

- **Phase 0 — green first.** No cleanup begins on a red or flaky suite. (Note: an intermittent order/timing flake exists around the async-materialize drain in `init_with_agent_build_spec`; it is a watch item, not a blocker.)
- **Phase 1 — finish the rename.** Migrate the residual `quarantine` literals to the fixture vocabulary; rename the `quarantine_store` preset to a machine-zone name. Mechanical; no logic edits.
- **Phase 2 — install the guard (§4).** CI now blocks new raw zone-kind literals.
- **Phase 3 — coverage-gated retirement (§5).**
- **Phase 4 — optional consolidation.** Split the monolith conformance files (`conformance_spec.rb`, `events_spec.rb`) only if Phase 3 shows them carrying mixed concerns. Lowest priority.

## Consequences

- **The next zone/namespace rename is a one-file edit.** The ~30-file ripple ADR 0091 paid does not recur; the guard makes regression a CI failure rather than a review catch.
- **No specs were retired; the suite's legibility improved, on coverage evidence.** Phase 3's coverage-gated audit found the reconcile-era sweep (0087→0091) left no dead specs — every mention of a swept concept is an absence guard or live behavior (deltas all ≈0), so nothing was deleted; the audit's value is that evidence plus the standing §4 retired-token guard. Phase 4 split the `conformance_spec.rb` monolith — which bundled ~10 unrelated subsystem concerns yet contributed only 8 unique lines / 3 unique branches — into 8 per-concern conformance specs sharing one extracted `"textus/3 conformance fixture"` context; `events_spec.rb` was left intact (cohesive: one event-emission subsystem). Line/branch coverage held exactly at the measured baseline 94.05% / 77.77% (above ADR 0080's 93.43% / 75.65%, as the codebase grew since). Net example count unchanged: 2079 → 2079.
- **A new house invariant is written down.** "Conformance asserts contract, not fixture spelling" was implicit in 0080's exemption of string-described specs from the mirror; §3/§4 make it explicit and enforced.
- **No runtime change is promised or pursued.** The 9.5 s figure is the baseline, not a target to beat.
- **ADR 0080's Phase 4 is closed.** The staged-cleanup story that 0080 opened is finished here rather than left as a standing TODO.

## Alternatives considered

- **Delete a large fraction of the suite for speed.** Rejected: the measurement (9.5 s) shows no speed problem; mass deletion would trade real coverage — including the absence guards that pin the sweep's deletions — for nothing. This was the requested framing; the data does not support it.
- **A brand-new test-strategy ADR superseding 0080.** Rejected: 0080's layer contract is sound and adopted (116 specs use its shared foundation). A fresh ADR would re-litigate a settled decision; the honest shape is *refine and finish 0080*, in the house style where ADRs amend their predecessors (cf. 0091 → 0034/0090).
- **Document the invariant without enforcing it (convention only).** Rejected: §2/§3 are exactly the kind of convention the next rename erodes silently. 0080's own lesson is that a guard, not a guideline, is what makes a layout survive churn.
- **Retire dead specs by judgement, not coverage.** Rejected: 0080 added opt-in SimpleCov specifically so removal is evidence-backed. Judgement-only deletion risks dropping the one spec that covered an edge path; the coverage gate is cheap and decisive.
- **Skip the ADR and just do the cleanup on this branch.** Rejected: the cleanup decays without the §4 guard, and the "runtime is not a goal" decision needs a durable home so it is not re-opened. The branch work is the *implementation* of this decision, not a substitute for recording it.
