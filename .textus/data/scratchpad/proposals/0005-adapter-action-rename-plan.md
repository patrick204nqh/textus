# Implementation Plan: Complete Adapter Pattern + Verb→Action Rename

Two changes, two phases. Phase 1 is architectural (wires existing adapters). Phase 2 is cosmetic (renames verb→action) and MUST follow Phase 1 because Phase 1 deletes the Verb class hierarchy, eliminating ~50% of rename work.

---

## Phase 1: Complete the Adapter Pattern

**Goal**: Every surface goes through its adapter → Gate. Verb class hierarchy deleted. `Surface::Dispatch` removed. `Response` added.

### Current flow (what runs)

```
CLI argv → Verb class parse → Runner.dispatch → Dispatch.call → Session#method_missing → Request.new → Gate#dispatch → raw Hash
MCP JSON-RPC → Server#dispatch → Catalog.call → Dispatch.call → Session#method_missing → Request.new → Gate#dispatch → raw Hash
Web HTTP → post "/api/:verb" → Dispatch.call → Session#method_missing → Request.new → Gate#dispatch → raw Hash
```

Three surface paths, each builds a `Request` via `Session#method_missing`, then calls `Gate#dispatch` which returns a raw Hash. The adapters (`CliAdapter#normalize`, etc.) are never called.

### Target flow

```
CLI argv → CliAdapter#call → Gate#dispatch → Response → CliAdapter formats → stdout
MCP JSON → McpAdapter#call → Gate#dispatch → Response → McpAdapter formats → JSON-RPC
Web HTTP → WebAdapter#call → Gate#dispatch → Response → WebAdapter formats → HTTP JSON
```

Adapters are the sole surface-specific code. Gate knows nothing about argv, JSON-RPC, HTTP params, exit codes, or --stdin.

### Step 1a — Add `Adapters::Response`

```ruby
# lib/textus/adapters/response.rb
module Textus
  module Adapters
    Response = Data.define(:payload, :error) do
      def success? = error.nil?
    end
  end
end
```

### Step 1b — Gate returns Response

`Gate#dispatch` wraps the handler result:

```ruby
def dispatch(request, env: ENV, cwd: Dir.pwd)
  # ... existing validation, auth, binding ...
  result = handler.public_send(request.verb, **bound, ctx:, call: call_obj)
  persist_session(session, spec) if spec.write?
  Response.new(payload: result, error: nil)
rescue Textus::Error => e
  Response.new(payload: nil, error: e)
end
```

Session#method_missing unwraps when called directly:

```ruby
def method_missing(name, *args, **kwargs)
  if DOMAIN_VERBS.include?(name)
    request = Adapters::Request.new(...)
    response = @gate.dispatch(request)
    raise response.error if response.error
    response.payload
  end
end
```

### Step 1c — Rewrite CliAdapter as a full lifecycle adapter

Current `CliAdapter` only has `normalize(argv) → Request`. Expand it to:

```ruby
class CliAdapter
  SPECIAL_VERBS = {
    %w[init]         => :handle_init,
    %w[mcp serve]    => :handle_mcp_serve,
    %w[web serve]    => :handle_web_serve,
    %w[watch]        => :handle_watch,
  }.freeze

  def call(argv, gate:, stdin:, stdout:, stderr:, cwd:)
    sub = argv.dup
    SPECIAL_VERBS.each do |tokens, method|
      if sub.first(tokens.size) == tokens
        return send(method, gate:, argv: sub.drop(tokens.size), stdin:, stdout:, stderr:, cwd:)
      end
    end

    request = normalize(sub)
    request = enrich_inputs(request, stdin)
    response = gate.dispatch(request, cwd: cwd)
    format_response(response, stdout, stderr)
  end

  def normalize(raw)
    role_kv = raw.find { |a| a.start_with?("--as=") }
    non_flag = raw.reject { |a| a.start_with?("--") }
    action = non_flag.first
    Request.new(
      verb: (action || "help").to_s.to_sym,
      params: { positionals: non_flag.drop(1) },
      role: role_kv&.delete_prefix("--as=") || @default_role,
    )
  end

  private

  def enrich_inputs(request, stdin)
    spec = VerbRegistry.for(request.verb)
    return request.params unless spec
    inputs = request.params.dup
    inputs = apply_cli_defaults(spec, inputs)
    inputs = read_stdin(spec, inputs, stdin) if STDIN_VERBS.include?(request.verb)
    inputs
  end

  def format_response(response, stdout, stderr)
    if response.success?
      stdout.puts(JSON.generate({ "protocol" => PROTOCOL }.merge(response.payload)))
      0
    else
      err = response.error
      stdout.puts(JSON.generate(err.to_envelope))
      stderr.puts("#{err.code}: #{err.message}")
      stderr.puts("  → #{err.hint}") if err.hint
      err.exit_code
    end
  end
end
```

