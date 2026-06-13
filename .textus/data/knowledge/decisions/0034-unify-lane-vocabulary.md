# ADR 0034 — Unify the zone-kind/capability bijection into a single Lane table

**Date:** 2026-05-30
**Status:** Accepted — ships 0.34.0
**Refines:** [ADR 0028](./0028-coordination-planes.md) (closed primitive sets), [ADR 0030](./0030-capability-based-roles.md) (capability roles), [ADR 0033](./0033-complete-primitives-and-vocabulary.md) (completed the set at five + the kind-derived `desc:`)

## Context

ADR 0033 closed the coordination model at five zone-kinds and five capabilities and
established that write authority is `role.can ⊇ { verb_for(zone.kind) }`. With the fifth
pair added (`workspace`/`keep`), the relation between a zone-kind and the capability that
authorizes originating bytes in it is now a **total bijection**:

```
canon ⇄ author · workspace ⇄ keep · quarantine ⇄ fetch · queue ⇄ propose · derived ⇄ build
```

Yet the model is encoded as **three separate constants** in `Manifest::Schema`
(`ZONE_KINDS`, `CAPABILITIES`, `KIND_REQUIRES_VERB`). A reader must cross-reference all
three to answer "what writes a canon zone?", and a future sixth pair could be added to one
constant but not the others. This is the same "looks like a distinction, isn't one"
redundancy ADR 0030 removed (`write_policy`), ADR 0032 removed (`read_policy`), and ADR
0033 removed (the `identity`/`working` split). The bijection becoming *total* in 0.33 is
the signal that the three constants are one concept expressed thrice.

Separately, ADR 0033 §6 established that zone descriptions should be manifest data keyed by
zone *kind/identity*, not hardcoded by zone *name* in `boot.rb` (the rename-fragility
class). It fixed exactly one of `boot.rb`'s four hardcoded-zone-name sites (`ZONE_PURPOSES`).
The other three — `WRITE_FLOW_TEMPLATES`, the `agent_protocol` recipes, and the CLI verb
catalog — still embed the retired instance names (`review.*`, `intake`, `identity/working`,
`output`), so the **agent-facing boot envelope** can instruct an agent to write a zone the
store no longer has. 0.33 also added the `keep` capability but no boot write-flow for it,
silently dropping the agent's `notebook` guidance — the one lane 0.33 exists to deliver.

## Decision

1. **`Schema::LANES` (`{ zone-kind => required-capability }`) is the single source of truth**
   for the closed vocabulary. `ZONE_KINDS`, `CAPABILITIES`, and `KIND_REQUIRES_VERB` are
   **derived** from it. Values are byte-identical to 0.33.0; this is a representation
   refactor, not a vocabulary change. A future kind cannot be added without its capability.
2. **`boot` names zones by kind, never by hardcoded instance.** A new
   `Policy#zones_of_kind(kind)` lookup backs kind-derived strings in `WRITE_FLOW_TEMPLATES`,
   the `agent_protocol` recipes, and (via the stable kind vocabulary) the CLI verb catalog.
   This completes the fragility fix ADR 0033 §6 began.
3. **`keep`-holders get a `notebook` write-flow in `boot`.**
4. **`pulse` derives the queue zone from `policy.queue_zone`** instead of the literal
   `"review"`. 0.33 renamed the default queue zone `review → proposals` but missed this read
   site, so `pulse`'s `pending_review` returns `[]` on every default 0.33 store — a shipped
   correctness regression in the same rename-fragility class. The kind-derived form cannot rot.
5. **The vestigial `Manifest::Data#zones` (`name => []`) map is removed.** It carried no
   values (writer lists moved to capability-derivation in ADR 0030) and duplicated the
   keyset of `declared_zone_kinds`; its four readers (`.keys`/`.key?`) move to that one
   kind-keyed map. Single source for "which zones are declared," consistent with §1's
   single-source intent.

## Consequences

- **No `textus/3` wire change. No manifest-schema change.** The five kinds and five
  capabilities, their names, and `KIND_REQUIRES_VERB`'s mapping are unchanged. Manifests,
  envelopes, audit log, and key grammar do not move.
- `boot`'s `write_flows`/`recipes`/`cli_verbs` *string content* changes (it now reflects the
  live store), and `write_flows` gains a row for every `keep`-holder. The boot envelope's
  top-level shape and keys are unchanged.
- **`pulse.pending_review` starts working again** on default stores (it was silently empty
  since 0.33). Its envelope key name `pending_review` is unchanged (it is a wire-ish read
  field; renaming it is out of scope).
- **`Manifest::Data#zones` is removed** — a breaking *internal* API change (no external
  consumer; the manifest schema is untouched). Any code/spec reading `manifest.data.zones`
  must move to `manifest.data.declared_zone_kinds`.
- `Schema::CAPABILITIES` array *ordering* changes (it is now `LANES.values`); no behaviour
  depends on its order — only `.include?` checks and an error-message list that is not
  order-asserted by any spec. `ZONE_KINDS` ordering is preserved (one spec asserts the
  unknown-kind message order).

## Alternatives considered

- **Keep three constants, add a unit test asserting they agree.** Rejected: a guard test
  papers over the duplication instead of removing it; the bijection is data, so it should
  be one datum.
- **Derive `CAPABILITIES` but keep its current order via an explicit list.** Rejected:
  re-introduces a second hand-maintained copy of the capability set — the thing we are
  removing. Order is not load-bearing.
