# textus — Agent Protocol

Every session follows **INPUT → LOOP → OUTPUT**. Execute these commands in order.

## INPUT (session start — run these 3 commands)

1. `textus session open --as=agent`
   → Returns `{session_id, status, boot}` — boot gives lanes, verbs, loop structure.

2. `textus get knowledge.loop.constraint.protocol.0014-data-flow`
   → Read the data flow diagram. Understand write → EventEmitter → Queue → Consumer flow.

3. `textus get knowledge.loop.judgment.engineering.0009-conventions`
   → Read folder structure, naming conventions, and training instructions.

## LOOP (during the session — check nodes before acting)

| If you are about to... | Check this node first | Command |
|---|---|---|
| Write code or change architecture | `constraint.repo` | `textus list --prefix=knowledge.loop.constraint.repo` |
| Touch protocol or surface | `constraint.protocol` | `textus list --prefix=knowledge.loop.constraint.protocol` |
| Use an existing pattern | `judgment.engineering` | `textus list --prefix=knowledge.loop.judgment.engineering` |
| Make a permanent decision | `evidence` (ADRs) | `textus get artifacts.decisions.log` |
| Follow a procedure | `execution` | `textus list --prefix=knowledge.loop.execution` |
| End a session | `feedback` | `textus get knowledge.loop.feedback` |

If you skip a node, record why in session notes.

## OUTPUT (session end — run these 3 commands)

1. `textus session close <id> --as=agent`
   → Pass `nodes_checked` listing which loop nodes you actually checked.

2. `textus get scratchpad.sessions.<id>.feedback`
   → Read the auto-generated feedback. Compare against `knowledge.loop.feedback.*`.

3. `textus drain --as=automation`
   → Re-publish artifacts (updates published docs, boot).

---

> **Context store:** `.textus/` (textus, protocol textus/4).
> **MCP:** `.mcp.json` wires the `textus` server.
> **Write authority:** knowledge (human) scratchpad (human, agent) artifacts (automation) raw (human, agent, automation) > **Loop:** intent → constraint.repo → constraint.protocol → judgment.engineering → judgment.agent-behavior → evidence → execution → adoption

A coordination space for humans, AI, and automation — durable, multi-writer repo memory that survives the session, the model, and the vendor.

## Developer Commands
- **test**: `bundle exec rspec`
- **lint**: `bundle exec rubocop`
- **lint-fix**: `bundle exec rubocop -A`
- **setup**: `bundle install`
- **help**: `bundle exec exe/textus --help`
- **drain**: `bundle exec exe/textus drain --as=automation`

## Runbooks
- **doctor** — Read and act on doctor workflow reports to keep the store healthy.
- **session** — Begin and end agent sessions, review feedback, propose changes to canon.
- **deploy** — Cut a textus release — bump version, update lockfile, tag, publish.
- **release** — Cut a textus release — bump the version, regenerate Gemfile.lock, then tag via PR.
- **adr** — Add an Architecture Decision Record for a load-bearing decision.
- **quickstart** — Four-command demo of the role-gated propose→accept flow, plus full store walkthrough and protocol reference.

## Session Lifecycle

- **begin** — `textus session open` creates a workspace.
- **end** — `textus session close <id>` seals the session with feedback.
- **feedback → canon** — propose feedback to `knowledge.loop.feedback` to close the loop.

## Docs

Read the map with `textus get artifacts.docs.readme`; decision log: `textus get artifacts.decisions.log`.

<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
