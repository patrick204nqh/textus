---
name: '0122-proposal-diff-preview'
uid: ''
refines: knowledge.architecture.conventions
---

# ADR-0122: Proposal diff, preview, and rejection feedback

## Status

Accepted

## Date

2026-07-01

## Context

The propose→accept→reject loop (ADR 0035, 0072) is textus's core human-in-the-loop trust path. An agent proposes a change by writing to the proposals lane; a human runs `textus accept` or `textus reject` to decide. The human has no way to:

1. **See what changed** — the proposal's content vs the current knowledge entry. No built-in diff between proposed and existing.
2. **Preview the result** — promote is all-or-nothing, no dry-run.
3. **Tell the agent why** — rejection deletes the proposal silently. The agent on the next `pulse` sees the proposal disappear from `pending_review` but has no way to learn why.

Without these, the human-in-the-loop operates blind. Trust is asserted, not verified.

## Decision

Add three capabilities to the propose→accept→reject loop:

### 1. Structural diff (`diff` verb)

A new `diff` verb compares a proposal's content against its target knowledge entry:

```
textus diff proposals.decisions.foo
→ {
    "body_diff": [{ op: "equal", value: "..." }, { op: "replace", value: "..." }],
    "meta_diff": { "added": { "status": "accepted" }, "removed": {}, "changed": {} },
    "schema_diff": { "field_added": ["reviewer"], "field_removed": [] }
  }
```

Three levels, all returned in one response:

- **Body diff** — line-level text diff (body-only for markdown, content-only for json/yaml) using a simple Myers- or patience-diff on lines.
- **Meta diff** — structural diff of frontmatter keys (added, removed, changed values).
- **Schema diff** — compares the proposal's `_meta` against the target entry's declared schema (field added/removed/type-changed).

The diff verb is surfaced to both CLI and MCP — agents can inspect their own proposal's diff before asking for human review, catching mistakes early.

### 2. Accept with preview (`accept --dry-run`)

`accept` gains an optional `--dry-run` flag:

```
textus accept proposals.decisions.foo --dry-run
→ {
    "dry_run": true,
    "proposal_key": "proposals.decisions.foo",
    "target_key": "knowledge.decisions.foo",
    "action": "put",
    "diff": { ... }  // same shape as `diff` verb response
  }
```

Dry-run returns the diff the human would apply, without promoting. No audit entry is written. The human can then run `textus accept proposals.decisions.foo` without `--dry-run` to commit.

### 3. Rejection with reason (`reject --reason`)

`reject` gains an optional `--reason` flag:

```
textus reject proposals.decisions.foo --reason="wrong route, try knowledge.runbooks"
```

The rejection is logged in the audit log with the reason. The `RejectProposal` handler emits `:proposal_rejected` with the reason attached. The proposing agent sees the rejection in `pulse().changed` (the proposal key leaves `pending_review` and a rejection note is surfaced).

Optionally, a rejection also writes a note to the agent's scratchpad (e.g. `scratchpad.notes.rejected-reason.<key>`) so the reason survives process restarts.

## Consequences

- **Positive:** Humans review with confidence — diff, preview, then accept.
- **Positive:** Agents self-check proposals via `diff` before submitting.
- **Positive:** Rejection with reason closes the feedback loop — agents can learn from rejections.
- **Neutral:** `diff` verb adds one new verb to the registry; `accept --dry-run` adds one optional arg to the existing `accept` contract.
- **Negative:** Diff implementation must handle all four format types (markdown, json, yaml, text). Json/yaml have no line-level body diff semantic; their diff is structural (key-level).
- **Negative:** Rejection reasons stored in the audit log are private to the store owner — textus does not sync or propagate them.
- **Cost:** The diff engine is new code, not a library dependency. A pure Ruby diff (Myers) is ~100 LOC; structural meta/schema diff is another ~80 LOC.

## Alternatives Considered

### Delegate diff to an external tool (git diff, difftastic)
Rejected. textus proposals are transient queue entries not tracked in git — there is no git commit to diff against. Reading the current knowledge file from the store and diffing against the proposal body in memory is the only honest comparison. textus owns the diff.

### Show diff in pulse instead of a separate verb
Rejected. `pulse` returns a delta summary; showing full diffs for every pending proposal would bloat the pulse response. A dedicated `diff` verb keeps the protocol layered — `pulse` for discovery, `diff` for inspection.

### Mandatory rejection reason
Rejected. The human knows best whether a reason is valuable. Making it mandatory would encourage throwaway reasons, degrading signal quality.

### Rejection reason written to proposals lane
Rejected. The proposal entry is deleted on reject. Writing a "reason" entry to the proposals lane conflates the queue with a feedback channel. The audit log and optional scratchpad note are sufficient.
