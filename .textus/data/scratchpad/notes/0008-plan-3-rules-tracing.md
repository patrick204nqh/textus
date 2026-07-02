---
title: Rules System Debugging — Resolution Tracing Implementation Plan
uid: e673a7d0b2892938
---
# Rules System Debugging — Resolution Tracing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rule resolution tracing to `Manifest::Rules` and expose it as a new `rule_trace` verb on CLI and MCP.

**Architecture:** `Manifest::Rules#for(key)` is refactored to delegate to `for_with_trace(key)`, which returns `[RuleSet, RuleTrace]`. `RuleTrace` is a `Data.define` capturing every pattern tested, which matched, and which won. A new `rule_trace` verb is registered in `VerbRegistry`, a handler module added to `Handlers::Maintenance`, a contract added to `Dispatch::Contracts`, and a row added to `Dispatch::Assembler::HANDLER_MANIFEST`.

**Tech Stack:** Ruby 3.x, Data.define, RSpec, bundle exec rspec

## Global Constraints

- No Co-Authored-By trailers in commits
- All tests: `bundle exec rspec`; lint: `bundle exec rubocop -A`
- Stage specific files only, never `git add -A`

---

## File Map

### New
- `lib/textus/manifest/rule_trace.rb` — `Manifest::RuleTrace = Data.define(...)`
- `lib/textus/handlers/maintenance/rule_trace.rb` — handler module
- `spec/unit/manifest/rules_trace_spec.rb`
- `spec/unit/handlers/maintenance/rule_trace_spec.rb`
- `spec/conformance/read/rule_trace_verb_spec.rb`

### Modified
- `lib/textus/manifest/rules.rb` — `for` delegates to `for_with_trace`; `for_with_trace` added; `pick` refactored to expose specificity
- `lib/textus/dispatch/contracts.rb` — add `RuleTrace = Data.define(:key)`
- `lib/textus/verb_registry.rb` — register `:rule_trace` VerbSpec
- `lib/textus/dispatch/assembler.rb` — add `RuleTrace` row to `HANDLER_MANIFEST`

---

## Task 1: RuleTrace value object + Rules#for_with_trace

**Files:**
- Create: `lib/textus/manifest/rule_trace.rb`
- Modify: `lib/textus/manifest/rules.rb`
- Create: `spec/unit/manifest/rules_trace_spec.rb`

**Interfaces:**
- Produces: `Textus::Manifest::RuleTrace` (Data.define with 4 fields)
- `Manifest::Rules#for_with_trace(key) → [RuleSet, RuleTrace]`
- `Manifest::Rules#for(key) → RuleSet` (unchanged behaviour)

---

- [ ] **Step 1: Write the failing tests**

