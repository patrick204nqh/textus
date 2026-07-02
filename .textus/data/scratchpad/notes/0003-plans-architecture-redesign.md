---
title: Architecture Redesign Plan
uid: 52acce6ae1c53fe1
---
# Architecture Redesign — WriteStep Chain, HANDLER_MANIFEST, entry/ops/rule API

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three independent structural improvements: decompose `Entry::Writer#put` into a named step chain; replace `Container#build_pipeline`'s 80-line imperative registration with a declarative `HANDLER_MANIFEST`; and replace the 30 dynamically generated verb methods on `Store` with three noun-domain façade methods (`entry`, `ops`, `rule`).

**Architecture:** Task 1 is purely internal (no callers change). Task 2 is a Container refactor that deletes the registration loop without changing any public API. Task 3 is the only externally visible change: CLI runner gets one-line update; existing generated verb methods are removed.

**Tech Stack:** Ruby 3.x, Data.define, RSpec, bundle exec rspec

## Global Constraints

- No Co-Authored-By trailers in commits
- All tests run with `bundle exec rspec`; lint with `bundle exec rubocop`
- Breaking changes are acceptable — no compat shims
- Stage specific files only, never `git add -A`

---

## Task 1: WriteStep chain for Entry::Writer

Decompose `Writer#put`'s sequential local-variable code into named step modules, each a pure `step.call(ctx, deps) → WriteContext`, reducible over a `DEFAULT_PUT` constant. `delete` and `move` are not changed.

**Files:**
- Create: `lib/textus/store/entry/write_step.rb`
- Modify: `lib/textus/store/entry/writer.rb`
- Create: `spec/unit/store/entry/write_step_spec.rb`

**Interfaces:**
- Produces: `Textus::Store::Entry::WriteStep::WriteContext`, `WriteStep::WriteDeps`, `WriteStep::DEFAULT_PUT`
- `Writer#put` signature unchanged: `put(key, mentry:, payload:, if_etag: nil) → Envelope`

---

- [ ] **Step 1: Write the failing test**

```ruby
# spec/unit/store/entry/write_step_spec.rb
require "spec_helper"

RSpec.describe Textus::Store::Entry::WriteStep do
  let(:key) { "knowledge.demo" }
  let(:mentry) { instance_double("Textus::Manifest::Entry::Leaf", format: :markdown, lane: "knowledge", schema: nil) }
  let(:payload) { Textus::Value::Payload.new(meta: { "title" => "Demo" }, body: "hello", content: nil) }

  describe "WriteContext" do
    it "holds inputs and all step outputs as nil by default" do
      ctx = described_class::WriteContext.new(
        key: key, mentry: mentry, payload: payload, if_etag: nil,
        path: nil, existing_env: nil, meta: nil, content: nil,
        bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
        etag_before: nil, envelope: nil
      )
      expect(ctx.key).to eq(key)
      expect(ctx.path).to be_nil
      expect(ctx.envelope).to be_nil
    end

    it "supports immutable update via #with" do
      ctx = described_class::WriteContext.new(
        key: key, mentry: mentry, payload: payload, if_etag: nil,
        path: nil, existing_env: nil, meta: nil, content: nil,
        bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
        etag_before: nil, envelope: nil
      )
      updated = ctx.with(path: "/tmp/demo.md")
      expect(updated.path).to eq("/tmp/demo.md")
      expect(ctx.path).to be_nil
    end
  end

  describe "DEFAULT_PUT" do
    it "is an array of modules with .call" do
      described_class::DEFAULT_PUT.each do |step|
        expect(step).to respond_to(:call)
      end
    end

    it "contains exactly the expected steps in order" do
      names = described_class::DEFAULT_PUT.map(&:name).map { |n| n.split("::").last }
      expect(names).to eq(%w[
        ResolvePath ReadExisting InjectMeta Serialize
        EnforceNameMatch ValidateSchema ValidateRaw
        CheckEtag WriteBytes BuildEnvelope AppendAudit
      ])
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -f doc
```

Expected: `NameError: uninitialized constant Textus::Store::Entry::WriteStep`

---

