# ADR 0045 — Close the role-name set to {human, agent, automation}; keep capabilities open

**Date:** 2026-06-01
**Status:** Accepted
**Amends:** [ADR 0028](./0028-coordination-planes.md) (its "open policy" plane — role *names* are now closed; only `can` stays open). **Refines:** [ADR 0030](./0030-capability-based-roles.md) (a role is now a *fixed-archetype name* + composable verbs, not an arbitrary name + verbs). **Complements:** [ADR 0044](./0044-system-actors-resolved-by-capability.md) (capability-resolution of system actors), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (per-transport default identity).

## Context

ADR 0030 made role *names* arbitrary (any string matching `Role::PATTERN = /\A[a-z][a-z0-9_-]*\z/`), with authority derived from capabilities × zone-kind. ADR 0028 framed this as the "open policy" plane atop a closed topology and closed transition set. `Manifest::Capabilities.resolve` honors it literally:

```
manifest/capabilities.rb   raw_roles.nil? ? DEFAULT_MAPPING : raw_roles.to_h { |r| [r["name"], r["can"]] }
role.rb                    PATTERN = /\A[a-z][a-z0-9_-]*\z/   # any name; ':' excluded
manifest/schema.rb:104     author_holders <= 1                 # the one hard constraint today
```

Three observations from the codebase and from this design review converged:

1. **The three names already do all the work.** `human`/`agent`/`automation` are the fallback vocabulary (`DEFAULT_MAPPING`), the per-transport default identities (`Role::DEFAULT`, `Role::AGENT`; ADR 0040), the scaffold (`Init::DEFAULT_MANIFEST`), and the three coordinator archetypes the mental model is built on (`explanation/concepts.md`: human curates canon, agent proposes, automation fetches/builds).

2. **Arbitrary names are exercised in tests but unused in practice.** Every shipped manifest (`init`, `examples/`, the dogfood `.textus/`) uses only the three. Custom names (`compiler`, `importer`, `proposer`, `weirdo`, `co_owner`, …) appear *only* in spec fixtures that exercise the open-names contract — never in a real store.

3. **Open names are the root of recurring friction.** They made the hardcoded `|| "automation"` literals a defect ([ADR 0044](./0044-system-actors-resolved-by-capability.md)); they block a single source-of-truth constant for the names; and they invite role sprawl with no payoff. The value of "name a role anything" is low; its costs are real and recurring.

The deciding insight: **multiplicity of *principals* belongs on the `owner:` field, not the role.** `owner: human:patrick` / `human:kevin` / `agent:claude` already expresses "who" (attribution); the role expresses "what authority" (the archetype). Roles are few and fixed; owners are unbounded and free-form. Once that split is accepted, arbitrary role names lose their last justification.

## Decision (proposed)

1. **The role-name set is closed.** Introduce `Role::NAMES = %w[human agent automation].freeze` as the single source of truth. A manifest declaring any other role name is rejected at load with a clear error. `Role::PATTERN` continues to validate `owner:` *subjects* (`human:patrick`); role *names* switch from regex to `Role::NAMES` membership.

2. **Capabilities stay open.** Each declared role may hold any subset of the closed five-verb set (`author`, `propose`, `keep`, `fetch`, `build`), subject to the existing single-`author` rule (`schema.rb:104`). This is the "flexible on `can`": a manifest tunes *what each archetype may do*, not *what they're called*.

3. **A manifest need not declare all three.** It declares the subset it uses; closed names do **not** assume presence. Who-acts for system-initiated operations is still resolved by capability (`actor_for`, ADR 0044), never by assuming a name exists. Closed names and capability-resolution are complementary.

4. **Principal multiplicity moves to `owner:`.** Multiple humans/agents/automations are expressed as `owner: <archetype>:<subject>` (attribution), not as distinct roles (authority). Roles are the authority/identity layer (three archetypes); owners are the attribution layer (unbounded).

5. **`Role::NAMES` is authoritative.** `Role::DEFAULT`/`Role::AGENT` and `Capabilities::DEFAULT_MAPPING` keys validate against it; `default_roles_consistency_spec` extends to assert membership. The three literals throughout the code are no longer a smell — they reference a closed, single-sourced vocabulary.

## Consequences

