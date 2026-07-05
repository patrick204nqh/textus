# ADR 0136 — Priority-based multi-workflow routing replaces inline chaining and boot_refresh

**Date:** 2026-07-05
**Status:** Accepted
**Supersedes:** The boot_refresh workflow pattern (explicit inline `Runner` call to trigger downstream workflows)
**Refines:** [ADR 0087](../archive/0087-fold-build-into-reconcile.md) (materialization is system-pushed; this ADR adds multi-workflow routing via priority), [ADR 0124](./0124-workflow-parallel-steps.md) (parallel steps kept; sequential chaining shifts from inline Runner to priority ordering)

> **One sentence:** The `Materialize` workflow could only match one workflow per key (using `find`), forcing workflows that needed to run in sequence (boot_refresh → doctor checks → boot) to use inline `Runner.new(...).run(...)` calls — a leaky bypass that circumvented the event system and created dead code (`Produce::Engine.converge` never existed); this ADR changes Materialize to iterate all matching workflows sorted by `priority`, eliminates the boot_refresh workflow entirely, and makes the doctor workflow the sole knowledge-change handler that triggers boot via `notify`.

## Context

The trigger chain for knowledge changes had accumulated three layers of indirection:

1. **`boot_refresh.rb`** was a separate workflow whose only job was to execute two other workflows in sequence (boot rebuild, then doctor checks). It used `match "knowledge.loop.**"` but this never worked — `Definition#match?` in dsl.rb explicitly returned false for patterns ending with `**`, so Materialize's `match_for_key` could never route to boot_refresh. The workflow was dead code.

2. **`Produce::Engine.converge`** was called from boot_refresh's steps to trigger downstream artifacts (boot, doctor checks). This method was documented in ADRs and architecture docs but **never implemented** — `lib/textus/protocol/produce/engine.rb` doesn't exist. Both `step :refresh` and `step :doctor` in boot_refresh called dead code.

3. **Inline `Runner.new(...).run(key)`** was the only working mechanism for one workflow to trigger another. But it bypassed the event system entirely — runs synchronously, no queuing, no event emission, no Materialize involvement. This made it hard to reason about ordering and coupling.

The root causes were two design gaps:

1. **`Registry#match_for_key` used `find`** — returning only the first matching workflow. If boot_refresh and doctor both matched `knowledge.loop.**`, only one would run. The solution was a separate boot_refresh workflow that explicitly called the other two.

2. **`Definition#match?` excluded `**` patterns** — `return false unless @match_pattern && !@match_pattern.end_with?("**")` — meaning no workflow using `match "prefix.**"` could ever be triggered by Materialize. This was a bug, not intentional: `Pattern.match?` already handled `**` correctly; the guard in `match?` blocked it.

Additionally, **17 individual doctor workflow files** each matched their own `artifacts.doctor.<check>` key. Adding a new doctor required creating a new file AND adding its key to boot_refresh's hardcoded 16-key trigger list.

## Decision

### 1. Multi-workflow routing in Materialize

`Registry` gains `workflows_for_key(key)` — replaces `find` with `select` + `sort_by(&:priority)`:

```ruby
def workflows_for_key(key)
  @definitions.select { |wf| wf.match?(key) }.sort_by(&:priority)
end
```

Materialize's converge step iterates all matching workflows in priority order instead of running just the first match:

```ruby
workflows.each { |wf| Runner.new(wf, ...).run(key) }
```

This enables multiple workflows to respond to the same event, ordered by priority.

### 2. `match?` bug fixed

Removed the `!@match_pattern.end_with?("**")` guard. `**` patterns now correctly match through Materialize's key routing. Any workflow using `on "prefix.**"` is triggered when any entry under that prefix is written.

### 3. Doctor consolidation → priority 20

17 individual doctor files collapsed into one `doctors.rb` with 18 `check` blocks:
- 12 naming convention checks (were `loop_shape.rb`)
- 8 structural checks (manifest integrity, schema conformance, sentinels, etc.)

The doctor workflow:
- `on "knowledge.loop.**"` — fires on any knowledge change
- `priority 20` — runs before boot (and any future workflow without a priority override)
- `save to: "artifacts.doctor"` — persists health data
- `notify "artifacts.boot"` — triggers boot rebuild

### 4. Boot_refresh eliminated

`boot_refresh.rb` deleted. Its responsibilities split:
- **Rebuild boot** — the doctor workflow's `notify "artifacts.boot"` triggers the boot workflow via the event system (Materialize → boot workflow matching `artifacts.boot`)
- **Run doctor checks** — the doctor workflow matches `knowledge.loop.**` directly

No more inline Runner calls. No more dead `Engine.converge` references.

### 5. Data flow for boot health data

The boot workflow now reads from `artifacts.doctor` (written by the doctor workflow) to optionally include health data in the orientation output (CLAUDE.md/AGENTS.md).

### Event chain

```
1. knowledge.loop.intent.0001 written
2. Materialize → workflows_for_key → [doctor (p20)]
3. Doctor runs checks, save to: artifacts.doctor, notify artifacts.boot
4. write to artifacts.boot → Materialize → boot (matches artifacts.boot)
5. Boot reads artifacts.doctor data, renders CLAUDE.md/AGENTS.md
```

## Consequences

- **25 workflow config files → 10.** The 17 individual doctor files, loop_shape.rb, naming_check.rb, manifest_files.rb, publish_tree_overlap.rb, and boot_refresh.rb are all gone.
- **17 manifest entries → 1.** `artifacts.doctor.*` entries collapsed to `artifacts.doctor`.
- **Dead code removed.** `Produce::Engine.converge` references in boot_refresh are gone. The `match?` bug is fixed. Three layers of indirection collapsed to one.
- **Multi-workflow routing enabled.** Any workflow can declare priority to order against other workflows matching the same key. Default priority is 0 — the doctor uses 20.
- **Boot_refresh was always dead.** It had never triggered via Materialize (`match?` excluded `**`). The `Engine.converge` calls invoked non-existent code. This change makes the reactive chain actually work for the first time.

## Alternatives considered

- **Keep boot_refresh with inline Runner.** Rejected: the user identified this as redundant during review. The inline Runner bypasses the event system and creates tight coupling. The `notify` keyword is declarative and explicit.
- **Wire `depends_on` instead of multi-workflow routing.** Rejected: `depends_on` was already declared but never implemented. Multi-workflow routing via priority is a smaller change (one method in Registry + one loop change in Materialize) and enables the same ordering without a new concept.
- **Keep individual doctor artifact keys.** Rejected: the hardcoded 16-key list in boot_refresh was the maintenance burden. One key (`artifacts.doctor`) plus priority routing is simpler.
