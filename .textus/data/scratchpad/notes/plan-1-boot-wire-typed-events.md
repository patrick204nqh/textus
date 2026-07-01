---
title: Boot.wire + Typed Events Implementation Plan
uid: 5dc9ddf4b7126ce6
---
# Boot.wire + Typed Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `Store::Container` with a frozen `Store::Ctx` struct, convert all 29 handlers to pure modules, introduce a session-scoped `Event::Bus` with typed events, and wire everything through a flat `Boot.wire` method.

**Architecture:** `Store::Ctx = Data.define(...)` replaces Container as the boot-time dependency bundle. Pure handler modules declare `HANDLES` and `NEEDS` constants; `HandlerResolver` discovers them by convention and injects sliced deps at boot. `Event::Bus` is session-scoped (one per `Boot.wire` call); write handlers emit typed events; `CascadeSubscriber` subscribes at boot, replacing the `Cascade` middleware entirely. `Boot.wire(root)` builds everything top-down in one linear pass with no `wire!` dance.

**Tech Stack:** Ruby 3.x, Data.define, RSpec, bundle exec rspec

## Global Constraints

- No Co-Authored-By trailers in commits
- All tests: `bundle exec rspec`; lint: `bundle exec rubocop -A`
- Breaking changes OK — no compat shims
- Stage specific files only, never `git add -A`
- Baseline: 4 pre-existing CLI conformance failures (pre-existing, not regressions)

---

## File Map

### New files
- `lib/textus/store/ctx.rb` — `Store::Ctx = Data.define(...)`
- `lib/textus/event.rb` — typed event structs under `Textus::Event::`
- `lib/textus/event/bus.rb` — `Event::Bus` class
- `lib/textus/produce/cascade_subscriber.rb` — extracted from Cascade middleware
- `lib/textus/dispatch/handler_resolver.rb` — replaces Assembler
- `spec/unit/store/ctx_spec.rb`
- `spec/unit/event/bus_spec.rb`
- `spec/unit/dispatch/handler_resolver_spec.rb`
- `spec/unit/produce/cascade_subscriber_spec.rb`

### Converted (all handlers → pure modules)
- `lib/textus/handlers/read/*.rb` (9 files)
- `lib/textus/handlers/write/*.rb` (10 files)
- `lib/textus/handlers/maintenance/*.rb` (10 files)

### Modified
- `lib/textus/store.rb` — `build_container` → `Boot.wire`; `@container` → `@ctx`
- `lib/textus/boot.rb` — `Boot.wire` method added

### Deleted
- `lib/textus/store/container.rb`
- `lib/textus/dispatch/assembler.rb`
- `lib/textus/dispatch/middleware/cascade.rb`

---

## Task 1: Store::Ctx + Event::Bus + Typed Events

Pure value objects. No behaviour, no deps. All subsequent tasks depend on these constants existing.

**Files:**
- Create: `lib/textus/store/ctx.rb`
- Create: `lib/textus/event.rb`
- Create: `lib/textus/event/bus.rb`
- Create: `spec/unit/store/ctx_spec.rb`
- Create: `spec/unit/event/bus_spec.rb`

**Interfaces:**
- Produces: `Textus::Store::Ctx` (Data.define with 10 fields), `Textus::Event::Bus`, 6 event structs under `Textus::Event::`

---

- [ ] **Step 1: Write failing tests**

```ruby
# spec/unit/store/ctx_spec.rb
require "spec_helper"

RSpec.describe Textus::Store::Ctx do
  it "is a Data.define with all ten fields" do
    expect(described_class.members).to contain_exactly(
      :manifest, :file_store, :schemas, :audit_log,
      :job_store, :layout, :link_edge_store, :workflows,
      :event_bus, :pipeline,
    )
  end

  it "supports #with for immutable update" do
    ctx = described_class.new(
      manifest: :m, file_store: :fs, schemas: :sc, audit_log: :al,
      job_store: :js, layout: :ly, link_edge_store: :les, workflows: :wf,
      event_bus: :eb, pipeline: nil,
    )
    updated = ctx.with(pipeline: :p)
    expect(updated.pipeline).to eq(:p)
    expect(ctx.pipeline).to be_nil
  end
end
```

