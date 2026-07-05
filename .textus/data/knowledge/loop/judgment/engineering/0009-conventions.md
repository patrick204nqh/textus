# Architecture Conventions

## Folder Structure
```
lib/textus/
  protocol/    # Core protocol: Session, Gate, Builder, Handlers, StoreEngine, Format
  infra/       # Infrastructure: SQLite, FileStore, Ports, Adapters
  lanes/       # Lane-specific handlers (knowledge, scratchpad, artifact)
  surface/     # Entry points (CLI, MCP, Watcher)
  workflow/    # Workflow engine (DSL, Runner, StepExecutor, Consumer, Publisher)
  value/       # Value objects (Role, Etag, Call, Uid, Duration)
  errors.rb    # Error hierarchy
```

## Role Design
| Role | Used By | Default | Capabilities |
|------|---------|---------|-------------|
| automation | System (drain, watcher, workflows) | Yes | converge |
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
| judgment/engineering | Reusable solutions and conventions | unified-dispatch, store-builder, anti-patterns, error-handling |
| evidence/ | Why we chose — historical ADRs | all ADR files |
| execution/ | How to execute — procedural | adr, release |
| feedback/ | Audits and review loops | solid-audit |
| constraint/protocol | Formal contract — what we commit to | 0001-conventions through 0014-data-flow |

The loop is self-correcting: judgment identifies issues and patterns → evidence captures the decision record → execution operationalizes it → feedback measures outcomes → back into judgment. Intent and constraints validate input before anything enters the loop, and loop output may signal updates to intent or constraints.

## Agent Training

On session start, agents should read:
1. `knowledge.loop.judgment.engineering.0009-conventions` — this file (folder structure, role design, pipeline)
2. `knowledge.loop.constraint.protocol.0014-data-flow` — how data flows through the system
3. `knowledge.loop.judgment.engineering.0010-anti-patterns` — what to avoid
4. `knowledge.loop.judgment.engineering.0015-solid-audit` — SOLID evaluation of the codebase
5. `knowledge.loop.judgment.engineering.*` — reusable patterns when designing new code

When designing new code, prefer:
- **Unified dispatch** — new verbs automatically route through Protocol::Session#method_missing
- **QueryContext/CommandContext** — CQS split for read vs write handler access
- **Pipeline steps** — StoreEngine pipeline steps as Data.define context + module step
- **Protocol::Builder** — 3-layer dependency construction (infra/domain/runtime)

When reviewing:
- Check for dual paths (two ways to do the same thing)
- Check vocabulary collisions (same term, different meanings)
- Check layer violations (protocol/ never references surface/ or lanes/)
- Check for vestigial code (dead branches, unused value objects)

## Naming
- Handlers: `<Module>::<verb>` (Handlers::Read.get, Handlers::Write.put)
- Pipeline steps: `<Action><Noun>` (Validate, Prepare, Write, Emit)
- Contexts: `QueryContext`, `CommandContext`, pipeline-specific `*Context`
- call = Value::Call, ctx = context at the handler seam, deps = pipeline dependencies

## Avoid
1. Dual paths — never two ways to do the same thing
2. God classes — Gate and Session stay thin
3. Vestigial code — delete what's unused
4. Layer violations — protocol/ never references surface/ or lanes/

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
