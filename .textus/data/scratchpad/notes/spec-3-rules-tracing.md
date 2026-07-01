---
title: 'Spec 3: Rules System Debugging — Resolution Tracing'
uid: 13a45efeac2f6dd5
---
# Spec 3: Rules System Debugging — Resolution Tracing

**Date:** 2026-06-30  
**Status:** Approved  
**Scope:** Add rule resolution tracing to `Manifest::Rules`, surface it as a new `rule_trace` verb on CLI and MCP.

---

## Problem

`rules.for("decisions.adr-0001")` is a black box. It runs glob matching, picks the most-specific winning rules, and returns a `RuleSet` with no record of how it got there. When an entry has unexpected lifecycle behaviour (wrong retain policy, publish gated unexpectedly, schema validator not firing), there is no way to ask "which rules matched and why did that one win?" The `rule_explain` verb shows the *result*, not the *reasoning*.

---

## Goals

- `Manifest::Rules` exposes a tracing path that captures every decision made during resolution: which patterns were tested, which matched, which won, what the final RuleSet carries.
- The trace is a plain `Data.define` value — serializable, inspectable in tests, returned by a new verb.
- `for(key)` is unchanged. No existing callers are affected.
- New `rule_trace` verb surfaces the trace on CLI (`:cli`) and MCP (`:mcp`) in the `:rule` domain.

---

## Architecture

### 1. `RuleTrace` value object

```ruby
module Textus::Manifest
  RuleTrace = Data.define(
    :key,            # String — the key that was resolved
    :candidates,     # Array<Hash> — every rule block tested; see schema below
    :winners,        # Array<Hash> — blocks that matched, sorted by specificity desc
    :ruleset_fields, # Hash — the merged fields of the final RuleSet
  )
  # candidates element schema:
  #   { "pattern" => String, "matched" => Boolean, "specificity" => Integer }
  #
  # winners element schema:
  #   { "pattern" => String, "specificity" => Integer, "fields" => Hash }
end
```

`candidates` covers every block defined in the manifest — including non-matching ones. This answers "why did block X not apply?" as well as "why did block Y win?". `specificity` is 0 for non-matching blocks.

### 2. `Manifest::Rules#for_with_trace`

`for(key)` is refactored to call `for_with_trace(key)` internally, returning only the `RuleSet`. No callers change.

```ruby
class Textus::Manifest::Rules
  # Unchanged public interface — delegates to for_with_trace
  def for(key)
    for_with_trace(key).first
  end

  # New — returns [RuleSet, RuleTrace]
  def for_with_trace(key)
    candidates = @blocks.map do |block|
      matched      = block.pattern.match?(key)
      specificity  = matched ? block.pattern.specificity(key) : 0
      { "pattern" => block.pattern.to_s, "matched" => matched, "specificity" => specificity }
    end

    winning_blocks = @blocks
      .select  { |b| b.pattern.match?(key) }
      .sort_by { |b| -b.pattern.specificity(key) }

    ruleset = RuleSet.merge(winning_blocks.map(&:fields))

    trace = RuleTrace.new(
      key:,
      candidates:,
      winners: winning_blocks.map do |b|
        { "pattern" => b.pattern.to_s, "specificity" => b.pattern.specificity(key), "fields" => b.fields }
      end,
      ruleset_fields: ruleset.to_h,
    )

    [ruleset, trace]
  end
end
```

`Manifest::Pattern#specificity(key)` is a new method (or promoted from private) that returns an integer score representing how specific the pattern match is. Higher = wins over less-specific patterns. The existing most-specific-wins logic must use the same score — `specificity` in the trace must be the same number used to pick winners.

### 3. New `rule_trace` verb

Registered in `VerbRegistry` alongside `rule_explain` and `rule_list`. Fits the `rule` domain (already routing `:rule_explain`, `:rule_list`, `:schema_show`, `:rule_lint`).

```ruby
# In VerbRegistry:
register VerbSpec.new(
  :rule_trace,
  "Trace rule resolution for a key — shows every pattern tested, which matched, and which won.",
  [ArgSpec.arg(name: :key, required: true, positional: true,
               description: "dotted key whose rule resolution you want to trace")],
  %i[cli mcp],
  { default: ->(trace, _) { trace.to_h } },
  "rule trace",
  nil,
  :read
)
```

