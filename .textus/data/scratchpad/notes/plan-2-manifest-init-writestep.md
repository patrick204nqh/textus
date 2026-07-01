---
title: Manifest Init Hardening + WriteStep Completion Implementation Plan
uid: 2b7fd08ba06866e0
---
# Manifest Init Hardening + WriteStep Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the fragile 3-step manifest initialization order by making `Manifest.build` explicitly two-phase; extend the WriteStep pattern from `put` to `delete` and `move`.

**Architecture:** Part A: Move entry-building out of `Manifest::Data#initialize` into a two-phase `Manifest.build` — Phase 1 builds Data+Policy (no entries), Phase 2 builds entries with a fully-formed Policy so `derived_entry?` works correctly. Part B: Add `DeleteContext`, `MoveContext`, `DEFAULT_DELETE`, `DEFAULT_MOVE` to `lib/textus/store/entry/write_step.rb`; rewrite `Writer#delete` and `Writer#move` to reduce over those constants.

**Tech Stack:** Ruby 3.x, Data.define, RSpec, bundle exec rspec

## Global Constraints

- No Co-Authored-By trailers in commits
- All tests: `bundle exec rspec`; lint: `bundle exec rubocop -A`
- Breaking changes OK — no compat shims
- Stage specific files only, never `git add -A`

---

## File Map

### Modified
- `lib/textus/manifest.rb` — two-phase `build`; move entry-building out of Data
- `lib/textus/manifest/data.rb` — remove `@policy` and `@entries` from `initialize`; add pure field accessors
- `lib/textus/manifest/policy.rb` — `derived_entry?` now works (policy receives fully-built entries)
- `lib/textus/store/entry/write_step.rb` — add `DeleteContext`, `MoveContext`, step modules, constants
- `lib/textus/store/entry/writer.rb` — replace `delete` and `move` bodies with step-chain

### Tests
- `spec/unit/manifest/two_phase_load_spec.rb` (new)
- `spec/unit/store/entry/write_step_spec.rb` (extend existing)

---

## Task 1: Two-phase Manifest initialization

**Files:**
- Modify: `lib/textus/manifest/data.rb`
- Modify: `lib/textus/manifest.rb`
- Modify: `lib/textus/manifest/policy.rb`
- Create: `spec/unit/manifest/two_phase_load_spec.rb`

**Interfaces:**
- `Manifest::Data.parse(raw, root:)` — no longer builds Policy or entries; pure field parsing only
- `Manifest.build(raw, root)` — Phase 1: Data + Policy; Phase 2: entries via Entry::Parser with Policy available
- `Policy#derived_entry?(key)` — returns correct value (no longer always false)

---

- [ ] **Step 1: Write the failing test**

This test proves `derived_entry?` works after loading — the bug that two-phase init fixes.

```ruby
# spec/unit/manifest/two_phase_load_spec.rb
require "spec_helper"

RSpec.describe "Manifest two-phase initialization" do
  def build_manifest_with_produced_entry(root)
    FileUtils.mkdir_p(File.join(root, "data", "artifacts"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: canon,     kind: canon    }
        - { name: artifacts, kind: machine  }
      entries:
        - key: canon.source
          path: canon/source.md
          lane: canon
          owner: human:self
          kind: leaf
        - key: artifacts.derived
          path: artifacts/derived.md
          lane: artifacts
          owner: automation:self
          kind: produced
          source:
            - { key: canon.source }
    YAML
    Textus::Manifest.load(root)
  end

  it "derived_entry? returns true for a produced entry after load" do
    Dir.mktmpdir do |tmp|
      root = File.join(tmp, ".textus")
      FileUtils.mkdir_p(root)
      manifest = build_manifest_with_produced_entry(root)
      expect(manifest.policy.derived_entry?("artifacts.derived")).to be(true)
    end
  end

  it "derived_entry? returns false for a plain canon entry" do
    Dir.mktmpdir do |tmp|
      root = File.join(tmp, ".textus")
      FileUtils.mkdir_p(root)
      manifest = build_manifest_with_produced_entry(root)
      expect(manifest.policy.derived_entry?("canon.source")).to be(false)
    end
  end

  it "Phase 1 and Phase 2 are structurally sequential — no ordering invariant hidden in Data" do
    Dir.mktmpdir do |tmp|
      root = File.join(tmp, ".textus")
      FileUtils.mkdir_p(root)
      File.write(File.join(root, "manifest.yaml"), <<~YAML)
        version: textus/4
        lanes:
          - { name: knowledge, kind: canon }
        entries:
          - { key: knowledge.demo, path: knowledge/demo.md, lane: knowledge, owner: human:self, kind: leaf }
      YAML
      manifest = Textus::Manifest.load(root)
      # Data no longer holds @policy or @entries internally
      expect(manifest.data).not_to respond_to(:policy)
      expect(manifest.data).not_to respond_to(:entries)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```
