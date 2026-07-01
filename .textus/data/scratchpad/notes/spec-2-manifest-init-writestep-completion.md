---
title: 'Spec 2: Manifest Init Hardening + WriteStep Completion'
uid: 8db8fa1fa6e2d257
---
# Spec 2: Manifest Init Hardening + WriteStep Completion

**Date:** 2026-06-30  
**Status:** Approved  
**Scope:** Fix the fragile 3-step manifest initialization order; extend WriteStep pattern to `delete` and `move`.

---

## Problem

### Manifest initialization

`Manifest.load` has an implicit 3-step ordering constraint: `Data` must be built before `Policy`, `Policy` must be built before entry validators, and `derived_entry?` always returns false during construction (because Policy isn't complete yet). Nothing in the code enforces or documents this order — it is a runtime invariant discovered only when violated.

### WriteStep gap

`Writer#put` was decomposed into `WriteStep::DEFAULT_PUT` in the previous refactor, making the put pipeline inspectable and each step individually testable. `Writer#delete` and `Writer#move` were left with the old sequential-local-variable structure. They have the same problems `put` had: hard to test in isolation, impossible to skip or reorder steps, internal logic invisible from outside.

---

## Goals

- `Manifest.load` has two named, structural phases. Phase 2 cannot start until Phase 1 returns. The init order becomes a compile-time constraint, not a runtime convention.
- `Writer#delete` and `Writer#move` follow the same pattern as `Writer#put`: named step modules, reduce over a constant, each step individually testable.
- `WriteDeps` is reused unchanged across all three pipelines (put, delete, move).

---

## Architecture

### Part A: Two-phase `Manifest.load`

`Manifest.load` becomes a two-pass factory. The class constructor `Manifest.new` becomes a simple value constructor — no logic, no ordering.

```ruby
module Textus
  class Manifest
    # Phase 1: structural data + authority policy — no cross-entry validation
    # Phase 2: entries — validators now have a fully-formed Policy
    def self.load(root)
      raw = YAML.safe_load(File.read(File.join(root, "manifest.yaml")), symbolize_names: false)
      Schema.validate!(raw)

      # Phase 1
      data   = Manifest::Data.new(raw)
      policy = Manifest::Policy.new(data)

      # Phase 2 (Policy is complete — validators may call policy.derived_entry? safely)
      resolver = Manifest::Resolver.new(data, root)
      rules    = Manifest::Rules.new(data)
      entries  = Manifest::Entry::Parser.parse(raw.fetch("entries", []), policy:, data:)

      new(data:, policy:, resolver:, rules:, entries:)
    end

    def self.parse(yaml_text, root:)
      # Same two-phase pattern for the test helper path
      raw = YAML.safe_load(yaml_text, symbolize_names: false)
      # ... same as load but without file I/O ...
    end

    # Plain value constructor — no logic
    def initialize(data:, policy:, resolver:, rules:, entries:)
      @data     = data
      @policy   = policy
      @resolver = resolver
      @rules    = rules
      @entries  = entries
    end

    attr_reader :data, :policy, :resolver, :rules, :entries
  end
end
```

**What changes:**
- `Manifest::Data` no longer needs to know about `Policy` during its own construction.
- `Manifest::Entry::Parser.parse` receives `policy:` and `data:` as keyword args. It can call `policy.derived_entry?` freely because Phase 1 is complete.
- `derived_entry?` works correctly during entry construction — no more always-false race condition.
- `Manifest.new` is now a boring keyword-arg constructor. It cannot be called with a partial state.

**What stays the same:**
- `Manifest::Data`, `Manifest::Policy`, `Manifest::Resolver`, `Manifest::Rules` internal APIs unchanged.
- All callers of `Manifest.load` and `Manifest.parse` unchanged — same return type, same attribute names.

### Part B: WriteStep for `delete` and `move`

#### `DeleteContext` and `DEFAULT_DELETE`

```ruby
module Textus::Store::Entry::WriteStep
  DeleteContext = Data.define(
    :key, :mentry, :if_etag,   # inputs
    :path,                      # from ResolvePath
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
        role: deps.call.role, verb: "key_delete", key: ctx.key,
        etag_before: ctx.etag_before, etag_after: nil,
        extras:
      )
      ctx
    end
  end

  DEFAULT_DELETE = [
    ResolvePath,      # key → path (reused from put pipeline)
    AssertExists,     # raises UnknownKey unless file exists
    ReadEtagBefore,   # etag_before = file_store.etag(path)
    CheckEtag,        # raises EtagMismatch if if_etag given and mismatches (reused from put)
    DeleteFile,       # file_store.delete(path)
    PruneParents,     # remove now-empty ancestor directories
    AppendDeleteAudit,# audit_log.append(verb: "key_delete", ...)
  ].freeze
end
```

#### `MoveContext` and `DEFAULT_MOVE`

```ruby
module Textus::Store::Entry::WriteStep
  MoveContext = Data.define(
    :from_key, :to_key, :new_mentry, :if_etag,   # inputs
    :from_path, :to_path,                          # from ResolvePaths
    :etag_before,                                  # from ReadEtagBefore
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
      raise UnknownKey.new(ctx.from_key, suggestions: deps.manifest.resolver.suggestions_for(ctx.from_key))
    end
  end

  module ReadMoveEtagBefore
    def self.call(ctx, deps)
      etag_before = deps.file_store.etag(ctx.from_path)
      ctx.with(etag_before:)
    end
  end

  module MoveFile
    def self.call(ctx, deps)
      deps.file_store.mv(ctx.from_path, ctx.to_path)
      ctx
    end
  end

  module PruneSourceParents
    # Same logic as PruneParents but operates on from_path
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
    def self.call(ctx, deps)
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
        "from_key"  => ctx.from_key, "to_key"   => ctx.to_key,
        "from_path" => ctx.from_path, "to_path"  => ctx.to_path,
        "uid"       => ctx.envelope.uid,
      }
      extras["correlation_id"] = deps.call.correlation_id if deps.call.correlation_id
      deps.audit_log.append(
        role: deps.call.role, verb: "key_mv", key: ctx.to_key,
        etag_before: ctx.etag_before, etag_after: ctx.etag_after,
        extras:
      )
      ctx
    end
  end

  DEFAULT_MOVE = [
    ResolvePaths,        # from_key/to_key → from_path/to_path
    AssertSourceExists,  # raises UnknownKey unless from_path exists
    ReadMoveEtagBefore,  # etag_before = file_store.etag(from_path)
    CheckEtag,           # raises EtagMismatch if if_etag given and mismatches (reused from put)
    MoveFile,            # file_store.mv(from_path, to_path)
    PruneSourceParents,  # remove now-empty ancestor dirs from source side
    RewriteBasename,     # Format.rewrite_name(to_path, basename)
    ReadEtagAfter,       # etag_after = Value::Etag.for_file(to_path)
    ReadEnvelope,        # reader.read(to_key) → envelope
    AppendMoveAudit,     # audit_log.append(verb: "key_mv", ...)
  ].freeze
end
```

#### Updated `Writer#delete` and `Writer#move`

Both become structurally identical to `Writer#put`:

```ruby
def delete(key, mentry: nil, if_etag: nil)
  ctx = WriteStep::DeleteContext.new(
    key:, mentry:, if_etag:,
    path: nil, etag_before: nil
  )
  deps = WriteStep::WriteDeps.new(
    file_store: @file_store, manifest: @manifest, schemas: @schemas,
    audit_log: @audit_log, call: @call, reader: @reader, layout: @layout
  )
  WriteStep::DEFAULT_DELETE.reduce(ctx) { |c, step| step.call(c, deps) }
  nil
end

def move(from_key:, to_key:, new_mentry:, if_etag: nil)
  ctx = WriteStep::MoveContext.new(
    from_key:, to_key:, new_mentry:, if_etag:,
    from_path: nil, to_path: nil,
    etag_before: nil, etag_after: nil, envelope: nil
  )
  deps = WriteStep::WriteDeps.new(
    file_store: @file_store, manifest: @manifest, schemas: @schemas,
    audit_log: @audit_log, call: @call, reader: @reader, layout: @layout
  )
  ctx = WriteStep::DEFAULT_MOVE.reduce(ctx) { |c, step| step.call(c, deps) }
  ctx.envelope
end
```

**Reused steps across pipelines:**
- `ResolvePath` — reused in delete (single key → path)
- `CheckEtag` — reused in both delete and move (if_etag guard logic is identical)

---

## Files

### Modified
- `lib/textus/manifest.rb` — two-phase `load` + `parse`; `initialize` becomes plain constructor
- `lib/textus/store/entry/write_step.rb` — add `DeleteContext`, `MoveContext`, new step modules, `DEFAULT_DELETE`, `DEFAULT_MOVE`
- `lib/textus/store/entry/writer.rb` — replace `delete` and `move` bodies with step-chain pattern

### Tests
- `spec/unit/manifest/two_phase_load_spec.rb` — derived_entry? works in Phase 2; Policy available to validators
- `spec/unit/store/entry/write_step_spec.rb` — extend existing spec with DeleteContext, MoveContext, DEFAULT_DELETE, DEFAULT_MOVE step order and .call interface
- Integration: existing `spec/conformance/write/mv_spec.rb` + delete conformance specs cover end-to-end

---

## Error Handling

| Scenario | Step | Behaviour |
|---|---|---|
| Key doesn't exist (delete) | `AssertExists` | Raises `UnknownKey` with resolver suggestions |
| Key doesn't exist (move from) | `AssertSourceExists` | Raises `UnknownKey` with resolver suggestions |
| Etag mismatch | `CheckEtag` | Raises `EtagMismatch` (same as put — reused step) |
| Prune fails (race / non-empty dir) | `PruneParents` / `PruneSourceParents` | `rescue SystemCallError → ctx` — best-effort, never fatal |
| Manifest Phase 1 validation fails | `Schema.validate!` | Raises `SchemaViolation` before Phase 2 starts |

---

## Testing Strategy

- `Manifest.load` two-phase: a fixture with a derived entry; assert `derived_entry?` returns true for it in the loaded result (was always false before the fix).
- Each new WriteStep module tested with a synthetic context + fake deps (FileStore double, AuditLog spy).
- `DEFAULT_DELETE` and `DEFAULT_MOVE` step-order tests match the put pattern in the existing `write_step_spec.rb`.
- Integration: existing mv and delete conformance specs must continue to pass with no behavioural change.
