---
uid: '08b43cb02e8331f5'
---
# Verb Registry Standardization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-ruby:subagent-driven-development (recommended) or superpowers-ruby:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four concrete standardization gaps found in an API/interface audit of `Textus::VerbRegistry` / `Dispatch::Contracts` / `Value::Result`: an MCP/CLI surface-parity gap on six verbs, an internal contract-naming inconsistency, a mixed-intent `jobs` verb, and a `Result.extract` path that silently downgrades typed errors (including a currently-unreachable `Textus::CursorExpired`) to a generic `ActionError`.

**Architecture:** No new layers. Every change is a projection-level or contract-level edit inside the existing `VerbRegistry` → `Dispatch::Contracts` → `HandlerResolver`/`Pipeline` → `Value::Result` pipeline described in ADR 0117 and ADR 0125. Task 3 (jobs split) follows the exact `key_*` / `rule_*` precedent already in the registry (multi-word verb → auto-derived CLI group).

**Tech Stack:** Ruby 3.x, RSpec, the existing `Textus::Dispatch` pipeline (no new gems).

---

## Before you start

Run the full suite once to get a clean baseline:

```bash
bundle exec rspec
```

Expected: all green (per project memory, this environment has 4 known pre-existing CLI-conformance failures unrelated to this work — note them now so you don't chase them later).

Work through tasks in order. Each task is independently committable and independently revertable.

---

### Task 1: Expose `uid`, `blame`, `audit`, `rule_list`, `published`, `doctor` over MCP

**Why this is safe:** `Store#method_missing` dispatches every verb in `VerbRegistry::DOMAIN_VERBS` (built from `ENTRY_VERBS + OPS_VERBS + RULE_VERBS`, independent of `surfaces`) through the same `Dispatch::Pipeline`. The CLI already calls these six verbs this way. Adding `:mcp` to `surfaces` only changes whether `MCP::Catalog.specs`/`.build_tools` advertises the tool — no use-case, pipeline, or Store change is needed.

**Files:**
- Modify: `lib/textus/verb_registry.rb` (six `register VerbSpec.new(...)` calls)
- Test: `spec/integration/surface/mcp/catalog_dispatch_spec.rb`

- [ ] **Step 1: Write the failing tests**

Add to the bottom of `spec/integration/surface/mcp/catalog_dispatch_spec.rb` (before the final `end`):

```ruby
  # ── Newly-exposed observability verbs (verb-registry standardization) ──────

  describe ".call('uid', ...)" do
    it "returns the entry's stable uid" do
      result = described_class.call("uid", store: human_store, args: { "key" => "identity.self" })
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end

  describe ".call('blame', ...)" do
    it "returns an array of audit rows annotated with git info" do
      result = described_class.call("blame", store: human_store, args: { "key" => "identity.self" })
      expect(result).to be_an(Array)
    end
  end

  describe ".call('audit', ...)" do
    it "returns an array of audit rows" do
      result = described_class.call("audit", store: human_store, args: {})
      expect(result).to be_an(Array)
    end
  end

  describe ".call('rule_list', ...)" do
    it "returns an array of rule blocks" do
      result = described_class.call("rule_list", store: human_store, args: {})
      expect(result).to be_an(Array)
    end
  end

  describe ".call('published', ...)" do
    it "returns an array of published entries" do
      result = described_class.call("published", store: human_store, args: {})
      expect(result).to be_an(Array)
    end
  end

  describe ".call('doctor', ...)" do
    it "returns a health-check result hash" do
      result = described_class.call("doctor", store: human_store, args: {})
      expect(result).to include("ok")
    end
  end

  it "advertises all six previously CLI-only verbs as MCP tool names" do
    expect(Textus::Surface::MCP::Catalog.names).to include(
      "uid", "blame", "audit", "rule_list", "published", "doctor",
    )
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/integration/surface/mcp/catalog_dispatch_spec.rb -e "uid" -e "blame" -e "audit" -e "rule_list" -e "published" -e "doctor" -e "previously CLI-only"`
Expected: FAIL with `Textus::Surface::MCP::ToolError: unknown tool: uid` (and similarly for the other five, plus the aggregate `names` example)

- [ ] **Step 3: Flip each verb's `surfaces` from `[:cli]` to `%i[cli mcp]`**

In `lib/textus/verb_registry.rb`, six one-line changes (only the `surfaces` argument — the 2nd positional array argument to `VerbSpec.new` — changes on each):

```ruby
    # ── uid ──────────────────────────────────────────────
    register VerbSpec.new(
      :uid, "Return the stable UID of an entry without reading its body.",
      [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key")],
      %i[cli mcp], { cli: ->(uid, inputs) { { "key" => inputs[:key], "uid" => uid } }, default: identity }, "key uid", nil, :read
    )
```

```ruby
    # ── blame ────────────────────────────────────────────
    register VerbSpec.new(
      :blame, "Annotate audit rows with the git commit that introduced each file state.",
      [ArgSpec.arg(name: :key, required: true, positional: true, description: "entry key to blame"),
       ArgSpec.arg(name: :limit, type: Integer,
                   description: "maximum number of audit rows to return")],
      %i[cli mcp], {
        cli: ->(rows, inputs) { { "verb" => "blame", "key" => inputs[:key], "rows" => rows } },
        default: identity,
      }, "blame", nil, :read
    )
```

```ruby
    # ── audit ────────────────────────────────────────────
    register VerbSpec.new(
      :audit, "Query the audit log with optional filters.",
      [ArgSpec.arg(name: :key, description: "filter to rows for this key"),
       ArgSpec.arg(name: :lane, description: "filter to keys in this lane"),
       ArgSpec.arg(name: :role, description: "filter to rows written under this role"),
       ArgSpec.arg(name: :verb, description: "filter to rows for this verb"),
       ArgSpec.arg(name: :since,
                   description: "ISO-8601 timestamp or relative offset (e.g. 1h, 30m)"),
       ArgSpec.arg(name: :seq_since, type: Integer,
                   description: "return rows with seq > this cursor value"),
       ArgSpec.arg(name: :correlation_id,
                   description: "filter to rows with this correlation_id"),
       ArgSpec.arg(name: :limit, type: Integer,
                   description: "maximum number of rows to return")],
      %i[cli mcp], { cli: ->(rows, _) { { "verb" => "audit", "rows" => rows } }, default: identity }, "audit", nil, :read
    )
```

```ruby
    # ── rule_list ────────────────────────────────────────
    register VerbSpec.new(
      :rule_list, "List every rule block in the manifest.",
      [], %i[cli mcp], { cli: ->(p, _) { { "verb" => "rule_list", "policies" => p } }, default: identity }, "rule list", nil, :read
    )
```

```ruby
    # ── published ────────────────────────────────────────
    register VerbSpec.new(
      :published, "List all entries that declare a publish target.",
      [], %i[cli mcp], { default: identity }, "published", nil, :read
    )
```

```ruby
    # ── doctor ───────────────────────────────────────────
    register VerbSpec.new(
      :doctor, "Run health checks on the textus store.",
      [ArgSpec.arg(name: :checks, type: Array,
                   description: "subset of check names to run (default: all)")],
      %i[cli mcp], { default: identity }, "doctor", nil, :read
    )
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec rspec spec/integration/surface/mcp/catalog_dispatch_spec.rb`
Expected: all PASS

- [ ] **Step 5: Run the full-catalog conformance suite**

Run: `bundle exec rspec spec/conformance/surface/mcp/integration_spec.rb`
Expected: PASS — this spec compares `tools/list` output against `Catalog.names` dynamically, so no fixture list needs updating.

- [ ] **Step 6: Run the full suite and commit**

```bash
bundle exec rspec
bundle exec rubocop lib/textus/verb_registry.rb spec/integration/surface/mcp/catalog_dispatch_spec.rb
git add lib/textus/verb_registry.rb spec/integration/surface/mcp/catalog_dispatch_spec.rb
git commit -m "feat(verbs): expose uid, blame, audit, rule_list, published, doctor over MCP"
```

---

### Task 2: Rename `Dispatch::Contracts::MoveKey` → `MvKey` for naming consistency

**Why:** Every other prefix/bulk contract in this family already abbreviates "move" to "mv" (`DataMv`, `KeyMvPrefix`) to match the wire-facing verb symbols (`key_mv`, `data_mv`, `key_mv_prefix`). `MoveKey` is the one contract class spelling the word out, which reads as accidental drift to anyone scanning `contracts.rb` top-to-bottom. This is an internal Ruby class rename only — the wire verb name (`key_mv`) and CLI path (`key mv`) do not change, so there is no consumer-facing break.

**Files:**
- Modify: `lib/textus/dispatch/contracts.rb:12`
- Modify: `lib/textus/verb_registry.rb:67`
- Modify: `lib/textus/dispatch/middleware/audit_index.rb:15`
- Modify: `lib/textus/use_cases/write/move_key.rb:5`
- Test: existing suites (no new spec file needed — this is a pure rename with full existing coverage)

- [ ] **Step 1: Confirm current coverage exists (no new test needed)**

Run: `bundle exec rspec -e "key mv" -e "key_mv"`
Expected: PASS (existing `key_mv` behavior specs establish the safety net for this rename)

- [ ] **Step 2: Rename the contract class**

In `lib/textus/dispatch/contracts.rb`, change:

```ruby
      MoveKey = Data.define(:old_key, :new_key, :if_etag, :dry_run)
```

to:

```ruby
      MvKey = Data.define(:old_key, :new_key, :if_etag, :dry_run)
```

- [ ] **Step 3: Update the three call sites**

In `lib/textus/verb_registry.rb`, change:

```ruby
      key_mv: Dispatch::Contracts::MoveKey,
```

to:

```ruby
      key_mv: Dispatch::Contracts::MvKey,
```

In `lib/textus/dispatch/middleware/audit_index.rb`, change:

```ruby
          Contracts::MoveKey,
```

to:

```ruby
          Contracts::MvKey,
```

In `lib/textus/use_cases/write/move_key.rb`, change:

```ruby
        HANDLES = Dispatch::Contracts::MoveKey
```

to:

```ruby
        HANDLES = Dispatch::Contracts::MvKey
```

(Leave the enclosing Ruby module name `UseCases::Write::MoveKey` and the file name `move_key.rb` as-is — this rename is scoped to the wire-contract class only, not the use-case module that implements it.)

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rspec`
Expected: all PASS (a stale reference to `Contracts::MoveKey` anywhere would raise `NameError` at boot, since `HandlerResolver.eager_load!` requires every use-case file)

- [ ] **Step 5: Grep for any missed reference**

Run: `grep -rn "Contracts::MoveKey" lib/ spec/`
Expected: no output

- [ ] **Step 6: Commit**

```bash
bundle exec rubocop lib/textus/dispatch/contracts.rb lib/textus/verb_registry.rb lib/textus/dispatch/middleware/audit_index.rb lib/textus/use_cases/write/move_key.rb
git add lib/textus/dispatch/contracts.rb lib/textus/verb_registry.rb lib/textus/dispatch/middleware/audit_index.rb lib/textus/use_cases/write/move_key.rb
git commit -m "refactor(contracts): rename MoveKey to MvKey for naming consistency with DataMv/KeyMvPrefix"
```

---

### Task 3: Split the `jobs` verb into `jobs_list` / `jobs_retry` / `jobs_purge`

**Why:** `jobs` today is one verb that both lists jobs (read) and mutates queue state via an untyped `action: "retry"|"purge"` string (write) — the one place in the registry where a single verb's `category` (`:maintenance`) doesn't tell you whether a call is safe to retry or has side effects. Splitting it also gives `jobs` the same multi-word-verb → auto-derived-CLI-group treatment already used for `key_*` (`Group::Key`) and `rule_*` (`Group::Rule`), so `textus jobs list|retry|purge` becomes structurally consistent with `textus key delete|mv|mv-prefix|delete-prefix|uid`. This is a breaking CLI/MCP change (`jobs` the bare verb goes away) — acceptable per this project's current fast-dev, breaking-changes-OK posture.

**Files:**
- Create: `lib/textus/use_cases/ops/jobs_list.rb`
- Create: `lib/textus/use_cases/ops/jobs_retry.rb`
- Create: `lib/textus/use_cases/ops/jobs_purge.rb`
- Delete: `lib/textus/use_cases/ops/jobs_action.rb`
- Modify: `lib/textus/dispatch/contracts.rb` (replace `JobsAction` with three contracts)
- Modify: `lib/textus/verb_registry.rb` (replace the `jobs` registration with three registrations; update `VERB_TO_CONTRACT` and `OPS_VERBS`)
- Modify: `lib/textus/surface/cli.rb` (help text)
- Modify: `spec/conformance/surface/cli/contract_spec.rb` (verb table + group subcommand table)
- Test: `spec/integration/use_cases/ops/jobs_spec.rb` (new)

- [ ] **Step 1: Write the failing use-case tests**

Create `spec/integration/use_cases/ops/jobs_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe "jobs_list / jobs_retry / jobs_purge use cases" do
  include_context "textus_store_fixture"

  let(:manifest_yaml) do
    <<~YAML
      version: textus/4
      lanes:
        - { name: knowledge, kind: canon }
      entries:
        - { key: knowledge.note, path: knowledge/note.md, lane: knowledge, owner: human:self, kind: leaf }
    YAML
  end

  before do
    FileUtils.mkdir_p(File.join(root, "data/knowledge"))
    FileUtils.mkdir_p(File.join(root, "schemas"))
    File.write(File.join(root, "manifest.yaml"), manifest_yaml)
    FileUtils.mkdir_p(audit_dir_path(root))
    File.write(audit_log_path(root), "")
  end

  let(:store) { Textus::Store.new(root) }
  let(:queue) { Textus::Store::Jobs::Queue.new(store: store.job_store) }

  it "jobs_list returns queued job ids for a state without mutating anything" do
    store.enqueue(type: "materialize", args: { "key" => "knowledge.note" })
    result = store.jobs_list(state: "ready")
    expect(result["jobs"]).to be_an(Array)
    expect(result["jobs"].size).to eq(1)
  end

  it "jobs_retry re-queues a dead-lettered job by id" do
    # NOTE (fixed during quality verification): Queue#list returns an array of
    # job-id strings, not hashes — an earlier draft of this test called
    # `.first["id"]` on that string (String#[] with a substring argument),
    # which silently returned nil and never exercised a real retry. Build an
    # actually dead-lettered job instead: max_attempts: 1 + one queue.fail
    # call moves it straight to "failed".
    job = Textus::Store::Jobs::Queue::Job.new(
      type: "materialize", args: { "key" => "knowledge.note" }, role: "automation", max_attempts: 1,
    )
    queue.enqueue(job)
    leased = queue.lease(worker_id: "spec-worker", lease_ttl: 5)
    queue.fail(leased, error: "boom") # attempts (1) >= max_attempts (1): dead-lettered
    expect(store.jobs_list(state: "failed")["jobs"]).to eq([job.id])

    result = store.jobs_retry(job_id: job.id)

    expect(result["ok"]).to be(true)
    expect(store.jobs_list(state: "ready")["jobs"]).to eq([job.id])
    expect(store.jobs_list(state: "failed")["jobs"]).to eq([])
  end

  it "jobs_purge removes every job in a state" do
    store.enqueue(type: "materialize", args: { "key" => "knowledge.note" })
    result = store.jobs_purge(state: "ready")
    expect(result["ok"]).to be(true)
    expect(store.jobs_list(state: "ready")["jobs"]).to eq([])
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/integration/use_cases/ops/jobs_spec.rb`
Expected: FAIL with `NoMethodError: unknown verb: jobs_list` (and similarly for `jobs_retry`/`jobs_purge`)

- [ ] **Step 3: Replace the `JobsAction` contract with three contracts**

In `lib/textus/dispatch/contracts.rb`, change:

```ruby
      JobsAction = Data.define(:state, :action, :job_id)
```

to:

```ruby
      JobsList = Data.define(:state)

      JobsRetry = Data.define(:job_id)

      JobsPurge = Data.define(:state)
```

- [ ] **Step 4: Replace the `jobs_action.rb` use case with three focused use cases**

Delete `lib/textus/use_cases/ops/jobs_action.rb`.

Create `lib/textus/use_cases/ops/jobs_list.rb`:

```ruby
# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module JobsList
        HANDLES = Dispatch::Contracts::JobsList
        NEEDS = %i[job_store].freeze

        def self.call(command, _call, deps)
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true,
                                "state" => command.state, "jobs" => queue.list(command.state))
        end
      end
    end
  end
