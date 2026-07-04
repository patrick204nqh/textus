# Data Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                           INPUT (Sources)                           │
│                                                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │  raw/    │  │knowledge/│  │scratchpad│  │proposals/│           │
│  │external  │  │human     │  │agent     │  │pending   │           │
│  │material  │  │truth     │  │memory    │  │changes   │           │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘           │
│       │  ingest     │  put        │  put        │  accept/reject   │
│       ▼             ▼             ▼             ▼                  │
├─────────────────────────────────────────────────────────────────────┤
│                         CORE (Protocol Layer)                       │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Gate (auth → resolve → validate)          │   │
│  └────────────────────────┬─────────────────────────────────────┘   │
│                           │                                         │
│                           ▼                                         │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  EntryStore (format parse + DB index + FTS + audit log)     │   │
│  └──┬───────────────────────────────────────────────┬──────────┘   │
│     │ write                                         │ read         │
│     ▼                                               ▼              │
│  ┌──────────┐  ┌───────────────────────────────────────────────┐   │
│  │FileSystem│  │                   SQLite                       │   │
│  │.md .json │  │ ┌──────────┐┌──────────┐┌───────────────┐    │   │
│  │.yaml on  │  │ │ entries  ││ audit    ││workflow_events│    │   │
│  │disk      │  │ │ (FTS5)   ││_events   ││(event queue)  │    │   │
│  └──────────┘  │ ├──────────┤├──────────┤├───────────────┤    │   │
│                │ │ cursors  ││loop_pos  ││ link_edges    │    │   │
│                │ └──────────┘└──────────┘└───────────────┘    │   │
│                └──────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────┤
│                     EVENT BUS (Workflow Engine)                     │
│                                                                     │
│  entry.written / entry.deleted / entry.moved                        │
│         │                                                           │
│         ▼                                                           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │
│  │  Materialize │───>│    Workflow   │───>│  Workflow::  │          │
│  │ (auto, on    │    │   Registry    │    │   Runner     │          │
│  │  every write) │    │ (key→workflow)│    │ (exec steps) │          │
│  └──────────────┘    └──────────────┘    └──────┬───────┘          │
│                                                  │                  │
│                     ┌────────────────────────────┼──────┐           │
│                     │                            │      │           │
├─────────────────────────────────────────────────────────────────────┤
│  KNOWLEDGE LOOP      │            ┌──────────┐   │      │           │
│                      │            │  boot_   │   │      │           │
│  ┌──────┐            │            │ refresh  │   │      │           │
│  │intent│◄───────────┼────────────│ (watches │   │      │           │
│  └──┬───┘            │            │know.boot)│   │      │           │
│     ▼                │            └─────┬────┘   │      │           │
│  ┌──────────┐        │                  │triggers│      │           │
│  │constraint│        │                  ▼        │      │           │
│  │ .repo    │        │           ┌──────────┐    │      │           │
│  │ .protocol│        │           │Produce:: │    │      │           │
│  └──┬───────┘        │           │Engine.con│    │      │           │
│     ▼                │           │verge     │    │      │           │
│  ┌──────────┐        │           └──────────┘    │      │           │
│  │judgment  │        │                           │      │           │
│  │.engineer │        │                           ▼      ▼           │
│  │.agent-beh│        │                    ┌──────────────────┐     │
│  └──┬───────┘        │                    │  Publisher       │     │
│     ▼                │                    │  (templating +   │     │
│  ┌──────────┐        │                    │  publish_to)     │     │
│  │evidence  │        │                    └────────┬─────────┘     │
│  └──┬───────┘        │                             │               │
│     ▼                │                             │               │
│  ┌──────────┐        │                             ▼               │
│  │execution │        │                    ┌──────────────────┐     │
│  └──┬───────┘        │                    │  CLAUDE.md       │     │
│     ▼                │                    │  AGENTS.md       │     │
│  ┌──────────┐        │                    │  README.md       │     │
│  │ feedback │        │                    └──────────────────┘     │
│  │(signals: │        │                                             │
│  │promote/  │        │                                             │
│  │eliminate │        │                                             │
│  │/refine)  │        │                                             │
│  └──────────┘        │                                             │
│                      │                                             │
├──────────────────────┼──────────────────────────────────────────────┤
│                      │                                             │
│  OUTPUT              ▼                                             │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  artifacts.boot     artifacts.docs.*  artifacts.changelog  │    │
│  │  artifacts.system.index  (+ 40+ config/workflow outputs)   │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  SURFACE (CLI / MCP Server / Watcher) → all verbs hit Gate         │
│  pulse → cursor_store + loop_state  |  loop → flow + feedback      │
└─────────────────────────────────────────────────────────────────────┘
```

## Mermaid version

```mermaid
flowchart TB
    subgraph INPUT["INPUT — Sources"]
        RAW[".textus/data/raw/\nExternal material\n(urls, files, assets)"]
        KNOWLEDGE[".textus/data/knowledge/\nHuman-maintained truth\n(boot, loop nodes, project)"]
        SCRATCH[".textus/data/scratchpad/\nAgent working memory"]
        PROPOSALS[".textus/data/proposals/\nSuggested changes\nawaiting human accept"]
    end

    subgraph CORE["CORE — Protocol Layer"]
        GATE["Gate\nauth → resolve → validate"]
        ESTORE["EntryStore\nformat parse + DB index\n+ FTS + audit log"]
        FS["File System\n.markdown / .json / .yaml"]
        DB[("SQLite\n· entries (FTS5)\n· audit_events\n· workflow_events\n· cursors\n· loop_positions\n· link_edges")]
    end

    subgraph LOOP["LOOP — Knowledge Pipeline"]
        direction LR
        I["intent"]
        CR["constraint.repo"]
        CP["constraint.protocol"]
        JE["judgment.engineering"]
        JA["judgment.agent-behavior"]
        EV["evidence"]
        EX["execution"]
        FB["feedback"]
        I --> CR --> CP --> JE --> JA --> EV --> EX --> FB --> I
    end

    subgraph EVENTS["EVENT BUS — Workflow Engine"]
        MAT["Materialize\n(auto, on every write)"]
        WREG["Workflow Registry\nmatches key → workflow"]
        RUNNER["Workflow::Runner\nexecutes steps"]
        PUB["Publisher\ntemplate → publish_to"]
    end

    subgraph OUTPUT["OUTPUT — Artifacts"]
        BOOT["artifacts.boot\norientation contract"]
        DOCS["artifacts.docs.*\nreference docs"]
        CHANGELOG["artifacts.changelog"]
        SYSTEM["artifacts.system.index"]
        CLAUDE["CLAUDE.md / AGENTS.md\n(published via template)"]
    end

    subgraph SURFACE["SURFACE — Interfaces"]
        CLI["CLI\n(textus get/put/list/…)"]
        MCP["MCP Server\n(agent tools via stdio)"]
        WATCH["Watcher\n(fs events → drain)"]
    end

    PROPOSALS -- "accept/reject" --> GATE
    KNOWLEDGE -- "put (human)" --> GATE
    SCRATCH -- "put (agent)" --> GATE
    RAW -- "ingest" --> GATE
    GATE --> ESTORE
    ESTORE <--> FS
    ESTORE --> DB
    ESTORE -- "entry.written\nentry.deleted\nentry.moved" --> MAT
    MAT --> WREG
    WREG --> RUNNER
    RUNNER -- "read knowledge.loop.*" --> ESTORE
    RUNNER -- "read knowledge.boot" --> ESTORE
    BOOT_REFRESH["boot_refresh workflow\n(watches knowledge.boot)"] -. "triggers" -.-> PRODUCE["Produce::Engine.converge"]
    RUNNER --> BOOT
    RUNNER --> DOCS
    RUNNER --> CHANGELOG
    RUNNER --> SYSTEM
    RUNNER --> PUB
    PUB --> CLAUDE
    PULSE["pulse verb\n(delta + loop_state)"]
    LOOP_VERB["loop verb\n(flow + feedback signals)"]
    DB --> PULSE
    DB --> LOOP_VERB
    LOOP_VERB --> FB
    CLI --> GATE
    MCP --> GATE
    WATCH --> MAT
```

## Key flows

- **Write path:** `put` → Gate (auth/resolve/validate) → EntryStore (file + DB index + audit + FTS) → Materialize → Workflow Runner → reads knowledge → produces artifacts → Publisher → CLAUDE.md/AGENTS.md
- **Read path:** `get` → Gate → Manifest resolver (key→path) → FileSystem (read bytes) → Format parser (md/json/yaml → envelope) → response
- **Loop cycle:** intent → constraint → judgment → evidence → execution → feedback → (repeat); `pulse` returns position, `loop` returns flow + feedback signals
- **Boot refresh:** writing `knowledge.boot` → Materialize → boot_refresh workflow → triggers produce on `artifacts.boot` → boot workflow regenerates