bundle exec rspec spec/unit/manifest/two_phase_load_spec.rb -f doc
```

Expected: the `derived_entry?` test fails (returns false when it should return true), and the `respond_to?` test may pass or fail depending on current Data implementation.

---

- [ ] **Step 3: Strip entry-building and policy from Manifest::Data**

In `lib/textus/manifest/data.rb`, remove `@policy` and `@entries` from `initialize`. The `initialize` becomes pure field parsing:

```ruby
def initialize(raw:, root:)
  @raw    = raw
  @root   = root
  @declared_lane_kinds = Array(raw["lanes"]).to_h do |z|
    [z["name"], z["kind"]&.to_sym]
  end
  @lane_descs    = Array(raw["lanes"]).to_h { |z| [z["name"], z["desc"]] }
  @lane_owners   = Array(raw["lanes"]).to_h { |z| [z["name"], z["owner"]] }.compact
  @audit_config  = build_audit_config(raw)
  @worker_config = build_worker_config(raw)
  @role_caps     = Capabilities.resolve(raw["roles"])
  freeze
end
```

Remove `attr_reader :policy` and `attr_reader :entries` from Data. Remove `build_entries` private method from Data (it moves to `Manifest.build`). Remove `validate_declared_keys!` call (it moves too — see Step 4).

Keep all other private methods that `build_entries` called (`build_audit_config`, `build_worker_config`).

- [ ] **Step 4: Rewrite Manifest.build as two explicit phases**

In `lib/textus/manifest.rb`, replace `build`:

```ruby
def build(raw, root)
  # Phase 1: structural data + authority policy (no entries)
  data   = Manifest::Data.parse(raw, root: root)
  policy = Manifest::Policy.new(data)

  # Phase 2: entries — validators now have a fully-formed Policy
  entries  = Manifest::Entry::Parser.parse(Array(raw["entries"]), policy: policy, data: data)
  resolver = Manifest::Resolver.new(data, entries)
  rules    = Manifest::Rules.parse(raw["rules"] || [])

  validate_declared_keys!(data, entries)

  new(data: data, policy: policy, resolver: resolver, rules: rules)
end

def validate_declared_keys!(data, entries)
  # Move the validate_declared_keys! logic here from Data#initialize
  # It validates that entry keys don't collide with lane names etc.
  # Copy the existing implementation from Manifest::Data#validate_declared_keys!
end
```

> **Resolver change:** `Manifest::Resolver.new` currently takes only `data`. After this change it takes `data` and `entries` separately (since entries are no longer inside data). Update `Manifest::Resolver#initialize` to accept `(data, entries)` and replace `@data.entries` with `@entries` throughout Resolver.

- [ ] **Step 5: Update Policy#derived_entry? to use actual entries**

In `lib/textus/manifest/policy.rb`, `Policy.new` now receives both `data` and `entries` (or just a reference to the entries array). Update the constructor:

```ruby
def initialize(data, entries = [])
  @data    = data
  @entries = entries  # populated in Phase 2
end

# Now works correctly:
def derived_entry?(key)
  entry = @entries.find { |e| e.key == key }
  entry&.is_a?(Textus::Manifest::Entry::Produced) || false
end
```