- [ ] **Step 3: Create write_step.rb**

```ruby
# lib/textus/store/entry/write_step.rb
module Textus
  class Store
    module Entry
      module WriteStep
        WriteContext = Data.define(
          :key, :mentry, :payload, :if_etag,
          :path, :existing_env,
          :meta, :content,
          :bytes, :eff_meta, :eff_body, :eff_content,
          :etag_before, :envelope
        ) do
          def with(**attrs) = self.class.new(**to_h.merge(attrs))
        end

        WriteDeps = Data.define(
          :file_store, :manifest, :schemas, :audit_log, :call, :reader, :layout
        )

        module ResolvePath
          def self.call(ctx, deps)
            path = deps.manifest.resolver.resolve(ctx.key).path
            ctx.with(path:)
          end
        end

        module ReadExisting
          def self.call(ctx, deps)
            existing_env = deps.reader.read(ctx.key)
            ctx.with(existing_env:)
          end
        end

        module InjectMeta
          def self.call(ctx, deps)
            existing_meta = ctx.existing_env ? ctx.existing_env.meta : {}
            raw_meta = ctx.payload.meta || {}
            meta, content = Envelope::Meta.inject_all(
              raw_meta, ctx.payload.content, existing_meta,
              format: ctx.mentry.format,
              etag_for: method(:resolve_source_etag).curry.call(deps)
            )
            ctx.with(meta:, content:)
          end

          def self.resolve_source_etag(deps, key)
            path = deps.manifest.resolver.resolve(key).path
            return nil unless deps.file_store.exists?(path)

            Value::Etag.for_file(path)
          rescue Textus::Error
            nil
          end
        end

        module Serialize
          def self.call(ctx, _deps)
            bytes, eff_meta, eff_body, eff_content =
              Textus::Format.for(ctx.mentry.format).serialize_for_put(
                meta: ctx.meta, body: ctx.payload.body,
                content: ctx.content, path: ctx.path
              )
            ctx.with(bytes:, eff_meta:, eff_body:, eff_content:)
          end
        end

        module EnforceNameMatch
          def self.call(ctx, _deps)
            Textus::Format.for(ctx.mentry.format).enforce_name_match!(ctx.path, ctx.eff_meta)
            ctx
          end
        end

        module ValidateSchema
          def self.call(ctx, deps)
            schema = deps.schemas.fetch_or_nil(ctx.mentry.schema)
            if schema
              Format.for(ctx.mentry.format).validate_against(
                schema,
                { "_meta" => ctx.eff_meta, "content" => ctx.eff_content }
              )
            end
            ctx
          end
        end

        module ValidateRaw
          def self.call(ctx, _deps)
            Textus::Format.for(ctx.mentry.format).validate_raw_entry!(
              { "_meta" => ctx.eff_meta, "content" => ctx.eff_content },
              ctx.mentry.lane
            )
            ctx
          end
        end

        module CheckEtag
          def self.call(ctx, deps)
            etag_before = deps.file_store.exists?(ctx.path) ? deps.file_store.etag(ctx.path) : nil
            if ctx.if_etag && (etag_before != ctx.if_etag)
              raise EtagMismatch.new(ctx.key, ctx.if_etag, etag_before)
            end

            ctx.with(etag_before:)
          end
        end

        module WriteBytes
          def self.call(ctx, deps)
            deps.file_store.write(ctx.path, ctx.bytes)
            ctx
          end
        end

        module BuildEnvelope
          def self.call(ctx, _deps)
            envelope = Textus::Value::Envelope.build(
              key: ctx.key, mentry: ctx.mentry, path: ctx.path,
              meta: ctx.eff_meta, body: ctx.eff_body,
              etag: Value::Etag.for_bytes(ctx.bytes),
              content: ctx.eff_content
            )
            ctx.with(envelope:)
          end
        end

        module AppendAudit
          def self.call(ctx, deps)
            extras = deps.call.correlation_id ? { "correlation_id" => deps.call.correlation_id } : nil
            deps.audit_log.append(
              role: deps.call.role, verb: "put", key: ctx.key,
              etag_before: ctx.etag_before, etag_after: ctx.envelope.etag,
              extras:
            )
            ctx
          end
        end

        DEFAULT_PUT = [
          ResolvePath, ReadExisting, InjectMeta, Serialize,
          EnforceNameMatch, ValidateSchema, ValidateRaw,
          CheckEtag, WriteBytes, BuildEnvelope, AppendAudit
        ].freeze
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -f doc
```

