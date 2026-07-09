# Format + Loop Constant + Key Duality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate duplicated `data_to_payload` across format classes, derive loop nodes from manifest instead of hardcoded constant, and canonicalize to string keys internally.

**Architecture:** Three independent subsytems: (1) Lift `data_to_payload` to `Format::Base` as a template method. (2) Replace `LOOP_NODE_KEYS` constant with manifest-derived query. (3) Pick string keys as canonical internal format, eliminating scattered `transform_keys` calls.

**Tech Stack:** Ruby 3.3+, RSpec

---

## File Inventory

### Candidate 3 — Format Duplication
| File | Action |
|------|--------|
| `lib/textus/protocol/format/base.rb` | Add `data_to_payload` template method + `format_payload` hook |
| `lib/textus/protocol/format/json.rb` | Replace `data_to_payload` with `format_payload` |
| `lib/textus/protocol/format/yaml.rb` | Replace `data_to_payload` with `format_payload` |
| `lib/textus/protocol/format/markdown.rb` | Replace `data_to_payload` with `format_payload` |
| `lib/textus/protocol/format/text.rb` | Replace `data_to_payload` with `format_payload` |
| `lib/textus/protocol/format/script.rb` | Replace `data_to_payload` with `format_payload` |

### Candidate 4 — Loop Constant
| File | Action |
|------|--------|
| `lib/textus/lanes/knowledge/handlers.rb` | Delete `LOOP_NODE_KEYS`, replace with manifest-derived query |
| `spec/unit/lanes/knowledge/handlers_spec.rb` | Update tests |

### Candidate 6 — Key Duality
| File | Action |
|------|--------|
| `lib/textus/adapters/mcp_adapter.rb` | `deep_stringify_keys` on params before binding |
| `lib/textus/adapters/web_adapter.rb` | Stringify keys instead of symbolize |
| `lib/textus/protocol/format/json.rb` | Remove `transform_keys(&:to_s)` from all `data_to_payload` |
| `lib/textus/protocol/format/yaml.rb` | Same |
| `lib/textus/protocol/format/markdown.rb` | Same |
| `lib/textus/protocol/format/text.rb` | Same |
| `lib/textus/protocol/format/script.rb` | Same |
| `lib/textus/protocol/binder.rb` | Ensure `inputs_from_wire` is the primary binding path |
| `lib/textus/adapters/web_adapter.rb` | Change `transform_keys(&:to_sym)` to stringify |
| `lib/textus/handlers/concern.rb` | Update `response` helper |

---

## Task Breakdown

### Task 1: Lift data_to_payload to Format::Base

**Files:**
- Modify: `lib/textus/protocol/format/base.rb`

- [ ] **Step 1: Write the failing test for Base template method**

```ruby
# spec/unit/protocol/format/base_spec.rb
RSpec.describe Textus::Protocol::Format::Base do
  it "provides data_to_payload template method" do
    expect(described_class).to respond_to(:data_to_payload)
  end

  it "stringifies hash keys before calling format_payload" do
    result = described_class.data_to_payload({ name: "test" })
    expect(result[:meta]).to eq({})
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/unit/protocol/format/base_spec.rb`
Expected: FAIL — no such method

- [ ] **Step 3: Add template method to Base**

```ruby
# lib/textus/protocol/format/base.rb — add after validate_raw_entry!
def self.data_to_payload(data)
  data = data.transform_keys(&:to_s) if data.is_a?(Hash)
  format_payload(data)
end

def self.format_payload(data)
  { meta: data["_meta"] || {}, body: (data["body"] || "").to_s, content: nil }
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/unit/protocol/format/base_spec.rb`
Expected: PASS

- [ ] **Step 5: Replace data_to_payload in json.rb**

```ruby
# lib/textus/protocol/format/json.rb — replace existing data_to_payload
def self.format_payload(data)
  { meta: data["_meta"] || {}, body: nil, content: data["content"] || data }
end
```

- [ ] **Step 6: Replace data_to_payload in yaml.rb**

```ruby
# lib/textus/protocol/format/yaml.rb — replace existing data_to_payload
def self.format_payload(data)
  { meta: data["_meta"] || {}, body: nil, content: data["content"] || data }
end
```

- [ ] **Step 7: Replace data_to_payload in markdown.rb**

```ruby
# lib/textus/protocol/format/markdown.rb — replace existing data_to_payload
def self.format_payload(data)
  { meta: data["_meta"] || {}, body: (data["body"] || "").to_s, content: nil }
end
```

- [ ] **Step 8: Replace data_to_payload in text.rb**

```ruby
# lib/textus/protocol/format/text.rb — replace existing data_to_payload
def self.format_payload(data)
  { meta: data["_meta"] || {}, body: (data["body"] || "").to_s, content: nil }
end
```

- [ ] **Step 9: Replace data_to_payload in script.rb**

```ruby
# lib/textus/protocol/format/script.rb — replace existing data_to_payload
def self.format_payload(data)
  { meta: data["_meta"] || {}, body: (data["body"] || "").to_s, content: nil }
end
```

- [ ] **Step 10: Run full test suite**

Run: `bundle exec rspec`
Expected: all green

- [ ] **Step 11: Commit**

```
git add lib/textus/protocol/format/
git commit -m "refactor: lift data_to_payload to Format::Base template method"
```

---

### Task 2: Replace LOOP_NODE_KEYS with manifest-derived query

**Files:**
- Modify: `lib/textus/lanes/knowledge/handlers.rb`

