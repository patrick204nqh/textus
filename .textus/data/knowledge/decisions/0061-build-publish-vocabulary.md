# ADR 0061 — Reconcile the `build`/`publish` vocabulary: the verb is `build`, `publish` is the output-destination noun

**Date:** 2026-06-03
**Status:** Accepted (ships 0.44.0)
**Refines:** [ADR 0058](./0058-one-verb-name-across-surfaces.md) (one verb name across surfaces — this completes the deferred row 0061: the one operation that materializes derived output now has a single name, `build`, on every surface, where before the use-case class said `publish` and everything else said `build`), [ADR 0052](./0052-typed-publish-block.md) (the typed `publish:` entry block — this ADR explicitly *retains* `publish:` as the output-destination concept and resolves the collision by word-sense, not by renaming the block).
**Touches:** [ADR 0034](./0034-unify-lane-vocabulary.md) (the unified lane vocabulary maps the `derived` zone-kind to the required verb `build`; renaming the use-case onto `build` makes the verb an agent/operator types the same token the lane already requires), [ADR 0039](./0039-mcp-catalog-derive-or-guard.md) (the verb is derived from the contract — but `Write::Build` carries **no** contract, so the MCP catalog is unchanged; this is a CLI+Ruby rename, not a surfacing decision).

> **One sentence:** the one write operation that materializes derived entries wore two names — the use-case class, the dispatcher key, the `RoleScope` method, and the CLI command's dispatch all said `publish` (`Write::Publish`), while the capability, the `derived` zone-kind's required verb, `BuildLock`, the `build_in_progress` error, and all prose said **`build`** — so this renames the verb onto `build` end to end (`Write::Build`, `build:` dispatcher key, `RoleScope#build`, CLI `build` calling `ops.build`) and keeps `publish` **only** as the ADR-0052 output-destination noun (the `publish:` block, `publish_to`/`publish_tree`, the byte-copy-out `Ports::Publisher`, and the per-kind `publish_via`/`PublishContext` copy-out internals).

## Context

ADR 0058 made every verb's name singular across surfaces, but explicitly deferred one: the operation behind `Write::Publish`. Its drafting note recorded why — `build` is not a lone internal token. Five layers already say "build":

- the **capability** `build` (`Schema::CAPABILITIES = {author, keep, fetch, propose, build}`);
- the **`derived` zone-kind's required verb** `build` (`Manifest::Schema::LANES["derived"] => "build"`, ADR 0034);
- the **lock and error** — `Layout.build_lock`, the `build_in_progress` error code, "`textus build` already running";
- the **`build`-holder role** wording throughout `boot` and the CLI verb table;
- pervasive **concept-prose** in SPEC.md and the docs.

Only three layers said `publish`: the use-case **class** `Write::Publish`, the **`Dispatcher::VERBS`** key `publish:` (hence `RoleScope#publish`), and the CLI verb's **dispatch call** `ops.publish`. (During the 0058 PR the CLI *command* was briefly renamed `build`→`publish` too, then reverted — the command has always been `build`.) So the one-name principle points unambiguously one way: rename the verb onto `build`, not the five layers onto `publish`.

The reason this was deferred rather than folded into 0058 is the **ADR-0052 collision**. `publish` is not only a verb candidate — it is the name of a real, distinct concept: the typed `publish:` entry block (`publish: { to: [...] }` xor `publish: { tree: "dir" }`), its `publish_to`/`publish_tree` readers, the byte-for-byte copy-out `Ports::Publisher`, and the per-kind `publish_via`/`PublishContext` machinery the use-case drives. If the verb stayed `publish`, "publish" would mean both *the umbrella write operation* and *the copy-bytes-out step inside it* — an overload. The resolution is to separate the two senses cleanly, which is a vocabulary decision with its own blast radius (every `Write::Publish`/`RoleScope#publish`/`ops.publish` call site moves), hence its own ADR.

## Decision

**The verb is `build`; `publish` is the output-destination noun.** One umbrella write verb `build` materializes derived entries and drives their output; `publish` names *where* and *how* that output is copied out.