Expected: all examples pass

---

- [ ] **Step 5: Require write_step from writer.rb and replace Writer#put**

Add `require_relative "write_step"` at the top of `lib/textus/store/entry/writer.rb`.

Replace the `put` method body (currently lines 38–58) with:

```ruby
def put(key, mentry:, payload:, if_etag: nil)
  ctx = WriteStep::WriteContext.new(
    key:, mentry:, payload:, if_etag:,
    path: nil, existing_env: nil, meta: nil, content: nil,
    bytes: nil, eff_meta: nil, eff_body: nil, eff_content: nil,
    etag_before: nil, envelope: nil
  )
  deps = WriteStep::WriteDeps.new(
    file_store: @file_store, manifest: @manifest, schemas: @schemas,
    audit_log: @audit_log, call: @call, reader: @reader, layout: @layout
  )
  ctx = WriteStep::DEFAULT_PUT.reduce(ctx) { |c, step| step.call(c, deps) }
  ctx.envelope
end
```

Remove these private methods (now in WriteStep modules, dead code):
`read_existing`, `inject_meta`, `resolve_source_etag`, `resolve_path`, `serialize_entry`,
`enforce_name_match!`, `validate_schema`, `validate_raw`, `check_etag!`, `write_bytes`,
`build_envelope`, `audit_put`.

Keep `delete`, `move`, `prune_empty_parents` unchanged.

- [ ] **Step 6: Run full suite**

```
bundle exec rspec --format progress
```

Expected: passes (baseline: 4 pre-existing CLI conformance failures)

- [ ] **Step 7: Commit**

```bash
git add lib/textus/store/entry/write_step.rb \
        lib/textus/store/entry/writer.rb \
        spec/unit/store/entry/write_step_spec.rb
git commit -m "refactor: decompose Entry::Writer#put into WriteStep::DEFAULT_PUT chain"
```

---

## Task 2: HANDLER_MANIFEST + Dispatch::Assembler

Replace `Container.build_pipeline`'s 80-line imperative loop with a declarative `HANDLER_MANIFEST`. Container's `build_pipeline` becomes a one-liner.

**Files:**
- Create: `lib/textus/dispatch/assembler.rb`
- Modify: `lib/textus/store/container.rb` (replace lines 74–181)
- Create: `spec/unit/dispatch/assembler_spec.rb`

**Interfaces:**
- Produces: `Textus::Dispatch::Assembler.build_pipeline(container:) → Pipeline`
- Consumes: `Container.orchestration_for(container)` (existing, unchanged)

---

- [ ] **Step 1: Write the failing conformance test**

```ruby
# spec/unit/dispatch/assembler_spec.rb
require "spec_helper"

RSpec.describe Textus::Dispatch::Assembler do
  describe "HANDLER_MANIFEST" do
    it "covers every contract in VERB_TO_CONTRACT" do
      expected_contracts = Textus::VerbRegistry::VERB_TO_CONTRACT.values.to_set
      manifest_contracts = described_class::HANDLER_MANIFEST.map(&:first).to_set
      missing = expected_contracts - manifest_contracts
      extra   = manifest_contracts - expected_contracts
      expect(missing).to be_empty,
        "in VERB_TO_CONTRACT but missing from HANDLER_MANIFEST: #{missing.map(&:name)}"
      expect(extra).to be_empty,
        "in HANDLER_MANIFEST but absent from VERB_TO_CONTRACT: #{extra.map(&:name)}"
    end

    it "each row is [contract_class, handler_class, Hash]" do
      described_class::HANDLER_MANIFEST.each do |row|
        expect(row.size).to eq(3), "row for #{row.first} has #{row.size} elements"
        expect(row[0]).to be_a(Class)
        expect(row[1]).to be_a(Class)
        expect(row[2]).to be_a(Hash)
      end
    end

    it "all dep_map values are Symbols in COMPUTED_KEYS" do
      described_class::HANDLER_MANIFEST.each do |_contract, _handler, dep_map|
        dep_map.each_value do |v|
          expect(described_class::COMPUTED_KEYS).to include(v),
            "dep_map value :#{v} is not in COMPUTED_KEYS"
        end
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
bundle exec rspec spec/unit/dispatch/assembler_spec.rb -f doc
```

