---
uid: 0b136bdf3ef55e5e
---
# Implementation plan — architecture deepening v2

Four candidates from architecture review (2026-07-02). Each phase is independent and lands safely on its own.

---

## Phase 1: Use the container's Writer/Reader

Replace 12 scattered `Writer.new(...)` constructions with `container.writer`. The `Infrastructure` Data.define already declares `:reader` and `:writer` fields (lines 13-14) but they're never referenced by consumers.

### 1a. Wire Reader + Writer into Infrastructure (builder.rb)

- Edit `lib/textus/store/builder.rb` — construct Reader + Writer alongside other ports, include in partial container
  - After FileStore, Manifest, Schemas, AuditLog, Layout exist (already)
  - Before Pipeline is built (so middleware can reference through partial)
- Infrastructure gets fully populated `:reader` and `:writer` (currently nil)

### 1b. Replace all `Writer.new(...)` call sites

Each file: replace 8-10 line constructor block with `container.writer`. Update call sites:

| File | Change |
|---|---|
| `lib/textus/use_cases/write/put_entry.rb:10` | `writer = container.writer` |
| `lib/textus/use_cases/write/delete_key.rb:10` | same |
| `lib/textus/use_cases/write/propose_entry.rb:19` | same |
| `lib/textus/use_cases/write/accept_proposal.rb:45` | same |
| `lib/textus/use_cases/write/move_key.rb:32` | same |
| `lib/textus/use_cases/write/reject_proposal.rb:21` | same |
| `lib/textus/use_cases/ops/ingest_entry.rb:98,126` | same |
| `lib/textus/workflow/runner.rb:172,210` | same — enables Phase 3 |
| `lib/textus/store/jobs/retention/base.rb:48` | same |

### 1c. Update tests

- `spec/conformance/use_cases_spec.rb:15` — already lists `reader` and `writer` as valid Infrastructure keys (verify)
- `spec/support/fixtures.rb` — `build_envelope_reader/writer` helpers may need alignment (they construct directly, not via container)
- All existing tests should pass without changes (Writer behaviour is identical, just wiring source differs)

### 1d. Verify

Run full suite: `bundle exec rspec`. Conformance specs enforce envelope shape at every seam — any wiring error surfaces immediately.

---

## Phase 2: Flatten Jobs subsystem ceremony

### 2a. Replace 3 pass-through job classes with dispatch hash

Delete: `store/jobs/index.rb`, `store/jobs/materialize.rb`, `store/jobs/sweep.rb`

Add a hash in `store/jobs/registry.rb` (or a constant in `planner.rb`):

```ruby
JOB_DISPATCH = {
  "materialize" => ->(cmd, deps) { Produce::Engine.converge(key: cmd.key, deps) },
  "index"       => ->(cmd, deps) { Index::Builder.new.rebuild! },
  "sweep"       => ->(cmd, deps) { Retention::Sweep.new.call(cmd, deps) },
}.freeze
```

The `Registry` already maps type strings; change its lookup to return from the hash instead of resolving a class.

### 2b. Merge dual registries

- Delete `lib/textus/jobs.rb` (top-level `Textus::Jobs` wrapper)
- Collapse into `Store::Jobs::Registry` as the single registry
- Update any reference to `Textus::Jobs` → `Store::Jobs::Registry`

### 2c. Delete empty facade modules

- Delete `lib/textus/store/jobs/retention.rb` (empty module, was just a namespace marker)
- Delete `lib/textus/store/jobs/base.rb` (13-line abstract base class that just raises NoMethodError)
- Delete `lib/textus/store/jobs/plan.rb` (11-line Data.define alias — inline the struct)

### 2d. Verify

- `spec/conformance/store/jobs/registry_completeness_spec.rb` — update to check hash keys instead of subclass registration
- `bundle exec rspec`

---

## Phase 3: Deepen the Workflow Runner

### 3a. Extract `Workflow::Validator`

- New file `lib/textus/workflow/validator.rb`
- Move `Runner#validate_all`, `#all_matching_keys`, `#each_validate_step` into `Validator` class
- Pass `definition` and `container` to constructor
- Runner delegates to `Validator.new(@definition, @container).validate_all` (or wires via container)

### 3b. Extract `Workflow::Publisher`

- New file `lib/textus/workflow/publisher.rb`
- Extract `Runner#write_and_publish`, `#built_in_publish`, plus shared `do_write` and `do_publish` methods
- Accept `container`, `call`, `definition` via constructor
- Single `publish(key, data, ctx)` entry point matching current `Runner#publish` signature
- The `do_write` method: `container.writer.put(key, mentry:, payload:, call:)` (clean after Phase 1)
- The `do_publish` method handles publish-via-targets vs publish-via-entry logic

### 3c. Extract `StepScope` to own file

- New file `lib/textus/workflow/step_scope.rb`
- Move `Textus::Workflow::Runner::StepScope` class out
- It already has no dependency on Runner internals (only `@data`, `@ctx`, `@container`, `@call`)

### 3d. Clean up Runner

- Remove extracted code, replace with delegation calls
- Runner becomes: build context → execute steps → delegate publish = ~120-150 lines

### 3e. Verify

- `spec/integration/workflow/runner_spec.rb` — should pass without changes (same behaviour)
- Add unit specs for `Publisher` and `Validator` in `spec/unit/workflow/`
- `bundle exec rspec`

---

## Phase 4: Delete facade + dead code

### 4a. Delete Freshness Evaluator facade

- Delete `lib/textus/store/freshness/evaluator.rb`
- Edit `lib/textus/store/infrastructure.rb:16` — rename field `:freshness_evaluator` → `:ttl_evaluator`
- Edit `lib/textus/store/builder.rb:19,44` — assign to `:ttl_evaluator` directly
- Edit `lib/textus/use_cases/ops/doctor_store.rb:18` — `ttl_evaluator: nil`
- Update specs:
  - `spec/conformance/use_cases_spec.rb:15` — rename key
  - `spec/unit/dispatch/handler_resolver_spec.rb:17` — rename key

### 4b. Delete dead Invocation value object

- Delete `lib/textus/value/invocation.rb`
- No callers to update (grep confirmed zero references in lib or spec)

### 4c. Verify

- `bundle exec rspec`

---

## Ordering

```
Phase 1 ──→ Phase 3 (depends on Phase 1 for writer cleanup)
   │
   └──→ Phase 2 (independent)
   └──→ Phase 4 (independent)
```

Phase 1 first (enables Phase 3). Phase 2 and 4 can land in any order after.