Update `Manifest.build` to pass entries to Policy after Phase 2:

```ruby
# At the end of Manifest.build Phase 2:
policy.set_entries(entries)  # OR rebuild Policy with entries
```

Alternatively (simpler): make Policy a `Data.define` or accept entries lazily:

```ruby
# Simplest fix: Policy stores entries after Phase 2
class Policy
  attr_writer :entries

  def derived_entry?(key)
    entry = Array(@entries).find { |e| e.key == key }
    entry&.is_a?(Textus::Manifest::Entry::Produced) || false
  end
end

# In Manifest.build, after Phase 2:
entries = Manifest::Entry::Parser.parse(...)
policy.entries = entries
```

- [ ] **Step 6: Run the new tests**

```
bundle exec rspec spec/unit/manifest/two_phase_load_spec.rb -f doc
```

Expected: all 3 examples pass.

- [ ] **Step 7: Run the full suite to confirm no regressions**

```
bundle exec rspec --format progress
```

Expected: same pass count as baseline.

- [ ] **Step 8: Commit**

```bash
git add lib/textus/manifest.rb lib/textus/manifest/data.rb \
        lib/textus/manifest/policy.rb \
        spec/unit/manifest/two_phase_load_spec.rb
git commit -m "refactor: two-phase Manifest.build — derived_entry? now correct during Phase 2"
```

---

## Task 2: WriteStep for delete — DEFAULT_DELETE

Extend `write_step.rb` with `DeleteContext`, step modules for the delete pipeline, and `DEFAULT_DELETE`. Update `Writer#delete` to use it.

**Files:**
- Modify: `lib/textus/store/entry/write_step.rb` — add `DeleteContext` + step modules + `DEFAULT_DELETE`
- Modify: `lib/textus/store/entry/writer.rb` — replace `delete` body with step-chain
- Modify: `spec/unit/store/entry/write_step_spec.rb` — extend with delete coverage

**Interfaces:**
- Consumes: `WriteStep::WriteDeps` (already exists from put pipeline)
- Produces: `WriteStep::DeleteContext`, `WriteStep::DEFAULT_DELETE` (7 steps)
- `Writer#delete(key, mentry: nil, if_etag: nil)` — signature unchanged, behaviour unchanged

---

- [ ] **Step 1: Extend write_step_spec.rb with delete tests**

```ruby
# Add inside RSpec.describe Textus::Store::Entry::WriteStep do
describe "DeleteContext" do
  it "holds key, mentry, if_etag inputs and path, etag_before outputs" do
    ctx = described_class::DeleteContext.new(
      key: "knowledge.demo", mentry: nil, if_etag: nil,
      path: nil, etag_before: nil,
    )
    expect(ctx.key).to eq("knowledge.demo")
    expect(ctx.path).to be_nil
    expect(ctx.etag_before).to be_nil
  end

  it "supports immutable update via #with" do
    ctx = described_class::DeleteContext.new(
      key: "knowledge.demo", mentry: nil, if_etag: nil,
      path: nil, etag_before: nil,
    )
    expect(ctx.with(path: "/tmp/demo.md").path).to eq("/tmp/demo.md")
    expect(ctx.path).to be_nil
  end
end

describe "DEFAULT_DELETE" do
  it "contains exactly the expected steps in order" do
    names = described_class::DEFAULT_DELETE.map(&:name).map { |n| n.split("::").last }
    expect(names).to eq(%w[
      ResolvePath AssertExists ReadEtagBefore CheckEtag
      DeleteFile PruneParents AppendDeleteAudit
    ])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -e "DeleteContext" -f doc
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -e "DEFAULT_DELETE" -f doc
```

Expected: `NameError: uninitialized constant ...::DeleteContext`

---

- [ ] **Step 3: Add DeleteContext and delete steps to write_step.rb**

Append inside `module WriteStep` in `lib/textus/store/entry/write_step.rb`:

