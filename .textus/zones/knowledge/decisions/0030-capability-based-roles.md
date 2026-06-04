# ADR 0030 — Capability-based roles: role = name + composable verbs

**Date:** 2026-05-30
**Status:** Accepted
**Supersedes:** the parked `runner → fetcher` rename (the role `fetcher` dissolves into the `fetch` verb); retires the `role-kind` 1:1 mapping and per-zone `write_policy`
**Refines:** [ADR 0028](./0028-coordination-planes.md) (coordination planes), [ADR 0029](./0029-concept-vocabulary.md) (concept vocabulary)
**Updated by:** [ADR 0033](./0033-complete-primitives-and-vocabulary.md) — renames the `accept` capability to `author` and adds a fifth capability `keep`; the closed set is now `propose`, `author`, `keep`, `fetch`, `build`. The capability-based model and its invariants stand unchanged.

## Context

Cleaning up the weak `runner` role exposed a deeper question. Today a role maps **1:1**
to a `role-kind` (`human→accept_authority`, `agent→proposer`, `builder→generator`,
`runner→runner`). That coupling produced two complaints:

1. The kind names felt redundant with the role names (`fetcher`/`importer`,
   `builder`/`generator` read as synonyms).
2. The real desire is **flexible role names whose capacity is described by verbs** —
   "automation can fetch and build", "agent can propose (extend later)", "human can
   accept and propose". One role, possibly several responsibilities.

ADR 0028 closed the zone-kind and transition-verb sets and put flexibility in the
**predicate** layer (*"flexibility is added by composing primitives, never by minting
them"*). This ADR applies that philosophy one level over: **a role is an open *name*
plus a *subset* of a closed set of capability-verbs.** The verbs stay fixed and
legible; only their assignment to named roles becomes flexible.

## Decision

### 1. Replace `role → kind` (1:1) with `role = name + capabilities` (1:many)

The `role-kind` vocabulary is **replaced** by a closed capability set.

```yaml
roles:
  - { name: human,      can: [accept, propose] }   # authority; may also suggest
  - { name: agent,      can: [propose] }            # extend later, e.g. [propose, fetch]
  - { name: automation, can: [fetch, build] }       # data in + data out
```

### 2. The closed capability set (4 verbs)

Each capability is the authority to **originate in exactly one zone-kind** — capabilities
stay 1:1 with the (still-closed) four zone-kinds:

| verb | grants authority to | zone-kind |
|---|---|---|
| `propose` | write into a queue (awaits accept) | `queue` |
| `accept` | promote proposals **and** author authoritative zones | `origin` |
| `fetch` | bring external bytes in (TTL-cached; implies refresh-on-stale) | `quarantine` |
| `build` | compute derived artifacts | `derived` |

This dissolves the `fetcher`/`builder` naming problem: there is no such role; there is an
`automation` role that *holds* `[fetch, build]`. The in/out distinction **is** the verb.

### 3. Drop `write_policy`; derive write authority

A zone declares only its **kind**. Who may write it is **computed**:

> a role may write zone *Z* ⟺ its `can` includes the verb that *Z*'s kind requires.

```yaml
zones:
  - { name: identity, kind: origin }       # accept-holders write
  - { name: working,  kind: origin }       # accept-holders write
  - { name: intake,   kind: quarantine }   # fetch-holders write
  - { name: review,   kind: queue }        # propose-holders write; accept promotes
  - { name: output,   kind: derived }      # build-holders write
```

This is the cleaner design: roles state their capacity once, zones state their kind, and
the gate is the intersection. No `write_policy` list to keep in sync.

### 4. `refresh` transition → `fetch`

The data-in transition is renamed `refresh` → `fetch` (`textus fetch KEY --as=automation`).
TTL caching / refresh-on-stale is *implied* by `fetch`; we don't re-fetch on every read.

### 5. The gate names the missing capability

> `write_forbidden: writing 'output' needs capability **build**; role 'agent' has [propose].`

### 6. The invariant — `accept` is the single trust anchor

**At most one role may hold `accept`, and a low-trust role must never hold it.** A role
with `accept` is by definition the trusted authority (it can author `origin` directly),
so pairing it with `propose` is harmless. The danger — a low-trust role holding both
`propose` and `accept` and self-promoting — is blocked by the single-`accept` rule
(textus already enforced "at most one `accept_authority`"). The two-authority review
handshake is preserved: low-trust bytes still need a *separate* `accept` holder to climb.

`accept` stays **bundled** (author `origin` + sign `queue`); not split into `author`/`accept`.

## Consequences

- **Breaking, no back-compat (one user, clean break).** Ship as **0.31.0**.
- **Manifest schema changes** in two places: `roles:` entries `{name, kind}` → `{name, can: [...]}`;
  `zones:` entries drop `write_policy` (keep `name` + `kind`). `textus/3` wire is otherwise
  unchanged — role names remain opaque strings on the wire.
- **`role-kind` retires.** The gate matches capability-set membership against the zone's
  kind. The `accept_authority_signed` predicate is reframed against the `accept` capability.
- **Capabilities ≠ transitions.** The Plane-2 transition set stays closed
  (`put`/`accept`/`reject`/`fetch`/`build`/`mv`/`delete`); a capability gates which
  zone-kinds a role may originate in. `build` is intentionally both a capability and the
  `textus build` transition (helpful alignment).
- **Tradeoff — per-zone role isolation is gone.** Two zones of the same kind now share
  the same write-authority (e.g. every `fetch` role may write every `quarantine` zone).
  If isolation is ever needed ("only `notion-bot` writes `intake.notion`"), it returns as
  a **predicate** on the zone (ADR 0028's open policy plane), *not* as `write_policy` —
  keeping the topology plane clean.
- **One role can span zones** (`automation` writes `intake` *and* `output`).
- `agent` defaults to `[propose]`; an agent **scratch/memory** lane (ADR 0028 open
  question) is deferred to its own change.

## Alternatives considered

- **Keep 1:1 `role→kind` + rename `runner→fetcher`** (parked plan). Rejected: leaves the
  kind names redundant and never delivers the verb-described-capacity model; the
  destination makes it moot.
- **Open (free-form) capability vocabulary.** Rejected — opening the verb set destroys
  the legible refusal (ADR 0028). Capabilities stay closed (4).
- **Keep `write_policy` alongside capabilities.** Rejected by the owner: the redundancy
  isn't worth it; the derived gate is cleaner, and per-zone isolation (rarely needed)
  lives in the predicate plane.
- **Allow `propose`+`accept` in any role.** Rejected — self-approval collapses the review
  handshake. Hence the single-`accept`-anchor invariant.