```ruby
# spec/unit/manifest/rules_trace_spec.rb
require "spec_helper"

RSpec.describe "Manifest::Rules#for_with_trace" do
  # Manifest with two overlapping rules: "decisions.*" (more specific) and "*" (catchall)
  let(:rules) do
    Textus::Manifest::Rules.parse([
      { "match" => "decisions.*", "retain" => "90d" },
      { "match" => "*",           "fresh_within" => "7d" },
      { "match" => "knowledge.*"  },
    ])
  end

  describe "RuleTrace" do
    it "is a Data.define with key, candidates, winners, ruleset_fields" do
      expect(Textus::Manifest::RuleTrace.members).to contain_exactly(
        :key, :candidates, :winners, :ruleset_fields,
      )
    end
  end

  describe "#for_with_trace" do
    let(:key) { "decisions.adr-0001" }
    let(:result) { rules.for_with_trace(key) }
    let(:ruleset) { result.first }
    let(:trace)   { result.last }

    it "returns a two-element array [RuleSet, RuleTrace]" do
      expect(result.size).to eq(2)
      expect(ruleset).to be_a(Textus::Manifest::Rules::RuleSet)
      expect(trace).to be_a(Textus::Manifest::RuleTrace)
    end

    it "trace.key equals the queried key" do
      expect(trace.key).to eq(key)
    end

    it "candidates covers every rule block including non-matching ones" do
      expect(trace.candidates.size).to eq(3)  # decisions.*, *, knowledge.*
      decisions_candidate = trace.candidates.find { |c| c["pattern"] == "decisions.*" }
      knowledge_candidate = trace.candidates.find { |c| c["pattern"] == "knowledge.*" }
      expect(decisions_candidate["matched"]).to be(true)
      expect(knowledge_candidate["matched"]).to be(false)
      expect(knowledge_candidate["specificity"]).to eq(0)
    end

    it "winners contains only matched blocks, sorted highest-specificity first" do
      expect(trace.winners.map { |w| w["pattern"] }).to eq(["decisions.*", "*"])
    end

    it "ruleset_fields matches the RuleSet returned by for(key)" do
      expected_ruleset = rules.for(key)
      expect(trace.ruleset_fields).to eq(expected_ruleset.to_h)
    end

    it "#for(key) returns the same RuleSet as for_with_trace(key).first (non-regression)" do
      via_for       = rules.for(key)
      via_trace, _  = rules.for_with_trace(key)
      expect(via_for).to eq(via_trace)
    end

    it "specificity in candidates matches the scoring used to pick winners" do
      # decisions.* has specificity 11 (1 literal segment = 10, 1 wildcard = 1)
      # * has specificity 1 (1 wildcard)
      # The winner is decisions.* (higher specificity)
      winning_pattern = trace.winners.first["pattern"]
      expect(winning_pattern).to eq("decisions.*")
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```
bundle exec rspec spec/unit/manifest/rules_trace_spec.rb -f doc
```

Expected: `NameError: uninitialized constant Textus::Manifest::RuleTrace`

---

- [ ] **Step 3: Create RuleTrace**

```ruby
# lib/textus/manifest/rule_trace.rb
module Textus
  class Manifest
    # Captures every decision made during Rules#for_with_trace resolution.
    #
    # candidates — Array of { "pattern" => String, "matched" => Boolean, "specificity" => Integer }
    #   Every rule block tested, including non-matching ones (specificity 0 for non-matches).
    #
    # winners — Array of { "pattern" => String, "specificity" => Integer, "fields" => Hash }
    #   Matched blocks that contributed to the RuleSet, sorted highest-specificity first.
    #
    # ruleset_fields — Hash
    #   The merged result: identical to RuleSet#to_h for the same key.
    RuleTrace = Data.define(:key, :candidates, :winners, :ruleset_fields)
  end
end
```

- [ ] **Step 4: Add for_with_trace to Manifest::Rules**

In `lib/textus/manifest/rules.rb`, refactor `for` to call `for_with_trace`, and add `for_with_trace`:

```ruby
def for(key)
  for_with_trace(key).first
end

def for_with_trace(key)
  candidates = @blocks.map do |b|
    matched     = Textus::Manifest::Policy::Matcher.matches?(b.match, key)
    specificity = matched ? Textus::Manifest::Policy::Matcher.specificity(b.match) : 0
    { "pattern" => b.match, "matched" => matched, "specificity" => specificity }
  end

  winning_blocks = @blocks
    .select  { |b| Textus::Manifest::Policy::Matcher.matches?(b.match, key) }
    .sort_by { |b| [-Textus::Manifest::Policy::Matcher.specificity(b.match), b.match.length, b.match] }

  ruleset = build_ruleset_from(winning_blocks, key)

  trace = Manifest::RuleTrace.new(
    key:,
    candidates:,
    winners: winning_blocks.map do |b|
      {
        "pattern"     => b.match,
        "specificity" => Textus::Manifest::Policy::Matcher.specificity(b.match),
        "fields"      => PICK_FIELDS.each_with_object({}) { |f, h| h[f.to_s] = b.public_send(f) if b.public_send(f) },
      }
    end,
    ruleset_fields: ruleset.to_h,
  )

  [ruleset, trace]
end
```

Add `build_ruleset_from` as a private helper that replaces the existing inline slot-building logic:

```ruby
private

def build_ruleset_from(winning_blocks, key)
  slots = PICK_FIELDS.to_h { |f| [f, []] }
  # All blocks (not just winners) contribute their fields to the slots pool
  @blocks.each do |b|
    next unless Textus::Manifest::Policy::Matcher.matches?(b.match, key)
    slots.each_key { |slot| slots[slot] << b if b.public_send(slot) }
  end
  RuleSet.new(**slots.to_h { |slot, blocks| [slot, pick(blocks, slot, key)] })
