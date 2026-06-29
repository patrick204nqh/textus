---
uid: c5d89e9a8a8e4f0d
sources:
- raw.2026.06.29.url-principles-design-feed
- raw.2026.06.29.url-golden-rules-shneiderman
- raw.2026.06.29.url-karpathy-software-2
- raw.2026.06.29.url-addy-loop-engineering
---
# Design Invariants (Locked)

Philosophy, principles, and architectural invariants for textus.

Status: LOCKED
Locked on: 2026-06-29
Modification policy: Never modify directly. If reality diverges, write a new versioned invariant document and explicitly supersede this file.

## Purpose

These invariants exist to let the architecture evolve quickly without losing identity.
They lock the non-negotiables so teams can move fast everywhere else.

## North Star

textus exists to empower humans by coordinating agents and automation around durable context/knowledge.

Target outcome:
- humans spend more time on decisions, direction, and design;
- agents spend more time on creative synthesis and proposal work;
- automation handles accurate, repeatable, fixed-step operations;
- repetitive manual work is reduced without creating AI slop.

## Strength Model

- Human is strongest at intent, judgment, trade-offs, and final authority.
- Agent is strongest at creative generation, synthesis, drafting, and exploration.
- Automation is strongest at deterministic, recurring, and precision execution.

Architecture must route work to the actor that is naturally strongest at it.

## Golden Rules

1. Human-centric by default.
   Every feature must reduce unnecessary manual burden while preserving human control over important decisions.

2. Right work to the right actor.
   Creative/synthesis tasks go to agents. Repeatable/fixed-step tasks go to automation. Direction and acceptance stay with humans.

3. Canon is human-owned.
   Authoritative truth (`canon`) is never silently machine-promoted. Promotion always crosses explicit review (`propose -> accept`).

4. Agent proposes, human decides.
   Agents can draft, summarize, and propose at high speed; they do not self-authorize canonical change.

5. Automation runs the boring loops.
   Fetching feeds, scheduled materialization, sweeps, and other deterministic loops belong to automation, not ad hoc agent prompting.

6. Avoid AI slop.
   Prefer structured outputs, traceable provenance, and explicit constraints over verbose ungrounded generation.

7. Protocol before convenience.
   Keep `textus/4` deterministic and explicit. Do not introduce hidden behavior that makes results depend on who or what called it.

8. No hidden side effects on read.
   Reads return state and freshness only. Convergence is explicit (`drain`, jobs, workflows).

9. Provenance is mandatory.
   External inspiration/data should be referenceable from raw intake; canonical docs remain concise and goal/rule-focused.

10. One clear path for recurring operations.
    If a task repeats, encode it as workflow/schedule/automation. Do not normalize manual repeat prompting.

11. Keep seams explicit.
    Evolve via contracts, actions, rules, workflows, and ports. Avoid cross-layer shortcuts and dual paths.

12. Quality over volume.
    Fewer accurate artifacts beat many low-signal artifacts. Ship only what improves shared understanding and action.

## Evolution Rules

When changing textus, these rules are mandatory:

1. Preserve the protocol contract unless a deliberate protocol revision is introduced.
2. Keep lane authority derivation capability x kind; do not add ad hoc per-entry write policy.
3. Keep role boundaries sharp (human decision, agent creativity, automation repetition).
4. Never introduce hidden side effects on read paths.
5. Keep deterministic output semantics and explicit freshness reporting.
6. Prefer explicit seams over special-case branching.

## Decision Test

A proposed change is valid only if all answers are "yes":

1. Does it preserve protocol determinism and envelope stability?
2. Does it keep trust transitions explicit and auditable?
3. Does it route work to the actor naturally strongest at it?
4. Does it reduce manual repetition without reducing human agency?
5. Does it improve evolvability without weakening authority boundaries?

If any answer is "no", redesign the change.