1. **Rename the use-case.** `Write::Publish` → `Write::Build` (class and file `lib/textus/write/build.rb`). Its `#call(prefix:)` signature, return shape (`{protocol, built, published_leaves, pruned}`), and behaviour are unchanged. Note the response key `published_leaves` **stays** — those are leaves that were *published* (copied out), the noun sense.
2. **Rename the verb token.** `Dispatcher::VERBS` key `publish:` → `build:` (mapping to `Textus::Write::Build`). `RoleScope` metaprograms `#build` from the key; `#publish` ceases to exist as a verb method. (`EventBus#publish`, a different object's method, is untouched.)
3. **Point the CLI at it.** The CLI command is already `build` (`CLI::Verb::Build`, `command_name "build"`); its dispatch changes from `ops.publish(...)` to `ops.build(...)`. Operator ergonomics are unchanged — the command, the capability it checks, and the verb it now runs all read `build`.
4. **Keep `publish` for the copy-out concept — unchanged.** The ADR-0052 `publish:` block, `publish_to`/`publish_tree`, `Ports::Publisher.publish(source:, target:)`, the per-kind `publish_via`/`PublishContext`, the `Read::Published` (`published`) read verb, the `publish_error` code, and "wasn't published by textus" doctor prose all retain `publish`. `build` is the verb; `publish` is the destination/step it acts through.
5. **No MCP change, no contract.** `Write::Build` carries no contract (as `Write::Publish` did not) — it is CLI+Ruby only. The MCP catalog and `boot.read_verbs`/`write_verbs` are unaffected. Whether an agent should be able to trigger `build` is a separate surfacing decision, not this rename.
6. **Guard it.** The MCP-catalog↔dispatcher reconciliation omit-list moves its CLI-only entry `publish` → `build`; the CLI-registry reconciliation and `boot` CLI-verb catalog already say `build`. SPEC.md and the docs already speak the `build` verb (they were never on `publish`), so no prose sweep is needed beyond confirming the L4 "Publish" operation reads as the copy-out step `build` performs.

## Consequences

- **One name per operation, end to end.** The capability `build`, the `derived` zone-kind's required verb `build`, the CLI command `build`, the `RoleScope#build` method, and the `Write::Build` class are now the same token. A reviewer comparing any two of them sees one word.
- **`publish` now has exactly one meaning:** the output-destination concept (the `publish:` block and the copy-out machinery). The overload — verb vs config-block — is gone.
- **Breaking, no shims.** `RoleScope#publish` and the `publish` dispatcher verb are removed; programmatic Ruby callers using `store.as(role).publish` must call `.build`. Consistent with ADR 0058 house style (pre-1.0; the derive-or-guard machinery makes a name singular by construction; alias tables would reintroduce the many-names state). The MCP surface is unaffected (the verb was never surfaced).
- **No behaviour change.** Every edit is a token rename across co-moving sites plus call sites; args, return shape, lock, error codes, and the copy-out path are identical.
- **Ships in 0.44.0 alongside 0058–0060 and 0062** — same release, a distinct verifiable decision with its own ADR and specs.

## Alternatives considered

- **Rename the five `build` layers onto `publish` instead.** Rejected: it inverts the majority and collides head-on with the ADR-0052 `publish:` block — "publish" would name both the verb and the destination config. The one-name principle counts five surfaces saying `build` to three saying `publish`; the cheap, collision-free direction is onto `build`.
- **Treat `build` and `publish` as two separate verbs** (build = compute derived; publish = copy out). Rejected: the existing single use-case already composes both (compute → `publish_via` copy-out) and every caller runs them as one operation ("make derived outputs current and mirror them"). Splitting into two public verbs would add a second name and a sequencing burden for no user benefit. The clean shape is one verb (`build`) that drives a `publish` step.
- **Rename the `publish:` block too** (e.g. to `output:`/`destinations:`), so nothing is called `publish`. Rejected: out of scope and gratuitously breaking — `publish:` is a precise, well-understood ADR-0052 concept (a file is *published* to a path). Keeping the noun and freeing the verb is the minimal, legible fix.
- **Fold into ADR 0058.** Rejected there (0058 was pure same-name renames; this moves a use-case class and every call site, and must navigate the 0052 collision). Pulled into the same 0.44.0 PR on request, but kept a separate, verifiable decision.