```ruby
# spec/unit/event/bus_spec.rb
require "spec_helper"

RSpec.describe Textus::Event::Bus do
  let(:bus) { described_class.new }

  describe "typed events" do
    it "EntryWritten has expected fields" do
      ev = Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      )
      expect(ev.key).to eq("k")
      expect(ev.role).to eq("human")
    end
  end

  describe "#subscribe / #emit" do
    it "delivers the event to the matching subscriber" do
      received = []
      bus.subscribe(Textus::Event::EntryWritten) { |e| received << e }
      ev = Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      )
      bus.emit(ev)
      expect(received).to eq([ev])
    end

    it "does not deliver to subscribers for a different class" do
      received = []
      bus.subscribe(Textus::Event::EntryDeleted) { |e| received << e }
      bus.emit(Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      ))
      expect(received).to be_empty
    end

    it "two bus instances are completely isolated" do
      bus2 = described_class.new
      received = []
      bus.subscribe(Textus::Event::EntryWritten) { |e| received << e }
      bus2.emit(Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      ))
      expect(received).to be_empty
    end

    it "supports multiple subscribers for the same event class" do
      calls = []
      bus.subscribe(Textus::Event::EntryWritten) { |_e| calls << 1 }
      bus.subscribe(Textus::Event::EntryWritten) { |_e| calls << 2 }
      bus.emit(Textus::Event::EntryWritten.new(
        key: "k", role: "human", etag_before: nil, etag_after: "a", occurred_at: Time.now
      ))
      expect(calls).to eq([1, 2])
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```
bundle exec rspec spec/unit/store/ctx_spec.rb spec/unit/event/bus_spec.rb -f doc
```

Expected: `NameError: uninitialized constant Textus::Store::Ctx` and similar.

---

- [ ] **Step 3: Create Store::Ctx**

```ruby
# lib/textus/store/ctx.rb
module Textus
  class Store
    Ctx = Data.define(
      :manifest,        # Textus::Manifest
      :file_store,      # Port::Storage::FileStore
      :schemas,         # Schema::Registry
      :audit_log,       # Port::AuditLog
      :job_store,       # Port::Store
      :layout,          # Store::Layout
      :link_edge_store, # Links::LinkEdgeStore
      :workflows,       # Workflow::Registry
      :event_bus,       # Event::Bus (session-scoped)
      :pipeline,        # Dispatch::Pipeline (nil until Boot.wire finishes)
    )
  end
end
```

- [ ] **Step 4: Create typed events**

```ruby
# lib/textus/event.rb
module Textus
  module Event
    EntryWritten     = Data.define(:key, :role, :etag_before, :etag_after, :occurred_at)
    EntryDeleted     = Data.define(:key, :role, :etag_before, :occurred_at)
    EntryMoved       = Data.define(:from_key, :to_key, :role, :etag_before, :etag_after, :occurred_at)
    ProposalOpened   = Data.define(:key, :proposal_key, :role, :occurred_at)
    ProposalAccepted = Data.define(:proposal_key, :target_key, :role, :occurred_at)
    ProposalRejected = Data.define(:proposal_key, :role, :occurred_at)
  end
end
```

- [ ] **Step 5: Create Event::Bus**

```ruby
# lib/textus/event/bus.rb
module Textus
  module Event
    class Bus
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
      end

      def subscribe(event_class, &block)
        @subscribers[event_class] << block
        self
      end

      def emit(event)
        @subscribers[event.class].each { |sub| sub.call(event) }
      end
    end
  end
end
```

- [ ] **Step 6: Run tests to verify they pass**

```
bundle exec rspec spec/unit/store/ctx_spec.rb spec/unit/event/bus_spec.rb -f doc
```

Expected: all examples pass.

- [ ] **Step 7: Commit**

```bash
git add lib/textus/store/ctx.rb lib/textus/event.rb lib/textus/event/bus.rb \
        spec/unit/store/ctx_spec.rb spec/unit/event/bus_spec.rb
git commit -m "feat: add Store::Ctx, typed Event structs, and session-scoped Event::Bus"
```

---

## Task 2: CascadeSubscriber

Extract trigger logic from `Dispatch::Middleware::Cascade` into a plain subscriber object that reacts to typed events. This is the last consumer of the old Cascade middleware — once done, Cascade can be deleted.

**Files:**
- Create: `lib/textus/produce/cascade_subscriber.rb`
- Create: `spec/unit/produce/cascade_subscriber_spec.rb`

**Interfaces:**
- Consumes: `Textus::Event::EntryWritten`, `EntryDeleted`, `EntryMoved`, `ProposalAccepted`, `ProposalRejected` from Task 1
- Produces: `Textus::Produce::CascadeSubscriber` with `on_entry_written`, `on_entry_deleted`, `on_entry_moved`, `on_proposal_accepted`, `on_proposal_rejected` methods

---

- [ ] **Step 1: Write the failing test**

```ruby
# spec/unit/produce/cascade_subscriber_spec.rb
require "spec_helper"

