# Agent Session Protocol

Every agent session follows INPUT → LOOP → OUTPUT in that order.

## Rationale

Without a strict protocol, agents skip nodes, waste context on dead paths,
or produce output that hasn't been validated against constraints. This entry
codifies the deterministic session flow.

## INPUT

On session start, the agent reads exactly these sources in order:

1. `AGENTS.md` (rendered from `textus drain`) — contains the command chain
2. `textus session_open --as=agent` — returns boot context with lanes, verbs, loop
3. `textus get knowledge.loop.constraint.protocol.0014-data-flow` — data flow
4. `textus get knowledge.loop.judgment.engineering.0009-conventions` — conventions

## LOOP

Before acting, the agent checks the relevant loop node:

| Action | Check |
|--------|-------|
| Write code or change architecture | `knowledge.loop.constraint.repo.*` |
| Touch protocol or surface | `knowledge.loop.constraint.protocol.*` |
| Use or extend a pattern | `knowledge.loop.judgment.engineering.*` |
| Make a permanent decision | `knowledge.loop.evidence.*` (ADRs) |
| Follow a procedure | `knowledge.loop.execution.*` |
| End session | `knowledge.loop.feedback.*` |

Skipped nodes must be documented with a reason in session notes.

## OUTPUT

On session end, the agent:

1. Calls `session_close <id> --nodes_checked="[intent,constraint.repo,...]"` — includes which loop nodes were checked
2. Reads the auto-generated feedback and compares against `knowledge.loop.feedback.*`
3. Runs `textus drain --as=automation` to re-publish artifacts (AGENTS.md, boot, docs)
4. If a pattern repeated 3+ times: proposes to `knowledge.loop.judgment.engineering.*`
5. If the session contradicts an existing ADR: proposes to `knowledge.loop.evidence.*`

## Enforcement

The doctor workflow checks for sessions that closed without checking
`constraint.repo` but authored new entries. This is a warning, not a
block — the agent may have a valid reason to skip.
