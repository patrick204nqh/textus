# Architecture Conventions

## Folder Structure
```
lib/textus/
  surface/    # Entry points (CLI, MCP)
  use_cases/  # Orchestration (one file per contract read/write/ops)
  domain/     # Pure logic, zero I/O
  port/       # I/O abstractions (interface + impl)
  dispatch/   # Command bus (pipeline, middleware, registry)
  store/      # Store internals (Reader, Writer, Layout)
  value/      # Value objects
  manifest/   # Config data + policy
```

## Role Design
| Role | Used By | Default | Capabilities |
|------|---------|---------|-------------|
| automation | System (drain, converge, jobs) | Yes | converge |
| agent | MCP server | No | propose, keep |
| human | CLI, direct | No | author, ingest |

## Knowledge Pipeline

```
INPUT → LOOP:
           level 1: intent → constraint (validate before proceeding downstream)
           level 2: judgment → evidence → execution → feedback
       → OUTPUT
```

| Stage | Role | Examples |
|-------|------|----------|
| **Input** | Raw material | audit results, feature requests, bugs, agent sessions, external context |
| **Loop L1** | Principles — validate everything below | intent (north-star), constraint (repo/protocol) |
| **Loop L2** | Refinement — constrained by L1 | judgment → evidence → execution → feedback |
| **Output** | Hardened knowledge | protocol constraints, execution runbooks, projected docs |

### Level 2 Refinement Flow

```
judgment → evidence → execution → feedback
    ↑                                  │
    └──────────────────────────────────┘
```

| Section | Role | Examples |
|---------|------|----------|
| judgment/engineering | Reusable solutions and conventions | bounded-use-cases, dependency-adapters, anti-patterns |
| evidence/ | Why we chose — historical ADRs | all ADR files |
| execution/ | How to execute — procedural | adr, release |
| feedback/ | Audits and review loops | solid-audit |
| constraint/protocol | Formal contract — what we commit to | 0001-conventions through 0014-data-flow |

The loop is self-correcting: judgment identifies issues and patterns → evidence captures the decision record → execution operationalizes it → feedback measures outcomes → back into judgment. Intent and constraints validate input before anything enters the loop, and loop output may signal updates to intent or constraints.

## Agent Training

On session start, agents should read:
1. `knowledge.judgment.engineering.0009-conventions` — this file (folder structure, role design, pipeline)
2. `knowledge.constraint.protocol.0014-data-flow` — how data flows through the system
3. `knowledge.judgment.engineering.0010-anti-patterns` — what to avoid
4. `knowledge.feedback.0001-solid-audit` — SOLID evaluation of the codebase
5. `knowledge.judgment.engineering.*` — reusable patterns when designing new code

When designing new code, prefer:
- **Unified dispatch** — new verbs automatically route through Store#method_missing
- **Middleware chain** — cross-cutting concerns as pluggable middleware
- **Handler NEEDS** — declare minimal dependencies per use case
- **Store::Builder** — dependency construction extracted from Store

When reviewing:
- Check for dual paths (two ways to do the same thing)
- Check vocabulary collisions (same term, different meanings)
- Check layer violations (domain/ never references manifest/ or ports/)
- Check for vestigial code (HANDLES_ALL paths, dead branches)

## Naming
- Use cases: `<Layer>::<Verb><Noun>` (Read::GetEntry, Write::PutEntry)
- Contracts: `Dispatch::Contracts::<Same>` (GetEntry, PutEntry)
- call = Value::Call, deps = injected dep struct, command = contract instance

## Avoid
1. Dual paths — never two ways to do the same thing
2. God classes — Store stays thin
3. Vestigial code — delete what's unused
4. Layer violations — domain never references manifest/ or ports/

## Agent Scratchpad Structure

The scratchpad lane gives the agent full control over session working memory:

```
scratchpad.notes.{topic}          # Durable working notes (cross-session)
scratchpad.sessions.{session_id}  # Per-session scratchpad
  notes.md                        #   Working notes for this session
  plan.md                         #   Implementation plan
  artifacts/                      #   Temp files (diagrams, dumps)
  scripts/                        #   Shell scripts generated during this session
scratchpad.scripts.{name}         # Reusable scripts (promote from sessions)
```

- `session_id` = correlation_id or a short slug (`feat-auth`, `fix-bug-123`)
- Scripts generated during a session live under that session's `scripts/` sub-key
- Reusable scripts can be promoted to `scratchpad.scripts.{name}` for cross-session use
- Finished sessions consolidate durable output into `knowledge.*` and `scripts/`
- `scratchpad.notes` is git-tracked (durable working memory)
- `scratchpad.sessions` and `scratchpad.scripts` are gitignored (transient)
