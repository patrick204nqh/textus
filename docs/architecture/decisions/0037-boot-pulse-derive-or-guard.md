# ADR 0037 — Boot/pulse: derive-or-guard, no unguarded hand-maintained mirror

**Date:** 2026-05-31
**Status:** Accepted
**Refines:** [ADR 0030](./0030-capability-based-roles.md) (capability roles — "derive, don't list"), [ADR 0034](./0034-unify-lane-vocabulary.md) (single Lane table; boot names zones by kind), [ADR 0025](./0025-boot-doctor-as-verbs-and-etag-via-port.md) (precedent: a guard spec that fails the build on regression)

## Context

`textus boot` and `textus pulse` are the agent-facing contract. An agent loads
`boot` once to learn the store (zones, entries, hooks, write-flows, CLI catalog,
recipes, quickstart) and calls `pulse` each turn for the delta. SPEC §6's
`inject_boot:` flag is explicit that a rendered preamble must be trusted because
it "was produced by the same source of truth `textus boot` exposes." Boot is, by
design, *the* orientation source of truth.

That makes any **copy** of a fact that already lives elsewhere a liability: when
the original changes, the copy must be hand-updated, and nothing fails if it
isn't. The agent then follows stale guidance. This is the drift class ADR 0030
named ("derive, don't list") and ADR 0034 closed for the zone/capability
bijection.

Most of boot and all of pulse are already drift-proof: they are **derived** from
the manifest at call time (`zones_for`, `entries_for`, `hooks_for_container`,
`write_flows_for`, `recipes`, `agent_quickstart.writable_zones/propose_zone`,
and pulse's whole aggregate). ADR 0034 removed the last hardcoded zone name from
pulse (`manifest.policy.queue_zone`).

But unguarded hand-maintained mirrors remain, and at least one has already
drifted:

1. **`Boot::CLI_VERBS`** (`lib/textus/boot.rb`) — an 18-entry curated catalog
   carrying the comment *"Truth lives here; do not derive dynamically."* It is a
   deliberate **editorial** surface (agent-friendly summaries, a stable shape,
   intentionally *not* 1:1 with `Dispatcher::VERBS` internals). Nothing checks it
   against the real command registry `Textus::CLI.verbs`. A new top-level verb,
   or a removed one, drifts silently.

2. **`Boot::WRITE_FLOW_TEMPLATES`** keys — must match the capability vocabulary
   (`Manifest::Schema::CAPABILITIES`, derived from the `LANES` table per
   ADR 0034). A renamed capability silently orphans a template (the verb is just
   omitted from the write-flow, no error).

3. **`agent_quickstart.read_verbs`** — a hardcoded curated subset, mirrored again
   in SPEC §9's example JSON.

4. **SPEC §9 envelope examples** — hand-written `pulse` and `agent_quickstart`
   JSON. **Already drifted:** the documented `pulse` block lists 5 keys, but
   `Read::Pulse#call` returns 8 (`manifest_etag`, `next_due_at`, `hook_errors`
   are undocumented).

5. **`AGENT_PROTOCOL_TEMPLATE` section refs** — strings like `"SPEC.md §8"` /
   `"§5"` that rot when SPEC is renumbered.

## Decision

**Every agent-facing fact in boot/pulse is either *derived* from a single source
of truth, or it is a deliberate editorial copy *guarded* by a contract spec that
fails the build when it diverges from that source.** No agent-facing fact may be
a hand-maintained mirror with no derivation and no guard.

We keep the editorial copies that earn their keep (curated catalog wording, a
stable shape) — we do **not** delete `CLI_VERBS` in favour of dynamic derivation,
because the curation *is* the value. What changes is that drift becomes a red
test, not a human's job to remember.

Concretely:

1. **`CLI_VERBS` ↔ registry reconciliation.** A spec asserts
   `Textus::CLI.verbs.keys == CLI_VERBS-names ∪ INTENTIONALLY_OMITTED`, where the
   omit-list (e.g. `deps`, `rdeps`, `init`, `mcp`, `migrate`, `published`,
   `reject`, `retain`, `zone`) is explicit in the spec. Adding any top-level verb
   then forces a decision: surface it in boot, or list it as omitted. Summaries
   stay hand-written; only the **name set** is guarded.

2. **`WRITE_FLOW_TEMPLATES.keys` ↔ `CAPABILITIES`.** A spec asserts the template
   keys equal `Manifest::Schema::CAPABILITIES`. A capability rename now fails
   here instead of silently dropping a write-flow.

3. **Envelope-key snapshot.** A spec asserts the live key sets of
   `Read::Pulse#call` and `Boot.build`/`agent_quickstart` equal the key sets in
   the corresponding SPEC §9 fenced-JSON examples (extracted by anchored text).
   The doc JSON becomes a checked snapshot, not a guess.

4. **SPEC section refs exist.** A spec extracts every `"SPEC.md §N"` reference
   from `lib/textus/boot.rb` and asserts a matching `## N.` heading exists in
   `SPEC.md`.

5. **Fix the live drift now.** Add `manifest_etag`, `next_due_at`, `hook_errors`
   to the SPEC §9 `pulse` example so the new snapshot guard passes against
   reality.

`read_verbs` stays a hand-written curated subset (deriving it would add tags to
every catalog entry for marginal gain — YAGNI); it is covered by the snapshot
guard (3) rather than tagged.

## Consequences

- **No production behaviour change.** Boot/pulse output is unchanged except the
  SPEC §9 doc text, which is corrected to match what the code already returns.
- **Four new guard specs.** Mirror the ADR 0025 precedent
  (`no_handrolled_manifest_etag_spec`): cheap, fast, and they convert "cross-check
  on every change" into a build failure at the moment of divergence.
- **A new verb has a checklist.** Adding a top-level CLI verb now fails the
  reconciliation spec until the author either surfaces it in `CLI_VERBS` or adds
  it to the explicit omit-list — the decision is forced, not forgotten.
- **Stated invariant.** Future boot/pulse fields inherit the rule: derive, or add
  a guard. A reviewer can cite this ADR to reject an unguarded mirror.

## Alternatives considered

- **Derive `CLI_VERBS` dynamically from `Textus::CLI.verbs`.** Rejected: the
  catalog is intentionally a curated subset with agent-friendly summaries and a
  stable shape decoupled from internal command/group structure. Auto-deriving
  would either leak internal verbs (`mcp`, `migrate`, `zone`) into the agent
  surface or require an inline filter that is itself an unguarded list. The
  reconciliation spec keeps the curation *and* removes the drift.
- **Drop the SPEC §9 JSON examples entirely** (point readers at `textus boot`).
  Rejected: the examples are the fastest way for a human to understand the shape;
  the snapshot guard keeps them honest at near-zero cost.
- **Guard nothing; rely on review.** Rejected: this is exactly the status quo
  that let the §9 `pulse` example drift three keys behind the code.

## Open questions

- **Per-role agent-surface projection** (carried from ADR 0032 / 0028): if
  `boot`/`pulse` ever expose different zones per role, the snapshot guard's
  fixture must become role-parameterized. Out of scope until that projection
  exists.
