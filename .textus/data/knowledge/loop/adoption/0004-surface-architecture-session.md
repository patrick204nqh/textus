---
node: adoption
confidence: high
signal: session_close
summary: 'Surface architecture session: built web API + shared dispatch, removed pass-through
  Projector'
uid: 7864dee380cdd5c8
---
node: adoption
confidence: high
signal: session_close
summary: Surface architecture session: built web API + shared dispatch, removed pass-through Projector

Three observations from the surface architecture session:

1. **Pass-through detection** — The MCP `Projector` became a delegation-only shell after the shared `Dispatch` module was extracted (15 lines, one delegation method). Architecture reviews should check for delegation-only wrappers: modules whose only public method forwards to another module. The deletion test catches these.

2. **Verb registry + binder is surface-agnostic** — Shared `Dispatch.call` confirmed VerbRegistry + Binder + Session works identically for CLI, MCP, and Web. All three now route through the same 5-line core. Validates ADR-0063.

3. **Prototype dependency cost** — Sinatra + Puma + Rackup added ~8 transitive gems (Gemfile only, not gemspec). Acceptable for prototype stage.