- [ ] **Step 1: Write failing test for manifest-derived loop**

```ruby
# spec/unit/lanes/knowledge/handlers_spec.rb
RSpec.describe Textus::Lanes::Knowledge::Handlers do
  include_context "textus/4 conformance fixture"

  it "derives loop nodes from manifest" do
    result = described_class.loop(ctx: double("ctx", manifest: store.manifest, cursor_store: nil, call: nil))
    expect(result["loop"]).to be_an(Array)
    expect(result["loop"].first).to have_key("name")
    expect(result["loop"].first).to have_key("key")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/unit/lanes/knowledge/handlers_spec.rb`
Expected: FAIL — loop method may not exist with this signature

- [ ] **Step 3: Replace LOOP_NODE_KEYS with dynamic query**

```ruby
# lib/textus/lanes/knowledge/handlers.rb — delete LOOP_NODE_KEYS constant

# Update the loop method:
def loop(ctx:, call:)
  nodes = loop_nodes(ctx.manifest)
  role = call&.role || "agent"
  runner = Runner.new(ctx.manifest)
  feedback = recent_feedback(ctx)
  {
    "loop" => nodes,
    "count" => nodes.size,
    "flow" => runner.flow,
    "current_node" => runner.current_position(role),
    "feedback" => feedback,
  }
end

def loop_nodes(manifest)
  manifest.data.entries
    .select { |e| e.key.start_with?("knowledge.loop.") && e.key.count(".") == 2 }
    .map { |e| { "name" => e.key.split(".").last, "key" => e.key } }
end
```

- [ ] **Step 4: Run tests**

Run: `bundle exec rspec`
Expected: all green

- [ ] **Step 5: Commit**

```
git add lib/textus/lanes/knowledge/handlers.rb
git commit -m "refactor: derive loop nodes from manifest instead of hardcoded constant"
```

---

### Task 3: Canonicalize to string keys in web adapter

**Files:**
- Modify: `lib/textus/adapters/web_adapter.rb`

- [ ] **Step 1: Write failing test**

```ruby
# spec/unit/adapters/web_adapter_spec.rb
it "normalizes input with string keys" do
  req = adapter.normalize({ "action" => "get", "key" => "test" })
  expect(req.action).to eq(:get)
  expect(req.params).to include(:key)
end
```

- [ ] **Step 2: Change to stringify instead of symbolize**

```ruby
# lib/textus/adapters/web_adapter.rb
def call(action, params: {}, role: nil, gate:, session_id: nil)
  str_params = params.transform_keys(&:to_s)
  request = Request.new(
    action: action.to_s.to_sym,
    params: str_params,
    role: role,
    session_id: session_id,
  )
  gate.dispatch(request)
end

def normalize(raw)
  action = raw.delete("action").to_s.to_sym
  role = raw.delete("role")&.to_s
  session_id = raw.delete("session_id")
  Request.new(action:, params: raw, role:, session_id:)
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/unit/adapters/web_adapter_spec.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```
git add lib/textus/adapters/web_adapter.rb
git commit -m "refactor: WebAdapter uses string keys internally"
```

---

### Task 4: Ensure Binder.inputs_from_wire handles string keys consistently

**Files:**
- Modify: `lib/textus/protocol/binder.rb`

- [ ] **Step 1: Write failing test for string key binding**

```ruby
# spec/unit/protocol/binder_spec.rb
RSpec.describe Textus::Protocol::Binder do
  let(:spec) { Textus::Protocol::ActionRegistry.for(:get) }

  it "binds from string keys" do
    result = described_class.inputs_from_wire(spec, { "key" => "test" })
    expect(result[:key]).to eq("test")
  end

  it "binds from symbol keys" do
    result = described_class.bind(spec, { key: "test" })
    expect(result[:key]).to eq("test")
  end
end
```

- [ ] **Step 2: Ensure inputs_from_wire handles both string and symbol keys**

```ruby
# lib/textus/protocol/binder.rb
def inputs_from_wire(spec, raw)
  raw ||= {}
  raw = raw.transform_keys(&:to_s) unless raw.keys.all? { |k| k.is_a?(String) }
  spec.args.each_with_object({}) do |a, h|
    h[a.name] = raw[a.wire.to_s] if raw.key?(a.wire.to_s)
  end
end
```

- [ ] **Step 3: Run tests**

Run: `bundle exec rspec spec/unit/protocol/binder_spec.rb`
Expected: PASS

- [ ] **Step 4: Commit**

```
git add lib/textus/protocol/binder.rb
git commit -m "refactor: Binder.inputs_from_wire handles string keys consistently"
```

---

## Scope check

These three candidates are independent subsystems — each produces working software on its own:

1. **Format duplication (Task 1)** — purely mechanical, no behavioral change
2. **Loop constant (Task 2)** — standalone cleanup of one file
3. **Key duality (Tasks 3-4)** — web adapter + binder stringification. Note: MCP adapter already stringifies via `deep_stringify_keys`, so no change needed there.

Candidate 6 also removes `transform_keys(&:to_s)` from format classes — but Task 1 already does this by moving it to Base. So Candidate 6 is partially completed by Candidate 3.

---

## Verification

After all tasks:
1. `bundle exec rspec` — all green
2. `rtk grep -rn 'transform_keys.*to_sym\|transform_keys.*to_s' lib/textus/protocol/format/` — 0 matches in format/ (handled by Base)
3. `rtk grep -rn 'LOOP_NODE_KEYS' lib/` — 0 matches