end
```

Create `lib/textus/use_cases/ops/jobs_retry.rb`:

```ruby
# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module JobsRetry
        HANDLES = Dispatch::Contracts::JobsRetry
        NEEDS = %i[job_store].freeze

        def self.call(command, _call, deps)
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          queue.retry_failed(command.job_id)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true, "job_id" => command.job_id)
        end
      end
    end
  end
end
```

Create `lib/textus/use_cases/ops/jobs_purge.rb`:

```ruby
# frozen_string_literal: true

module Textus
  module UseCases
    module Ops
      module JobsPurge
        HANDLES = Dispatch::Contracts::JobsPurge
        NEEDS = %i[job_store].freeze

        def self.call(command, _call, deps)
          queue = Textus::Store::Jobs::Queue.new(store: deps.job_store)
          queue.purge(command.state)
          Value::Result.success("protocol" => Textus::PROTOCOL, "ok" => true,
                                "state" => command.state, "jobs" => queue.list(command.state))
        end
      end
    end
  end
end
```

- [ ] **Step 5: Replace the `jobs` registration with three registrations**

In `lib/textus/verb_registry.rb`, remove `jobs: Dispatch::Contracts::JobsAction,` from `VERB_TO_CONTRACT` and replace with:

```ruby
      jobs_list: Dispatch::Contracts::JobsList,
      jobs_retry: Dispatch::Contracts::JobsRetry,
      jobs_purge: Dispatch::Contracts::JobsPurge,
