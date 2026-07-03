---
uid: 578908fe598d9685
---
# Implementation plan — architecture deepening phase 3

## Phase 1: Container consolidation + Writer port + double-event fix
Safe internal refactors. No breaking changes.

### 1a. Add reader, writer, root to Infrastructure
- Edit `lib/textus/store/infrastructure.rb` — add :reader, :writer, :root
- Edit `lib/textus/store/builder.rb` — construct Reader + Writer, store in partial

### 1b. Delete UseCaseContainer + ContainerHelpers + build_container_proxy
- DELETE `lib/textus/store/use_case_container.rb`
- DELETE `lib/textus/container_helpers.rb`
- Edit `lib/textus/store.rb` — remove build_container_proxy, @container = @ctx
- Edit `lib/textus/workflow/context.rb` — inline ContainerHelpers methods
- Edit `lib/textus/workflow/runner.rb` — inline ContainerHelpers methods

### 1c. Move call: to Writer method args + drop From factories
- Edit `lib/textus/store/entry/writer.rb` — remove call from initialize, add to method sigs
- delete Writer.from() — callers use container.writer
- Edit `lib/textus/store/entry/reader.rb` — delete Reader.from(), callers use container.reader

### 1d. Update all Writer callers
- Edit use cases: put_entry, propose_entry, accept_proposal, delete_entry, move_entry
- Edit workflow/runner.rb
- Edit retention (wherever Writer called)
  Writer.from(container:, call:) → container.writer.put(key, ..., call:)

### 1e. Fix double-event bug
- Remove events.publish(EntryWritten) from put_entry, propose_entry, accept_proposal, delete_entry, move_entry use cases
- AuditIndex middleware stays as sole emitter

## Phase 2: Manifest→workflow boundary
Breaking. Coordinated commit.

### 2a. Add DSL declarations to Workflow::DSL
- Edit `lib/textus/workflow/dsl.rb`
- Add priority(N), depends_on(pattern), ttl(string), on_expire(sym), publish(to:, template: nil)

### 2b. Drop lifecycle fields from manifest parser
- Remove publish, source, rules, worker from manifest schema
- Raise helpful error: "moved to workflow DSL"
- Remove publish_targets, publish_to, publish_tree from Entry::Base

### 2c. Update Planner to read workflows
- Edit `lib/textus/store/jobs/planner.rb`
- producible_keys iterates workflows.all instead of manifest.data.entries
- dependent_keys uses workflow depends_on

### 2d. Update Publisher and Engine
- Engine reads publish config from workflow definition
- Publisher receives targets from caller

## Phase 3: Cleanup
Bonus deletions.

### 3a. Remove Collector + Registry
- DELETE collector.rb, registry.rb
- Edit loader.rb — use plain array
- Edit workflow.rb — pass registry kwarg

### 3b. Remove HandlerRegistry
- DELETE handler_registry.rb
- Edit handler_resolver.rb — return plain hash
- Edit pipeline.rb — .fetch() instead of .for()

### 3c. Inline Publisher
- DELETE publisher.rb
- Edit engine.rb — inline 7 lines into publish_only
