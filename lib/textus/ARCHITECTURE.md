<!-- The architecture map for `lib/textus/`. The why lives in ADR 0106
     (.textus/data/knowledge/decisions/0106-executable-layering-invariant.md);
     the enforcement lives in spec/conformance/architecture/layering_spec.rb. -->

# textus internal architecture

textus is a hexagonal (ports-and-adapters) design. Dependencies flow **inward**:
each layer may depend on the layers below it, never above.

```
  surfaces ──▶ use cases ──▶ domain ──▶ ports ──▶ adapters
  (cli/ mcp/)  (read/ write/  (pure)   (interfaces) (filesystem,
               maintenance/                          git, …)
               produce/)
```

| Layer | Directories | Responsibility |
|-------|-------------|----------------|
| **surfaces** | `cli/`, `mcp/` | Thin transports. Project the contract; carry no logic. |
| **use cases** | `read/`, `write/`, `maintenance/`, `produce/` | One class per verb (`extend Contract::DSL`). Invoked uniformly via `Dispatcher` (ADR 0022/0023). |
| **domain** | `domain/` | The pure core — freshness, retention, policy, permissions. No IO, no knowledge of how it is invoked. |
| **ports** | `ports/` | The only doorway to the outside world: `FileStore`, `Publisher`, `Clock`, `AuditLog`, `SentinelStore`, `BuildLock`. |
| **adapters** | (the filesystem/git the ports wrap) | Concrete IO. |

Cross-cutting value objects (`Container`, `Call`, `Envelope`, `Manifest`,
`Contract`, `errors`) are shared inward-pointing primitives, not a layer.

## The enforced rule

> **The domain layer (`domain/`) must not reference the use-case or surface
> layers** (`Read`, `Write`, `Maintenance`, `Produce`, `CLI`, `MCP`). IO happens
> only through `ports/`.

This is the load-bearing inward-dependency rule. It is **executable** —
`spec/conformance/architecture/layering_spec.rb` fails CI if a `domain/` file
reaches up. If you need domain logic to trigger something above it, invert the
dependency (a port the use case implements) or move the logic into the use-case
layer that owns the orchestration.

## Ports

`ports/` is the only layer permitted to perform IO. Everything above reaches the
outside world through it, never directly.
