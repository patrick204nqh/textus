# ADR 0044 — System-initiated actors are resolved by capability, never by a hardcoded role name

**Date:** 2026-06-01
**Status:** Proposed
**Refines:** [ADR 0030](./0030-capability-based-roles.md) (a role is a name + composable verbs; names carry no privilege; single trust anchor), [ADR 0034](./0034-unify-lane-vocabulary.md) (the zone-kind ↔ capability bijection), [ADR 0040](./0040-mcp-connection-role-and-two-channels.md) (the no-`--as` default identity per transport).

## Context

ADR 0030 makes role names **arbitrary**: authority is derived from capabilities × zone-kind, and the docs promise it twice — "`knowledge`, `scratchpad`, etc. have no privileged status in the code. Rename freely" (`how-to/configuring-zones.md`), and the same for roles. The test for any role-name string literal in `lib/` is therefore: *if I rename this role in my manifest, does this code path still work?*

A sweep of `lib/` for actor literals turns up three tiers. Only one is a defect.

```
A — authority-bearing (picks who an operation acts AS)
  ports/fetch/detached.rb:24   store.as("automation").fetch(key)               # forked background fetch
  cli/verb/build.rb:11         roles_with_capability("build").first || "automation"

B — defaulting / labelling (cosmetic)
  cli/verb/hooks.rb:38         defn["as"] || "automation"                      # echoed in a hook listing
  ports/audit_subscriber.rb:36 role: "automation", verb: "event_error"        # label on a system audit row

C — legitimate config defaults (apply only absent configuration)
  manifest/capabilities.rb:14  DEFAULT_MAPPING = { human:…, agent:…, automation:… }  # used iff `roles:` omitted
  role.rb:4,8                  DEFAULT="human", AGENT="agent"                  # no---as identity (ADR 0040)
```

**The defect (Tier A).** `Detached.spawn` is the forked child that completes a `timed_sync`
background fetch (`fetch_orchestrator.rb` → `run_timed_with_fork`). It hardcodes
`store.as("automation")`. Rename the fetch-holder `automation → importer` and every background
fetch acts as a role **that is not in the manifest** → the write gate refuses it → and the child
has `$stderr.reopen(File::NULL)` + `rescue StandardError` (`detached.rb:16,25`), so it fails
**silently**. The foreground `fetch --as=importer` works; the backgrounded fetch for the same
entry dies invisibly. That is the worst failure shape: silent, and mode-dependent.

`build.rb`'s `|| "automation"` is a milder fig-leaf — its primary path
(`roles_with_capability("build").first`) is already capability-derived and rename-safe; the
literal only "saves" the case where no role holds `build`, and even then only under the default
mapping. It reads like a safety net but launders a capability question back into a name guess.

**The pattern already exists.** `Policy#proposer_role` (`manifest/policy.rb:32`) is the correct
shape, and notably it never falls back to a string literal:

```ruby
def proposer_role
  proposers = roles_with_capability("propose")
  (proposers - roles_with_capability("author")).first || proposers.first   # a name in the manifest, or nil
end
```

So this is not "introduce a convention" — it is "the convention is `proposer_role`; finish
applying it." ADR 0030 *implies* the invariant ("system-initiated actors are capability-resolved")
but never states it, and `detached.rb` is the proof the line was not fully held.

Tier C is **not** a smell: `DEFAULT_MAPPING` exists only for a manifest that omits `roles:` and is
discarded the instant `roles:` is declared (`capabilities.rb:22-25`); `Role::DEFAULT` is the
deliberate no-`--as` identity (ADR 0040). These are the one legitimate home for role-name literals.

## Decision (proposed)

1. **State the invariant.** Every system-initiated operation (no human passing `--as`) resolves its
   acting role **by capability**, never by a role-name literal. Tier-C config defaults are the sole
   exception and stay where they are.

2. **One resolver on `Policy`.** Generalize `proposer_role` into:

   ```ruby
   # The role textus acts as for a system-initiated op requiring `verb`.
   def actor_for(verb) = roles_with_capability(verb).first
   ```

   `proposer_role` keeps its richer anchor-excluding logic; `actor_for` is the simple capability lookup.

3. **Route the Tier-A sites through it.**
   - `build.rb` → `policy.actor_for("build")`, dropping `|| "automation"`.
   - `detached.rb` → the forked child already rebuilds the `Store`, so it resolves
     `store.manifest.policy.actor_for("fetch")` itself — no need to thread a role through `fork`.
     This closes the silent-rename gap with a one-line change.

4. **No-holder behavior: raise, don't guess** (see Q1). When no role holds the required verb,
   `actor_for` returns `nil` and the caller raises a clear `no role holds 'build'` error rather than
   acting as a non-existent name and failing later at the write gate with a misdirected
   `write_forbidden`. `textus doctor` may pre-flight this.

5. **Tier B is cosmetic** — `hooks.rb` and `audit_subscriber.rb` may keep a soft default, but should
   prefer `actor_for` where an actual actor (not just a label) is implied.

## Consequences

- The "role names are arbitrary" promise (ADR 0030) holds **everywhere**, including the background
  fetch path — not just on the foreground gate. Renaming any role is rename-safe end to end.
- A build/fetch with no capable role fails **loudly and at the right layer** instead of limping to a
  confusing downstream `write_forbidden` (or, for background fetch, dying silently).
- **No `textus/3` wire change, no manifest-schema change.** Pure internal actor-resolution.
- One new public method on `Policy` (`actor_for`); `proposer_role` is unchanged.
- A regression risk worth a dedicated spec: rename `automation → importer` in a fixture manifest and
  assert background fetch **and** build still resolve an actor (the test the current code would fail).

## Alternatives considered

- **Keep a single named-constant fallback** (`SYSTEM_FALLBACK = "automation"`). Rejected: it merely
  relocates the magic string; a manifest that renames the fetch/build holder still breaks, just from
  one place instead of four.
- **Return `nil` and silently skip** the operation when no holder exists. Rejected: reintroduces the
  exact silent-failure smell this ADR removes.
- **Leave it (status quo).** Rejected: `detached.rb` is a latent, silent correctness bug, and the
  literals contradict a documented core invariant.
- **Thread the resolved role into `Detached.spawn` as a param.** Viable, but unnecessary — the child
  already has the manifest via `store_root`; self-resolving keeps the fork interface minimal.

## Open questions

- **Q1 — no-holder behavior.** Confirm **raise** (4 above) over (b) a named-constant fallback or
  (c) nil-and-skip. Recommendation: **raise**; it converts a misdirected, sometimes-silent failure
  into an explicit, actionable one and gives `doctor` a clean hook.
- **Q2 — doctor pre-flight.** Add a `Check` that flags a manifest declaring a `derived`/`quarantine`
  zone with no role holding the matching `build`/`fetch` verb (the operation can never run)? Cheap,
  and consistent with 0035's `ProposalTargets` precedent.
- **Q3 — background fetch identity.** Should the background continuation act as `actor_for("fetch")`
  (canonical fetch-holder, proposed) or inherit the *originating* request's role threaded through?
  The former matches `build`; the latter is more faithful but widens the fork interface. Lean former.
</content>
</invoke>
