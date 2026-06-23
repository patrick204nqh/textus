---
uid: d0c751422eaf634f
---
# Engineering Skills Process Contract

> **Reference** · for maintainers and AFK agents · **read when** running `to-prd`, `to-issues`, `triage`, or `qa`
> **SSoT for** issue-tracker selection, request-surface policy, and domain-doc consumption rules for engineering skills · **reviewed** 2026-06

This repository uses one explicit process contract so humans, agents, and automation coordinate through the same queue and the same vocabulary.

## Issue tracker

- **Tracker:** GitHub Issues for `patrick204nqh/textus`.
- **Expected interface:** `gh` CLI operations (`gh issue create`, `gh issue view`, `gh issue edit`, comments and labels).
- **Process source of truth:** issue state and labels in GitHub, not ad-hoc chat state.

## Request surface policy

- **External PRs are not a request intake surface by default.**
- Engineering skills should treat issues as the canonical intake channel unless a maintainer explicitly opts into PR triage.
- If PR triage is later enabled, this document is the single place to update that policy.

## Canonical triage labels

Engineering skills must use this canonical five-label vocabulary for issue state transitions:

- `needs-triage` — newly created or newly changed work that needs maintainer evaluation.
- `needs-info` — waiting on reporter input before a reliable plan can be produced.
- `ready-for-agent` — fully specified and AFK-executable by an implementation agent.
- `ready-for-human` — requires human implementation, decision, or merge action.
- `wontfix` — intentionally not actioned.

Notes:

- Use exact label names to avoid duplicate state taxonomies.
- `ready-for-agent` is the default output state for PRD/to-issues artifacts intended for AFK execution.

## Domain-doc consumption rules

Before writing PRDs, issue breakdowns, or implementation plans, engineering skills should read the repo's canon in this order:

1. `docs/architecture/README.md` for implementation orientation.
2. `SPEC.md` for the protocol contract (`textus/4`).
3. `docs/architecture/decisions/README.md` plus relevant ADRs for the touched area.
4. `docs/reference/lanes.md` and `docs/reference/authority.md` for lane, role, and capability semantics.

Planning artifacts should preserve textus vocabulary (lanes, capabilities, proposals queue, canon/workspace/machine/queue/raw, ingest, converge) and avoid introducing competing terms for the same concepts.

## Maintenance

- Keep this contract minimal and high-signal.
- Update this file whenever issue-tracker or request-surface policy changes.
- Treat this page as the durable repo-local process memory that skills should follow across sessions.

## Operational check — ready-for-agent lifecycle proof

Use this rerunnable check to confirm issue workflow compatibility at the highest seam (tracker state + consumable issue contract):

1. Create a structured issue with PRD-style sections (Problem Statement, Solution, User Stories, Implementation Decisions, Testing Decisions, Out of Scope, Further Notes).
2. Apply `needs-triage` at creation.
3. Transition the issue by removing `needs-triage` and adding `ready-for-agent` when the body is fully specified.
4. Verify only canonical labels were used.
5. Verify the issue can be consumed without chat context.

Reference proof artifact: `https://github.com/patrick204nqh/textus/issues/242`.