Expected: `NameError: uninitialized constant Textus::Dispatch::Assembler`

---

- [ ] **Step 3: Create assembler.rb**

```ruby
# lib/textus/dispatch/assembler.rb
module Textus
  module Dispatch
    class Assembler
      COMPUTED_KEYS = %i[
        container manifest audit_log file_store job_store schemas link_edge_store fe orch
      ].to_set.freeze

      # [ContractClass, HandlerClass, { kwarg_name: :computed_key }]
      # Computed key legend:
      #   :container       → the Container itself
      #   :manifest        → container.manifest
      #   :audit_log       → container.audit_log
      #   :file_store      → container.file_store
      #   :job_store       → container.job_store
      #   :schemas         → container.schemas
      #   :link_edge_store → container.link_edge_store
      #   :fe              → TtlEvaluator (built once)
      #   :orch            → Orchestration (built once, shared by 4 handlers)
      HANDLER_MANIFEST = [
        [Contracts::GetEntry,        Handlers::Read::GetEntry,
         { container: :container, freshness_evaluator: :fe }],
        [Contracts::PutEntry,        Handlers::Write::PutEntry,        { container: :container }],
        [Contracts::ListKeys,        Handlers::Read::ListKeys,         { manifest: :manifest, job_store: :job_store }],
        [Contracts::DeleteKey,       Handlers::Write::DeleteKey,       { container: :container }],
        [Contracts::MoveKey,         Handlers::Write::MoveKey,         { container: :container, manifest: :manifest }],
        [Contracts::ProposeEntry,    Handlers::Write::ProposeEntry,    { container: :container }],
        [Contracts::AcceptProposal,  Handlers::Write::AcceptProposal,  { container: :container }],
        [Contracts::RejectProposal,  Handlers::Write::RejectProposal,  { container: :container }],
        [Contracts::EnqueueJob,      Handlers::Write::EnqueueJob,      { job_store: :job_store }],
        [Contracts::WhereEntry,      Handlers::Read::WhereEntry,       { manifest: :manifest }],
        [Contracts::UidEntry,        Handlers::Read::UidEntry,         { container: :container }],
        [Contracts::DepsEntry,       Handlers::Read::DepsEntry,        { manifest: :manifest }],
        [Contracts::RdepsEntry,      Handlers::Read::RdepsEntry,
         { manifest: :manifest, link_edge_store: :link_edge_store }],
        [Contracts::BootStore,       Handlers::Maintenance::BootStore,       { container: :container }],
        [Contracts::DoctorStore,     Handlers::Maintenance::DoctorStore,     { container: :container }],
        [Contracts::PublishedEntries, Handlers::Maintenance::PublishedEntries, { manifest: :manifest }],
        [Contracts::RuleExplain,     Handlers::Maintenance::RuleExplain,     { manifest: :manifest }],
        [Contracts::RuleList,        Handlers::Maintenance::RuleList,        { manifest: :manifest }],
        [Contracts::SchemaEnvelope,  Handlers::Maintenance::SchemaEnvelope,
         { manifest: :manifest, schemas: :schemas }],
        [Contracts::DrainStore,      Handlers::Maintenance::DrainStore,
         { container: :container, job_store: :job_store }],
        [Contracts::IngestEntry,     Handlers::Maintenance::IngestEntry,     { container: :container }],
        [Contracts::JobsAction,      Handlers::Maintenance::JobsAction,      { job_store: :job_store }],
        [Contracts::RuleLint,        Handlers::Maintenance::RuleLint,        { manifest: :manifest }],
        [Contracts::DataMv,          Handlers::Write::DataMv,                { container: :container }],
        [Contracts::AuditEntries,    Handlers::Read::AuditEntries,
         { manifest: :manifest, audit_log: :audit_log }],
        [Contracts::PulseEntries,    Handlers::Read::PulseEntries,
         { manifest: :manifest, audit_log: :audit_log,
           file_store: :file_store, job_store: :job_store, orchestration: :orch }],
        [Contracts::BlameEntry,      Handlers::Read::BlameEntry,
         { manifest: :manifest, orchestration: :orch }],
        [Contracts::KeyMvPrefix,     Handlers::Write::KeyMvPrefix,     { orchestration: :orch }],
        [Contracts::KeyDeletePrefix, Handlers::Write::KeyDeletePrefix, { orchestration: :orch }],
      ].freeze

      MIDDLEWARE_MANIFEST = [
        ->(_c) { Middleware::Binder.new },
        ->(_c) { Middleware::Auth.new },
        ->(c)  { Middleware::AuditIndex.new(job_store: c.job_store, audit_log: c.audit_log) },
        ->(_c) { Middleware::Cascade.new },
      ].freeze

      def self.build_pipeline(container:)
        fe   = freshness_evaluator(container)
        orch = Store::Container.orchestration_for(container)

        computed = {
          container:,
          manifest:        container.manifest,
          audit_log:       container.audit_log,
          file_store:      container.file_store,
          job_store:       container.job_store,
          schemas:         container.schemas,
          link_edge_store: container.link_edge_store,
          fe:,
          orch:,
        }

        registry = HandlerRegistry.new
        HANDLER_MANIFEST.each do |contract_class, handler_class, dep_map|
          deps = dep_map.transform_values { |key| computed.fetch(key) }
          registry.register(contract_class, handler_class.new(**deps))
        end

        middleware = MIDDLEWARE_MANIFEST.map { |factory| factory.call(container) }
        Pipeline.new(registry:, container:, middleware:)
      end

      def self.freshness_evaluator(container)
        Store::Freshness::TtlEvaluator.new(
          manifest: container.manifest,
          file_stat: Textus::Port::Storage::FileStat.new,
          clock: Textus::Port::Clock.new,
        )
      end
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```
bundle exec rspec spec/unit/dispatch/assembler_spec.rb -f doc
```

Expected: all 3 examples pass

---

- [ ] **Step 5: Replace Container.build_pipeline with a one-liner**

In `lib/textus/store/container.rb`:

Replace the entire `build_pipeline` private class method body (lines 74–158) with:

```ruby
def self.build_pipeline(container)
  Dispatch::Assembler.build_pipeline(container:)
