# Operating inside the Loop

This repo's `knowledge.*` zones are the Loop model, exhaustively: `intent`
(why), `constraint.repo`/`constraint.protocol` (hard limits — engineering
principles vs. wire contract), `judgment.engineering`/`judgment.agent-behavior`
(principles — how to build vs. how to operate), `evidence` (logged
decisions), `execution` (runbooks), `feedback` (evaluation against intent).
Nothing else in `knowledge.*` exists — anything that looks like a separate
concern is either one of these six in disguise, or a workflow-rendered
extraction over them (README.md, SPEC.md, CLAUDE.md/AGENTS.md).

Default flow (Downward): intent exists -> check constraint -> apply/consult
judgment -> record evidence -> produce execution.

Per-node behavior:

- **Touching intent** — human-authored only. Your job is to *surface* drift,
  never self-author a goal.
- **Hit a hard limit** — check `knowledge.loop.constraint.repo` (engineering
  rules) or `knowledge.loop.constraint.protocol` (wire contract) before
  improvising.
- **A judgment call constraint doesn't cover** — consult
  `knowledge.loop.judgment.engineering`. If you're repeating the same judgment
  call, that's the Upward flow: propose compressing it into a new pattern
  entry there.
- **Logging a one-off choice** — propose an entry under `knowledge.evidence`.
- **Producing a runnable procedure** — `knowledge.execution`.
- **End of a session/task** — Feedback: did this serve `knowledge.intent`?
  If not, write a `knowledge.feedback` entry and propose the upstream
  amendment. This is the Reverse flow — the one edge that makes this a
  growth system instead of a pipeline. Silent drift is a structural
  failure, not a style choice. Feedback/Reverse are judgment-driven in
  this version, not mechanically enforced — don't wait for a check to
  tell you to write one.
- **Scratchpad content** — `.textus/data/scratchpad/` is agent-owned working
  memory, not canon. Content that repeats or proves durable across
  sessions -> propose it into the matching node above. Content that
  doesn't survive past the session it was written in is fine to leave or
  delete.
