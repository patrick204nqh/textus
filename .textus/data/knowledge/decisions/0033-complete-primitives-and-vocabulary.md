# ADR 0033 — Complete the primitive set (`workspace` + `keep`) and clarify the vocabulary

**Date:** 2026-05-30
**Status:** Accepted — ships 0.33.0
**Refines:** [ADR 0028](./0028-coordination-planes.md) (closed primitive sets), [ADR 0029](./0029-concept-vocabulary.md) (concept vocabulary), [ADR 0030](./0030-capability-based-roles.md) (capability roles), [ADR 0031](./0031-unified-guard.md) (`accept_signed` predicate)
**Partially supersedes:** the capability/zone-kind *membership* in ADR 0028 §1 (four → five each), the `accept` capability name in ADR 0030, the `accept_signed` predicate name in ADR 0031. The *invariants* of all three stand unchanged.

## Context

Three reviews converged on the same finding: the coordination model is sound, but
its **primitive set is one element short** and its **vocabulary names two things
for the wrong axis**.

**The hole (topology).** The README's load-bearing promise is *"you keep your space,
agents keep theirs, automation keeps external data fresh."* The topology delivers two
of three. A human owns `canon` zones (`identity`, `working`); automation owns
`quarantine` (`intake`) and `derived` (`output`). The **agent owns nothing durable** —
its only writable zone is `review` (`kind: queue`), a *proposal queue* whose bytes are
pending a human accept and retention-swept, not memory. ADR 0028 already flagged this
("agents have a proposal lane but no memory lane, contradicting the README promise")
and parked it.

It cannot be patched within the four existing kinds. `canon` (then `origin`) is defined
as "accept-holders write." To give an agent a durable private lane you must either give
it the `accept` capability — which detonates the single-trust-anchor invariant
(ADR 0030 §6) — or attach an `owner_is` predicate to a canon zone, but the floor
predicate `zone_writable_by` still demands `accept` and refuses the agent before the
predicate runs. **The four-verbs ↔ four-zone-kinds correspondence conflates *ownership*
("whose lane is this") with *trust* ("does it need review to climb").** No primitive
expresses "an actor's own durable lane that is *not* the trust anchor."

**The naming seams (vocabulary).** A code survey found two names placed on the wrong axis:

1. **`accept` is named for the wrong axis.** The other three capabilities are named for
   *the act of originating* in their zone-kind — you `fetch` into quarantine, `build`
   into derived, `propose` into a queue. But authoring `identity`/`working` is just
   *writing*; `accept` names the *queue → canon promotion gesture*, a different boundary
   crossing. The capability that grants "author your authoritative space" is named after
   the review handshake. This is why ADR 0030 §7 had to admit `accept` is "bundled"
   (author origin + sign queue) — the bundling is the symptom of the name.
2. **`origin` is a weak zone-kind name.** ADR 0028's own principle is "topology answers
   *who may originate bytes, and where.*" — **all four kinds originate bytes** (intake
   originates external bytes, queue originates proposals, derived originates computed
   bytes). Naming one kind `origin` collides with the general verb, and it is the only
   kind whose name pairs with *neither* of its zones (`identity`, `working`), whereas
   `quarantine`↔`intake`, `queue`↔`review`, `derived`↔`output` each pair cleanly. The
   distinguishing property of `identity`/`working` is that they are *authoritative* —
   the trust anchor — not that they "originate."

**The default-scaffold confusion (instances).** The shipped zone names (`identity`,
`working`, `intake`, `review`, `output`) mix metaphors and obscure the workflow. A
verification grep confirmed the engine **never special-cases these names** — they appear
only in `init.rb` defaults and as two hardcoded description strings in `boot.rb`
(`boot.rb:14-18`). In particular `identity` and `working` are **byte-identical at the
topology layer**: same kind, same gate, same transitions, same guard. The split is
*convention, not topology* — exactly the "looks like a distinction, isn't one"
redundancy ADR 0030 and ADR 0032 removed (`write_policy`, `role-kind` 1:1, `read_policy`).
The `boot.rb` descriptions, keyed by zone *name*, also silently vanish on rename — the
same rename-fragility class ADR 0028 flagged with the `"review"` substring match.