end
private_class_method :build_pipeline
```

Remove the `self.freshness_evaluator` private class method (lines 175–181) — moved to Assembler.

Add `require_relative "../dispatch/assembler"` in the correct place in `lib/textus/init.rb` (after `dispatch/pipeline`).

- [ ] **Step 6: Run full suite**

```
bundle exec rspec --format progress
```

Expected: same pass count as after Task 1

- [ ] **Step 7: Commit**

```bash
git add lib/textus/dispatch/assembler.rb \
        lib/textus/store/container.rb \
        spec/unit/dispatch/assembler_spec.rb
git add lib/textus/init.rb
git commit -m "refactor: replace Container#build_pipeline with declarative HANDLER_MANIFEST in Dispatch::Assembler"
```

---

## Task 3: entry/ops/rule surface API on Store

Replace the 30 dynamically generated verb methods with three noun-domain façade methods.

**Files:**
- Modify: `lib/textus/verb_registry.rb` — add `ENTRY_VERBS`, `OPS_VERBS`, `RULE_VERBS`, `VERB_DOMAIN`; delete `Store.class_eval` block
- Modify: `lib/textus/store.rb` — add `entry`, `ops`, `rule`, `_dispatch_in_domain`
- Modify: `lib/textus/surface/cli/runner.rb` — update one dispatch line (~line 62)
- Modify: all specs calling old verb methods

**Domain mapping:**
- `entry`: `get put list key_delete key_mv propose accept reject audit blame where uid deps rdeps ingest`
- `ops`: `boot drain doctor pulse jobs enqueue data_mv key_mv_prefix key_delete_prefix published`
- `rule`: `rule_explain rule_list schema_show rule_lint`

**Call-site translation table:**
```
store.get(key: "x")                          → store.entry(:get, key: "x")
store.put(key: "x", body: "y")               → store.entry(:put, key: "x", body: "y")
store.list(prefix: "x")                      → store.entry(:list, prefix: "x")
store.key_delete(key: "x")                   → store.entry(:key_delete, key: "x")
store.key_mv(old_key: "a", new_key: "b")     → store.entry(:key_mv, old_key: "a", new_key: "b")
store.propose(key: "x", body: "y")           → store.entry(:propose, key: "x", body: "y")
store.accept(pending_key: "queue.pending.x") → store.entry(:accept, pending_key: "queue.pending.x")
store.reject(pending_key: "queue.pending.x") → store.entry(:reject, pending_key: "queue.pending.x")
store.audit(key: "x")                        → store.entry(:audit, key: "x")
store.blame(key: "x")                        → store.entry(:blame, key: "x")
store.where(key: "x")                        → store.entry(:where, key: "x")
store.uid(key: "x")                          → store.entry(:uid, key: "x")
store.deps(key: "x")                         → store.entry(:deps, key: "x")
store.rdeps(key: "x")                        → store.entry(:rdeps, key: "x")
store.ingest(kind: "url", slug: "x", url: y) → store.entry(:ingest, kind: "url", slug: "x", url: y)
store.drain                                  → store.ops(:drain)
store.boot                                   → store.ops(:boot)
store.pulse(since: 0)                        → store.ops(:pulse, since: 0)
store.doctor                                 → store.ops(:doctor)
store.jobs(state: "ready")                   → store.ops(:jobs, state: "ready")
store.enqueue(type: "x", args: {})           → store.ops(:enqueue, type: "x", args: {})
store.data_mv(from: "a", to: "b")            → store.ops(:data_mv, from: "a", to: "b")
store.key_mv_prefix(from_prefix: "a", to_prefix: "b") → store.ops(:key_mv_prefix, from_prefix: "a", to_prefix: "b")
store.key_delete_prefix(prefix: "x")        → store.ops(:key_delete_prefix, prefix: "x")
store.published                              → store.ops(:published)
store.rule_explain(key: "x")                → store.rule(:rule_explain, key: "x")
store.rule_list                              → store.rule(:rule_list)
store.schema_show(key: "x")                 → store.rule(:schema_show, key: "x")
store.rule_lint(candidate_yaml: "x")        → store.rule(:rule_lint, candidate_yaml: "x")
```

---

- [ ] **Step 1: Write failing tests**

Add inside `RSpec.describe Textus::Store do` in `spec/integration/store_spec.rb`:

```ruby
describe "noun-domain API" do
  let(:store) { described_class.new(root) }

  describe "#entry" do
    it "dispatches :list without arguments" do
      result = store.entry(:list)
      expect(result).to be_an(Array)
    end

    it "raises ArgumentError for a non-entry verb" do
      expect { store.entry(:drain) }.to raise_error(ArgumentError, /drain.*not in this domain/)
    end

    it "raises ArgumentError for an unknown verb" do
      expect { store.entry(:frobnicate) }.to raise_error(ArgumentError, /unknown verb/)
    end
  end

  describe "#ops" do
    it "dispatches :boot" do
      result = store.ops(:boot)
      expect(result).to be_a(Hash)
    end

    it "raises ArgumentError for a non-ops verb" do
      expect { store.ops(:get) }.to raise_error(ArgumentError, /get.*not in this domain/)
    end
  end

  describe "#rule" do
    it "dispatches :rule_list" do
      result = store.rule(:rule_list)
      expect(result).to be_an(Array)
    end

    it "raises ArgumentError for a non-rule verb" do
      expect { store.rule(:put) }.to raise_error(ArgumentError, /put.*not in this domain/)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```
bundle exec rspec spec/integration/store_spec.rb -e "noun-domain" -f doc
```