```

Change `OPS_VERBS` from:

```ruby
    OPS_VERBS = %i[
      boot drain doctor pulse jobs enqueue data_mv
      key_mv_prefix key_delete_prefix published
    ].freeze
```

to:

```ruby
    OPS_VERBS = %i[
      boot drain doctor pulse jobs_list jobs_retry jobs_purge enqueue data_mv
      key_mv_prefix key_delete_prefix published
    ].freeze
```

Replace the `# ── jobs ──` registration block:

```ruby
    # ── jobs ─────────────────────────────────────────────
    register VerbSpec.new(
      :jobs, "List queued jobs by state; retry a dead-lettered job or purge.",
      [ArgSpec.arg(name: :state, default: "ready",
                   description: "ready|leased|done|failed"),
       ArgSpec.arg(name: :action, description: "retry|purge (optional)"),
       ArgSpec.arg(name: :job_id, description: "job id (required for action=retry)")],
      %i[cli mcp], { default: identity }, "jobs", nil, :maintenance
    )
```

with three registrations:

```ruby
    # ── jobs_list ────────────────────────────────────────
    register VerbSpec.new(
      :jobs_list, "List queued jobs by state.",
      [ArgSpec.arg(name: :state, default: "ready",
                   description: "ready|leased|done|failed")],
      %i[cli mcp], { default: identity }, "jobs list", nil, :read
    )

    # ── jobs_retry ───────────────────────────────────────
    register VerbSpec.new(
      :jobs_retry, "Re-queue a dead-lettered job by id.",
      [ArgSpec.arg(name: :job_id, required: true, positional: true, description: "job id to retry")],
      %i[cli mcp], { default: identity }, "jobs retry", nil, :write
    )

    # ── jobs_purge ───────────────────────────────────────
    register VerbSpec.new(
      :jobs_purge, "Delete every job in a state.",
      [ArgSpec.arg(name: :state, required: true, positional: true, description: "ready|leased|done|failed")],
      %i[cli mcp], { default: identity }, "jobs purge", nil, :write
    )
```

