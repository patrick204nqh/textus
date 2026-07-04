# Error Handling Conventions

## Raise, don't rescue silently

- Domain errors inherit from `Textus::Error` (not `StandardError`). Catch them
  explicitly.
- `rescue StandardError` is permitted only at system boundaries (MCP server
  dispatch, workflow step execution) where the error must be translated to a
  transport-appropriate form.
- Never `rescue StandardError` in business logic. Masked bugs rot silently.

## Pipeline steps must propagate

Write pipeline steps (Put, Delete, Move) use a context-passing pattern:
each step receives `(ctx, deps)` and returns a new ctx. If a step fails,
it MUST raise — never swallow and return ctx.

Three emit steps currently violate this (ADRs 0133, 0135):
```ruby
# BAD — silence hides real failures
rescue StandardError
  ctx
```
Fix: raise `Textus::Error`, let the pipeline runner handle retry.

## Catch-and-convert at boundaries

| Layer | Rescue scope | Action |
|-------|-------------|--------|
| Surface (MCP) | `rescue StandardError` | Translate to `ToolError`, surface to client |
| Workflow runner | `rescue StandardError` | Wrap in `StepFailed`, route through retry policy |
| Produce engine | `rescue StandardError` | Convert to `DeadLettered` outcome |
| All domain code | `rescue Textus::Error` | Re-raise or handle specifically |

---

See also: `knowledge.loop.judgment.engineering.0009-conventions`, commit `97abe966`
