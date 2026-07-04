---
name: session
description: Begin and end agent sessions, review feedback, propose changes to canon.
---
## session

**Begin a session:**

```sh
textus session_open --as=agent
```
Returns `{session_id, status: "active", workspace}`. The workspace has `notes/`, `scripts/`, `output/` subdirectories.

**Work during session:**

Use the workspace for temporary files, notes, and scripts. Write durable notes to `scratchpad.sessions.<id>.notes.*`.

**End a session:**

```sh
textus session_close <id> --as=agent
```

This seals the session and writes a feedback entry to `scratchpad.sessions.<id>.feedback` with duration, timestamps, and session metadata.

**Review feedback:**

```sh
textus get scratchpad.sessions.<id>.feedback
```

Check the feedback against criteria in `knowledge.loop.feedback.*` to decide if anything warrants proposing to canon.

**Propose upstream changes:**

```sh
textus propose scratchpad.proposals.<topic> \
  --target=knowledge.<node>.<path> \
  --body="..." --as=agent
```

Human reviews and accepts:

```sh
textus accept scratchpad.proposals.<topic> --as=human
```