- [ ] **Step 6: Run the use-case tests to verify they pass**

Run: `bundle exec rspec spec/integration/use_cases/ops/jobs_spec.rb`
Expected: all PASS

- [ ] **Step 7: Update the CLI help text**

In `lib/textus/surface/cli.rb`, in `print_help`, change:

```ruby
            textus drain [PREFIX] --as=ROLE
            textus watch
            textus jobs
```

to:

```ruby
            textus drain [PREFIX] --as=ROLE
            textus watch
            textus jobs {list,retry,purge}
```

- [ ] **Step 8: Update the CLI conformance fixture table**

In `spec/conformance/surface/cli/contract_spec.rb`, change:

```ruby
      "jobs" => Textus::Surface::CLI::Verb::GenJobs,
```

to:

```ruby
      "jobs" => Textus::Surface::CLI::Group::Jobs,
```

Then, in the same file, the existing `"group subcommand tables are auto-derived from parent_group"` example already asserts `Group::Key`, `Group::Rule`, `Group::Data`, and `Group::Schema` and sits right at this repo's `RSpec/ExampleLength` ceiling (25 lines, per `.rubocop.yml`). Rather than push it over that ratchet, add the `Jobs` assertion as its own example immediately after it:

```ruby
  it "the jobs group subcommand table is auto-derived from parent_group" do
    expect(Textus::Surface::CLI::Group::Jobs.subcommands).to eq(
      "list" => Textus::Surface::CLI::Verb::GenJobsList,
      "purge" => Textus::Surface::CLI::Verb::GenJobsPurge,
      "retry" => Textus::Surface::CLI::Verb::GenJobsRetry,
    )
  end
```