```ruby
DeleteContext = Data.define(
  :key, :mentry, :if_etag,   # inputs (mentry accepted for symmetry, not used)
  :path,                      # from ResolvePath (reused from put pipeline)
  :etag_before,               # from ReadEtagBefore
) do
  def with(**attrs) = self.class.new(**to_h, **attrs)
end

module AssertExists
  def self.call(ctx, deps)
    return ctx if deps.file_store.exists?(ctx.path)

    raise UnknownKey.new(ctx.key, suggestions: deps.manifest.resolver.suggestions_for(ctx.key))
  end
end

module ReadEtagBefore
  def self.call(ctx, deps)
    etag_before = deps.file_store.etag(ctx.path)
    ctx.with(etag_before:)
  end
end

module DeleteFile
  def self.call(ctx, deps)
    deps.file_store.delete(ctx.path)
    ctx
  end
end

module PruneParents
  def self.call(ctx, deps)
    floor = deps.layout.lane_floor(ctx.path)
    if floor
      dir = File.dirname(ctx.path)
      while dir.start_with?("#{floor}/") && deps.file_store.dir_empty?(dir)
        deps.file_store.rmdir(dir)
        dir = File.dirname(dir)
      end
    end
    ctx
  rescue SystemCallError
    ctx
  end
end

module AppendDeleteAudit
  def self.call(ctx, deps)
    extras = deps.call.correlation_id ? { "correlation_id" => deps.call.correlation_id } : nil
    deps.audit_log.append(
      role:        deps.call.role,
      verb:        "key_delete",
      key:         ctx.key,
      etag_before: ctx.etag_before,
      etag_after:  nil,
      extras:      extras,
    )
    ctx
  end
end

# CheckEtag is reused from the put pipeline — it reads ctx.path and ctx.if_etag,
# raising EtagMismatch if the guard fails. DeleteContext has both fields.

DEFAULT_DELETE = [
  ResolvePath,      # key → path (module shared with put pipeline)
  AssertExists,     # raises UnknownKey unless file_store.exists?(path)
  ReadEtagBefore,   # etag_before = file_store.etag(path)
  CheckEtag,        # raises EtagMismatch if if_etag given and mismatches
  DeleteFile,       # file_store.delete(path)
  PruneParents,     # remove now-empty ancestor directories
  AppendDeleteAudit, # audit_log.append(verb: "key_delete", ...)
].freeze
```

- [ ] **Step 4: Replace Writer#delete body**

In `lib/textus/store/entry/writer.rb`, replace the existing `delete` method:

```ruby
def delete(key, mentry: nil, if_etag: nil)
  ctx = WriteStep::DeleteContext.new(
    key:, mentry:, if_etag:,
    path: nil, etag_before: nil,
  )
  deps = WriteStep::WriteDeps.new(
    file_store: @file_store, manifest: @manifest, schemas: @schemas,
    audit_log: @audit_log, call: @call, reader: @reader, layout: @layout,
  )
  WriteStep::DEFAULT_DELETE.reduce(ctx) { |c, step| step.call(c, deps) }
  nil
end
```

- [ ] **Step 5: Run write_step spec and conformance suite**

```
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -f doc
bundle exec rspec spec/conformance/write/ -f progress
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```
bundle exec rspec --format progress
```

- [ ] **Step 7: Commit**

```bash
git add lib/textus/store/entry/write_step.rb \
        lib/textus/store/entry/writer.rb \
        spec/unit/store/entry/write_step_spec.rb
git commit -m "refactor: decompose Writer#delete into WriteStep::DEFAULT_DELETE chain"
```

---

## Task 3: WriteStep for move — DEFAULT_MOVE

Same pattern as Task 2 for `move`. `MoveContext` has more fields (two paths, envelope) and DEFAULT_MOVE has 10 steps.

**Files:**
- Modify: `lib/textus/store/entry/write_step.rb` — add `MoveContext` + move step modules + `DEFAULT_MOVE`
- Modify: `lib/textus/store/entry/writer.rb` — replace `move` body with step-chain
- Modify: `spec/unit/store/entry/write_step_spec.rb` — extend with move coverage

**Interfaces:**
- Consumes: `WriteStep::WriteDeps` (reused); `CheckEtag` (reused — reads `ctx.if_etag` and `ctx.etag_before`)
- Produces: `WriteStep::MoveContext`, `WriteStep::DEFAULT_MOVE` (10 steps)
- `Writer#move(from_key:, to_key:, new_mentry:, if_etag: nil) → Envelope` — signature unchanged