Expected: `NoMethodError: undefined method 'entry'`

---

- [ ] **Step 3: Add verb-domain constants to verb_registry.rb**

After the `CONTRACT_TO_VERB` constant in `lib/textus/verb_registry.rb`, add:

```ruby
ENTRY_VERBS = %i[
  get put list key_delete key_mv propose accept reject
  audit blame where uid deps rdeps ingest
].freeze

OPS_VERBS = %i[
  boot drain doctor pulse jobs enqueue data_mv
  key_mv_prefix key_delete_prefix published
].freeze

RULE_VERBS = %i[rule_explain rule_list schema_show rule_lint].freeze

VERB_DOMAIN = (
  ENTRY_VERBS.to_h { |v| [v, :entry] }
    .merge(OPS_VERBS.to_h { |v| [v, :ops] })
    .merge(RULE_VERBS.to_h { |v| [v, :rule] })
).freeze
```

Delete the entire `Textus::Store.class_eval do ... end` block at the bottom of the file.

- [ ] **Step 4: Add entry/ops/rule to Store**

In `lib/textus/store.rb`, after `def dry_run? = @dry_run`, add:

```ruby
def entry(verb, **opts)
  _dispatch_in_domain(verb, VerbRegistry::ENTRY_VERBS, **opts)
end

def ops(verb, **opts)
  _dispatch_in_domain(verb, VerbRegistry::OPS_VERBS, **opts)
end

def rule(verb, **opts)
  _dispatch_in_domain(verb, VerbRegistry::RULE_VERBS, **opts)
end
```

