# Testing Strategy

> **Reference** · for contributors and AI agents · **read when** writing or reviewing specs
> **SSoT for** test placement, scope decisions, shared patterns, and anti-patterns · **reviewed** 2026-06 (v0.44)

Textus evolves fast. The strategy is **test the contract, not the plumbing** — write specs that survive a refactor because they assert observable outcomes, not implementation details.

---

## The three questions before writing any spec

1. **Is this layer stable?** If it lives in `dispatch/`, `surfaces/`, or `jobs/` internals, it is volatile — test it through a conformance or integration boundary instead.
2. **What is the contract?** For a value object, the contract is its public method signatures and return values. For a verb, it is the envelope shape from `Contract::DSL`. Write against the contract, not the implementation.
3. **Does a shared context cover this setup?** If yes, use it. If no, add to support — never duplicate setup inline across specs.

---

## Stability map — where to invest

| Layer | Spec type | Invest |
|---|---|---|
| `core/` — Duration, Freshness, Retention, Sentinel | Unit (pure, no store) | High — these are frozen by ADR |
| `manifest/` — Entry, Policy, Source, Retention | Unit | High |
| `entry/`, `key/`, `role/`, `envelope/` | Unit | High |
| `contract/` verb contracts | Conformance | High — this IS the protocol |
| `dispatch/` internals — planner, pipeline, executor | Integration boundary only | Low; tag `:volatile` |
| `surfaces/` — CLI, MCP | Conformance fixture | Low; tag `:volatile` on unit specs |
| `step/` — Fetch, Derive, External | Interface contract only | Medium |
| `doctor/` checks | Integration (one spec per check) | Medium |

**Rule:** if you're asserting on a private method, an internal class name, or a log format — stop. Those are not contracts.

---

## Spec placement

```
spec/unit/          Pure: no Store, no tmpdir, no real I/O.
                    Classes under core/, manifest/, entry/, key/, role/, envelope/.
                    Describe a Textus:: constant → path must mirror lib/.

spec/integration/   Store-backed: uses store_from_manifest / minimal_store / intake_store.
                    Test a use-case outcome (envelope shape, audit log verb, error code).
                    Describe a string, not a constant.

spec/conformance/   Protocol contracts and structural invariants.
                    Each spec locks an ADR-backed rule forever.
                    Describe a string.
```

The spec_layout guard enforces placement. A constant-described spec in `spec/unit/` that calls `store_from_manifest` is a misfile — move it to `spec/integration/`.

---

## Shared support — use before building

| Context / helper | Use for |
|---|---|
| `include_context "textus_store_fixture"` | Any spec that needs a `root` tmpdir |
| `store_from_manifest(root, manifest:, lanes:)` | Building a real Store from inline YAML |
| `minimal_store(root)` | Single canon leaf — most read/write specs |
| `machine_store(root)` | Dual zone: machine + canon |
| `intake_store(root, intake_body:, ttl:)` | Intake entry with a fetch step |
| `include_context "core domain doubles"` | `fake_clock`, `fake_file_stat` for pure domain classes |
| `fail_guard_with(*predicates)` | Assert `GuardFailed` with named unmet predicates |
| `have_audit_verb(verb)` | Assert the last audit row |
| `test_ctx(role:)` | Build a `Textus::Call` without a store |

**Before writing setup code inline, check `spec/support/`.** Add to support when you need it a second time.

---

## Anti-patterns — do not write these

| Anti-pattern | Why | Instead |
|---|---|---|
| Spec asserts on a private method | Tests implementation, not contract | Test the public output |
| Setup duplicated across 3+ specs | Brittle; breaks together | Extract to a shared context |
| `store_from_manifest` inside `spec/unit/` | Misfile; unit/ must be store-free | Move to `spec/integration/` |
| Testing the same branch in unit AND integration | Redundant; unit is proof, integration is smoke | Delete the duplicate |
| `:volatile` on a spec permanently | `:volatile` is a branch-lifespan signal, not a skip tag | Delete specs that are permanently invalid |
| Asserting on audit log structure when not needed | Log format is not the contract | Assert on the returned envelope or raised error |
| Testing `dispatch/` internals directly | Dispatch is volatile by design | Write a conformance spec against the verb output |

---

## Volatile tag contract

Mark a spec `:volatile` when it covers a surface or internal that is actively being redesigned on the current branch. The tag is a **temporary** signal — it gates out the spec from the fast feedback loop during active churn.

Rules:
- A spec that is `:volatile` for more than one merged PR is a candidate for deletion.
- Conformance specs (`spec/conformance/`) are **never** `:volatile` — they are the frozen protocol record.
- Path-based volatile patterns (in `spec_helper.rb`) cover whole directories; file-specific patterns cover known-unstable specs.

To run the fast loop (excluding volatile and slow): `bundle exec rspec --tag ~volatile`

---

## Regression test rule

When fixing a bug: write the failing spec first, confirm it fails, then fix the code. The spec is the proof the bug existed and cannot return. This is not optional — a bug fixed without a spec will reappear.

---

## Coverage guidance

`COVERAGE=1 bundle exec rspec` produces a branch-coverage report. Use it to find specs worth retiring (low-value coverage of volatile internals), not to chase a percentage. A spec that tests a path that will be deleted next sprint costs more than it saves.