end
```

Add `require_relative "rule_trace"` to `lib/textus/manifest/rules.rb` (or to `lib/textus/manifest.rb`).

- [ ] **Step 5: Run the new tests**

```
bundle exec rspec spec/unit/manifest/rules_trace_spec.rb -f doc
```

Expected: all examples pass.

- [ ] **Step 6: Run full suite to confirm non-regression**

```
bundle exec rspec --format progress
```

- [ ] **Step 7: Commit**

```bash
git add lib/textus/manifest/rule_trace.rb \
        lib/textus/manifest/rules.rb \
        spec/unit/manifest/rules_trace_spec.rb
git commit -m "feat: add Manifest::RuleTrace and Rules#for_with_trace — resolution tracing"
```

---

## Task 2: rule_trace verb — contract, handler, VerbRegistry, HANDLER_MANIFEST

Wire the new trace capability into the dispatch pipeline and expose it on CLI + MCP.

**Files:**
- Modify: `lib/textus/dispatch/contracts.rb` — add `RuleTrace = Data.define(:key)`
- Create: `lib/textus/handlers/maintenance/rule_trace.rb` — handler module
- Modify: `lib/textus/verb_registry.rb` — register `:rule_trace` VerbSpec
- Modify: `lib/textus/dispatch/assembler.rb` — add `RuleTrace` row to `HANDLER_MANIFEST`
- Create: `spec/conformance/read/rule_trace_verb_spec.rb`

**Interfaces:**
- Consumes: `Manifest::RuleTrace` and `Rules#for_with_trace` from Task 1
- Produces: `store.rule(:rule_trace, key: "decisions.adr-0001") → Hash` with keys "key", "candidates", "winners", "ruleset_fields"

---

- [ ] **Step 1: Write the conformance test**

```ruby
# spec/conformance/read/rule_trace_verb_spec.rb
require "spec_helper"

RSpec.describe "rule_trace verb" do
  include_context "textus_store_fixture"

  before do
    FileUtils.mkdir_p(File.join(root, "data", "decisions"))
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: decisions, kind: canon }
      entries:
        - key: decisions.adr-0001
          path: decisions/adr-0001.md
          lane: decisions
          owner: human:self
          kind: leaf
      rules:
        - match: "decisions.*"
          retain: "90d"
        - match: "*"
          fresh_within: "7d"
    YAML
  end

  let(:store) { Textus::Store.new(root) }

  it "returns a trace with candidates, winners, and ruleset_fields" do
    result = store.rule(:rule_trace, key: "decisions.adr-0001")

    expect(result["key"]).to eq("decisions.adr-0001")
    expect(result["candidates"]).to be_an(Array)
    expect(result["candidates"].size).to eq(2)

    decisions_candidate = result["candidates"].find { |c| c["pattern"] == "decisions.*" }
    expect(decisions_candidate["matched"]).to be(true)
    expect(decisions_candidate["specificity"]).to be > 0

    star_candidate = result["candidates"].find { |c| c["pattern"] == "*" }
    expect(star_candidate["matched"]).to be(true)

    expect(result["winners"].first["pattern"]).to eq("decisions.*")
    expect(result["ruleset_fields"].key?("retain")).to be(true)
  end

  it "includes non-matching candidates with matched: false" do
    File.write(File.join(root, "manifest.yaml"), <<~YAML)
      version: textus/4
      lanes:
        - { name: decisions, kind: canon }
      entries:
        - { key: decisions.foo, path: decisions/foo.md, lane: decisions, owner: human:self, kind: leaf }
      rules:
        - match: "knowledge.*"
          retain: "30d"
        - match: "decisions.*"
          retain: "90d"
    YAML
    store2 = Textus::Store.new(root)
    result = store2.rule(:rule_trace, key: "decisions.foo")

    knowledge_candidate = result["candidates"].find { |c| c["pattern"] == "knowledge.*" }
    expect(knowledge_candidate["matched"]).to be(false)
    expect(knowledge_candidate["specificity"]).to eq(0)
  end

  it "is accessible via CLI as 'textus rule trace KEY'" do
    out = StringIO.new
    err = StringIO.new
    code = Textus::Surface::CLI.run(
      ["rule", "trace", "decisions.adr-0001"],
      stdin: StringIO.new, stdout: out, stderr: err, cwd: File.dirname(root)
    )
    expect(code).to be_an(Integer)
    parsed = JSON.parse(out.string)
    expect(parsed["key"]).to eq("decisions.adr-0001")
  end
end
```