- **Single source of truth achieved.** The recurring "should we define human/agent/automation as a source of truth?" question resolves: yes — `Role::NAMES`. Closing the set is precisely what makes that constant meaningful (it was *not* meaningful while names were open).
- **Accepted trade-off — loss of per-coordinator least privilege (security-relevant).** Two automations with *different enforced* capabilities (a `fetch`-only ingest bot vs a `build`-only CI bot) is no longer expressible: all automation shares one role and one capability profile. Distinguishing them is now *attribution only* (`owner: automation:ci` vs `automation:nightly`), not enforcement. **This is accepted.** Escape hatch if it ever bites: owner-scoped enforcement (the deferred feature in `reference/zones.md`) or re-opening names via a future ADR.
- **No `PROTOCOL` bump.** Closing names is a stricter `textus/3` validation in `Schema.validate_roles!`. Compliant manifests (all real ones) are unaffected; only manifests declaring custom role names are now rejected. Cost was concentrated in test fixtures + docs, not a protocol revision.
- **Amends ADR 0028 / refines ADR 0030.** Policy is no longer fully open: names are closed, capabilities remain open. A role is an archetype-name + composable verbs.
- **ADR 0044 stands unchanged.** Its capability-resolution code is still correct and still needed (a manifest may omit a role), and closed names now make its Tier-C literals (`DEFAULT_MAPPING`, `Role::DEFAULT`) legitimate rather than tolerated.

## Alternatives considered

- **Open names + a closed `archetype:` tag** (mirror the zone `kind` design: `{ name: claude, archetype: agent, can: [...] }`). Preserves per-coordinator least privilege *and* multiplicity, and would let transport defaults resolve by archetype. **Rejected by decision:** it keeps two concepts (name + archetype) where the team wants one, and does not deliver the conceptual simplicity or the single `Role::NAMES` SSoT that motivated this change. Recorded because it is the natural re-opening path if least-privilege is later needed.
- **Status quo + owner attribution** (leave names open; use `owner:` for "who"). **Rejected:** leaves the three literals a perennial smell with no SSoT and does nothing to prevent role sprawl.
- **Keep names fully open (do nothing).** **Rejected:** the arbitrary-name flexibility is unused in real manifests and is the recurring source of the hardcoded-literal temptation that ADR 0044 had to clean up.

## Open questions

- **Q1 — extensibility.** Should `Role::NAMES` ever be operator-extensible (a manifest-level allow-list), or strictly hardcoded? Recommendation: **strictly hardcoded** — closure is the point; revisit only on a concrete need (which would likely be the `archetype:` alternative above, not a longer name list).
- **Q2 — least-privilege escape hatch.** Owner-scoped enforcement (promoting `owner:` from advisory to authority-bearing) is the mitigation if the accepted trade-off bites. Separate future ADR; not in scope here.
- **Q3 — migration behavior.** Should `textus migrate` rewrite/flag a `textus/3` manifest carrying custom role names, or fail closed with guidance? Lean: fail closed with a clear "role names must be one of human/agent/automation" error and a doctor check, mirroring 0035's `ProposalTargets` precedent.

## Resolutions (accepted)

- **Version: no bump** — closing names ships as a stricter `textus/3` validation in `Schema.validate_roles!`, not a wire-version revision (see Consequences).
- **Q1: `Role::NAMES` is hardcoded**, not operator-extensible. Closure is the point; re-opening would go through the `archetype:` alternative in a future ADR, not a longer name list.
- **Q3: fail closed** — a manifest with an illegal role name is rejected at load with `unknown role name '<x>' (allowed: human, agent, automation)`; dedicated migration tooling is out of scope.

## Implementation notes

- **Owner-subject validation lives in `Manifest::Schema`, not `Role`** (#135). D1 above anticipated `Role::PATTERN` validating `owner:` subjects; in implementation the owner-validation *rule* is `Manifest::Schema.valid_owner?`, which composes the archetype set (`Role::NAMES`, still owned by `Role`) with an owner-specific subject shape (`Manifest::Schema::OWNER_SUBJECT_PATTERN`). The old `Role::PATTERN` constant — a vestige of ADR 0030's open role *names* — was relocated and renamed accordingly: `Role` keeps the role-name vocabulary, `Schema` owns the owner grammar. An owner is a bare archetype (`agent`) or `<archetype>:<subject>` (`human:patrick`); both zone and entry owners are validated at load, raising `BadManifest`.
</content>