**The CliAdapter replaces**: `verb.rb` (base class), `runner.rb`, `sources.rb`, `group.rb`, `group/*.rb` (6), `verb/*.rb` (11) = **18 files deleted**.

### Step 1d — Simplify Surface::CLI

Before: `CLI#run` resolves Verb class via `self.class.verbs[verb]`, creates instance, parses, calls.

After:
```ruby
def run(argv)
  adapter = Adapters::CliAdapter.new
  adapter.call(argv, gate: store_gate, stdin: @stdin, stdout: @stdout, stderr: @stderr, cwd: @cwd)
end

def store_gate
  Session.open(store_root).gate
end
```

### Step 1e — Simplify Surface::Web

Before: `post "/api/:verb"` → `Dispatch.call(session, params[:verb], body)` → Session#method_missing.

After:
```ruby
post "/api/:verb" do
  adapter = Adapters::WebAdapter.new
  body = JSON.parse(request.body.read) rescue {}
  response = adapter.call(verb: params[:verb], **body, gate: settings.textus_gate)
  status response.success? ? 200 : error_status(response.error)
  content_type :json
  JSON.generate(response.payload || { error: response.error.message })
end
```

### Step 1f — Simplify Surface::MCP::Server#dispatch

Before: `Server#dispatch` → `Catalog.call` → `Dispatch.call` → Session#method_missing.

After: `Server#dispatch` calls `McpAdapter` directly, which normalizes + dispatches via Gate + formats Response as JSON-RPC result/error.

```ruby
def dispatch(verb_name, args, _server_context)
  adapter = Textus::Adapters::McpAdapter.new
  request = adapter.normalize({ "method" => verb_name, "params" => args })
  response = @gate.dispatch(request)
  response = DriftAnnotation.apply(response, verb_name:, drifted:, ...)
  adapter.format(response)
end
```

### Step 1g — Delete dead files (18)

- `lib/textus/surface/cli/verb.rb`
- `lib/textus/surface/cli/runner.rb`
- `lib/textus/surface/cli/sources.rb`
- `lib/textus/surface/cli/group.rb`
- `lib/textus/surface/cli/group/data.rb`
- `lib/textus/surface/cli/group/key.rb`
- `lib/textus/surface/cli/group/mcp.rb`
- `lib/textus/surface/cli/group/node.rb`
- `lib/textus/surface/cli/group/schema.rb`
- `lib/textus/surface/cli/group/web.rb`
- `lib/textus/surface/cli/verb/get.rb`
- `lib/textus/surface/cli/verb/init.rb`
- `lib/textus/surface/cli/verb/mcp_serve.rb`
- `lib/textus/surface/cli/verb/node_back.rb`
- `lib/textus/surface/cli/verb/node_enter.rb`
- `lib/textus/surface/cli/verb/node_exit.rb`
- `lib/textus/surface/cli/verb/node_status.rb`
- `lib/textus/surface/cli/verb/node_switch.rb`
- `lib/textus/surface/cli/verb/put.rb`
- `lib/textus/surface/cli/verb/watch.rb`
- `lib/textus/surface/cli/verb/web_serve.rb`
- `lib/textus/surface/dispatch.rb`

### Step 1h — Spec updates

- Update adapter specs for full lifecycle
- Remove specs for deleted Verb/Group classes
- Update gate_spec.rb for Response return type

---

## Phase 2: Verb → Action Rename

**Goal**: Hard cut — every internal reference to `verb` is renamed to `action`. No aliases, no backward-compat constants, no `alias_method`. The word "verb" survives ONLY in the DB column name (`:verb`) and the JSON-RPC wire field (`"verb"`).

**Prerequisite**: Phase 1 complete (deletes Verb class hierarchy, removing ~50% of rename surface area).

**Hard cut rule**: After Phase 2, code search for `\bverb\b` in `lib/` should return ZERO results except for:
1. `:verb` as a Sequel column reference (maps to DB column name — schema fact, not terminology)
2. `"verb"` as a JSON key in error envelopes (wire protocol backward compat)

Anything else — constants, modules, methods, variables, file paths — gets renamed.

### Step 2a — Rename core protocol types

**File rename**: `lib/textus/protocol/verb_registry.rb` → `lib/textus/protocol/action_registry.rb`