- [ ] **Step 9: Run the CLI conformance suite**

Run: `bundle exec rspec spec/conformance/surface/cli/contract_spec.rb`
Expected: all PASS

- [ ] **Step 10: Grep for any other reference to the old bare `jobs` verb**

Run: `grep -rn '"jobs"\|:jobs\b\|Verb::GenJobs\b\|Contracts::JobsAction\|JobsAction' lib/ spec/ docs/reference docs/how-to 2>/dev/null`
Expected: no output (aside from this plan file and unrelated matches like `"jobs_list"`)

- [ ] **Step 11: Run the full suite and commit**

```bash
bundle exec rspec
bundle exec rubocop lib/textus/dispatch/contracts.rb lib/textus/verb_registry.rb lib/textus/surface/cli.rb lib/textus/use_cases/ops/jobs_list.rb lib/textus/use_cases/ops/jobs_retry.rb lib/textus/use_cases/ops/jobs_purge.rb spec/integration/use_cases/ops/jobs_spec.rb spec/conformance/surface/cli/contract_spec.rb
git add lib/textus/dispatch/contracts.rb lib/textus/verb_registry.rb lib/textus/surface/cli.rb \
        lib/textus/use_cases/ops/jobs_list.rb lib/textus/use_cases/ops/jobs_retry.rb lib/textus/use_cases/ops/jobs_purge.rb \
        spec/integration/use_cases/ops/jobs_spec.rb spec/conformance/surface/cli/contract_spec.rb
git rm lib/textus/use_cases/ops/jobs_action.rb
git commit -m "refactor(jobs): split jobs into jobs_list/jobs_retry/jobs_purge, matching key_*/rule_* group convention"
```

