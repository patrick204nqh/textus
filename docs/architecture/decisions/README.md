# Architecture Decision Records

This log records *why* textus is shaped the way it is. Each ADR captures one
decision, its context, the alternatives weighed, and the consequences accepted.

- **`SPEC.md`** is the current normative contract (the *what*).
- **ADRs** are the append-only reasoning behind how that contract and its
  reference implementation got here (the *why*).
- **`CHANGELOG.md`** records what shipped per version (the *when*).

ADRs are immutable once accepted. When a later decision overtakes an earlier
one, we do **not** rewrite the old ADR — we update its `**Status:**` line to
point forward (`Superseded by NNNN` / `Partially superseded by NNNN`) and leave
the original reasoning intact. The history is the point.

## Status legend

| Status | Meaning |
|---|---|
| **Accepted** | In force; reflected in `SPEC.md` and/or the implementation. |
| **Proposed** | Drafted, not yet ratified/shipped. |
| **Partially superseded by NNNN** | Core decision still stands; specifics (names, namespaces) changed by a later ADR. |
| **Superseded by NNNN** | Fully replaced; read the named ADR for current truth. |

## Index

| # | Decision | Status |
|---|---|---|
| [0001](./0001-skill-bundle-deferral.md) | Defer first-class skill-bundle support | Accepted |
| [0002](./0002-textus-3-vocabulary-redesign.md) | textus/3 vocabulary redesign | Accepted |
| [0003](./0003-legacy-sweep.md) | Legacy sweep (v0.12.0) | Accepted |
| [0004](./0004-operations-rename-and-store-facade-removal.md) | Operations rename + Store facade removal | Partially superseded by 0010 |
| [0005](./0005-store-facade-final-removal.md) | Store facade final removal (Phase 1 completion) | Accepted |
| [0006](./0006-format-strategy-extraction.md) | Format-strategy extraction (Phase 2) | Accepted |
| [0007](./0007-envelope-data-class.md) | Envelope as `Data.define` + build/publish split | Accepted |
| [0008](./0008-freshness-and-resolution-types.md) | Freshness and Resolution value objects | Accepted |
| [0009](./0009-audit-subscriber-split.md) | AuditSubscriber split from `Hooks::Dispatcher` | Partially superseded by 0022 |
| [0010](./0010-flat-operations-api.md) | Flat Operations API | Partially superseded by 0022 |
| [0011](./0011-authorize-bang-in-context.md) | Authorize-bang in Context | Superseded by 0031 (read side by 0032) |
| [0012](./0012-explicit-hook-registration.md) | Explicit hook registration | Accepted |
| [0013](./0013-port-extraction-store-as-root.md) | Port extraction: Store as composition root | Partially superseded by 0022 |
| [0014](./0014-explicit-dependencies.md) | Explicit dependencies | Partially superseded by 0022 |
| [0015](./0015-agent-gate-mcp.md) | Agent gate (MCP-shaped surface) | Accepted |
| [0016](./0016-application-ports-value.md) | Application `Ports` value object | Superseded by 0020 |
| [0017](./0017-envelope-io-split.md) | Split `EnvelopeIO` into Reader and Writer | Partially superseded by 0022 |
| [0018](./0018-manifest-carving.md) | Carve Manifest into Data/Resolver/Policy/Rules | Accepted |
| [0019](./0019-hooks-bus-split.md) | Split `Hooks::Bus` into EventBus and RpcRegistry | Accepted |
| [0020](./0020-capability-records.md) | Replace Ports with ReadCaps/WriteCaps/HookCaps | Accepted |
| [0021](./0021-session-and-module-use-cases.md) | Session + module-function use-cases | Partially superseded by 0022 |
| [0022](./0022-container-call-dispatcher.md) | Container + Call + Dispatcher | Accepted |
| [0023](./0023-uniform-use-case-shape.md) | Uniform use-case shape | Accepted |
| [0024](./0024-domain-purity-ports.md) | Domain purity via FileStat/Clock ports | Accepted |
| [0025](./0025-boot-doctor-as-verbs-and-etag-via-port.md) | Boot/Doctor as dispatched verbs + manifest etag via port | Accepted |
| [0026](./0026-use-case-construction-seams.md) | Use-case construction seams | Accepted |
| [0027](./0027-hook-signature-and-mcp-policy.md) | Hook-registry convergence + MCP transport de-leak | Accepted |
| [0028](./0028-coordination-planes.md) | Coordination space: closed topology, closed transitions, open policy | Accepted (membership extended by 0033) |
| [0029](./0029-concept-vocabulary.md) | Concept vocabulary: coordination space → lanes → zones | Accepted |
| [0030](./0030-capability-based-roles.md) | Capability-based roles: role = name + composable verbs | Partially superseded by 0033 (`accept` capability → `author`) |
| [0031](./0031-unified-guard.md) | The unified Guard: one authorization path for every transition | Accepted (ships 0.32.0) · `accept_signed` renamed by 0033 |
| [0032](./0032-drop-read-policy.md) | Drop `read_policy`: gate writes, not reads | Accepted (folded into 0031, 0.32.0) |
| [0033](./0033-complete-primitives-and-vocabulary.md) | Complete the primitive set (workspace + keep) + clarify vocabulary | Accepted (ships 0.33.0) |
| [0034](./0034-unify-lane-vocabulary.md) | Unify the zone-kind/capability bijection into a single Lane table | Accepted (ships 0.34.0) |
| [0035](./0035-proposal-target-zone-constraint.md) | Constrain a proposal's target zone; keep the accept/reject anchor-gate explicit | Accepted (ships 0.35.0) |
| [0036](./0036-transports-as-pure-framings.md) | Transports are pure framings: one verb vocabulary, one session, lifted to core | Accepted |
| [0037](./0037-boot-pulse-derive-or-guard.md) | Boot/pulse: derive-or-guard, no unguarded hand-maintained mirror | Accepted |
| [0039](./0039-mcp-catalog-derive-or-guard.md) | The MCP catalog derives from one declared verb contract | Accepted |
| [0040](./0040-mcp-connection-role-and-two-channels.md) | MCP connection acts as `agent`; human authority is a separate channel | Accepted (§1/§2/§4 ship 0.38.0) |
| [0041](./0041-dogfood-textus-in-its-own-repo.md) | Dogfood textus in its own repo: a self-development store + MCP wiring | Accepted |
| [0042](./0042-native-ignore-patterns-for-entry-enumeration.md) | Native ignore patterns for entry enumeration: one shared filter seam, evaluated above legality | Accepted (ships 0.39.0) |
| [0043](./0043-feed-ergonomics-without-breaking-core-purity.md) | Feed ergonomics without breaking core purity: intake cookbook + environment as a `feeds.machine` snapshot | Proposed |
| [0044](./0044-system-actors-resolved-by-capability.md) | System-initiated actors are resolved by capability, never by a hardcoded role name | Proposed |
| [0045](./0045-close-role-name-set.md) | Close the role-name set to {human, agent, automation}; keep capabilities open | Proposed |
| [0046](./0046-publish-leaf-subtrees.md) | `publish_each` publishes a leaf's whole subtree; siblings are opaque attachments, never keys | Accepted (ships 0.40.0) · "no third key" scoped to index-present case by 0047 · `publish_each` removed by 0051 |
| [0047](./0047-publish-tree-keyless-subtree-mirror.md) | `publish_tree`: a key-less subtree mirror for a derived-index leaf | Accepted (ships 0.41.0) |
| [0048](./0048-fetch-subsystem-three-concerns.md) | Fetch subsystem: separate intake invocation, deadline/async policy, and lifecycle events | Accepted (ships 0.41.0) |
| [0049](./0049-publish-modes-as-sum-type.md) | Publish modes as a resolved sum type + one shared subtree mirror | Accepted (ships 0.41.0) |
| [0050](./0050-native-authoring-and-content-identical-adoption.md) | Own multi-file artifacts by native authoring; migrate by content-identical adoption (resolves #132 direction) | Accepted (ships 0.41.0) |
| [0051](./0051-remove-publish-each.md) | Remove `publish_each`: collapse publish to two modes (`publish_to`, `publish_tree`) | Accepted (ships 0.42.0) · supersedes the `publish_each` half of 0046 · keys folded into `publish:` by 0052 |
| [0052](./0052-typed-publish-block.md) | Fold `publish_to`/`publish_tree` into one typed `publish:` block (`to:` xor `tree:`) | Accepted (ships 0.43.0) |
| [0053](./0053-remove-index-filename.md) | Remove `index_filename`: nested entries enumerate files | Accepted (ships 0.43.0) · orphaned by 0051 |
| [0054](./0054-entry-level-desc.md) | Entry-level `desc`: the manifest as a navigable index | Proposed |
| 0055 | A `find`/search verb over `desc` + frontmatter — evidence-triggered by 0054 once a labeled index outgrows one cheap read | Proposed (not drafted) |
| [0056](./0056-boot-quickstart-speaks-the-mcp-catalog.md) | `boot`'s agent surface derives `read_verbs` from the MCP catalog; recipes reference verbs, not CLI strings | Proposed |
| [0057](./0057-agent-legible-mcp-contracts.md) | Agent-legible MCP contracts: per-arg descriptions, `_meta` wire parity for `put`/`propose`, and `write_verbs` derived from the catalog | Accepted (ships 0.43.2) |
| [0058](./0058-one-verb-name-across-surfaces.md) | One verb name across surfaces: `schema`→`schema_show`, `fetch stale`→`fetch all`, `retention_sweep`→`retain`, collapse top-level `delete` into `key delete` | Accepted (ships 0.44.0) |
| [0059](./0059-one-rule-verb-two-depths.md) | One rule verb, two depths: merge `rules` + `policy_explain` into `rule_explain` (lean default, `detail: true` verbose); `rule list` gets a use-case | Accepted (ships 0.44.0) |
| [0060](./0060-agent-safety-graph-reads-and-default-dry-run.md) | Close the agent safety asymmetry: surface `deps`/`rdeps`/`where` to MCP + default-dry-run on the four bulk-destructive verbs | Accepted (ships 0.44.0) · amended (single-key `delete`/`mv` + `deps`/`rdeps` shape) |
| [0061](./0061-build-publish-vocabulary.md) | Reconcile `build`/`publish` vocabulary — the verb is `build` end to end (`Write::Build`, `build:`, `RoleScope#build`); `publish` kept only as the ADR-0052 output-destination noun (`publish:` block, `Ports::Publisher`, `publish_via`) | Accepted (ships 0.44.0) |
| [0062](./0062-one-get-read-through.md) | One `get`: unify the public read verb on read-through; **one `Read::Get#call(key, fetch:)` class** (GetEntry merged); drop `get_or_fetch` | Accepted (ships 0.44.0) |
| [0063](./0063-cli-is-a-projection-of-the-contract.md) | The CLI is a projection of the contract: `CLI::Runner` generates commands from `Contract` (`cli` + `cli_response` facets), escape hatches subclass `Runner::Base` (name derived), total reconciliation guard — closes the hand-wiring gap behind 0058/0059/0061 | Accepted (ships 0.44.0) |
| [0064](./0064-derive-command-name-and-guard-dispatcher-key.md) | Derive the CLI `command_name` from the contract `cli_leaf` (drop 13 hand literals) and guard `Dispatcher::VERBS` key == `contract.verb` — removes the two name-restatements ADR 0063 left as reconciled-not-derived; records `boot` as the deliberate curated+guarded exception | Accepted (ships 0.44.0) |
| [0065](./0065-finish-cli-response-shrink-escape-hatches.md) | Finish the `cli_response` projection: grow the facet to see call inputs (`uid`/`blame` envelopes) and align CLI-positional args, moving output-only escape hatches into the generated population — keeps imperative CLI code out of the contract (the alternative to "Option D") | Accepted (ships 0.44.1) |