Module rename within file:
```ruby
# Before: module VerbRegistry → After: module ActionRegistry
module Textus
  module Protocol
    module ActionRegistry
      ACTIONS = {}
      POSITIONAL = {}

      def self.register(spec)
        ACTIONS[spec.action] = spec
        POSITIONAL[spec.action] = spec.args.select(&:positional).map(&:name)
      end

      def self.for(action) = ACTIONS[action]
      def self.positional_for(action) = POSITIONAL[action] || []
      def self.summary_for(action) = ACTIONS[action]&.summary
      def self.registered = ACTIONS.values
```

**Directory rename**: `lib/textus/protocol/verb_registry/` → `lib/textus/protocol/action_registry/`

Update all `require_relative` paths in sibling files.

### Step 2b — Rename VerbSpec → ActionSpec, property `verb` → `action`

```ruby
# Before: VerbSpec = Data.define(:verb, :summary, ...)
# After:  ActionSpec = Data.define(:action, :summary, ...)
ActionSpec = Data.define(:action, :summary, :args, :surfaces, :category) do
  # NO alias_method — this is a hard cut
  def initialize(action:, summary:, args:, surfaces:, category:, lane: nil)
    @lane = lane
    super(action:, summary:, args:, surfaces:, category:)
  end

  def lane = @lane
  def system? = SYSTEM_ACTIONS.include?(action)
  def mcp? = surfaces.include?(:mcp)
  def cli? = surfaces.include?(:cli)
  # ...
end
```

### Step 2c — Rename lane Verbs modules → Actions

Each lane's verb registration file:
```ruby
# Before: module Verbs → After: module Actions
module Textus
  module Lanes
    module Knowledge
      module Actions
      end
    end
  end
end

Textus::Protocol::ActionRegistry.register(
  Textus::Protocol::ActionRegistry::ActionSpec.new(
    action: :loop, summary: "Return the knowledge loop structure...",
    ...
```

### Step 2d — Mechanical renames (no aliases, no backward compat)

| Old | New | Notes |
|---|---|---|
| `VerbRegistry` | `ActionRegistry` | Module name, all references |
| `VerbSpec` | `ActionSpec` | Class name, all references |
| `CoreVerbs` | `CoreActions` | core_verbs.rb constant |
| `NodeVerbs` | `NodeActions` | node_verbs.rb module |
| `VERBS` (hash) | `ACTIONS` | ActionRegistry internal hash |
| `ENTRY_VERBS` | `ENTRY_ACTIONS` | action_registry.rb |
| `OPS_VERBS` | `OPS_ACTIONS` | action_registry.rb |
| `NODE_VERBS` | `NODE_ACTIONS` | action_registry.rb |
| `VERB_DOMAIN` | `ACTION_DOMAIN` | action_registry.rb |
| `DOMAIN_VERBS` | `DOMAIN_ACTIONS` | session.rb |
| `AUTHOR_VERBS` | `AUTHOR_ACTIONS` | gate.rb |
| `SYSTEM_VERBS` | `SYSTEM_ACTIONS` | verb_spec.rb → action_spec.rb |
| `STDIN_VERBS` | `STDIN_ACTIONS` | cli_adapter.rb |
| `read_verbs` / `write_verbs` | `read_actions` / `write_actions` | catalog.rb, context.rb |
| `build_verb_lists` | `build_action_lists` | context.rb |
| `verb_name` param | `action_name` | dispatch.rb, server.rb, drift_annotation.rb |
| `spec.verb` | `spec.action` | Every ActionSpec consumer |
| `request.verb` | `request.action` | gate.rb, session.rb, all adapters |
| `request#verb` Data.define member | `request#action` | request.rb — Data.define(:action, ...) |
| `check_author_verb!` | `check_author_action!` | gate.rb |
| `handler.public_send(request.verb, ...)` | `handler.public_send(request.action, ...)` | gate.rb |
| `AUTHOR_VERBS.include?(verb)` | `AUTHOR_ACTIONS.include?(action)` | gate.rb |
| `for(verb)` | `for(action)` | ActionRegistry method |
| `positional_for(verb)` | `positional_for(action)` | ActionRegistry method |
| `summary_for(verb)` | `summary_for(action)` | ActionRegistry method |
| File `verb_spec.rb` | `action_spec.rb` | Core file rename |
| File `core_verbs.rb` | `core_actions.rb` | Core file rename |
| File `node_verbs.rb` | `node_actions.rb` | Core file rename |
| File `verbs.rb` (knowledge) | `actions.rb` | Lane rename |
| File `verbs.rb` (scratchpad) | `actions.rb` | Lane rename |
| File `verbs.rb` (artifact) | `actions.rb` | Lane rename |

### Step 2e — NOT renamed (schema + wire protocol)

These survive as the ONLY occurrences of "verb" in lib/ after Phase 2:

