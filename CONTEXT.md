# Textus Context

Textus is a coordination space where humans, agents, and automation write to different lanes under explicit capability rules. This glossary defines the canonical language used when discussing architecture and seams.

## Language

**Lane**:
A write-authority partition that groups entries by trust and ownership intent.
_Avoid_: Zone, bucket

**Role**:
A named writer identity that holds a capability set used to authorize transitions.
_Avoid_: Actor type, user class

**Capability**:
A verb-level authority token that allows a role to perform a class of writes.
_Avoid_: Permission flag, access bit

**Proposal Trust Path**:
The transition path where a proposal is queued by `propose` and promoted to canon only by `author`.
_Avoid_: Fast path, direct write

**VerbDispatch Module**:
The module that resolves a verb token into one dispatched operation through a single interface for all adapters.
_Avoid_: Router service, command boundary

**Invocation**:
The per-request pair of command intent and call context that crosses the dispatch seam.
_Avoid_: Request bag, context blob

**Infrastructure Module**:
The unified dependency module that replaces the old container seam and supplies collaborators to dispatch and use-case modules.
_Avoid_: Container bag, dependency blob

**Dependency Adoption Gate**:
The rule module that every new external dependency must pass before adoption, based on seam clarity, interface depth, and exit cost.
_Avoid_: Gem trial, convenience install

**Dependency Adapter Module**:
An adapter module that exposes the published interface textus depends on while hiding dependency-specific implementation details.
_Avoid_: Direct gem call, vendor lock-in seam

**Runtime Store**:
The runtime data directory under `.textus/` that holds transient and persistent operational state. Subdirectories: `db/` (SQLite database — backup target), `log/` (append-only logs — logrotate target), `run/` (ephemeral scratch — safe to delete), `track/` (sentinel metadata — durable but derivable).
_Avoid_: State dir, run dir, .state

**Audit Table**:
The `audit_events` SQLite table recording every write operation (seq, ts, role, verb, key, etag_before, etag_after). Serves as the system's unified change log for `pulse`, `audit`, and cursor advancement.
_Avoid_: Audit log, audit file, journal

**Workflow Table**:
The `workflow_events` SQLite table recording workflow-scheduled events (id, event_type, workflow_type, key, payload, state, scheduled_at, retry_count, error). Consumed by `Events::Consumer` during `drain`.
_Avoid_: Job queue, event store

**Runtime Cursor**:
The `cursors` SQLite table storing per-role position in the audit stream (role, seq, updated_at). Written atomically by `pulse`. Read at session start to resume from last position.
_Avoid_: Cursor file, checkpoint file, seq file

**Loop State**:
The current knowledge pipeline phase (intent, constraint, judgment, evidence, execution, feedback) returned in `pulse` output as an advisory label. Not a state machine — agents read it to decide what to work on.
_Avoid_: Loop driver, pipeline state, workflow phase

**Workflow Consumer**:
The module that executes a single workflow event row and handles its lifecycle (success completion, retry with backoff, dead-letter failure). Shared between the drain loop and the watcher to avoid duplicate retry logic.
_Avoid_: Job runner, event handler

**Workflow EventEmitter**:
The module that observes store mutations and dispatches workflow events to the Workflow Queue. Replaces in-pipeline event emission so the store engine does not need to know about the workflow registry.
_Avoid_: Event hook, pipeline step, workflow enqueuer

**QueryContext**:
A per-invocation value exposing only read-side operations (read, resolve, list, exists?, mentry_for) plus read-only container metadata (manifest, schemas, layout, link_store, entry_index). Injected by Gate into read-category handlers. Separates query from command at the seam — a read handler cannot accidentally write.
_Avoid_: Context, god object, handler context bag

**CommandContext**:
A per-invocation value extending QueryContext with write-side operations (put, delete, move) and infrastructure access (audit_log, cursor_store, workflow_queue, file_system, workflows, workflow_registry). Injected by Gate into write- and maintenance-category handlers. Satisfies CQS: the caller's verb category determines which context type they see.
_Avoid_: Context, god object, handler context bag