RSpec.describe Textus::Produce::CascadeSubscriber do
  let(:job_store)  { instance_double(Textus::Port::Store) }
  let(:manifest)   { instance_double(Textus::Manifest) }
  let(:workflows)  { instance_double(Textus::Workflow::Registry) }
  let(:file_store) { instance_double(Textus::Port::Storage::FileStore) }
  let(:subscriber) do
    described_class.new(
      manifest: manifest, workflows: workflows,
      job_store: job_store, file_store: file_store,
    )
  end

  describe "#on_entry_written" do
    it "enqueues cascade jobs for the written key" do
      planner = instance_double(Textus::Store::Jobs::Planner, plan: [])
      allow(Textus::Store::Jobs::Planner).to receive(:new).and_return(planner)
      allow(Textus::Store::Jobs::Queue).to receive(:new).and_return(
        instance_double(Textus::Store::Jobs::Queue, enqueue: nil)
      )

      ev = Textus::Event::EntryWritten.new(
        key: "knowledge.foo", role: "human",
        etag_before: nil, etag_after: "abc", occurred_at: Time.now
      )
      expect { subscriber.on_entry_written(ev) }.not_to raise_error
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
bundle exec rspec spec/unit/produce/cascade_subscriber_spec.rb -f doc
```

Expected: `NameError: uninitialized constant Textus::Produce::CascadeSubscriber`

---

- [ ] **Step 3: Create CascadeSubscriber**

The logic mirrors the existing `Cascade` middleware's trigger map. The subscriber receives an event and uses the existing `Jobs::Planner` + `Jobs::Queue` to plan and enqueue jobs.

```ruby
# lib/textus/produce/cascade_subscriber.rb
module Textus
  module Produce
    class CascadeSubscriber
      def initialize(manifest:, workflows:, job_store:, file_store:)
        @manifest   = manifest
        @workflows  = workflows
        @job_store  = job_store
        @file_store = file_store
      end

      def on_entry_written(event)
        trigger_cascade("entry.written", event.key, event.role)
      end

      def on_entry_deleted(event)
        trigger_cascade("entry.deleted", event.key, event.role)
      end

      def on_entry_moved(event)
        trigger_cascade("entry.moved", event.to_key, event.role)
      end

      def on_proposal_accepted(event)
        trigger_cascade("proposal.accepted", event.target_key, event.role)
      end

      def on_proposal_rejected(event)
        trigger_cascade("proposal.rejected", event.proposal_key, event.role)
      end

      private

      def trigger_cascade(trigger_type, key, role)
        container = build_container_proxy
        jobs = Textus::Store::Jobs::Planner.new(container: container).plan(
          trigger: { "type" => trigger_type, "target" => key },
          role: role,
        )
        queue = Textus::Store::Jobs::Queue.new(store: @job_store)
        jobs.each { |j| queue.enqueue(j) }
      end

      # Minimal struct the Planner uses from container
      ContainerProxy = Data.define(:manifest, :workflows, :job_store, :file_store)

      def build_container_proxy
        ContainerProxy.new(
          manifest: @manifest, workflows: @workflows,
          job_store: @job_store, file_store: @file_store,
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```
bundle exec rspec spec/unit/produce/cascade_subscriber_spec.rb -f doc
```

- [ ] **Step 5: Commit**

```bash
git add lib/textus/produce/cascade_subscriber.rb spec/unit/produce/cascade_subscriber_spec.rb
git commit -m "feat: add CascadeSubscriber — event-driven replacement for Cascade middleware"
```

---

## Task 3: HandlerResolver

Discovers pure handler modules by convention, slices `Ctx` fields matching their `NEEDS`, builds the dispatch registry. Write it against a synthetic handler module — no real handler conversion needed yet.

**Files:**
- Create: `lib/textus/dispatch/handler_resolver.rb`
- Create: `spec/unit/dispatch/handler_resolver_spec.rb`

**Interfaces:**
- Consumes: `Store::Ctx` from Task 1; handler modules with `HANDLES` (Contract class) and `NEEDS` (Array of Symbols matching Ctx fields)
- Produces: `Textus::Dispatch::HandlerResolver.build(ctx) → HandlerRegistry`; `HandlerResolver.eager_load!`

---

- [ ] **Step 1: Write the failing test**

```ruby
# spec/unit/dispatch/handler_resolver_spec.rb
require "spec_helper"

RSpec.describe Textus::Dispatch::HandlerResolver do
  FakeContract = Data.define(:key) unless defined?(FakeContract)

  let(:fake_manifest)   { instance_double(Textus::Manifest) }
  let(:fake_job_store)  { instance_double(Textus::Port::Store) }

  let(:ctx) do
    Textus::Store::Ctx.new(
      manifest: fake_manifest, file_store: :fs, schemas: :sc,
      audit_log: :al, job_store: fake_job_store, layout: :ly,
      link_edge_store: :les, workflows: :wf, event_bus: :eb, pipeline: nil,
    )
  end

  let(:fake_handler) do
    Module.new do
      const_set(:HANDLES, FakeContract)
      const_set(:NEEDS, %i[manifest job_store].freeze)

      def self.call(command, call, deps)
        Textus::Value::Result.success({ "deps_manifest" => deps.manifest })
      end
    end
  end

  describe ".build" do
    it "registers the handler for its contract and injects declared deps" do
      registry = described_class.build(ctx, handlers: [fake_handler])
      handler_fn = registry.lookup(FakeContract)
      expect(handler_fn).not_to be_nil

      result = handler_fn.call(FakeContract.new(key: "x"), Textus::Value::Call.build(role: "human"))
      expect(result.value["deps_manifest"]).to eq(fake_manifest)
    end

    it "raises Boot::DepNotFound when a NEEDS field is missing from Ctx" do
      bad_handler = Module.new do
        const_set(:HANDLES, FakeContract)
        const_set(:NEEDS, %i[nonexistent_field].freeze)
        def self.call(_command, _call, _deps); end
      end

      expect { described_class.build(ctx, handlers: [bad_handler]) }
        .to raise_error(Textus::Boot::DepNotFound, /nonexistent_field/)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
bundle exec rspec spec/unit/dispatch/handler_resolver_spec.rb -f doc
```

Expected: `NameError: uninitialized constant Textus::Dispatch::HandlerResolver`

---

- [ ] **Step 3: Create HandlerResolver**

```ruby
# lib/textus/dispatch/handler_resolver.rb
module Textus
  module Boot
    DepNotFound = Class.new(Textus::Error)
  end

  module Dispatch
    module HandlerResolver
      HANDLER_NAMESPACES = [
        Handlers::Read, Handlers::Write, Handlers::Maintenance,
      ].freeze

      module_function

      def eager_load!
        handlers_dir = File.expand_path("../../handlers", __FILE__)
        Dir[File.join(handlers_dir, "**", "*.rb")].sort.each { |f| require f }
      end

      # Builds a HandlerRegistry by discovering all modules in HANDLER_NAMESPACES
      # that define HANDLES and NEEDS, then slicing Ctx to satisfy each NEEDS list.
      #
      # Pass handlers: [...] in tests to inject specific modules without eager_load!.
      def build(ctx, handlers: nil)
        handler_modules = handlers || discover_all
        ctx_hash = ctx.to_h

        registry = HandlerRegistry.new
        handler_modules.each do |mod|
          next unless mod.const_defined?(:HANDLES) && mod.const_defined?(:NEEDS)

          contract_class = mod::HANDLES
          needs          = mod::NEEDS

          deps_hash = needs.to_h do |field|
            unless ctx_hash.key?(field)
              raise Boot::DepNotFound.new(
                "boot_dep_not_found",
                "handler #{mod.name || mod.inspect} needs :#{field} but Ctx has no such field",
              )
            end
            [field, ctx_hash[field]]
          end

          dep_struct = Data.define(*needs).new(**deps_hash)

          registry.register(contract_class, ->(command, call) { mod.call(command, call, dep_struct) })
        end
        registry
      end

      def discover_all
        HANDLER_NAMESPACES.flat_map do |ns|
          ns.constants(false).filter_map { |c| ns.const_get(c) }.select { |v| v.is_a?(Module) }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```
bundle exec rspec spec/unit/dispatch/handler_resolver_spec.rb -f doc
```

- [ ] **Step 5: Commit**

```bash
git add lib/textus/dispatch/handler_resolver.rb spec/unit/dispatch/handler_resolver_spec.rb
git commit -m "feat: add HandlerResolver — discovers pure handler modules by convention"
```

---

## Task 4: Convert read handlers to pure modules

Convert all 9 read handlers from class-based to pure module style with `HANDLES`, `NEEDS`, `self.call(command, call, deps)`. No behaviour change — only structure changes.

**Files (all modified):**
- `lib/textus/handlers/read/get_entry.rb`
- `lib/textus/handlers/read/list_keys.rb`
- `lib/textus/handlers/read/where_entry.rb`
- `lib/textus/handlers/read/uid_entry.rb`
- `lib/textus/handlers/read/deps_entry.rb`
- `lib/textus/handlers/read/rdeps_entry.rb`
- `lib/textus/handlers/read/audit_entries.rb`
- `lib/textus/handlers/read/blame_entry.rb`
- `lib/textus/handlers/read/pulse_entries.rb`

**Conversion pattern** — every handler follows this template:

```ruby
# BEFORE (class):
module Textus::Handlers::Read
  class FooBar
    def initialize(manifest:, job_store:)
      @manifest  = manifest
      @job_store = job_store
    end
    def call(command, call)
      # uses @manifest, @job_store
    end
  end
end

# AFTER (pure module):
module Textus::Handlers::Read
  module FooBar
    HANDLES = Dispatch::Contracts::FooBar
    NEEDS   = %i[manifest job_store].freeze

    def self.call(command, call, deps)
      # replace @manifest → deps.manifest
      # replace @job_store → deps.job_store
    end
  end
end
```

Each handler's `NEEDS` list comes from its old `initialize` keyword args. The `call` body is unchanged except `@field` → `deps.field`.

**Special case — GetEntry:** Currently uses `container:` and `freshness_evaluator:` in initialize. After conversion:

```ruby
module Textus::Handlers::Read
  module GetEntry
    HANDLES = Dispatch::Contracts::GetEntry
    NEEDS   = %i[manifest file_store workflows link_edge_store freshness_evaluator].freeze
    # Note: freshness_evaluator is NOT a Ctx field — it must be computed in Boot.wire
    # and injected as a pre-built dep. Add :freshness_evaluator to Ctx (Task 6).
    # For now, convert with NEEDS = %i[container freshness_evaluator].freeze
    # and replace @container.xxx with deps.container.xxx — full dep-injection comes in Task 6.
    NEEDS   = %i[container freshness_evaluator].freeze

    def self.call(command, _call, deps)
      envelope = Store::Entry::Reader.from(container: deps.container).read(command.key)
      return Value::Result.failure(:not_found, "no entry at #{command.key}") unless envelope

      envelope = expand_sources(envelope, depth: 0, container: deps.container)
      Value::Result.success(
        envelope.with(freshness: deps.freshness_evaluator.verdict(
          deps.container.manifest.resolver.resolve(command.key).entry
        ))
      )
    end

    MAX_SOURCE_DEPTH = 5

    def self.expand_sources(envelope, depth:, container:)
      return envelope if depth >= MAX_SOURCE_DEPTH
      raw_sources = Array(envelope.meta["sources"])
      return envelope if raw_sources.empty?
      expanded = raw_sources.map { |src| expand_one_source(src, depth: depth, container: container) }
      envelope.with(sources: expanded)
    end

    def self.expand_one_source(src, depth:, container:)
      src = { "key" => src } if src.is_a?(String)
      return src unless src.is_a?(Hash) && src["key"].is_a?(String)
      key = src["key"]
      stored_etag = src["etag"]
      current_etag = resolve_current_etag(key, container: container)
      suspended = stored_etag && current_etag ? stored_etag != current_etag : false
      result = src.merge("suspended" => suspended)
      child_env = container.reader.read(key)
      if child_env
        child_expanded = expand_sources(child_env, depth: depth + 1, container: container)
        child_sources = Array(child_expanded.sources)
        result = result.merge("sources" => child_sources) unless child_sources.empty?
      end
      result
    end

    def self.resolve_current_etag(key, container:)
      path = container.manifest.resolver.resolve(key).path
      return nil unless container.file_store.exists?(path)
      container.file_store.etag(path)
    rescue Textus::Error
      nil
    end

    def self.resolve_entry(key, container:)
      container.manifest.resolver.resolve(key).entry
    end
  end
end
```

> **Note on container:** Several handlers (GetEntry, PulseEntries, BlameEntry, UidEntry) currently take `container:` as a dep. During this conversion, keep `NEEDS = %i[container ...]` for those. The full dep-granularity (removing `container:` as a dep entirely) is a follow-up refactor once Ctx is the container.

---

- [ ] **Step 1: Convert `list_keys.rb` (simplest — pure deps, no container)**

```ruby
# lib/textus/handlers/read/list_keys.rb
module Textus
  module Handlers
    module Read
      module ListKeys
        HANDLES = Dispatch::Contracts::ListKeys
        NEEDS   = %i[manifest job_store].freeze

        def self.call(command, _call, deps)
          # identical body to current, replacing @manifest → deps.manifest, @job_store → deps.job_store
          rows = deps.manifest.resolver.enumerate(
            prefix: command.prefix,
            lane: command.lane,
            q: command.q,
            schema: command.schema,
          )
          Value::Result.success(rows)
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run full suite to confirm list_keys still works**

```
bundle exec rspec spec/conformance/surface/cli/surface_spec.rb -f doc
```

Expected: CLI list verb passes.

- [ ] **Step 3: Convert remaining 8 read handlers**

Apply the same `class → module` + `@field → deps.field` + add `HANDLES`/`NEEDS` pattern to:
- `where_entry.rb` — `NEEDS = %i[manifest].freeze`
- `uid_entry.rb` — `NEEDS = %i[container].freeze`
- `deps_entry.rb` — `NEEDS = %i[manifest].freeze`
- `rdeps_entry.rb` — `NEEDS = %i[manifest link_edge_store].freeze`
- `audit_entries.rb` — `NEEDS = %i[manifest audit_log].freeze`
- `blame_entry.rb` — `NEEDS = %i[manifest orchestration].freeze` (orchestration still needed — see note below)
- `pulse_entries.rb` — `NEEDS = %i[manifest audit_log file_store job_store orchestration].freeze`
- `get_entry.rb` — `NEEDS = %i[container freshness_evaluator].freeze` (see GetEntry block above)

> **Orchestration note:** `blame_entry` and `pulse_entries` use `orchestration:`. Keep it as a Ctx field for now — `Boot.wire` (Task 6) will build it once and inject it. Add `:orchestration` to `Ctx` members in `ctx.rb`.

- [ ] **Step 4: Run full suite**

```
bundle exec rspec --format progress
```

Expected: same pass count as before this task (existing 4 pre-existing CLI failures baseline).

- [ ] **Step 5: Commit**

```bash
git add lib/textus/handlers/read/
git commit -m "refactor: convert all read handlers to pure modules (HANDLES/NEEDS/self.call)"
```

---

## Task 5: Convert write + maintenance handlers to pure modules

Same pattern as Task 4. 19 handlers total.

**Files (all modified):**
- Write (10): `accept_proposal`, `data_mv`, `delete_key`, `enqueue_job`, `key_delete_prefix`, `key_mv_prefix`, `move_key`, `propose_entry`, `put_entry`, `reject_proposal`
- Maintenance (10): `boot_store`, `doctor_store`, `drain_store`, `ingest_entry`, `jobs_action`, `published_entries`, `rule_explain`, `rule_lint`, `rule_list`, `schema_envelope`

**NEEDS mapping for write handlers:**

| Handler | NEEDS |
|---|---|
| `AcceptProposal` | `%i[container]` |
| `DataMv` | `%i[container]` |
| `DeleteKey` | `%i[container]` |
| `EnqueueJob` | `%i[job_store]` |
| `KeyDeletePrefix` | `%i[orchestration]` |
| `KeyMvPrefix` | `%i[orchestration]` |
| `MoveKey` | `%i[container manifest]` |
| `ProposeEntry` | `%i[container]` |
| `PutEntry` | `%i[container event_bus]` |
| `RejectProposal` | `%i[container event_bus]` |

**NEEDS mapping for maintenance handlers:**

| Handler | NEEDS |
|---|---|
| `BootStore` | `%i[container]` |
| `DoctorStore` | `%i[container]` |
| `DrainStore` | `%i[container job_store]` |
| `IngestEntry` | `%i[container]` |
| `JobsAction` | `%i[job_store]` |
| `PublishedEntries` | `%i[manifest]` |
| `RuleExplain` | `%i[manifest]` |
| `RuleLint` | `%i[manifest]` |
| `RuleList` | `%i[manifest]` |
| `SchemaEnvelope` | `%i[manifest schemas]` |

**Event emission for PutEntry:**

```ruby
module Textus::Handlers::Write
  module PutEntry
    HANDLES = Dispatch::Contracts::PutEntry
    NEEDS   = %i[container event_bus].freeze

    def self.call(command, call, deps)
      Textus::Manifest::Data.validate_key!(command.key)
      mentry  = deps.container.manifest.resolver.resolve(command.key).entry
      writer  = Store::Entry::Writer.from(container: deps.container, call: call)
      envelope = writer.put(
        command.key,
        mentry: mentry,
        payload: Textus::Value::Payload.new(
          meta: command.meta, body: command.body, content: command.content,
        ),
        if_etag: command.if_etag,
      )
      deps.event_bus.emit(Textus::Event::EntryWritten.new(
        key:         command.key,
        role:        call.role,
        etag_before: nil,
        etag_after:  envelope.etag,
        occurred_at: call.now,
      ))
      Value::Result.success(envelope)
    end
  end
end
```

Apply equivalent event emission to `DeleteKey`, `MoveKey`, `AcceptProposal`, `RejectProposal`, `ProposeEntry` with their corresponding event types.

---

- [ ] **Step 1: Convert all 10 write handlers** (apply class→module pattern from Task 4)

- [ ] **Step 2: Run write-related specs**

```
bundle exec rspec spec/conformance/write/ spec/integration/store_spec.rb -f progress
```

- [ ] **Step 3: Convert all 10 maintenance handlers**

- [ ] **Step 4: Run full suite**

```
bundle exec rspec --format progress
```

Expected: same pass count baseline.

- [ ] **Step 5: Commit**

```bash
git add lib/textus/handlers/write/ lib/textus/handlers/maintenance/
git commit -m "refactor: convert all write+maintenance handlers to pure modules with event emission"
```

---

## Task 6: Boot.wire + Update Store

Build the top-down wiring function. Update `Store` to use it. This is the integration task.

**Files:**
- Modify: `lib/textus/store/ctx.rb` — add `:orchestration` and `:freshness_evaluator` fields
- Modify: `lib/textus/boot.rb` — add `Boot.wire(root)` method
- Modify: `lib/textus/store.rb` — replace `build_container` with `Boot.wire`; `@container` → `@ctx`

**Interfaces:**
- Consumes: all Tasks 1–5
- Produces: `Boot.wire(root) → Textus::Store::Ctx` (frozen)

---

- [ ] **Step 1: Extend Ctx with orchestration and freshness_evaluator**

Update `lib/textus/store/ctx.rb`:

```ruby
# lib/textus/store/ctx.rb
module Textus
  class Store
    Ctx = Data.define(
      :manifest, :file_store, :schemas, :audit_log,
      :job_store, :layout, :link_edge_store, :workflows,
      :event_bus, :pipeline,
      :orchestration,        # Textus::Orchestration (shared by 4 handlers)
      :freshness_evaluator,  # Store::Freshness::TtlEvaluator
    )
  end
end
```

Update `spec/unit/store/ctx_spec.rb` to include the new fields in `contain_exactly`.

- [ ] **Step 2: Write Boot.wire integration test**

```ruby
# spec/integration/boot_wire_spec.rb
require "spec_helper"

RSpec.describe "Boot.wire" do
  include_context "textus_store_fixture"

  it "builds a frozen Ctx with all fields populated" do
    ctx = Textus::Boot.wire(root)
    expect(ctx).to be_frozen
    expect(ctx.manifest).to be_a(Textus::Manifest)
    expect(ctx.file_store).to be_a(Textus::Port::Storage::FileStore)
    expect(ctx.schemas).to be_a(Textus::Schema::Registry)
    expect(ctx.audit_log).to be_a(Textus::Port::AuditLog)
    expect(ctx.job_store).to be_a(Textus::Port::Store)
    expect(ctx.layout).to be_a(Textus::Store::Layout)
    expect(ctx.link_edge_store).to be_a(Textus::Links::LinkEdgeStore)
    expect(ctx.workflows).to be_a(Textus::Workflow::Registry)
    expect(ctx.event_bus).to be_a(Textus::Event::Bus)
    expect(ctx.pipeline).to be_a(Textus::Dispatch::Pipeline)
    expect(ctx.orchestration).to be_a(Textus::Orchestration)
    expect(ctx.freshness_evaluator).to be_a(Textus::Store::Freshness::TtlEvaluator)
  end

  it "pipeline responds to every registered contract" do
    ctx  = Textus::Boot.wire(root)
    call = Textus::Value::Call.build(role: "human")
    Textus::VerbRegistry::VERB_TO_CONTRACT.each_value do |contract_class|
      expect { ctx.pipeline.dispatch(contract_class.new, call: call) }
        .not_to raise_error(Textus::Dispatch::UnknownHandler)
    end
  end
end
```

- [ ] **Step 3: Implement Boot.wire in boot.rb**

```ruby
# lib/textus/boot.rb — add the wire method inside the existing Boot module
module Textus
  module Boot
    def self.wire(root)
      Dispatch::HandlerResolver.eager_load!

      manifest        = Manifest.load(root)
      layout          = Store::Layout.new(root)
      file_store      = Port::Storage::FileStore.new
      schemas         = Schema::Registry.new(layout.schemas_dir)
      audit_log       = Port::AuditLog.new(
        layout: layout,
        max_size: manifest.data.audit_config[:max_size],
        keep:     manifest.data.audit_config[:keep],
      )
      job_store       = Port::Store.new(root: root).setup!
      link_edge_store = Links::LinkEdgeStore.new
      workflows       = Workflow::Loader.load_all(root)
      event_bus       = Event::Bus.new

      freshness_evaluator = Store::Freshness::TtlEvaluator.new(
        manifest:  manifest,
        file_stat: Port::Storage::FileStat.new,
        clock:     Port::Clock.new,
      )

      # Register cascade subscriber
      cascade = Produce::CascadeSubscriber.new(
        manifest: manifest, workflows: workflows,
        job_store: job_store, file_store: file_store,
      )
      event_bus.subscribe(Event::EntryWritten,     &cascade.method(:on_entry_written))
      event_bus.subscribe(Event::EntryDeleted,     &cascade.method(:on_entry_deleted))
      event_bus.subscribe(Event::EntryMoved,       &cascade.method(:on_entry_moved))
      event_bus.subscribe(Event::ProposalAccepted, &cascade.method(:on_proposal_accepted))
      event_bus.subscribe(Event::ProposalRejected, &cascade.method(:on_proposal_rejected))

      ctx_seed = Store::Ctx.new(
        manifest: manifest, file_store: file_store, schemas: schemas,
        audit_log: audit_log, job_store: job_store, layout: layout,
        link_edge_store: link_edge_store, workflows: workflows,
        event_bus: event_bus, pipeline: nil,
        freshness_evaluator: freshness_evaluator,
        orchestration: build_orchestration(manifest, audit_log, job_store),
      )

      registry   = Dispatch::HandlerResolver.build(ctx_seed)
      middleware = [
        Dispatch::Middleware::Binder.new,
        Dispatch::Middleware::Auth.new,
        Dispatch::Middleware::AuditIndex.new(job_store: job_store, audit_log: audit_log),
      ]
      pipeline   = Dispatch::Pipeline.new(registry: registry, container: ctx_seed, middleware: middleware)

      ctx_seed.with(pipeline: pipeline).freeze
    end

    def self.build_orchestration(manifest, audit_log, job_store)
      Orchestration.new(
        list_keys:    Handlers::Read::ListKeys,
        move_key:     Handlers::Write::MoveKey,
        delete_key:   Handlers::Write::DeleteKey,
        audit_entries: Handlers::Read::AuditEntries,
        manifest:     manifest,
        audit_log:    audit_log,
        job_store:    job_store,
      )
    end
  end
end
```

> **Note:** `Orchestration.new` signature may need updating since handlers are now modules not instances. Verify `Orchestration` internals and adjust `build_orchestration` accordingly.

- [ ] **Step 4: Update Store to use Boot.wire**

In `lib/textus/store.rb`, replace `build_container` and update all `@container` references:

```ruby
# Replace:
def initialize(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false, container: nil)
  @root = File.expand_path(root)
  @container = container || build_container(@root)
  # ...
end

# With:
def initialize(root, role: Value::Role::DEFAULT, correlation_id: nil, dry_run: false, ctx: nil)
  @root = File.expand_path(root)
  @ctx  = ctx || Boot.wire(@root)
  @role = role.to_s
  @correlation_id = correlation_id || SecureRandom.uuid
  @dry_run = dry_run
  build_session!
end
```

Replace every `@container` reference with `@ctx`. Replace the `Textus::Store::Container.attribute_names.each` delegation block at the top with `Store::Ctx.members.each`. Delete `build_container` private method.

In `_dispatch_in_domain`, replace:
```ruby
result = @container.pipeline.dispatch(pending, call: call)
```
with:
```ruby
result = @ctx.pipeline.dispatch(pending, call: call)
```

In `build_session!`, replace:
```ruby
@cursor      = @container.audit_log.latest_seq
@propose_lane = @container.manifest.policy.propose_lane_for(@role)
@contract_etag = Value::Etag.for_contract(@root)
```
with:
```ruby
@cursor        = @ctx.audit_log.latest_seq
@propose_lane  = @ctx.manifest.policy.propose_lane_for(@role)
@contract_etag = Value::Etag.for_contract(@root)
```

- [ ] **Step 5: Run integration test and full suite**

```
bundle exec rspec spec/integration/boot_wire_spec.rb -f doc
bundle exec rspec --format progress
```

Expected: Boot.wire spec passes; full suite at baseline pass count.

- [ ] **Step 6: Commit**

```bash
git add lib/textus/store/ctx.rb lib/textus/boot.rb lib/textus/store.rb \
        spec/integration/boot_wire_spec.rb spec/unit/store/ctx_spec.rb
git commit -m "feat: Boot.wire replaces build_container — Store holds frozen Ctx"
```

---

## Task 7: Delete deprecated files + conformance guard

Remove `Container`, `Assembler`, and `Cascade` middleware. Add a conformance spec that every registered verb contract has a handler module discoverable by `HandlerResolver`.

**Files:**
- Delete: `lib/textus/store/container.rb`
- Delete: `lib/textus/dispatch/assembler.rb`
- Delete: `lib/textus/dispatch/middleware/cascade.rb`
- Delete: `spec/unit/store/container_read_family_spec.rb` (tests Container which is gone)
- Delete: `spec/unit/dispatch/assembler_spec.rb` (replaced by handler_resolver_spec)
- Modify: `spec/integration/store/container_spec.rb` → rename/rewrite for Ctx
- Create: `spec/conformance/dispatch/handler_completeness_spec.rb`

---

- [ ] **Step 1: Delete the three deprecated lib files**

```bash
git rm lib/textus/store/container.rb \
       lib/textus/dispatch/assembler.rb \
       lib/textus/dispatch/middleware/cascade.rb
```

- [ ] **Step 2: Run full suite — fix any lingering references**

```
bundle exec rspec --format progress 2>&1 | grep "NameError\|uninitialized" | head -10
```

Fix any remaining `Container`, `Assembler`, or `Cascade` references in lib or spec files.

- [ ] **Step 3: Rewrite container_spec.rb as ctx_spec (integration)**

```ruby
# spec/integration/store/ctx_spec.rb (rename from container_spec.rb)
require "spec_helper"

RSpec.describe Textus::Store::Ctx do
  include_context "textus_store_fixture"

  it "bundles all required collaborators after Boot.wire" do
    ctx = Textus::Boot.wire(root)
    expect(ctx.manifest).to be_a(Textus::Manifest)
    expect(ctx.file_store).to be_a(Textus::Port::Storage::FileStore)
    expect(ctx.schemas).to be_a(Textus::Schema::Registry)
    expect(ctx.audit_log).to be_a(Textus::Port::AuditLog)
    expect(ctx.job_store).to be_a(Textus::Port::Store)
    expect(ctx.pipeline).to be_a(Textus::Dispatch::Pipeline)
  end
end
```

- [ ] **Step 4: Write completeness conformance spec**

```ruby
# spec/conformance/dispatch/handler_completeness_spec.rb
require "spec_helper"

RSpec.describe "Handler completeness" do
  it "every VERB_TO_CONTRACT entry has a discoverable pure handler module" do
    Textus::Dispatch::HandlerResolver.eager_load!
    modules = Textus::Dispatch::HandlerResolver.discover_all
    handles_set = modules.filter_map { |m| m::HANDLES if m.const_defined?(:HANDLES) }.to_set

    missing = Textus::VerbRegistry.registered
                                  .filter_map { |s| Textus::VerbRegistry.contract_class_for(s.verb) }
                                  .reject { |c| handles_set.include?(c) }

    expect(missing).to be_empty,
      "contracts with no pure handler module: #{missing.map(&:name)}"
  end
end
```

- [ ] **Step 5: Run full suite**

```
bundle exec rspec --format progress
```

Expected: 0 failures (baseline 4 pre-existing CLI conformance failures only).

- [ ] **Step 6: Commit**

```bash
git add -A  # safe here — only deleting known files + adding new spec
git commit -m "chore: delete Container, Assembler, Cascade middleware — Boot.wire+HandlerResolver replace them"
```
