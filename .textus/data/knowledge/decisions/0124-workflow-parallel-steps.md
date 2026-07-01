---
name: '0124-workflow-parallel-steps'
uid: ''
---

# ADR-0124: Workflow parallel steps with concurrent-ruby

## Status

Accepted

## Date

2026-07-01

## Context

The workflow DSL (Workflow::DSL) is linear — steps execute sequentially:

```ruby
Textus.workflow "my-report" do
  match "artifacts.my-report"
  step :fetch_stars  { http_get("https://api.github.com/...") }
  step :fetch_downloads { http_get("https://api.npmjs.org/...") }
  step :merge { |data, ctx| ... }
end
```

For workflows that acquire data from independent sources, sequential execution
multiplies latency: total = sum(t1, t2, t3) instead of max(t1, t2) + t3.
There is no way to express that `:fetch_stars` and `:fetch_downloads` have no
dependency on each other and could run concurrently.

The workflow runner (Workflow::Runner) is simple enough that a concurrency
change is bounded — it iterates steps in order, calls each step with
`context.call`, and collects the result. The seam for parallel execution is
at the runner level, not the DSL level.

## Decision

### 1. `parallel` block syntax

Add a `parallel` block to the workflow DSL that declares concurrent execution:

```ruby
Textus.workflow "my-report" do
  match "artifacts.my-report"

  parallel do
    step :fetch_stars  { http_get("https://api.github.com/...") }
    step :fetch_downloads { http_get("https://api.npmjs.org/...") }
  end

  step :merge { |data, ctx| ... }
end
```

A `parallel` block wraps its steps in a `Parallel` data object (distinct
from a `Step`). The runner detects `Parallel` objects in the steps list and
executes their child steps concurrently using a thread pool.

Blocks can be nested (`parallel` inside `parallel` is a single flat pool) or
sequential (`step` after `parallel` waits for all parallel steps to finish).

### 2. Add concurrent-ruby dependency

`concurrent-ruby` provides `Concurrent::Promises` (future/promise) and
thread pool factories. It is added to the gemspec:

```ruby
s.add_dependency "concurrent-ruby", "~> 1.3"
```

The runner uses `Concurrent::Promises.future` for each step in a parallel
block and `Concurrent::Promises.zip(*futures).value!` to collect results.
The thread pool is `Concurrent::FixedThreadPool.new(size)` with size
defaulting to `Etc.nprocessors` and configurable via the manifest's
`worker_config.pool_size`.

### 3. Wait-for-all error handling

When a parallel block completes, all step results are collected:
- **All succeed** — results are merged into the step output hash (same as
  sequential execution).
- **Some fail** — all failures are collected and reported as a single
  `ParallelStepFailed` error listing each failed step and its error message.
  Partial results from successful steps are discarded (the workflow fails).
  No automatic retry — the standard job `max_attempts` retries the entire
  workflow.

This is consistent with the existing philosophy: a workflow is an atomic
unit of work. Either all steps succeed or the workflow is retried from the
beginning.

### 4. DSL changes to Workflow::DSL

```ruby
class Definition
  attr_reader :name, :steps, :...

  Parallel = Data.define(:steps)

  def parallel(&block)
    saved = @steps
    @steps = []
    instance_eval(&block)
    parallel_steps = @steps.dup
    @steps = saved << Parallel.new(steps: parallel_steps)
  end
end
```

The `Definition` object gains a `Parallel` Data class. Steps inside the
`parallel` block are collected into a `Parallel` instance and appended to the
top-level steps array. The runner pattern-matches on `Parallel` vs `Step`:

```ruby
def run_steps
  futures = @definition.steps.map do |item|
    case item
    when DSL::Step then execute_step(item)
    when DSL::Parallel then run_parallel(item)
    end
  end
  # ...
end
```

## Consequences

- **Positive:** Multi-source workflows run in max-latency instead of sum-latency.
- **Positive:** DSL change is backward-compatible — existing workflows (no
  `parallel` block) execute identically.
- **Positive:** Error semantics are clear — parallel failures are collected
  and the workflow retries as a unit.
- **Neutral:** Adds `concurrent-ruby` (~150 KB) to the dependency tree.
- **Negative:** Thread safety becomes a concern — step blocks that capture
  mutable shared state risk races. The runner does not provide isolation;
  step authors must use thread-safe patterns or confine shared state to the
  Context.
- **Cost:** ~80 lines of DSL changes + ~60 lines of runner changes + the
  concurrent-ruby dependency.

## Alternatives Considered

### Step-level `parallel: true` flag
`step :a, parallel: true; step :b, parallel: true` — runner groups adjacent
parallel-flagged steps. Rejected: implicit grouping is fragile (inserting a
sequential step between two parallel steps silently serializes them), and
the flag meaning depends on adjacent steps.

### DAG-style `depends_on`
`step :c, depends_on: [:a, :b]` — explicit dependency declarations, runner
resolves topological order. Rejected: over-engineered for textus workflows,
which are typically 2-5 steps. The `parallel` block is explicit and visual.

### Return to sequential on first failure
Rejected. The workflow is atomic — partial results are meaningless. The
caller (a `materialize` job) retries the full workflow on failure, so
fast-failing vs wait-for-all is indistinguishable in outcome. Collecting
all errors gives better diagnostics.

### Fiber-based concurrency instead of threads
Rejected. Fibers require an external scheduler in Ruby 3.x or explicit
`Fiber.transfer` management. Threads with concurrent-ruby provide the same
I/O concurrency benefit with simpler semantics and a well-known API.

### No new dependency — use Thread + Queue
Rejected. concurrent-ruby provides error propagation (future.value!),
timeout support, and thread pool management that would need to be
reimplemented. The dependency is mature, well-maintained, and widely used.