## Decision

### 1. Add the fifth primitive: `workspace` zone-kind + `keep` capability

The closed sets grow by one each, re-closing the model at five:

```
ZONE_KINDS   = canon · workspace · quarantine · queue · derived
CAPABILITIES = author · keep · fetch · build · propose
KIND_REQUIRES_VERB = { canon: author, workspace: keep, quarantine: fetch,
                       queue: propose, derived: build }
```

`workspace` is the dual of `canon`: **self-owned and durable, but not the trust anchor.**
The role named in the zone's `owner:` writes it freely; bytes there **never auto-promote**
— they climb to `canon` only through the existing `propose → proposals → accept` path,
exactly as an agent's proposals do today. Trust still flows uphill through guarded
transitions (ADR 0028 §3); `workspace` adds a *low-trust origin*, not a bypass.

This **preserves** ADR 0028's invariant rather than breaking it. The invariant is "add
flexibility by *composing* primitives, never by *minting* them at will." We are not
opening the set to operator extension — we are correcting a one-time, provable
incompleteness (no primitive expressed self-owned-but-low-trust) and re-closing it. The
flexibility test still holds: a new writer-role is a manifest edit, not engine code.

### 2. Rename capability `accept` → `author`; `accept` survives only as a transition

Every capability is now named for *the act of originating in its zone-kind*:

| capability | originates in | zone-kind |
|---|---|---|
| `propose` | a queue (awaits accept) | `queue` |
| `author` | the authoritative record | `canon` |
| `fetch` | external quarantine | `quarantine` |
| `build` | computed artifacts | `derived` |
| `keep` | the actor's own workspace | `workspace` |

`accept` is **no longer a capability**. It remains a **transition** (the closed Plane-2
set is unchanged: `put · accept · reject · fetch · build · mv · delete`) — the
queue → canon promotion, which is genuinely a *boundary crossing*, not an origination.
The `accept`/`reject` transitions require the **`author`** capability (you author the
canonical copy from the proposal). The `accept_signed` predicate is renamed
**`author_signed`**.

**Single-anchor invariant, restated:** *at most one role may hold `author`, and a
low-trust role must never hold it.* (Unchanged from ADR 0030 §6; only the name moves.)

### 3. Rename zone-kind `origin` → `canon`

`canon` names the distinguishing property — *the authoritative, single-writer source of
truth that trust flows toward* — without colliding with the general "originate bytes"
verb that applies to every kind.

### 4. Collapse the default `canon` zones; `identity` becomes a key prefix

The default scaffold ships **one** `canon` zone. The `identity`/`working` split was
topology-invisible; it returns as a **key namespace** (`knowledge.identity.*` alongside
`knowledge.notes.*`). Any *real* difference is expressible without a second zone:

- stricter change-control on identity → a `rules[].guard:` glob on `*.identity.**`;
- different retention/cadence → a `rules[].retention:` glob;
- "agent reads identity first at boot" → a boot projection (ADR 0032 open question).

(Operators who want `identity`/`working` visibly separate may still declare two `canon`
zones — the engine supports N zones per kind. This decision is about the *default*.)

### 5. Rename the default zones for workflow legibility (Setup 1)

