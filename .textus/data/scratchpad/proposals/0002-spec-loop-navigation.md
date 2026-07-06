---
uid: 8fef718cd3304506
---
## Proposal: Write spec file

Target: docs/superpowers/specs/2026-07-06-loop-navigation-ceremony.md

## Spec: Loop Navigation Ceremony

### Problem

The session has no concept of where the agent is in the loop. Three gaps:
1. No state machine — session has no node stack, no current-node tracking
2. No ceremony — moving between nodes is implicit, no hooks
3. No human visibility — session status returns nothing about loop position

### Design

#### 1. Session gains a node_stack

Protocol::Session gets a node_stack — array of NodeEntry value objects.

NodeEntry = Data.define(:path, :entered_at, :exited_at)

path is an array: [:constraint, :protocol, "0014-data-flow"]
Node is first segment, topic second, item third. Unbounded depth.

#### 2. Session.open seeds the stack

Every session starts in intent.

#### 3. Verbs

| Verb | Action | Example |
|------|--------|---------|
| node enter PATH | Push to stack, fire hooks | node enter evidence |
| node back | Pop one segment | node back |
| node exit | Pop to previous node | node exit |
| node switch PATH | Exit + enter in one verb | node switch constraint |
| session status | Display stack + timing | session status |

Path is space-separated segments.

enter ceremony:
1. Validate first segment is known node
2. Check transition rules
3. Topic/item within same node: lightweight push (no hooks)
4. Node change: fire on_exit, push, fire on_enter
5. Write audit event

back: pop one segment, if node changed fire on_enter.
exit: pop to previous node boundary, fire on_enter.
switch: exit + enter in one verb, single audit event.

#### 4. Transition rules

Forward any: allowed. Backward to intent/evidence: allowed. Backward to other: denied.

#### 5. Entry/Exit hooks

on_node_enter(path) — audit event, update status
on_node_exit(path) — audit event, check items visited

Only node boundaries fire hooks. Topic/item changes within a node are silent.

#### 6. Session status display

Shows current node/topic/item, full stack, and per-node timing.

#### 7. Session close serializes stack

node_stack written to session scratchpad on close.

#### 8. Relationship to Loop Runner

Runner: cross-session position (cursor_store).
Node stack: within-session trail.
node enter also advances Runner position.

### Files

lib/textus/protocol/session.rb — add node_stack, methods
lib/textus/protocol/session/node_entry.rb — new
lib/textus/loop/transitions.rb — new
lib/textus/loop/hooks.rb — new
lib/textus/surface/cli/verb/node_enter.rb — new
lib/textus/surface/cli/verb/node_exit.rb — new
lib/textus/surface/cli/verb/node_back.rb — new
lib/textus/surface/cli/verb/node_switch.rb — new
lib/textus/surface/cli/group/node.rb — new
lib/textus/surface/cli/verb/session_status.rb — enhanced

~300 lines total.

### References

Loop State Design (2026-07-04) — evaluation-focused, complementary.
Session Deepening (2026-07-04) — Context/Bridge split.
ADR-0130 section 8 — called for loop navigation.
