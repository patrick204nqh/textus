---
node: execution
confidence: medium
signal: repetition
summary: When the agent performs the same manual task 3+ times across sessions, propose a new execution entry codifying it.
---

If the same multi-step procedure is performed manually across three or more
separate sessions, the agent should propose a runbook, checklist, or procedure
entry under knowledge.loop.execution.

Threshold: 3 occurrences of the same or substantially similar task flow.
