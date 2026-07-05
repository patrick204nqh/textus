---
uid: 0d5255f6ff0daf46
---
---
proposal:
  target_key: knowledge.loop.evidence.0138-surface-architecture-web-api
  action: put
---

# ADR 0138 — Surface Architecture: Web API + Shared Dispatch

**Date:** 2026-07-05
**Status:** Proposed
**Refines:** [ADR 0063](./0063-cli-is-a-projection-of-the-contract.md) (CLI/MCP surface contract), [ADR 0058](./0058-one-verb-name-across-surfaces.md) (surface verb consistency)

> **One sentence:** Adopt a thin shared dispatch module that all three surfaces (CLI, MCP, Web) route through, and a verb-dispatch-only web API at `POST /api/:verb`.

## Decision

### 1. Shared Dispatch Module

Extract a thin core dispatch into `Textus::Surface::Dispatch`:

```ruby
def self.call(session, verb, raw_args)
  spec = VerbRegistry.for(verb)
  bound = Binder.inputs_from_wire(spec, raw_args)
  session.public_send(verb, **bound)
end
```

Each surface calls this and owns its own error translation:

| Surface | Dispatch | Error Format |
|---------|----------|-------------|
| CLI | Auto-generated Verb classes | Exit codes (Integer) |
| MCP | Projector + Catalog | JSON-RPC error codes |
| Web | POST /api/:verb | HTTP status + JSON `{error, code}` |

### 2. Web API Surface

```
POST /api/:verb            — verb dispatch (JSON body → bound args)
GET  /api/status           — health check: {protocol, lanes[], store_root}
X-Textus-Role header       — role selection (default: agent)
```

Port 9292, Puma via Sinatra 4.x.

## Rationale

- **Consistency:** all three surfaces speak the same verb contract. The web is the same protocol over HTTP, not a separate API.
- **Prototype scope:** dedicated resource endpoints (entries, lanes, audit) duplicate the verb registry. Deferred until a GUI proves which endpoints are worth extracting.
- **Hyrum's Law:** verb-dispatch means every new verb is automatically web-available — no endpoint to add, no contract to maintain separately.

## Files

| File | Status |
|------|--------|
| `lib/textus/surface/web.rb` | Built — Sinatra app |
| `lib/textus/surface/cli/group/web.rb` | Built — `textus web` group |
| `lib/textus/surface/cli/verb/web_serve.rb` | Built — `textus web serve` verb |
| `lib/textus/surface/dispatch.rb` | Pending — shared dispatch module |
| `Gemfile` | Modified — sinatra, rackup, puma added |
