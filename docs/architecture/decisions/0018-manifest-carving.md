# ADR 0018 — Carve Manifest into Data, Resolver, Policy, Rules

**Date:** 2026-05-28
**Status:** Proposed
**Depends on:** [ADR 0013](./0013-port-extraction-store-as-root.md), [ADR 0016](./0016-application-ports-value.md)

## Context

`Textus::Manifest` is the most-passed object in the codebase. Every
application use case takes it. Almost every domain object reaches
into it. It is also the largest behavioural surface that survived
ADRs 0004 / 0005 / 0013 unchanged. Today, a single `Manifest` instance
exposes:

```
Manifest
├── data                       — raw YAML, zones, entries
│   ├── #zones                  → { zone_name => write_policy[] }
│   ├── #zone_readers           → { zone_name => read_policy[] | :all }
│   ├── #entries                → [Entry::Leaf | ::Nested | ::Derived | ::Intake]
│   └── #audit_config           → { max_size, keep }
├── resolver                   — key → path → entry
│   ├── #resolver                → Resolver (extracted)
│   └── #validate_key!          → Key::Grammar.validate!
├── policy                     — role / zone authority
│   ├── #zone_writers           → write_policy
│   ├── #permission_for         → Domain::Permission
│   ├── #zone_kinds             → Set<kind>
│   ├── #role_mapping
│   ├── #role_kind
│   └── #roles_with_kind
└── rules                      — refresh rules, glob matching
    ├── #rules                   → Manifest::Rules
    └── #rules_for(key)
```

Four distinct concerns wearing one name. Three concrete costs:

1. **Use cases over-depend.** `Reads::Get` accepts a `manifest:` so
   it can call `manifest.rules_for(key)` (rules) and
   `manifest.resolver.resolve(key)` (resolver). It does not need
   `zones`, `entries`, `permission_for`, `audit_config`, or
   `role_mapping`. Today there is no way to express that narrowing.
2. **God-object passing pattern.** Tests, hooks, restructure ops,
   and doctor checks all take `manifest:` because *something* in
   their call graph eventually needs one of the four roles. Tracking
   which role a given consumer actually uses requires reading the
   body.
3. **No room for derived data.** `Manifest#permission_for` builds a
   fresh `Domain::Permission` on every call. `Manifest#zone_kinds`
   memoises into `@zone_kinds_cache` on the manifest object. There
   is no natural home for "the digested authority view"; everything
   lives on the same class.

ADR 0013 took the I/O port narrow. ADR 0016 introduces a `Ports`
struct. The remaining wide port is `manifest:`. This ADR narrows it.

## Decision

Split `Textus::Manifest` into four collaborators under the same
namespace:

```
Textus::Manifest::Data        — raw declaration (was: Manifest core)
Textus::Manifest::Resolver    — key/path resolution (already extracted)
Textus::Manifest::Policy      — role/zone authority view (NEW)
Textus::Manifest::Rules       — refresh rules (already extracted)
```

`Manifest` itself becomes a thin **composition record** that holds
the four — purely so that `Manifest.load(root)` still returns one
object — but no longer exposes the union of methods on its own
surface:

```ruby
Manifest = Data.define(:data, :resolver, :policy, :rules) do
  def self.load(root)
    raw = YAML.safe_load_file(File.join(root, "manifest.yaml"), aliases: false)
    check_version!(raw, root)
    data = Data.parse(raw, root: root)
    new(
      data:     data,
      resolver: Resolver.new(data),
      policy:   Policy.new(data),
      rules:    Rules.parse(raw["rules"] || []),
    )
  end
end
```

### Per-role surfaces

**`Manifest::Data`** — parsed declaration. No behaviour, no caches.

```ruby
class Manifest::Data
  attr_reader :root, :raw, :entries, :zones, :zone_readers, :audit_config, :role_mapping
end
```

**`Manifest::Resolver`** — already exists. Adds the key validator
(`validate_key!`) that currently lives on `Manifest` so callers don't
need both.

**`Manifest::Policy`** — new. Owns the digested authority view:

```ruby
class Manifest::Policy
  def zone_writers(zone_name)
  def zone_readers_for(zone_name)
  def permission_for(zone_name)         # → Domain::Permission
  def zone_kinds(zone_name)             # → Set<:human|:agent|:runner|:builder|:generator|:proposer>
  def role_kind(name)
  def roles_with_kind(kind)
end
```

Caches that today live on `Manifest` (`@zone_kinds_cache`,
`@role_mapping`) move here.

**`Manifest::Rules`** — already exists. No change.

### Use-case constructors narrow

Before:

```ruby
def initialize(ctx:, manifest:, file_store:, …)
  @manifest = manifest
  …
end

def call(key)
  rules = @manifest.rules_for(key)
  path  = @manifest.resolver.resolve(key).path
end
```

After:

```ruby
def initialize(ctx:, ports:, file_store:, …)
  @resolver = ports.manifest.resolver
  @rules    = ports.manifest.rules
  …
end

def call(key)
  rules = @rules.for(key)
  path  = @resolver.resolve(key).path
end
```

The `ports.manifest` access remains for cases that genuinely need
the composition record (e.g. `Pulse`, `Doctor`, `boot`), but those
are a minority. Most use cases narrow to one or two children.

### Migration helper

`Manifest` keeps `#resolver`, `#rules`, and adds `#policy`, `#data`
as direct delegators. The old top-level methods
(`#zones`, `#zone_writers`, `#permission_for`, `#zone_kinds`,
`#rules_for`, `#validate_key!`, `#audit_config`, `#role_mapping`,
`#role_kind`, `#roles_with_kind`) are deprecated with a one-cycle
shim that emits a warning and forwards to the new child:

```ruby
def permission_for(zone)
  warn "[textus] Manifest#permission_for is deprecated; use manifest.policy.permission_for(zone)"
  policy.permission_for(zone)
end
```

Shims are removed in 0.26.0.

## Consequences

**Positive**

- Use-case constructors declare exactly which manifest concern they
  depend on. Reading the body becomes optional for tracking
  dependencies.
- The `Policy` view becomes a natural home for future authority
  features (e.g. zone-level read-policy expansion, ADR 0015
  Phase 2 contract surface). They no longer accrete on `Manifest`.
- `Manifest::Data` becomes safe to share between processes (no
  caches, no behaviour) — useful for the MCP server's contract
  envelope.
- `Doctor::Check::*` consumers narrow: each check declares which
  child it inspects. Today most checks take `store` only to reach
  `store.manifest.something`.

**Negative**

- One-cycle deprecation noise on every existing caller. Most
  internal callers update in the same PR; user-supplied hooks that
  read `store.manifest.zone_writers` see a warning until 0.26.0.
- `Manifest` as a `Data.define` composition record means
  `manifest.entries` becomes `manifest.data.entries`. The deprecation
  shim keeps the short form working for one cycle.

**Neutral**

- No wire-format change. Bumps with 0.25.1.
- `Manifest.load(root)` signature unchanged. Composition root
  (`Store`) calls it the same way.

## Alternatives considered

**Keep `Manifest` whole, document the four roles in comments.**
Cheaper, but doesn't narrow any constructor — the whole point.

**Make `Manifest` a module of class methods over a raw Hash.**
Loses caching, loses the `Data.define` ergonomics, loses the
natural home for `Policy` state.

**Carve only `Policy` out, leave Resolver/Rules where they sit on
Manifest.** Half-measure; the four roles are equally distinct and
every consumer already grabs `.resolver` or `.rules` through
delegation. Carving all four at once removes the ambiguity rather
than postponing it.