---

### Task 4: Preserve typed errors through `Value::Result.extract`, and fix the dead `Textus::CursorExpired` path

**Why:** `Result.extract` always re-raises failures as a generic `Textus::ActionError` with `exit_code: 1`, regardless of what `code:` was passed to `Result.failure`. Concretely, `move_key.rb`, `enqueue_job.rb`, `ingest_entry.rb`, and others pass `:usage_error` as the code — semantically a `UsageError` (`exit_code: 2`) — but it always surfaces as `ActionError` (`exit_code: 1`). Worse: `audit_entries.rb`'s cursor-expiry check passes `:cursor_expired`, which is supposed to become `Textus::CursorExpired` — a class with a dedicated JSON-RPC error code (`-32002`) that both `MCP::Catalog#call` and `MCP::Server#dispatch` specifically rescue and re-raise unwrapped. Because that path always produces `ActionError` instead, **`Textus::CursorExpired` is never actually raised anywhere in the codebase today** — its JSON-RPC handling is dead code, and MCP agents calling `audit` with a stale `seq_since` get a generic tool error instead of the `-32002` signal ADR 0123's session-resilience contract depends on.

The fix adds an opt-in `Value::Result.from_error(err)` constructor that carries the real exception through, and updates `audit_entries.rb` to use it. Existing `Result.failure(code, message)` call sites are untouched — this is additive, not a behavior change for anyone not using the new path.

**Files:**
- Modify: `lib/textus/value/result.rb`
- Modify: `lib/textus/use_cases/read/audit_entries.rb`
- Test: `spec/unit/value/result_spec.rb` (new)
- Test: `spec/unit/use_cases/read/audit_entries_spec.rb` (new)

- [ ] **Step 1: Write the failing `Value::Result` unit tests**

Create `spec/unit/value/result_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Textus::Value::Result do
  describe ".from_error" do
    it "wraps a Textus::Error instance as a failed Result carrying the original exception" do
      err = Textus::UsageError.new("bad input", hint: "fix your input")
      result = described_class.from_error(err)

      expect(result.success?).to be(false)
      expect(result.error[:code]).to eq("usage")
      expect(result.error[:message]).to eq("bad input")
    end
  end

  describe ".extract" do
    it "raises the original exception type for a Result built with .from_error" do
      err = Textus::UsageError.new("bad input")
      result = described_class.from_error(err)

      expect { described_class.extract(result) }.to raise_error(Textus::UsageError, "bad input")
    end

    it "still raises a generic ActionError for a Result built with .failure (unchanged behavior)" do
      result = described_class.failure(:something_wrong, "it broke")

      expect { described_class.extract(result) }.to raise_error(Textus::ActionError, "it broke")
    end

    it "preserves the raised exception's exit_code" do
      err = Textus::UsageError.new("bad input")
      result = described_class.from_error(err)

      begin
        described_class.extract(result)
      rescue Textus::UsageError => e
        expect(e.exit_code).to eq(2)
      end
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec rspec spec/unit/value/result_spec.rb`
Expected: FAIL with `NoMethodError: undefined method 'from_error' for Textus::Value::Result:Class`

- [ ] **Step 3: Implement `Result.from_error` and update `Result.extract`**

Replace the full contents of `lib/textus/value/result.rb`:

```ruby
module Textus
  module Value
    # rubocop:disable Lint/ConstantDefinitionInBlock
    Result = Data.define(:ok, :value, :error) do
      def self.success(value) = new(ok: true, value: value, error: nil)

      def self.failure(code, message, details: {})
        new(ok: false, value: nil, error: { code: code, message: message, details: details })
      end

      # Wraps an already-constructed Textus::Error so .extract can re-raise the
      # exact type (and its exit_code/hint/JSONRPC behavior) instead of
      # collapsing every failure into a generic ActionError.
      def self.from_error(err)
        new(ok: false, value: nil, error: { code: err.code, message: err.message, details: err.details, exception: err })
      end

      def self.extract(result)
        case result
        when self
          if result.success?
            result.value
          else
            err = result.error
            raise err[:exception] if err[:exception]

            raise Textus::ActionError.new(err[:code] || :error, err[:message] || "action failed", details: err[:details] || {})
          end
        else
          result
        end
      end

      def success? = ok
      def failure? = !ok

      def unwrap
        raise Result::UnwrapError.new(error[:code], error[:message], details: error[:details]) unless ok

        value
      end

      class UnwrapError < StandardError
        attr_reader :code, :details

        def initialize(code, message, details: {})
          super(message)
          @code = code
          @details = details
        end
      end
    end
    # rubocop:enable Lint/ConstantDefinitionInBlock
  end
end
```

