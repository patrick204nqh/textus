---
uid: d998ad2711b6c2f6
---
## Phase 2 Changes

### Gate (architecture)
- Gate is now wired as the single dispatch path via `Builder::Runtime`
- Session rewritten to delegate to Gate directly — no more Bridge, Context, or old Gate
- Old Gate, Bridge, Context classes deleted
- ~1100 lines removed: old `gate.rb`, `bridge.rb`, `context/global.rb`, `context/current.rb`, `gate_routing_spec.rb`, session bridge/context specs

### Propose/accept/reject role gating
- Gate now enforces author-only `accept`/`reject` at the dispatch level
- Matches the existing boot-layer verb hiding (which already hides these verbs from non-author agents)
- Uses the same source of truth: knowledge lane writers == author role set

### Session-scratchpad link
- Gate#create_session also writes a durable `scratchpad.sessions.<id>` entry
- Every Gate session now has a persistent record in the scratchpad lane
- Non-critical side effect: failures are caught and warned without affecting session lifecycle

### GateV2 → Gate rename
- Class `Textus::Protocol::GateV2` → `Textus::Protocol::Gate`
- File `gate_v2.rb` → `gate.rb`, spec `gate_v2_spec.rb` → `gate_spec.rb`
- Container attribute `gate_v2` consolidated into single `gate`
- Runtime builder uses `gate` variable everywhere; `Components.gate_v2` removed

### `--under` rename (prefix: → under: everywhere)
- Verb/tool names: `key_mv_prefix`→`key_mv_under`, `key_delete_prefix`→`key_delete_under`
- CLI paths: `key mv-prefix`→`key mv-under`, `key delete-prefix`→`key delete-under`
- Param names: `prefix:`→`under:` across StoreEngine#list, Resolver#enumerate, BulkPlanner, EntryIndex#search, TtlEvaluator, all handlers
- MCP arg names: `from_prefix:→from_under:`, `to_prefix:→to_under:`, `prefix:`→`under:` in key_delete_under and list
- CLI flag: `--prefix=KEY`→`--under=KEY` (via wire name change)
- ADR archives intentionally untouched (historical records)
- Not renamed: `shared_prefix_segments` (internal Levenshtein helper, different concept), publishing `prefix:` (entry publishing scope, different concept)
- Template `.textus/templates/docs/architecture/index.erb` updated

### Status
- 1096 specs passing, 0 failures, 2 pending
