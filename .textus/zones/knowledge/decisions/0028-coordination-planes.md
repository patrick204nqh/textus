# ADR 0028 — Coordination space: closed topology, closed transitions, open policy

**Date:** 2026-05-29
**Status:** Accepted — moves 1 & 4 shipped in 0.30.0 (zone kind + retention); moves 2 & 3 shipped in 0.32.0 ([ADR 0031](./0031-unified-guard.md))
**Refines:** [ADR 0002](./0002-textus-3-vocabulary-redesign.md), [ADR 0018](./0018-manifest-carving.md), [ADR 0027](./0027-hook-signature-and-mcp-policy.md)

## Context

textus exists so that humans, agents, and runners can write into one durable fabric
without overwriting each other, and so the *refusal* — `write_forbidden`, naming the
role that would be allowed — is legible at the moment a writer breaks the rule. That
legible refusal is the product, not a side effect.

A brainstorm on 2026-05-29 asked the next question: how do we shape this space so an
operator can describe a *novel* coordination arrangement — new roles, new zones, new
conditions on a hand-off — without engine changes, and without the refusal becoming
illegible? "Flexible to define zones, rules, policy" is the ask. The trap is that if
*everything* becomes configurable, the gate stops being explainable and textus
quietly becomes a workflow engine.

A survey of the code found that the architecture is already trending toward an answer
it has not named:

- **An emerging predicate layer.** `lib/textus/domain/policy/predicates/` already holds
  `accept_authority_signed` and `schema_valid`. `Domain::Policy::Promotion.from_names`
  composes predicates from the role-kinds a `promotion.requires:` block names
  (`lib/textus/write/accept.rb:74`).
- **A closed, hand-rolled transition set.** `lib/textus/write/` holds `put`, `accept`,
  `reject`, `refresh`, `build`/`materializer`, `mv`, `delete`. Each re-runs the write
  gate — `accept` writes its target through `put` (`write/accept.rb:34`), so no
  transition launders bytes past the authority matrix.
- **A role-kind vocabulary.** `Manifest::RoleKinds::DEFAULT_MAPPING` maps
  `human → accept_authority`, `agent → proposer`, `builder → generator`,
  `runner → runner`.
- **A `rules:` block** (`Manifest::Rules`) with `refresh`, `promotion (requires:)`,
  `intake_handler_allowlist`, and a reserved-but-inert `retention` slot, matched by
  most-specific glob (`Domain::Policy::Matcher`).

But the model is fighting itself in two places. Zone *kind* is **inferred** from the
role-kinds of its writers (`Manifest::Policy#zone_kinds`) and, worse, the proposal
zone is found by **string-matching** `"review"` in the zone name
(`Manifest::Policy#propose_zone_for`, introduced in ADR 0027). That directly
contradicts the documented promise that zones may be renamed freely
(`docs/zones.md §4`): rename `review` and proposals silently break. And only one
transition — `accept` — consults a declarative guard; `refresh` and `build` bake
their conditions in elsewhere, so there is no single thing called "the guard" that an
operator learns once.

This ADR names the model the code is reaching for and ratifies the invariant that
keeps it legible. It is a *direction* decision: it binds the invariant, not a
schedule of code changes.

## Decision

### 1. Three planes

A textus store's coordination model is exactly three planes:

```
PLANE 1 · TOPOLOGY      zones · roles · role-kinds · the authority matrix   [CLOSED — data]
PLANE 2 · TRANSITIONS   put · accept · reject · refresh · build · mv · delete [CLOSED — verbs]
PLANE 3 · POLICY        predicates composed by rules:                        [OPEN — composable]
```

- **Topology** answers *who may originate bytes, and where.* Pure manifest data.
- **Transitions** are the named, audited boundary crossings. Each crossing is re-gated
  and audited, and each asks the policy plane a single question: *may this cross?*
- **Policy** answers *what must be true to cross* — a composition of pure predicates.

### 2. The invariant — closed primitives, open policy

**The set of zone-kinds and the set of transition verbs are CLOSED.** Only the
**predicate vocabulary** (Plane 3) and **hooks** (effects) are open for extension.

This is the load-bearing rule. Flexibility is added by *composing predicates* and
*subscribing hooks*, never by minting a new zone-kind or a new verb. The primitive
sets stay small and legible; that is what keeps every refusal self-explaining.

The flexibility test the model must pass: **adding a new writer-role
(`reviewer`, `scheduler`, `import-bot`) is a manifest edit** — declare the role, map
it to one of the closed role-kinds, name its origin zone, and name the predicate its
output must satisfy to climb. Zero engine code. If a proposed feature requires a new
verb or a new zone-kind, the model has failed and the feature must be reshaped.

### 3. The principle — trust flows uphill through guarded transitions