- [ ] **Step 2: Run to verify it fails**

```
bundle exec rspec spec/conformance/read/rule_trace_verb_spec.rb -f doc
```

Expected: failures related to missing `:rule_trace` verb or handler.

---

- [ ] **Step 3: Add RuleTrace contract**

In `lib/textus/dispatch/contracts.rb`, after `RuleLint`:

```ruby
RuleTrace = Data.define(:key)
```

- [ ] **Step 4: Create handler module**

```ruby
# lib/textus/handlers/maintenance/rule_trace.rb
module Textus
  module Handlers
    module Maintenance
      module RuleTrace
        HANDLES = Dispatch::Contracts::RuleTrace
        NEEDS   = %i[manifest].freeze

        def self.call(command, _call, deps)
          _, trace = deps.manifest.rules.for_with_trace(command.key)
          Value::Result.success(trace.to_h)
        end
      end
    end
  end
end
```

- [ ] **Step 5: Register rule_trace in VerbRegistry**

In `lib/textus/verb_registry.rb`, after the `rule_lint` registration block:

```ruby
# ── rule_trace ──────────────────────────────────────────────
register VerbSpec.new(
  :rule_trace,
  "Trace rule resolution for a key — shows every pattern tested, which matched, and which won.",
  [ArgSpec.arg(name: :key, required: true, positional: true,
               description: "dotted key whose rule resolution you want to trace")],
  %i[cli mcp],
  { default: ->(v, _) { v.is_a?(Hash) ? v : v.to_h } },
  "rule trace",
  nil,
  :read,
)
```

Also add `:rule_trace` to `VERB_TO_CONTRACT` in VerbRegistry:

```ruby
rule_trace: Dispatch::Contracts::RuleTrace,
```

And add `:rule_trace` to `RULE_VERBS` in VerbRegistry:

```ruby
RULE_VERBS = %i[rule_explain rule_list schema_show rule_lint rule_trace].freeze
```

- [ ] **Step 6: Add row to HANDLER_MANIFEST**

In `lib/textus/dispatch/assembler.rb`, in `HANDLER_MANIFEST`, after the `RuleLint` row:

```ruby
[Contracts::RuleTrace,
 Handlers::Maintenance::RuleTrace,
 { manifest: :manifest }],
```

- [ ] **Step 7: Run the conformance test**

```
bundle exec rspec spec/conformance/read/rule_trace_verb_spec.rb -f doc
```

Expected: all examples pass.

- [ ] **Step 8: Run the assembler completeness spec**

```
bundle exec rspec spec/unit/dispatch/assembler_spec.rb -f doc
```

Expected: all 3 pass (the new `RuleTrace` contract is now in HANDLER_MANIFEST).

- [ ] **Step 9: Run full suite**

```
bundle exec rspec --format progress
```

Expected: same pass count baseline.

- [ ] **Step 10: Rubocop**

```
bundle exec rubocop lib/textus/dispatch/contracts.rb \
                    lib/textus/handlers/maintenance/rule_trace.rb \
                    lib/textus/verb_registry.rb \
                    lib/textus/dispatch/assembler.rb
```

Fix any offenses.

- [ ] **Step 11: Commit**

```bash
git add lib/textus/dispatch/contracts.rb \
        lib/textus/handlers/maintenance/rule_trace.rb \
        lib/textus/verb_registry.rb \
        lib/textus/dispatch/assembler.rb \
        spec/conformance/read/rule_trace_verb_spec.rb
git commit -m "feat: rule_trace verb — expose Rules#for_with_trace via CLI+MCP"
```
