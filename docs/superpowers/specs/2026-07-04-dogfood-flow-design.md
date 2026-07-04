# Dogfood Flow: Session Lifecycle, Feedback Criteria, Execution Zone

**Date:** 2026-07-04  
**Status:** Draft  
**Driver:** Dogfood audit findings — session verbs hidden, proposals lane unused, feedback node misused, execution zone flat

## Problem

The dogfood audit revealed four structural issues in the self-development `.textus/` store:

1. **Session verbs hidden** — `session_open`/`session_close` are registered with MCP surface but deliberately omitted from the agent boot catalog. Agents can't discover them naturally.

2. **Proposals lane unused** — `proposals.*` has never held a real entry. The propose→accept gate adds ceremony without use. The same flow works with agents writing to scratchpad and humans manually promoting.

3. **Feedback node misused** — `knowledge.loop.feedback` currently holds agent-authored feedback records (SOLID audit, workflow triggers). The feedback node should define *criteria* for when to generate feedback/proposals, not archive past entries. Actual feedback records belong in scratchpad (ephemeral, agent-owned).

4. **Execution zone flat** — all entries share a single `runbook` schema with `name` + `description`. Different execution types (runbooks, checklists, procedures) need distinct schemas.

## Design

### 1. Surface session verbs

Remove `session` from `BOOT_GUARD_INTENTIONALLY_OMITTED` in `spec/conformance/boot/cli_verbs_spec.rb`. The verbs are already registered with MCP surface — they'll appear in the boot catalog automatically.

### 2. Remove proposals lane, fold into scratchpad

The proposals lane is removed. The `propose`/`accept`/`reject` verbs are repurposed to target `scratchpad.proposals.*` instead of `proposals.*`.

**Manifest changes:**
- Remove `proposals:` block from `manifest.yaml`
- Remove `scratchpad.notes` and `scratchpad.scripts` entries (unused)
- Keep `scratchpad.sessions` (active) and add `scratchpad.proposals`

**File changes:**
- Delete `.textus/data/proposals/` directory
- `propose` verb writes to `scratchpad.proposals.*` instead of `proposals.*`
- `accept` verb promotes from `scratchpad.proposals.*` to `knowledge.*`
- `reject` verb discards from `scratchpad.proposals.*`

**Capabilities:**
- `propose` stays as a capability that maps to `scratchpad` lane kind
- `author` stays human-only on `knowledge`

**Session feedback flow:**
- `session_close` writes feedback to `scratchpad.sessions.<id>.feedback` (already implemented)
- No auto-propose — feedback stays scratchpad-native
- Human reviews feedback and decides what to promote

### 3. Feedback node: criteria, not archive

Clear the existing `knowledge.loop.feedback` entries:
- Move `0001-solid-audit.md` to `knowledge.loop.judgment.engineering.0015-solid-audit`
- Delete `0002-session-lifecycle.md` (workflow trigger, no permanent value)

Write 2-3 criteria entries defining when the agent should generate feedback or propose upstream:

| Key | Purpose |
|-----|---------|
| `knowledge.loop.feedback.0001-protocol-gap` | When the agent discovers behavior the protocol doesn't cover → propose to constraint.protocol |
| `knowledge.loop.feedback.0002-repetitive-task` | When the agent performs the same manual task 3+ times → propose a new execution entry |
| `knowledge.loop.feedback.0003-intent-drift` | When observed behavior diverges from stated intent → propose intent amendment |

Each entry uses the `loop-feedback` schema with `node` (which loop node to target), `confidence` (threshold), `signal` (trigger), `summary` (criteria description).

### 4. Execution zone: per-type schemas and sub-families

Split the flat `knowledge.loop.execution` family into typed sub-families:

**Manifest entries:**
```yaml
- key: knowledge.loop.execution.runbook
  naming: sequential
  schema: execution/runbook
- key: knowledge.loop.execution.checklist
  naming: sequential
  schema: execution/checklist
- key: knowledge.loop.execution.procedure
  naming: sequential
  schema: execution/procedure
```

**Schema files at `schemas/execution/`:**
- `runbook.yaml` — `name` (string), `description` (string), `steps` (array of strings)
- `checklist.yaml` — `name` (string), `description` (string), `items` (array of `{check: boolean, description: string}`)
- `procedure.yaml` — `name` (string), `description` (string), `inputs` (array of strings), `outputs` (array of strings), `steps` (array of strings)

**File moves:**
- `0001-release.md`, `0002-adr.md`, `0003-quickstart.md` move to `knowledge/loop/execution/runbook/`
- New entries under `knowledge/loop/execution/procedure/`:
  - `0001-doctor.md` — how to read doctor workflow reports
  - `0002-session.md` — the integrated session lifecycle
  - `0003-deploy.md` — how to cut a release

**Boot workflow update:**
- `read_family` lambda in `boot.rb` continues to work — it enumerates all `knowledge.loop.execution.*` prefixes and collects entries across sub-families
- Orientation template groups runbooks by type using schema_ref

### 5. Update orientation template

- Remove propose recipe from `agent_protocol.recipes`
- Update write authority table (no more proposals lane)
- Add procedures section alongside runbooks
- Reference feedback criteria

## Checklist

- [ ] Surface session verbs
- [ ] Remove proposals lane from manifest
- [ ] Repurpose propose/accept/reject to scratchpad.proposals
- [ ] Delete proposals data directory
- [ ] Remove scratchpad.notes and scratchpad.scripts from manifest
- [ ] Add scratchpad.proposals to manifest
- [ ] Move solid-audit to judgment.engineering
- [ ] Delete trigger feedback entry
- [ ] Write 2-3 feedback criteria entries
- [ ] Create schemas/execution/ directory with 3 schema files
- [ ] Split manifest execution entry into 3 sub-families
- [ ] Move existing runbooks to runbook/ subdirectory
- [ ] Add 3 procedure entries
- [ ] Update boot.rb read logic
- [ ] Update orientation template
- [ ] Update conformance tests
- [ ] Regenerate CLAUDE.md/AGENTS.md via drain
- [ ] Verify test suite passes

## Open Questions

- None