- [ ] **Step 4: Run the `Result` tests to verify they pass**

Run: `bundle exec rspec spec/unit/value/result_spec.rb`
Expected: all PASS

- [ ] **Step 5: Write the failing `audit_entries` cursor-expiry test**

Create `spec/unit/use_cases/read/audit_entries_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe Textus::UseCases::Read::AuditEntries do
  let(:audit_log) do
    Class.new do
      def min_available_seq = 20
      def scan(**) = []
    end.new
  end
  let(:deps) { Data.define(:manifest, :audit_log).new(manifest: nil, audit_log: audit_log) }
  let(:command) do
    Textus::Dispatch::Contracts::AuditEntries.new(
      key: nil, lane: nil, role: nil, verb: nil, since: nil,
      seq_since: 3, correlation_id: nil, limit: nil,
    )
  end

  it "returns a Result that raises the real Textus::CursorExpired when seq_since is below the retention window" do
    result = described_class.call(command, nil, deps)

    expect(result.success?).to be(false)
    expect { Textus::Value::Result.extract(result) }.to raise_error(Textus::CursorExpired) do |err|
      expect(err.requested).to eq(3)
      expect(err.min_available).to eq(20)
    end
  end

  it "returns a success Result of rows when seq_since is within the retention window" do
    command_ok = Textus::Dispatch::Contracts::AuditEntries.new(
      key: nil, lane: nil, role: nil, verb: nil, since: nil,
      seq_since: 25, correlation_id: nil, limit: nil,
    )
    result = described_class.call(command_ok, nil, deps)

    expect(result.success?).to be(true)
    expect(Textus::Value::Result.extract(result)).to eq([])
  end
end
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `bundle exec rspec spec/unit/use_cases/read/audit_entries_spec.rb`
Expected: FAIL — `Textus::Value::Result.extract(result)` raises `Textus::ActionError`, not `Textus::CursorExpired`

- [ ] **Step 7: Fix `audit_entries.rb` to raise the real error type**

In `lib/textus/use_cases/read/audit_entries.rb`, change:

```ruby
        def self.check_cursor_expiry(seq_since, deps)
          return unless seq_since

          min = deps.audit_log.min_available_seq
          return unless min && seq_since < min - 1

          Value::Result.failure(:cursor_expired, "requested seq #{seq_since} is below minimum available #{min}",
                                details: { requested: seq_since, min_available: min })
        end
```

to:

```ruby
        def self.check_cursor_expiry(seq_since, deps)
          return unless seq_since

          min = deps.audit_log.min_available_seq
          return unless min && seq_since < min - 1

          Value::Result.from_error(Textus::CursorExpired.new(requested: seq_since, min_available: min))
        end
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `bundle exec rspec spec/unit/use_cases/read/audit_entries_spec.rb`
Expected: all PASS

- [ ] **Step 9: Confirm the existing CLI cursor-expiry spec still passes**

Run: `bundle exec rspec spec/conformance/surface/cli/audit_seq_since_spec.rb`
Expected: all PASS (the existing assertion `stderr).to match(/cursor.*expired/i)` matches even more precisely now, since the real `CursorExpired#message` reads "audit cursor expired: ...")

- [ ] **Step 10: Add an MCP-level regression test proving the JSON-RPC code is now reachable**

This depends on Task 1 (audit must be MCP-exposed). Add to `spec/integration/surface/mcp/catalog_dispatch_spec.rb`, inside (or after) the `.call('audit', ...)` describe block added in Task 1:

```ruby
  describe ".call('audit', ...) with an expired cursor" do
    it "raises Textus::CursorExpired, not a generic ToolError, so the MCP server can emit JSONRPC -32002" do
      # NOTE (fixed during quality verification): stub the specific audit_log
      # instance the store already exposes, not allow_any_instance_of — this
      # repo's RSpec/AnyInstance cop bans the any-instance form, and stubbing
      # the real instance is just as direct here (Store#audit_log returns the
      # same object the pipeline dispatches against).
      allow(human_store.audit_log).to receive(:min_available_seq).and_return(20)

      expect do
        described_class.call("audit", store: human_store, args: { "seq_since" => 3 })
      end.to raise_error(Textus::CursorExpired)
    end
  end
```

