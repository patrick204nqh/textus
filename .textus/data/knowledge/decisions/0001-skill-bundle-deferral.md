# ADR 0.10.4 — Defer first-class skill-bundle support

**Status:** Accepted (2026-05-24). Ships alongside the recipe at `docs/recipe-github-skill-bundle.md`.

**Context.** A user-facing need surfaced: pull a folder (e.g. `affaan-m/ECC/skills/agent-eval`) from GitHub into the textus store, then fan that bundle out into per-file derived entries in a `vendor` zone. The current hook surface (`Textus.intake` + `Textus.refreshed` listener + `store.list` + `suppress_events: true`) can express this pattern, but every step bumps a sharp edge:

| Friction | Where it shows up |
|---|---|
| Intake is 1 key → 1 entry | `lib/textus/application/refresh/worker.rb:57` writes a single key |
| Fanout requires a `:refreshed` listener | side-effect at a distance; recursion guard required |
| Derived keys aren't manifest-declared | works today, will become a doctor gap if doctor tightens |
| No bundle/ownership concept | upstream file deletion → orphans unless the listener reconciles |
| Hooks aren't content | a "skill" can't carry its own intake handler |
| 30s refresh timeout (`worker.rb:7`) | tree + N raw fetches can blow past it on big folders |
| Inner writes need `suppress_events: true` | easy to forget; would cause infinite refresh |

**Options considered.**

1. **Status quo + recipe (this ADR's choice).** Ship `github_folder.rb` + `skill_fanout.rb` under `examples/claude-plugin/recipes/` with a docs page. Users copy them in. No `lib/` change. **Cost:** users must understand the suppress_events footgun. **Benefit:** zero core surface commitment, ships today.
2. **Intake handlers return N entries (Steps 1–3 of the previous design discussion).** Extend the intake contract: handler may return `{entries: [...]}` and the worker writes all of them, tracks ownership, reconciles on next refresh. Requires changes to `Refresh::Worker`, the intake hook contract, manifest schema (pattern entries for derived keys), and doctor. **Estimate:** ~3-5 days. **Benefit:** kills the listener-fanout footgun for everyone; makes "folder pull" a supported primitive. **Cost:** manifest schema change is a minor-version bump; back-compat for the old single-payload return needs preserving.
3. **Hooks-as-content.** Promote hook source code into a store zone (`hooks.<name>`), have the loader read from the store rather than disk. A skill bundle then includes its own intake handler. **Cost:** large. Trust/signing/sandbox model for executing fetched code. A whole project.

**Decision.** Take option 1 for 0.10.4. Defer option 2. Reject option 3 outright unless textus's product positioning shifts toward "plugin registry that distributes executable extensions."

**Rationale.** The pattern has come up exactly once. Designing a bundle primitive from one use case is the [premature abstraction trap](https://wiki.c2.com/?PrematureAbstraction). The workaround works; the recipe makes it documented and testable. The decision is reversible — promoting the recipe to first-class in a future minor release is straightforward.

**Criteria for revisiting (option 2).** Schedule the intake-returns-N-entries refactor when **any** of these is true:

- A third independent use case appears that copy-pastes (or wants to copy-paste) the fanout listener.
- A user reports the suppress_events footgun in the wild (event loop in production).
- A user reports orphaned derived entries from upstream deletions because they forgot the reconciliation step.
- Doctor adds a manifest-coverage check that flags derived keys (would force the issue regardless).

**Criteria for revisiting (option 3).** Don't, unless textus reframes as a plugin/extension marketplace and the security model for executing fetched code is in scope.

**Consequences if we never revisit.** Every team needing folder-pull writes (or copies) ~50 lines of listener boilerplate. Tolerable for one or two teams; unscalable past a handful. The ADR closes when option 2 ships or when this repo decides folder-pull isn't a core textus use case.

**Out-of-scope notes.**

- A `textus pull` CLI verb was considered as middle ground (a thin script around the existing primitives). Rejected: a CLI verb that doesn't change semantics is just sugar, and the recipe already covers the path. If usage data later shows the recipe is widely copied, revisit.
- Pattern manifest entries (`vendor.skills.*.**`) are mentioned in option 2 because they'd be required to keep doctor happy once derived keys are first-class. Standalone they're not useful.
