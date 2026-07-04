# ADR 0135 — Workflow DSL simplification: `on`/`save`/`notify` replace `match`/bare-publish/validate

**Date:** 2026-07-05
**Status:** Accepted
**Supersedes:** The `depends_on` pattern (declared but never wired, removed)
**Touches:** [ADR 0124](./0124-workflow-parallel-steps.md) (parallel steps kept; DAG-style `depends_on` per-step removed), [ADR 0134](./0134-architecture-deepening-phase-3.md) (planned `depends_on` DSL keyword — removed instead of implemented)

> **One sentence:** The workflow DSL had accumulated three overlapping concepts for validation (`check`/`validate`/`step`), three publish modes (bare/`to:`/block) where one was destructive and another required a Ruby helper (`store_put`), and two unused keywords (`depends_on`/`handles`) — this ADR collapses validation into one keyword (`check`), replaces bare publish and the `store_put` helper with explicit `save to:`, adds `notify` for downstream triggers, renames `match` to `on`, and removes the dead weight (`depends_on`, `handles`, `validate` step type).

## Context

The workflow DSL grew incrementally as needs emerged:

- `match` was the original trigger keyword — reads as a natural-language match against a key pattern, but the concept is really "what event triggers this workflow," not "does this pattern match."
- `publish` had three modes: bare (write to the matched store key), `to:` (write to a file), and block (arbitrary). Bare mode was implicit and confusing — it silently wrote to a key the user never explicitly named. When workflows needed to write to a *different* store key (not the matched trigger), a `store_put` Ruby helper was added as a workaround.
- `validate` was a separate step type with its own execution path (the Validator class), distinct from `check`. Both produced issue arrays. The only user was `pattern_crossrefs.rb`. The Validator execution path was redundant — `check` inside a workflow with an `on` pattern achieves the same effect.
- `depends_on` was declared as a DSL keyword but never wired into the trigger system. It existed in the Definition but no code ever read `@depends_on_patterns` to trigger anything.
- `handles` registered event types on a Definition — but this was only used by the built-in Materialize workflow. It leaked an implementation detail into the DSL surface.
- `store_put` was a Ruby method in the Helpers module, not a first-class DSL keyword. Steps called it to write to store keys with proper role authority — exactly what a DSL keyword should do.

The DSL had 12 concepts for what is fundamentally three concerns: **trigger → compute → output**.

## Decision

1. **`match` → `on`.** The new keyword reads naturally as "on this event, run this workflow." Supports multiple patterns: `on "pattern1", "pattern2"`.

2. **`publish` loses bare mode.** `publish` now requires `to:` (file), `tree:`, or a block. Bare `publish` raises an error directing users to `save to:`. `publish to:` (file output) is unchanged.

3. **`save to:`** — a new keyword that writes the step's accumulated data to a named store key. Replaces both bare `publish` (which wrote to the matched key) and the `store_put` helper (which wrote to a different key). Uses EntryStore with proper workflow call authority.

4. **`notify`** — a new keyword that writes an empty trigger payload to a store key, cascading to other workflows via Materialize. Replaces the `store_put("boot.key")` workaround pattern.

5. **`validate` step type removed.** `check` is the only validation keyword. The Validator class is deleted. `pattern_crossrefs.rb` now uses `check` in a workflow with `on "knowledge.loop.judgment.engineering.**"`.

6. **`depends_on` removed.** Never wired — no code consumed `@depends_on_patterns`. Removing it avoids confusion with the future dependency system (which will use `on` with priority ordering, not a separate keyword).

7. **`handles` removed from the DSL surface.** The method stays on Definition for internal use (Materialize needs it), but it's no longer documented or advertised as a user-facing keyword.

8. **`store_put` helper removed.** Replaced by `save to:`.

9. **`check` keyword `scope:` replaces `match:`.** The naming check form `check "name", match: "prefix.*", naming: /pattern/` was confusing — `match:` here described *which entries to validate*, not the workflow trigger. Changed to `scope:` (e.g., `check "name", scope: "prefix.*", naming: /pattern/`).

### The final three-concept surface

```
trigger  →  on pattern(s), priority ordering
compute  →  step :name { |data, ctx| data }
            check "name" { |ctx| issues }   (accumulating validation)
output   →  save to: "store-key"
            notify "downstream-key"
            publish to: "file", template: "tpl"
```

## Consequences

- **All 18 workflow config files updated** — every `match` → `on`, every bare `publish` → `save to:`, every `validate` → `check`, every `check match:` → `scope:`.
- **`store_put` and `Validator` deleted** — no replacement needed.
- **7 fewer DSL concepts** (went from 12 to 5 user-facing keywords: `on`, `step`, `check`, `save`, `notify`, plus `publish`/`priority`/`parallel`).
- **Breaking change for any external user** — but there are none; we dogfood our own tool.
- **Bare `publish` raises a descriptive error** — points users to `save to:` instead of failing silently.
- **`depends_on` can be re-added later** if a concrete need arises, but it should be wired into the trigger system from day one.
- **`check scope:` vs workflow `on` are now visually distinct** — `on` is the trigger, `scope:` is the entry scope for naming validation. No more overloaded `match:` meaning two different things.
