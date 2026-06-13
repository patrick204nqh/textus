# ADR 0032 — Drop `read_policy`: textus gates writes, not reads

**Date:** 2026-05-30
**Status:** Accepted — shipped in 0.32.0, folded into the unified-guard work ([ADR 0031](./0031-unified-guard.md))
**Refines:** [ADR 0030](./0030-capability-based-roles.md) (capability roles — derive, don't list), [ADR 0028](./0028-coordination-planes.md)

## Context

`read_policy` is a per-zone allow-list (`read_policy: [human]`, default `[all]`) that a zone
may declare alongside its `kind`. A full vertical of machinery serves it:

- parsed in `Manifest::Data` (`data.rb:43`), carried in `zone_readers`;
- `Manifest::Policy#zone_readers` + `permission_for` thread it into `Permission`;
- `Domain::Permission#allows_read?`;
- `Domain::Authorizer#can_read?` / `#authorize_read!`;
- `ReadForbidden` in `errors.rb`;
- `ZONE_KEYS` lists `read_policy` as a valid zone key;
- SPEC.md §5 documents it as *"An optional `read_policy:` (default `[all]`) gates reads."*

A survey for this ADR found three problems, each disqualifying on its own:

1. **It is never enforced.** No read path calls it. `git grep 'authorize_read!\|\.can_read?'
   -- lib exe` returns matches only inside `Authorizer` itself — `Read::Get`, `List`,
   `Where`, `Pulse`, the MCP tools, and the CLI verbs never invoke it. `ReadForbidden` is
   raised solely inside the uncalled `authorize_read!`. The gate has no door.
2. **It is a false guarantee.** The SPEC says it "gates reads." It does not. A user who
   writes `read_policy: [human]` on `identity/` reasonably believes agents cannot read it —
   and they can, with no restriction. A documented control that does nothing is worse than
   an absent one: it invites reliance the system silently betrays.
3. **It contradicts the model.** It is a per-zone allow-list — precisely the `write_policy`
   pattern ADR 0030 *removed* as redundant ("derive, don't list"). Capability roles deleted
   the write list and left the read list standing; `read_policy` is the last surviving
   `*_policy:` and it is the inert one. In practice every declared value is `[all]`.

## Decision

**Remove `read_policy` and its entire vertical.** textus gates **writes** — who may
originate bytes where — because write-coordination is a protocol invariant and the legible
refusal (`write_forbidden`) is the product. It does **not** gate reads.

### The principle — read confidentiality is unenforceable at this layer

textus stores plain files under `.textus/zones/`. Anyone with filesystem access reads them
with `cat`, regardless of any manifest field. A `read_policy` is therefore not merely
unused — it is **unenforceable in principle** for an on-disk store. Confidentiality of
bytes-at-rest belongs to a different product (an access-controlled server, OS file
permissions, encryption), not to a storage-and-coordination convention.

### Where read-scoping legitimately lives — the agent surface, not the gate

If an agent should not *see* `identity/` secrets, the honest mechanism is **projection**:
the MCP `boot`/`pulse` contract simply does not surface those zones to that role. That is a
transport decision — the agent receives only what the server hands it — not a manifest ACL
implying enforcement everywhere. This is latent in ADR 0028's open question about what the
agent surface exposes per role; if per-role read-scoping is ever wanted, it ships there as
an explicit projection, never as a resurrected `*_policy` list.

## Consequences

- **Breaking manifest-schema change, no back-compat** (single user, clean break). `zones:`
  entries lose the `read_policy` key; `ZONE_KEYS` drops it. A manifest still carrying
  `read_policy` gets an unknown-key rejection (we do not detect or alias it).
- **`Domain::Authorizer` is deleted entirely.** Its write half (`authorize_write!`) becomes
  the `zone_writable_by` predicate (ADR 0031); its read half had no callers. This corrects
  ADR 0031's claim that the Authorizer would be "retained only for the read path" — there
  is no read path.
- **Removed:** `read_policy` parsing, `zone_readers`, `Permission#allows_read?` (and
  likely `Permission` itself — post-guard its only field is `writers`, consumed only by
  `zone_writable_by`), `Authorizer#can_read?`/`#authorize_read!`, `ReadForbidden`.
- **SPEC §5 rewritten.** It currently documents both the removed `write_policy` and the
  fake read gate; both go. Reads are stated as unrestricted at the protocol layer.
- **`textus/3` wire unchanged.** Manifest schema only.

## Alternatives considered

- **Make it real and capability-shaped** — add a `read`/`view` capability and a
  `restricted` zone-kind, enforced on every read path. Rejected: it is unenforceable for an
  on-disk store (the files are right there), and it breaks ADR 0030's clean 4-verbs ↔
  4-zone-kinds correspondence by adding a verb that does not gate *origination*. Effort with
  no real boundary delivered.
- **Keep it as an unenforced declarative hint for the MCP server** — let the agent surface
  honor it. Rejected: a field named `read_policy` that implies enforcement but is honored by
  only one transport is more confusing than an explicit `boot`-level projection. If MCP
  scoping is wanted, design it as projection (above), not as a manifest "policy."
- **Keep as-is.** Rejected: inert + inconsistent + a false guarantee is the worst option.

## Open questions

- **Per-role agent-surface projection.** What does `boot`/`pulse` expose to each role, and
  is that configurable? (Deferred; ties to ADR 0028's agent `scratch`-lane question. Until
  then, the agent surface exposes all readable zones — i.e. all of them.)
