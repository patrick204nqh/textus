# ADR 0029 — Concept vocabulary: coordination space → lanes → zones

**Date:** 2026-05-30
**Status:** Accepted
**Refines:** [ADR 0028](./0028-coordination-planes.md) (which coined "coordination space" and the "three planes")
**Updated by:** [ADR 0030](./0030-capability-based-roles.md) — the role model is now **capability-based**: roles declare a `can:` set drawn from a closed four-verb vocabulary (`propose`, `accept`, `fetch`, `build`), and `automation` is the single umbrella role replacing the former `runner` and `builder`. "role-kind" in the table below is superseded by per-role capabilities; the spec/code/CLI term is now **role** + **capability** rather than **role-kind**.

## Context

textus accreted four spatial metaphors for the same idea: `zone` (the technical term,
579 uses across SPEC/manifest/CLI/code), `lane`/`lanes` (README prose plus the "Lanes"
logo and `DESIGN.md`), `fabric`/`durable fabric` (the Latin etymology, *textus* = woven
cloth), and `coordination space` (introduced only in ADR 0028). A reader meets
*space / lanes / fabric / zones / planes* and cannot tell which is load-bearing. The
brand is committed to "Lanes"; the code is committed to "zones"; the README headline
drifts between "shared workspace" and "durable fabric."

## Decision

One canon, layered by audience. Each concept has exactly one term per audience, and the
bridge between the human term and the technical term is stated once.

| Layer | Term | Used in |
|---|---|---|
| Product headline | **coordination space** for humans · AI · runners | README hero, one-liner, site |
| Brand / prose | **lane** = one actor's write-track | README prose, marketing copy |
| Spec / code / CLI | **zone**, **role**, **role-kind** | SPEC, manifest, `docs/zones.md`, examples |
| Architecture | **three planes** (topology · transitions · policy) | `architecture/`, ADRs only |
| Etymology | textus = woven *fabric* → *context* | one line, README + SPEC epigraph |

**Rule:** introduce *lane == zone* exactly once (in the README, where "lane" is first
used), then prefer "zone" in every technical sentence. "fabric" and "shared workspace"
are retired as headline terms; "fabric" survives only as the one-line etymology. "Three
planes" (ADR 0028) is an architecture-internal model and does not appear in the README.

## Consequences

- Docs link here instead of re-deriving terms; the doc convention (`docs/README.md`)
  references this ADR as the vocabulary SSoT.
- The "Lanes" brand and the "zones" implementation stop competing — they are the same
  thing named for two audiences, and the README says so once.
- "coordination space" becomes the product's one-line answer to *what is textus*.
- **The space is domain-agnostic.** "coordination space" names a *living, multi-writer
  context store* — not a code tool. A codebase (with its `CLAUDE.md` and runbooks) is the
  lead example, not the definition; a knowledge base or any project's operating context
  fits the same shape. The load-bearing promises are *stays current* (the `intake` lane +
  `refresh` + freshness) and *coordinated* (`pulse` + the audit cursor); positioning leads
  with those, never with "for codebases".
- No wire/protocol change. `textus/3` is untouched.

## Alternatives considered

**Collapse to "zones" everywhere.** Most internally consistent, but discards the "Lanes"
brand/logo and the friendly on-ramp "coordination space" gives newcomers. Rejected.

**Make "lanes" the headline.** Leans into the logo, but "lanes" describes the parts, not
the whole; "coordination space" names what the parts add up to and why textus exists.
Rejected as the headline, kept as the part-term.

**"Native storage" / "context store" as the headline.** Captures the always-current,
"you decide what to keep" feel, but "storage" undersells the part that is the actual
product — the role/zone gate, the review hand-off, and the audit trail. Multiple actors
*coordinating* over one store is the point; storage is the substrate. Rejected as the
headline; the storage qualities live in the body.