- [ ] **Step 11: Run the full suite and commit**

```bash
bundle exec rspec
bundle exec rubocop lib/textus/value/result.rb lib/textus/use_cases/read/audit_entries.rb spec/unit/value/result_spec.rb spec/unit/use_cases/read/audit_entries_spec.rb spec/integration/surface/mcp/catalog_dispatch_spec.rb
git add lib/textus/value/result.rb lib/textus/use_cases/read/audit_entries.rb \
        spec/unit/value/result_spec.rb spec/unit/use_cases/read/audit_entries_spec.rb \
        spec/integration/surface/mcp/catalog_dispatch_spec.rb
git commit -m "fix(errors): Result.from_error preserves typed exceptions; audit cursor-expiry now raises real CursorExpired"
```

---

## Self-review notes (for whoever executes this plan)

- **Task ordering matters:** Task 1 must land before Task 4's Step 10 (the MCP-level `audit` regression test needs `audit` already exposed over MCP).
- **Task 3 is the highest-risk task** (verb rename, breaking CLI/MCP change). If you want a lower-risk subset of this plan, Tasks 1, 2, and 4 can ship independently and are strictly additive/internal.
- **Not in scope for this plan:** broader documentation sweeps (`docs/reference/*`, `CHANGELOG.md` entries, ADR authoring). If this work should be recorded as a decision per this repo's ADR discipline, write that up separately per the `documentation-and-adrs` skill after these tasks land — this plan is implementation only.

---

## Post-implementation verification notes (2026-07-02)

This plan was executed, then re-verified against the actual diff (full suite green is not sufficient evidence on its own — a weak assertion can pass without testing anything). Findings and fixes, all within this plan's existing scope — nothing new was introduced:

1. **False-positive test (Task 3):** the original `jobs_retry` test read the job id via `store.jobs_list(state: "ready")["jobs"].first["id"]`. `Queue#list` returns an array of plain ID strings, not hashes, so `.first["id"]` (String#[] with a substring arg) silently returned `nil`. `jobs_retry` unconditionally returns `"ok" => true` regardless of whether any row matched, so the test passed without ever exercising a retry. Fixed as shown above — build a genuinely dead-lettered job via `Queue::Job.new(max_attempts: 1)` + `queue.fail`, and assert the actual state transition.
2. **Real latent bug surfaced by Task 1:** exposing `doctor` over MCP triggered `NoMethodError: undefined method 'dispatch' for nil` in `Doctor::Check::ProposalTargets`. Root cause: `Dispatch::HandlerResolver.build` snapshots `NEEDS` deps at build time, and `DoctorStore`'s `NEEDS` includes `:pipeline` — but the container passed to that first build (`partial` in `Store::Builder#call`) always has `pipeline: nil` (the pipeline doesn't exist yet at that point). Every doctor check that dispatches a sub-verb (like `ProposalTargets` calling `list`/`get`) was silently broken before Task 1 too — it just never fired because none of the CLI-only doctor specs exercised a pending-proposal fixture. Fixed in `lib/textus/store/builder.rb` by building the registry twice: once against `partial` to get a working interim pipeline, then wiring that into the container and rebuilding the registry so `:pipeline` resolves to a real value. (An earlier draft of this fix worked but left a stray `puts "DEBUG: ..."` in `doctor_store.rb`, an unused `pipeline_present?` method on `Infrastructure`, trailing whitespace, and redundant kwargs in `builder.rb` — all removed; `doctor_store.rb` and `infrastructure.rb` end up byte-identical to their pre-plan state, only `builder.rb` carries the real fix.)
3. **Style regressions caught by rubocop, not by the test suite:** a leading extra space + trailing blank line inside `AuditIndex::INDEXED_CONTRACTS` from the `MvKey` rename; `Metrics/ModuleLength`'s max (350, a comment-pinned ratchet tied to `VerbRegistry`'s prior 313-line count) needed bumping to 380 with an updated comment (371 lines) rather than being silently exceeded; the CLI conformance suite's `"group subcommand tables..."` example would have exceeded `RSpec/ExampleLength`'s 25-line ratchet (a value this repo's own `.rubocop.yml` comment says is deliberately not meant to be loosened) — split into its own example instead, as reflected in Task 3 Step 8 above; trailing commas and `allow_any_instance_of` (banned by `RSpec/AnyInstance`) in the new specs.

Final state: `bundle exec rspec` → 1433 examples, 0 failures, 1 pre-existing pending; `bundle exec rubocop` on every touched file → clean except one pre-existing, unrelated `Lint/UnusedMethodArgument` on `AuditIndex#call`'s `container:` param (confirmed present on `HEAD` before this work).