1. **DB column** — `String :verb` in `lib/textus/infra/database.rb` (maps to SQL column `verb`)  
   *Reason*: Schema fact, not code terminology. Changing would require a migration.
2. **audit_log method params** — `def append(role:, verb:, key:, ...)` and `def list(..., verb:, ...)`  
   *Reason*: These map directly to the DB column name. Renaming the Ruby param while the column stays `:verb` creates confusion.
3. **WriteForbidden error** — `verb:` param and `details["verb"] = verb` JSON key  
   *Reason*: User-facing error envelope. Changing the JSON key is a wire protocol change.
4. **JSON-RPC wire field** — `"verb"` filter key in audit params  
   *Reason*: MCP client sends `{"verb": "audit"}`. Renaming breaks every client.
5. **ArgSpec wire_name** — `ArgSpec.arg(name: :verb, ...)` for audit handler  
   *Reason*: The wire name maps to the JSON-RPC field `"verb"` that clients send.

These 5 locations are the ENTIRE remaining footprint of "verb" after Phase 2.
All are schema/wire concerns — invisible to internal dispatch, handler code,
and the adapter layer.

### Step 2f — Spec updates

Every spec file referencing VerbRegistry, VerbSpec, spec.verb, request.verb,
verb_name, etc. gets renamed. Wire protocol references (the 5 exceptions above) stay.

### Step 2g — Git-level confirmation

After Phase 2, confirm with:
```bash
grep -r '\bverb\b' lib/ --include='*.rb' | grep -v '^\s*#' | grep -v '^\s*$'
```
Expected output: only the 5 DB/wire locations from Step 2e (plus comments).

---

## Phase Order Dependency

```
Phase 1 (adapter wiring) ──→ Phase 2 (rename)
  │                           │
  │ Deletes 18 files          │ Renames ~30 remaining files
  │ Adds Response type        │ Renames 7 directories
  │ Adds CliAdapter lifecycle  │ Updates all spec references
  │ Removes Dispatch          │
  │                           │
  └── No overlap: Phase 1     │
      removes Verb classes    │
      (~50% of rename target) │
                              │
  Phase 2 is pure mechanical  │
  rename — no behavior change │
```

Phase 1 cannot be split from Phase 2 (would cause churn on Verb classes that get deleted anyway). Phase 2 is mechanical rename after Phase 1.

---

## Spec Strategy

1. **Adapter specs become integration specs**: each adapter test exercises the full parse→normalize→dispatch→format cycle.
2. **Verb class specs are deleted** (Phase 1 removes the classes).
3. **Gate spec updated** to assert Response type on success and error paths.
4. **Marry up**: `bundle exec rspec` must stay green after each commit.

---

## Risk Mitigation

### Phase 1 risks
- **Session#method_missing → backward compat break**: Update method_missing to unwrap Response. Direct Ruby API callers (specs, Session.open boot) continue to work.
- **Special verb behavior lost**: Each escape hatch (init, mcp_serve, web_serve, watch, get, put) gets explicit handling in CliAdapter.
- **Group subcommand routing lost**: `textus key delete`, `textus mcp serve`, etc. handled by SPECIAL_VERBS hash in CliAdapter.

### Phase 2 risks
- **Stale imports**: Every `require_relative "verb_registry/..."` path must be updated to `action_registry/...`.
- **Missed reference**: After Phase 2, `grep -r '\bverb\b' lib/ --include='*.rb'` must return zero code references. Any missed reference is a bug. Verify with the grep command from Step 2g.
- **Wire protocol break**: The 5 survivors (DB column, audit_log params, WriteForbidden, JSON-RPC field, ArgSpec wire_name) are the ONLY allowed occurrences. Internal `action_name` variable is invisible to clients.
- **DB schema**: `:verb` column stays. No migration needed.
- **Old require paths**: Spec files and `require` statements in non-renamed files may still point to `verb_registry/` paths. Must sweep all `require_relative` calls.

---

## Completion Check

After both phases:

```
bundle exec rspec          # all green
bundle exec rubocop        # all clean
textus boot                # still works
textus list                # still works
echo '{"method":"list","params":{}}' | textus mcp serve  # MCP still works
grep -r '\bverb\b' lib/ --include='*.rb' | grep -v '^\s*#' | grep -v '^\s*$'
# ^ Expected: ONLY the 5 schema/wire locations from Phase 2 Step 2e
```

No wire protocol changes. No DB schema changes. No manifest changes.

**Hard cut gate**: If `grep -r '\bverb\b' lib/ --include='*.rb'` returns more than the 5 exempted locations (DB column, audit_log params, WriteForbidden, JSON-RPC field, ArgSpec wire_name), Phase 2 is incomplete.
