# Contributor Conventions

> Reference for contributors - the single authoritative source for layer
> structure, naming, and testing rules. Contract with the codebase: if
> it contradicts this doc, the code is wrong.

## Layer structure

```
contract/     source of truth for all public interfaces
surfaces/     cli/  mcp/  role_scope.rb  - projections of contracts
dispatch/     gate.rb  auth.rb  ledger.rb  executor.rb  event.rb  actions/
manifest/     policy/  - manifest config objects (Source, Retention, etc.)
core/         Freshness  Jobs  Duration  Sentinel - cross-cutting value types
ports/        IO adapters
step/         user-injectable wrappers
```

Dependency direction (inward only):
  surfaces -> contract -> dispatch -> manifest + core + ports + step

No layer may depend on a layer to its left.

## Naming - one word per concept

| Concept | Name |
|---------|------|
| Storage partition | `lane` (YAML: `lane:`, `lanes:`) |
| Pull from external source | `from: fetch` |
| Compute from store entries | `from: derive` |
| Externally managed | `from: external` |
| Handler security policy | `handler_permit` (YAML), `HandlerPermit` (Ruby) |
| Write operation | `action` (not `transition`) |
| Pure value types namespace | `core/` (`Textus::Core`) |
| Manifest config objects | `manifest/policy/` (`Textus::Manifest::Policy`) |
| Auth predicate engine | `Dispatch::Auth` |

No disambiguation prefixes (no `intake_` prefix). If two concepts share a
name, rename one.

## Contract as source of truth

Nothing is published to a surface (CLI/MCP/Ruby) without a contract.
`Contract::DSL` on each surface verb class is mandatory. Surfaces project
from contracts - not from use-case internals.

## Data layout

All entry content lives under `.textus/data/`:

```
.textus/data/
  knowledge/          # canon lane
  scratchpad/           # workspace lane
  proposals/          # queue lane
  artifacts/
    intake/<step>/    # from: fetch entries
    derived/<step>/   # from: derive entries
    external/<name>/  # from: external entries
```

## Step pipeline

Each step base class declares:
- `STAGE` - pipeline position (:acquire / :compute / :verify / :react)
- `BURN`  - execution mode (:sync / :async / :async_event)
- `INPUT` - frozen hash of expected kwargs
- `OUTPUT` - shape symbol (:envelope / :content / :diagnostics / :none)

`def self.kind` is not declared - kind is derived from the class hierarchy.

## Test Surface Rules

Unit specs are for stable value objects only: `core/`, `manifest/`, `entry/`,
`key/`, `role/`, `envelope/`. For anything in `dispatch/`, test through verb
contract integration specs.

The `volatile` tag marks specs in active flux during a branch only — it is
not a permanent excuse to keep a spec that should be deleted.