In the `private` section, add:

```ruby
def _dispatch_in_domain(verb, allowed, **opts)
  unless allowed.include?(verb)
    raise ArgumentError, "#{verb} is not in this domain (allowed: #{allowed.first(4).join(', ')}...)"
  end

  spec = VerbRegistry.for(verb)
  raise ArgumentError, "unknown verb: #{verb}" unless spec

  pending = Dispatch::Binder.command(spec, opts)
  call    = Value::Call.build(role: @role, correlation_id: @correlation_id)
  result  = @container.pipeline.dispatch(pending, call: call)
  Value::Result.extract(result)
end
```

- [ ] **Step 5: Update CLI runner dispatch**

In `lib/textus/surface/cli/runner.rb`, find:

```ruby
result = s.public_send(spec.verb, **inputs)
```

Replace with:

```ruby
domain = Textus::VerbRegistry::VERB_DOMAIN.fetch(spec.verb) do
  raise Textus::UsageError.new("#{spec.verb} has no domain assignment")
end
result = s.public_send(domain, spec.verb, **inputs)
```

- [ ] **Step 6: Run new tests**

```
bundle exec rspec spec/integration/store_spec.rb -e "noun-domain" -f doc
```

Expected: all 7 examples pass

---

- [ ] **Step 7: Find and fix all callers of old verb methods in specs**

```bash
grep -rn "\bstore\.\(get\|put\|list\|drain\|boot\|pulse\|propose\|accept\|reject\|audit\|blame\|where\|uid\|deps\|rdeps\|ingest\|doctor\|published\|rule_explain\|rule_list\|schema_show\|rule_lint\|key_delete\|key_mv\|enqueue\|data_mv\|key_mv_prefix\|key_delete_prefix\|jobs\)(" spec/
```

Update each match using the translation table in the Interfaces section.

- [ ] **Step 8: Check lib/ for Store method calls**

```bash
grep -rn "\bstore\.\(get\|put\|list\|drain\|boot\|pulse\|propose\|accept\|reject\)(" lib/
```

Update any matches.

- [ ] **Step 9: Run full suite**

```
bundle exec rspec --format progress
```

Expected: same pass count as after Task 2

- [ ] **Step 10: Rubocop**

```
bundle exec rubocop lib/textus/store.rb lib/textus/verb_registry.rb lib/textus/surface/cli/runner.rb
```

Fix offenses.

- [ ] **Step 11: Commit**

```bash
git add lib/textus/verb_registry.rb lib/textus/store.rb lib/textus/surface/cli/runner.rb
git add spec/
git commit -m "feat: replace generated verb methods with entry/ops/rule noun-domain API on Store"
```
