---
uid: 578908fe598d9685
---
# Architecture Deepening Plan

> Proposed: 2026-07-01
> Target: Level 3.3 → Level 4 (Bounded Contexts with Explicit Contracts)

## Diagnosis

**Current state:** Excellent hexagonal layering with 128 ADRs, contract-first dispatch, Result monad, conformance specs. Fuzzy boundaries at the module seam.

### Key findings

1. **God Module use cases** — UseCases::EntryWrite dispatches 10 contracts via internal if/elsif; EntryRead handles 13. Dependencies = union of all needs.
2. **Port interfaces implicit** — Writer checks respond_to?(:mv) instead of calling a declared interface. Port::Storage::Interface exists but is unused.
3. **No pure domain layer** — lib/textus/domain/ is empty. Core logic lives in Store/UseCases.
4. **Dual verb maps** — VerbRegistry + MCP::Catalog::WRITE_VERBS drift independently.
5. **Validation inside Writer** — Not at the system boundary. Testing validation requires full write path.
6. **Inconsistent Store:: namespacing** — Some sub-namespaces are modules, others are classes.
7. **No architectural fitness functions** — No automated guards beyond basic layering specs.
8. **Event types unvalidated** — No schema guard on emit.

## The Plan

### Phase 1 — Land In-Flight ADRs (0120, 0121, 0125)

| ADR | Work |
|-----|------|
| 0125 | Split UseCases::EntryWrite (10→10 classes) and EntryRead (13→13 classes). +23 files, no god modules. |
| 0120 | Unify dispatch: method_missing on Store, delete RoleScope/ReadModel/CommandModel. One dispatch path. |
| 0121 | 8-item hygiene pass: CursorExpired, Result alias, FileStore interface, verb category, remove redundant fetch, report schema errors, namespace convention. |

### Phase 2 — Domain Model Extraction

Carve Textus::Domain from dispatch/use-case code:

- Domain::Key — resolve, suggest, match, distance (from Manifest::Resolver + Key::*)
- Domain::Envelope — build, parse, freshness (from Value::Envelope)
- Domain::Lane — authority queries (verb_for_lane, roles_with_capability from Manifest::Policy)

Manifest remains load-time config. Domain becomes the stateless rule engine. Result: domain_purity_spec.rb comes alive.

### Phase 3 — Formal Port Contracts

Every port gets a declared interface module + conformance spec verifying implementation:

- Port::Storage: read, write, delete, exists?, etag, mkdir_p, mv, rmdir, dir_empty?
- Port::AuditLog: append, latest_seq, events_since, rotate, prune
- Port::Store (SQLite): execute, query_value, transaction, setup!, close
- Port::Publisher: publish, sentinel_path
- Port::Clock: now

Kill all respond_to? checks — replace with interface-verified calls.

### Phase 4 — Architectural Fitness Functions

| Guard | Prevents | Mechanism |
|-------|----------|-----------|
| Layer import | domain/ importing use_cases/ | Static require graph analysis |
| Module export | Calling private symbols across namespace | private_constant enforcement |
| Verb completeness | Adding verb without registration | Regex: every VERBS entry has contract + handler + CLI verb |
| Port implementation | Port missing declared method | Interface conformance (Phase 3) |

### Phase 5 — Observability Middleware

Add Trace = Data.define(:verb, :duration_ms, :correlation_id, :role, :key) flowing through dispatch. Every dispatch auto-instruments. Accessible via pulse. No manual annotation.

### Phase 6 — Hard-Cut Cleanup

No deprecation window, no warnings period. Remove cleanly; trust git log. If a consuming script breaks, the diff tells them how to fix it. Fast evolution > compatibility tax at this stage.

## Decision Test

| Invariant | Pass? |
|-----------|-------|
| Preserves protocol determinism? | Yes — all changes at internal seams |
| Keeps trust transitions explicit? | Yes — no change to proposal/accept |
| Routes work to right actor? | Yes — domain extraction makes pure core testable |
| Reduces manual repetition? | Yes — fitness functions automate review |
| Improves evolvability? | Yes — bounded use cases make single-action changes safe |