---

- [ ] **Step 1: Extend write_step_spec.rb with move tests**

```ruby
# Add inside RSpec.describe Textus::Store::Entry::WriteStep do
describe "MoveContext" do
  it "holds all inputs and computed fields" do
    ctx = described_class::MoveContext.new(
      from_key: "knowledge.alpha", to_key: "knowledge.beta",
      new_mentry: nil, if_etag: nil,
      from_path: nil, to_path: nil,
      etag_before: nil, etag_after: nil, envelope: nil,
    )
    expect(ctx.from_key).to eq("knowledge.alpha")
    expect(ctx.from_path).to be_nil
    expect(ctx.envelope).to be_nil
  end

  it "supports immutable update via #with" do
    ctx = described_class::MoveContext.new(
      from_key: "knowledge.alpha", to_key: "knowledge.beta",
      new_mentry: nil, if_etag: nil,
      from_path: nil, to_path: nil,
      etag_before: nil, etag_after: nil, envelope: nil,
    )
    updated = ctx.with(from_path: "/tmp/alpha.md")
    expect(updated.from_path).to eq("/tmp/alpha.md")
    expect(ctx.from_path).to be_nil
  end
end

describe "DEFAULT_MOVE" do
  it "contains exactly the expected steps in order" do
    names = described_class::DEFAULT_MOVE.map(&:name).map { |n| n.split("::").last }
    expect(names).to eq(%w[
      ResolvePaths AssertSourceExists ReadMoveEtagBefore CheckMoveEtag
      MoveFile PruneSourceParents RewriteBasename
      ReadEtagAfter ReadEnvelope AppendMoveAudit
    ])
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -e "MoveContext" -f doc
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -e "DEFAULT_MOVE" -f doc
```

Expected: `NameError: uninitialized constant ...::MoveContext`

---

- [ ] **Step 3: Add MoveContext and move steps to write_step.rb**

Append inside `module WriteStep` in `lib/textus/store/entry/write_step.rb`:

```ruby
MoveContext = Data.define(
  :from_key, :to_key, :new_mentry, :if_etag,   # inputs
  :from_path, :to_path,                          # from ResolvePaths
  :etag_before,                                  # from ReadMoveEtagBefore
  :etag_after,                                   # from ReadEtagAfter
  :envelope,                                     # from ReadEnvelope
) do
  def with(**attrs) = self.class.new(**to_h, **attrs)
end

module ResolvePaths
  def self.call(ctx, deps)
    from_path = deps.manifest.resolver.resolve(ctx.from_key).path
    to_path   = deps.manifest.resolver.resolve(ctx.to_key).path
    ctx.with(from_path:, to_path:)
  end
end

module AssertSourceExists
  def self.call(ctx, deps)
    return ctx if deps.file_store.exists?(ctx.from_path)

    raise UnknownKey.new(
      ctx.from_key,
      suggestions: deps.manifest.resolver.suggestions_for(ctx.from_key),
    )
  end
end

module ReadMoveEtagBefore
  def self.call(ctx, deps)
    etag_before = deps.file_store.etag(ctx.from_path)
    ctx.with(etag_before:)
  end
end

module CheckMoveEtag
  # Identical logic to CheckEtag but reads from ctx.from_path's etag_before
  def self.call(ctx, _deps)
    if ctx.if_etag && (ctx.etag_before != ctx.if_etag)
      raise EtagMismatch.new(ctx.from_key, ctx.if_etag, ctx.etag_before)
    end

    ctx
  end
end

module MoveFile
  def self.call(ctx, deps)
    deps.file_store.mv(ctx.from_path, ctx.to_path)
    ctx
  end
end

module PruneSourceParents
  def self.call(ctx, deps)
    floor = deps.layout.lane_floor(ctx.from_path)
    if floor
      dir = File.dirname(ctx.from_path)
      while dir.start_with?("#{floor}/") && deps.file_store.dir_empty?(dir)
        deps.file_store.rmdir(dir)
        dir = File.dirname(dir)
      end
    end
    ctx
  rescue SystemCallError
    ctx
  end
end

module RewriteBasename
  def self.call(ctx, _deps)
    basename = ctx.to_key.split(".").last
    Format.for(ctx.new_mentry.format).rewrite_name(ctx.to_path, basename)
    ctx
  end
end

module ReadEtagAfter
  def self.call(ctx, _deps)
    etag_after = Value::Etag.for_file(ctx.to_path)
    ctx.with(etag_after:)
  end
end

module ReadEnvelope
  def self.call(ctx, deps)
    envelope = deps.reader.read(ctx.to_key)
    ctx.with(envelope:)
  end
end

module AppendMoveAudit
  def self.call(ctx, deps)
    extras = {
      "from_key"  => ctx.from_key, "to_key"    => ctx.to_key,
      "from_path" => ctx.from_path, "to_path"   => ctx.to_path,
      "uid"       => ctx.envelope.uid,
    }
    extras["correlation_id"] = deps.call.correlation_id if deps.call.correlation_id
    deps.audit_log.append(
      role:        deps.call.role,
      verb:        "key_mv",
      key:         ctx.to_key,
      etag_before: ctx.etag_before,
      etag_after:  ctx.etag_after,
      extras:      extras,
    )
    ctx
  end
end

DEFAULT_MOVE = [
  ResolvePaths,        # from_key/to_key → from_path/to_path
  AssertSourceExists,  # raises UnknownKey unless from_path exists
  ReadMoveEtagBefore,  # etag_before = file_store.etag(from_path)
  CheckMoveEtag,       # raises EtagMismatch if if_etag given and mismatches
  MoveFile,            # file_store.mv(from_path, to_path)
  PruneSourceParents,  # remove now-empty ancestor dirs on the source side
  RewriteBasename,     # Format.rewrite_name(to_path, basename)
  ReadEtagAfter,       # etag_after = Value::Etag.for_file(to_path)
  ReadEnvelope,        # reader.read(to_key) → envelope
  AppendMoveAudit,     # audit_log.append(verb: "key_mv", ...)
].freeze
```

- [ ] **Step 4: Replace Writer#move body**

In `lib/textus/store/entry/writer.rb`, replace the existing `move` method:

```ruby
def move(from_key:, to_key:, new_mentry:, if_etag: nil)
  ctx = WriteStep::MoveContext.new(
    from_key:, to_key:, new_mentry:, if_etag:,
    from_path: nil, to_path: nil,
    etag_before: nil, etag_after: nil, envelope: nil,
  )
  deps = WriteStep::WriteDeps.new(
    file_store: @file_store, manifest: @manifest, schemas: @schemas,
    audit_log: @audit_log, call: @call, reader: @reader, layout: @layout,
  )
  ctx = WriteStep::DEFAULT_MOVE.reduce(ctx) { |c, step| step.call(c, deps) }
  ctx.envelope
end
```

- [ ] **Step 5: Run write_step spec and mv conformance spec**

```
bundle exec rspec spec/unit/store/entry/write_step_spec.rb -f doc
bundle exec rspec spec/conformance/write/mv_spec.rb -f doc
```

Expected: all pass.

- [ ] **Step 6: Run full suite**

```
bundle exec rspec --format progress
```

- [ ] **Step 7: Commit**

```bash
git add lib/textus/store/entry/write_step.rb \
        lib/textus/store/entry/writer.rb \
        spec/unit/store/entry/write_step_spec.rb
git commit -m "refactor: decompose Writer#move into WriteStep::DEFAULT_MOVE chain"
```
