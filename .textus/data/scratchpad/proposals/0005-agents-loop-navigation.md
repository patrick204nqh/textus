---
uid: a69eec3aa2c5cb62
---
## Proposal: Update AGENTS.md with loop navigation instructions

Target: AGENTS.md
Action: put

Insert after the first 3 INPUT commands in AGENTS.md:

4. `textus node status`
   → Returns current loop node, topic, item, and full node stack.
   Every session starts seeded at the first loop node from the manifest.

And update the LOOP section to include the navigation ceremony:

| Navigate the loop | `node` | `textus node enter <path>` |

Add a note after the LOOP table:

> **Navigate the loop:** Use `textus node enter <path>` to move between nodes
> (e.g. `textus node enter evidence`). `textus node back` pops one level,
> `textus node exit` returns to the previous node, `textus node switch <path>`
> exits current and enters target in one verb. Check `textus node status`
> anytime to see where you are.
