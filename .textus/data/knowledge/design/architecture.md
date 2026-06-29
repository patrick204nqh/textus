---
uid: 9c4e39b1260d4ca8
sources:
- raw.2026.06.29.url-principles-design-feed
- raw.2026.06.29.url-golden-rules-shneiderman
- raw.2026.06.29.url-karpathy-software-2
- raw.2026.06.29.url-addy-loop-engineering
---
# Architecture (Current State)

Status: Living document
Last updated: 2026-06-29
Companion invariant: `design/invariants.md` (read first)

## System Intent

textus is a protocol-first memory coordination system.
It provides deterministic read/write over structured project memory with explicit authority boundaries for three actors, each optimized for different work:

- human (trust anchor: decision, direction, acceptance)
- agent (creative actor: synthesis, drafting, proposing)
- automation (deterministic actor: repeatable, scheduled, fixed-step execution)

Primary objective: reduce repetitive manual work while preserving human agency and avoiding AI slop.

## Architectural Shape

The implementation follows a layered shape with inward dependency flow:

Surfaces -> Dispatch -> Gate/Auth -> Actions -> Inner systems (Jobs, Produce, Workflow, Manifest, Ports, Core)

This keeps policy and behavior explicit while allowing multiple external surfaces (CLI, MCP) to share one execution model.

## Runtime Layers

1. Surfaces
   - CLI surface
   - MCP surface
   - Role-scoped invocation facade (`Store#as(role)`)

2. Contract/Dispatch
   - Verb contracts (args, summary, surface visibility, wrappers)
   - Binder, around resources, command builder, dispatcher

3. Gate/Auth
   - Verb routing to actions
   - Authorization via capability/lane-kind gate and guard predicates

4. Actions (Use Cases)
   - One action per verb (`get`, `put`, `accept`, `drain`, `pulse`, etc.)
   - Operate on container-provided collaborators

5. Jobs + Convergence
   - Planner seeds materialize/refresh/sweep
   - Worker leases and executes queue jobs
   - Materialization/publish runs through produce engine

6. Produce + Workflow
   - Workflow registry/loader/runner executes acquisition steps
   - Publish emits to consumer files (copy or template render)

7. Manifest/Rules/Schemas
   - Declarative policy (roles, lanes, entries, rules)
   - Resolver maps keys to paths
   - Schema contracts validate entry shape

8. Ports/Core
   - FileStore, AuditLog, JobStore, Publisher, BuildLock, SentinelStore
   - Pure value types (freshness, duration, retention, sentinel)

## Data Model

Core model elements:

- Key: dotted identifier (hierarchical addressing)
- Entry: typed content unit (markdown/json/yaml/text)
- Lane: storage partition with declared `kind`
- Role: actor identity with capability set
- Capability gate: lane write authority derived from `kind -> capability`
- RuleSet: retention/guard/permit overlays by key match

Default lane semantics:

- `knowledge` (`canon`): authored truth
- `notebook` (`workspace`): agent durable working memory
- `proposals` (`queue`): staged transitions awaiting review
- `artifacts` (`machine`): converged outputs/materialized data
- `raw` (`raw`): write-once intake of external material

## Workload Routing Model

Architecture enforces role-fit routing:

- Human-owned work
  - Canonical acceptance/rejection
  - Priority, scope, and quality bar decisions
  - Final policy and design direction

- Agent-owned work
  - Drafting and proposal generation
  - Cross-document synthesis
  - Exploratory analysis in workspace/proposals lanes

- Automation-owned work
  - Feed/fetch ingestion loops
  - Scheduled `drain` convergence and retention sweeps
  - Deterministic projection/materialization tasks

Rule of operation: if a task is recurring and fixed-step, move it to automation; if it is open-ended and creative, keep it with agent; if it changes authority or direction, keep it with human.

## Control Flows

### 1) Read flow

`surface -> gate -> Action::Get -> resolver + filestore + parser -> envelope + freshness verdict`

Properties:
- Pure read path
- No hidden ingestion or regeneration
- Freshness reported, not repaired

### 2) Write flow

`surface -> gate/auth -> Action::<write> -> Envelope::Writer`

Writer pipeline:
- serialize
- schema validate
- optional etag check
- write bytes
- append audit event

### 3) Proposal promotion flow

`propose` writes a candidate into queue lane.
`accept` (author capability required) applies candidate to canonical target and records audit provenance.

### 4) Convergence flow

`drain` triggers planning and queue-driven materialization.
Workflows acquire data; produce engine writes resulting entry content; publish projects data to consumer paths.
Retention and sweep jobs clean managed state explicitly.

This boundary is intentional: repetitive convergence belongs to automation so agents do not spend expensive tokens on predictable loops.

## Contract Surfaces

The system is consumed through stable envelopes:

- CLI verbs (`textus <verb>`) with JSON output envelopes
- MCP tools derived from the same verb contracts

Agent-oriented operations:
- `boot`: orientation and contract snapshot
- `pulse`: cursor-based change feed for continuous operation

## State and Persistence

Persistent state:
- `.textus/data/*` lane content
- `.textus/manifest.yaml`
- `.textus/schemas/*`

Runtime/disposable state:
- `.textus/.state/audit/*` (audit + rotation)
- `.textus/.state/cursors/*`
- `.textus/.state/locks/*`
- `.textus/.state/sentinels/*`
- `.textus/.state/indexes/*`

## Why this architecture evolves quickly

1. Fixed seams
   Contracts, actions, workflows, and ports are explicit extension points.

2. Shared execution core
   New surfaces can be added without forking core behavior.

3. Declarative policy plane
   Most authority and routing changes are manifest/rule changes, not code rewrites.

4. Deterministic observability
   Envelopes and audit log make behavior inspectable and automatable.

5. Trust layering
   Canon/workspace/queue/machine/raw separation allows rapid iteration without collapsing authority.

6. Role-fit execution
   Clear routing between human/agent/automation reduces coordination overhead and prevents uncontrolled generation in deterministic pipelines.

## Current Risks and Pressure Points

- Rule and guard complexity can become opaque without disciplined docs and diagnostics.
- Workflow sprawl can reduce predictability if naming and matching conventions drift.
- Publish overlap/mirroring requires careful ignore/prune discipline to avoid accidental file churn.
- Audit rotation and cursor expiration require robust agent recovery handling (`boot` re-sync).

## Architectural Guardrails

When changing architecture:

1. Keep read paths pure.
2. Keep capability x lane-kind write gating as the sole authority basis.
3. Keep source acquisition and publish projection separated.
4. Keep queue-driven convergence explicit (`drain`/jobs), not implicit.
5. Keep envelope and audit contracts stable.
6. Preserve inward-only dependencies across layers.

## Near-term Evolution Directions

- Strengthen diagnostics and explainability around rules/guards.
- Keep workflow registration, matching, and observability first-class.
- Continue reducing accidental coupling between surfaces and action internals.
- Preserve protocol contract while deepening implementation modules.
- Expand automation coverage for high-frequency repeat tasks currently done by manual agent prompting.
