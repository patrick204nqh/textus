# Data Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                            INPUT (Sources)                           │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│  │  raw/    │  │knowledge/│  │scratchpad│  │proposals/│            │
│  │external  │  │human     │  │agent     │  │pending   │            │
│  │material  │  │truth     │  │memory    │  │changes   │            │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘            │
│       │  ingest     │  put        │  put        │  accept/reject    │
│       ▼             ▼             ▼             ▼                   │
├──────────────────────────────────────────────────────────────────────┤
│                     GATE (Protocol Layer)                            │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Session#method_missing → Bridge#dispatch → Gate#dispatch    │   │
│  │   1. VerbRegistry.for(verb)    2. authorize! (write only)     │   │
│  │   3. Protocol::Binder.bind     4. resolve handler             │   │
│  │   5. handler.public_send(verb, **args, ctx:, call:)          │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                         │                                           │
│             ┌───────────┴───────────┐                               │
│             │ read (QueryContext)   │ write (CommandContext)        │
│             ▼                       ▼                               │
│  ┌────────────────────┐  ┌──────────────────────────┐               │
│  │  StoreEngine#read  │  │  StoreEngine#put          │               │
│  │  read file from    │  │  → PutPipeline:           │               │
│  │  disk, parse       │  │    Validate → Prepare →   │               │
│  │  format, return    │  │    Write → Emit           │               │
│  │  envelope          │  │  FileSystem + SQLite      │               │
│  └────────────────────┘  └──────────┬───────────────┘               │
│                                     │                               │
│                                     ▼                               │
├──────────── EVENT GATE ─────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  EventEmitter (centralized event gate)                       │   │
│  │  Receives from: Store writes (put/delete/move), Scheduler    │   │
│  │  (TTL expired), actor calls                                  │   │
│  │  Validates → looks up matching workflows → pushes to queue   │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                         │                                           │
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Infra::Store::WorkflowQueue (SQLite)                       │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐       │   │
│  │  │ pending  │ │processing│ │ failed   │ │ done     │       │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘       │   │
│  └──────────────────────┬───────────────────────────────────────┘   │
│                         │                                           │
│             ┌───────────┴───────────┐                               │
│             │                       │                               │
│        Drain mode             Watch mode                            │
│        (CLI, one-shot)        (process, continuous)                 │
│             │                       │                               │
│      1. seed_expired           each tick:                           │
│      2. pop all → consume      1. seed_expired                      │
│      3. report {ok, failed}    2. pop one → consume                 │
│                                 3. sleep(poll_interval)             │
│             │                       │                               │
│             └───────────┬───────────┘                               │
│                         │                                           │
├─────────────────────────┼───────────────────────────────────────────┤
│                         ▼                                           │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Core Execution (shared)                                    │   │
│  │                                                              │   │
│  │  Consumer.consume(row, queue)                                │   │
│  │    → mark_processing → Runner.run → complete or fail/resched │   │
│  │                                                              │   │
│  │  Runner.run(key) → resolve → StepExecutor.execute → Publish  │   │
│  │                                                              │   │
│  │  StepExecutor: serial steps (with timeout)                   │   │
│  │                parallel steps (Concurrent::Promise)           │   │
│  │                                                              │   │
│  │  Publisher: save_to → store_engine.put                       │   │
│  │             publish_to → file write via template             │   │
│  │             notify → empty trigger puts                      │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  OUTPUT                                                              │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  artifacts.boot     artifacts.docs.*  artifacts.changelog    │   │
│  │  artifacts.system.index  (+ published CLAUDE.md, AGENTS.md)  │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  SURFACES: CLI (textus get/put/list/...)                            │
│            MCP Server (agent tools via stdio)                       │
│            Watcher (poll loop, seed_expired + consume)              │
└──────────────────────────────────────────────────────────────────────┘
```

## Key flows

- **Write path:** `put` → Session → Gate → StoreEngine#put → PutPipeline (Validate → Prepare → Write → Emit) → FileSystem + SQLite → EventEmitter → WorkflowQueue
- **Read path:** `get` → Session → Gate → StoreEngine#read → FileSystem read → Format parser → envelope
- **Drain (CLI):** `drain` → Scheduler.seed_expired (TTL checks) → pop all pending from WorkflowQueue → Consumer.consume each → Runner → StepExecutor → Publisher
- **Watch (process):** Watcher tick → seed_expired → pop one → consume → sleep → repeat; triggered writes push events immediately via EventEmitter
- **Workflow execution:** EventEmitter receives event → looks up registry → pushes to WorkflowQueue → Consumer picks up → Runner resolves key → StepExecutor runs steps → Publisher writes save_to/publish_to/notify targets
- **Scheduler seeding:** Scheduler checks each workflow with TTL + save_to: if entry missing or older than TTL, pushes a "workflow" event to the queue

## Mermaid version

```mermaid
flowchart TB
    subgraph INPUT["INPUT — Sources"]
        RAW[".textus/data/raw/\nExternal material\n(urls, files, assets)"]
        KNOWLEDGE[".textus/data/knowledge/\nHuman-maintained truth\n(boot, loop nodes, project)"]
        SCRATCH[".textus/data/scratchpad/\nAgent working memory"]
        PROPOSALS[".textus/data/proposals/\nSuggested changes\nawaiting human accept"]
    end

    subgraph GATE_LAYER["GATE — Protocol Layer"]
        SESSION["Session#method_missing"]
        GATE["Gate#dispatch\n1. VerbRegistry\n2. authorize!\n3. Binder\n4. Handler"]
        STORE_ENGINE["StoreEngine\nread / put / delete / move\nvia Pipeline steps"]
        FS["File System\n.md / .json / .yaml on disk"]
        DB[("SQLite\n· entries (FTS5)\n· audit_events\n· workflow_events\n· cursors\n· link_edges")]
    end

    subgraph EVENTS["EVENT GATE — Workflow"]
        EE["EventEmitter\n(registry lookup → push)"]
        SCH["Scheduler\n(seed_expired: TTL check → push)"]
        WQ[("WorkflowQueue\n(SQLite: pending /\n processing / failed / done)")]
    end

    subgraph CORE["Core Execution (shared)"]
        CON["Consumer\nconsume(row, queue)\nmark → run → complete/fail"]
        RUN["Runner\nresolve → execute → publish"]
        SE["StepExecutor\nserial + parallel steps\nwith timeouts"]
        PUB["Publisher\nsave_to → store_engine.put\npublish_to → file write\nnotify → empty trigger"]
    end

    subgraph MODES["Invocation Modes"]
        DRAIN["Drain (CLI)\n1. seed_expired\n2. pop all → consume\n3. report"]
        WATCH["Watch (process)\neach tick:\n1. seed_expired\n2. pop one → consume\n3. sleep"]
    end

    subgraph OUTPUT["OUTPUT — Artifacts"]
        BOOT["artifacts.boot"]
        DOCS["artifacts.docs.*"]
        SYSTEM["artifacts.system.index"]
        PUBLISHED["CLAUDE.md / AGENTS.md\n(published via template)"]
    end

    INPUT --> GATE
    GATE --> STORE_ENGINE
    STORE_ENGINE <--> FS
    STORE_ENGINE --> DB
    STORE_ENGINE -- "entry.written/deleted/moved" --> EE
    SCH -. "TTL check" .-> DB
    SCH --> WQ
    EE --> WQ
    WQ --> DRAIN
    WQ --> WATCH
    DRAIN --> CORE
    WATCH --> CORE
    CORE --> OUTPUT
    CORE --> PUBLISHED
    DB --> PULSE["pulse verb\n(delta + loop_state)"]
```