Each writer-role carries a trust level. Low-trust origins (a runner's external bytes,
an agent's guess) reach high-trust zones (`working`, `identity`) **only** by crossing
a transition whose guard strength matches the height of the jump. `review` is the one
deliberate co-write zone — the table where two authorities (proposer + accept
authority) meet so the hand-off is explicit. No other zone shares write authority.

| Role-kind        | Originates in        | Guard its output passes to climb        |
|------------------|----------------------|------------------------------------------|
| `runner`         | quarantine (`intake`)| `schema_valid` + freshness — mechanical  |
| `proposer`       | `review` (+ its own scratch) | `accept_authority_signed` — reversible |
| `accept_authority` | `identity` / `working` | *is* the predicate that satisfies the top guard |
| `generator`      | `output`             | sources-fresh + idempotent — derives, never originates |

### 4. Q1 resolved — transitions stay closed

The pivotal fork was: *do operators get to declare their own transitions?* **No.** The
verb set is closed. Opening it turns textus into a turing-complete workflow engine and
kills the legible refusal that is its entire reason to exist. This decision binds that
answer; everything else in this ADR follows from it.

### 5. Directional consequences (follow-on work, not bound by this ADR)

Naming the model exposes four moves that bring the code into line with it. They are
recorded here as direction; each lands under its own change with its own review:

1. **[Shipped in 0.30.0, strict]** **Declare a zone's kind explicitly.** `kind:` is
   required and authoritative; the writers-inference and `"review"` substring
   fallbacks were never released — the cleanup was folded into 0.30.0 (no
   external users to migrate). A manifest with a kind-less zone is rejected at
   load; proposals route only to the zone declaring `kind: queue`.
2. **[Shipped in 0.32.0]** **Generalize `promotion.requires:`** from role-kind names to
   predicate references — now `rules[].guard: { accept: [accept_signed, schema_valid,
   { fresh_within: "1h" }] }` ([ADR 0031](./0031-unified-guard.md)).
3. **[Shipped in 0.32.0]** **Unify the guard** so every transition — not only `accept` —
   evaluates one `Guard` abstraction sourced from `rules:`. One thing to learn, one thing
   `policy explain` reports ([ADR 0031](./0031-unified-guard.md)).
4. **[Shipped in 0.30.0]** **Activate `retention`** (already reserved in
   `Manifest::Rules::Block`) as the lifetime axis: TTL/archive for `intake`, expiry for
   ephemeral `review`.

## Consequences

**No wire change in this ADR.** `textus/3` is unchanged; this ratifies a principle.
Move 1 (shipped in 0.30.0) did introduce a **manifest-schema change**: `kind:` is now a
required field on every zone, and manifests without it are rejected at load. No other
moves in this ADR touch the manifest schema; any that do will carry their own ADRs and
version notes.

**Predicates are the growth surface.** Adding a capability means adding a pure
predicate to `Domain::Policy::predicates/` and referencing it from `rules:` — not
editing `write/`. The verbs and zone-kinds are stable ground to build on.

**The refusal stays truthful.** Because predicates are pure functions of
`(envelope, actor, target, store-snapshot)`, `policy explain` can report *why* a
crossing would be refused before it is attempted, and the `write_forbidden` /
guard-failure message names the unmet predicate.

**`propose_zone_for` resolved.** ADR 0027 gave the `"review"` convention a single home
in `Manifest::Policy`; move 1 (shipped 0.30.0) replaced it — `propose_zone_for` now
resolves through `kind: queue` exclusively. The string-match and rename-fragility are
gone.

**Single-writer authority keeps consensus out.** Because exactly one authority
originates in each zone (except `review`), there is no concurrent-origin conflict to
resolve — no locking, no CRDTs. Any future design that breaks single-writer authority
contradicts this ADR.

## Alternatives considered

**Declarable transitions (open Plane 2).** Let operators define their own verbs with
custom guards and effects. Rejected — this is the Q1 fork. It yields a workflow-engine
DSL whose refusals are only as legible as the operator's config, destroying the
property the product is built on. Custom *effects* are already available through hooks
on the existing verbs; that is the sanctioned extension point.

**Everything configurable (collapse the planes).** Treat zones, verbs, and conditions
as one uniform rules table. Rejected — it removes the closed/open boundary that makes
the model teachable. The three-plane split is precisely the constraint that lets
flexibility live in one place without leaking into the legible core.

**Keep inferring zone kind from writers (do nothing).** Rejected as the long-term
shape. Inference plus the `"review"` substring match is the source of the
rename-fragility; an explicit zone kind is the honest fix. Deferred, not dismissed —
sequenced as move 1.

## Open questions

- **Predicate vocabulary for v1.** `schema_valid` and `accept_authority_signed` exist.
  Which join them — `fresh_within`, `owner_is`, `quorum(n)`? Is `AND`-composition
  enough, or is `OR` needed? (Blocks move 2; route through `product-capability`.)
- **Explicit zone kind — schema shape.** ~~Resolved in 0.30.0~~ — `kind:` is a required
  manifest field; existing manifests must declare it on every zone.
- **Agent memory zone (`scratch`).** Agents have a *proposal* lane (`review`) but no
  *memory* lane, contradicting the README promise that agents stop forgetting between
  sessions. Ship as a default zone, or document as an opt-in pattern?
- **One store or federated.** Is "the coordination space" a single `.textus/`, or do
  actors coordinate across multiple stores? This determines whether the audit cursor
  (`pulse --since=N`) must become global, and is expensive to retrofit.
- **Retention scope.** Is the lifetime axis (move 4) in scope for the next pass or
  deferred behind the predicate work?