Each default zone name now states its station in the byte-flow, named as a **noun
describing the contents** (never a state-adjective, never the product's own word):

```yaml
zones:
  - { name: knowledge, kind: canon }                   # was: identity + working
  - { name: scratchpad,  kind: workspace, owner: agent } # NEW — the agent's own lane
  - { name: feeds,     kind: quarantine }              # was: intake
  - { name: proposals, kind: queue }                   # was: review
  - { name: artifacts, kind: derived }                 # was: output
roles:
  - { name: human,      can: [author, propose] }       # was: [accept, propose]
  - { name: agent,      can: [propose, keep] }          # was: [propose] — gains its lane
  - { name: automation, can: [fetch, build] }
```

Reads as one sentence per actor: *automation **fetches** feeds and **builds** artifacts;
the agent **keeps** a scratchpad and **proposes** changes; you **author** them into
knowledge.*

### 6. Zone descriptions become manifest data

The hardcoded zone-name → description map in `boot.rb` moves to an optional `desc:` field
on each `zones:` entry; `boot` reads it from the manifest. Descriptions now survive
renames (killing the `boot.rb` rename-fragility) and live as data beside the zone they
describe.

## Consequences

- **Breaking, no back-compat (single user, clean break).** Ship as **0.33.0**, consistent
  with the 0.30/0.31/0.32 stance.
- **`textus/3` wire format is UNCHANGED.** Role names are opaque strings on the wire;
  zone-kinds, capabilities, and zone names are **manifest-only**. The entry/envelope
  contract, audit-log shape, and key grammar do not move. This is a *manifest-schema +
  default-scaffold + predicate/error-name + docs* change, not a protocol-version bump.
- **Manifest-schema changes:** `ZONE_KINDS` and `CAPABILITIES` each gain one member;
  `KIND_REQUIRES_VERB` gains `workspace → keep` and remaps `canon → author`; a `canon`
  zone may carry `owner:`; zones may carry `desc:`. A manifest using `origin`/`accept`
  gets an unknown-value rejection (no aliasing, no detection).
- **Error/predicate reshape:** `accept_signed` → `author_signed`; capability-naming
  strings in `write_forbidden` and `guard_failed` say `author`/`keep`. The
  `write_forbidden` code and its `pass --as=<role>` hint are preserved.
- **The closed-set invariant holds at five.** Predicates and hooks remain the only
  *operator* growth surface; the primitive sets are again closed. Any future request for a
  sixth kind/capability must clear the same bar this ADR cleared: prove the set is
  *provably incomplete*, not merely *inconvenient*.
- **Scope boundary.** This ADR does **not** address the freshness/staleness duplication
  (P2) or the single-store/federation question (P3) raised in the same review — those are
  separate decisions and keep their own ADRs.

## Alternatives considered

- **Patch the gap without a new kind** — give `agent` the `accept` capability, or gate a
  `canon` zone with `owner_is`. Rejected: the first breaks the single-anchor invariant;
  the second is refused by the `zone_writable_by` floor before any predicate runs. The
  honest fix is the missing primitive.
- **Keep the set at four; deliver agent memory as a boot projection only.** Rejected: a
  projection scopes *reads*, not *writes* — the agent still has nowhere it may *write*
  durably. The promise is about writing, not viewing.
- **Keep `origin`/`accept` names; only add `workspace`/`keep`.** Rejected: naming the new
  origination capability (`keep`) immediately re-exposes that `accept` is the lone
  capability *not* named for origination. Fixing the hole without fixing the names ships a
  five-element set that is inconsistent on its face.
- **Collapse `canon` to one and drop the ability to declare two.** Rejected: N-zones-per-kind
  is already supported and harmless; this ADR changes only the *default*, leaving operators
  free to split.

## Open questions

- **Human workspace.** Should `human` also get a `keep` lane by default, or is a personal
  scratch a per-operator opt-in? (Deferred; the default ships only the agent `scratchpad`.)
- **Multiple workspaces of the same kind.** Two agents → two `workspace` zones, each
  `owner:`-scoped. Does the `owner_is`-style per-zone write check (ADR 0030 / 0031 open
  question) land here as the predicate that enforces `owner:`? (Sequenced with the
  predicate-vocabulary work.)
- **Retention defaults per kind.** `workspace` is durable but unbounded; does it want a
  default retention rule the way `quarantine`/`queue` do (ADR 0028 move 4)?