The handler (`Handlers::Maintenance::RuleTrace`) calls `manifest.rules.for_with_trace(key)` and returns the `RuleTrace` as the result value. The default view serializes it to a plain hash.

```ruby
module Textus::Handlers::Maintenance::RuleTrace
  HANDLES = Dispatch::Contracts::RuleTrace
  NEEDS   = %i[manifest].freeze

  def self.call(command, _call, deps)
    _, trace = deps.manifest.rules.for_with_trace(command.key)
    Value::Result.success(trace)
  end
end
```

New contract:

```ruby
Dispatch::Contracts::RuleTrace = Data.define(:key)
```

### 4. CLI output

`textus rule trace decisions.adr-0001` emits JSON by default:

```json
{
  "key": "decisions.adr-0001",
  "candidates": [
    { "pattern": "decisions.*", "matched": true,  "specificity": 2 },
    { "pattern": "knowledge.*", "matched": false, "specificity": 0 },
    { "pattern": "*",           "matched": true,  "specificity": 1 }
  ],
  "winners": [
    { "pattern": "decisions.*", "specificity": 2, "fields": { "retain": "90d" } },
    { "pattern": "*",           "specificity": 1, "fields": { "fresh_within": "7d" } }
  ],
  "ruleset_fields": { "retain": "90d", "fresh_within": "7d" }
}
```

Reading the output: candidates with `"matched": false` explain why a rule did not apply. `winners` is sorted highest-specificity-first, showing the precedence order. `ruleset_fields` is the merged result — the `retain` from `decisions.*` won over any `retain` in `*`.

---

## Specificity scoring

`Pattern#specificity(key)` must return a consistent integer that reflects the existing "most specific wins" semantics. The exact scoring formula is implementation-defined (e.g. character length of the matched portion, segment count of the pattern). The only constraint: the score used to sort `winning_blocks` in `for_with_trace` must be identical to the score used in the existing `for` implementation — otherwise the trace would show a different winner than the actual behaviour.

If the existing `for` does not expose a public `specificity` method, the implementation of `for_with_trace` must extract and expose it to satisfy this constraint.

---

## Files

### New
- `lib/textus/manifest/rule_trace.rb` — `RuleTrace = Data.define(...)`
- `lib/textus/handlers/maintenance/rule_trace.rb` — handler module

### Modified
- `lib/textus/manifest/rules.rb` — `for` delegates to `for_with_trace`; `for_with_trace` added
- `lib/textus/manifest/pattern.rb` — `specificity(key)` promoted to public
- `lib/textus/dispatch/contracts.rb` — `RuleTrace = Data.define(:key)`
- `lib/textus/verb_registry.rb` — register `:rule_trace` verb

### Tests
- `spec/unit/manifest/rules_spec.rb` — extend with `for_with_trace` examples:
  - Returns a `RuleTrace` as second element
  - `candidates` includes non-matching blocks with `matched: false`
  - `winners` sorted by specificity descending
  - `ruleset_fields` matches `for(key).to_h`
  - `for(key)` returns the same RuleSet as before (non-regression)
- `spec/unit/handlers/maintenance/rule_trace_spec.rb` — handler unit test with synthetic manifest
- `spec/conformance/read/rule_trace_verb_spec.rb` — end-to-end: store with known rules → `rule_trace` returns expected candidates and winners

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Key not declared in manifest (unknown key) | Handler calls `for_with_trace` normally — the trace will show zero winners and no matching patterns. Returns a valid `RuleTrace` with empty `winners`. Does not raise. |
| Empty rules block in manifest | `for_with_trace` returns `[RuleSet.empty, RuleTrace.new(key:, candidates: [], winners: [], ruleset_fields: {})]` |

No new error classes needed. `rule_trace` is a read verb — it cannot fail with auth or etag errors.

---

## Testing Strategy

- Unit test `for_with_trace` directly against a `Rules` instance built from a fixture manifest with 3+ rule blocks (overlapping patterns, varying specificity).
- Assert: (a) `for(key)` result equals `for_with_trace(key).first`; (b) `candidates` count equals total rule blocks; (c) `winners` is a subset of `candidates` where `matched: true`; (d) `winners` is sorted highest-specificity-first; (e) `ruleset_fields` equals the RuleSet merged from winners.
- Conformance spec: a store with `decisions.*` and `*` rules; `rule_trace "decisions.foo"` returns `decisions.*` as winner over `*`.
