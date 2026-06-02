# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The **gem version** (`0.x.y`) is distinct from the **protocol version**
(currently `textus/3`, embedded in every envelope as `protocol`). A protocol
bump is a breaking change that requires a store migration; the gem version
tracks both additive improvements and breaking protocol bumps independently.

## 0.43.0 — 2026-06-02 — Typed `publish:` block + remove `index_filename` ([ADR 0052](docs/architecture/decisions/0052-typed-publish-block.md), [0053](docs/architecture/decisions/0053-remove-index-filename.md))

No `textus/3` wire-format change. Two breaking (pre-1.0) changes on the publish/enumeration surface: the two top-level publish keys become one typed `publish:` block, and the unused `index_filename:` enumeration feature is removed. Both fail at load with a migration-pointing message.

### Changed

- **BREAKING (pre-1.0): `publish_to:`/`publish_tree:` folded into one typed `publish:` block ([ADR 0052](docs/architecture/decisions/0052-typed-publish-block.md)).** Publishing is now configured by `publish: { to: [...] }` (file fan-out) **xor** `publish: { tree: "dir" }` (subtree mirror), mirroring the ADR 0049 internal sum type at the manifest layer and giving a future third mode a namespace instead of a third top-level key. Surface-only — the `Publish::*` modes, `:file_published` event, and build envelope are unchanged. A manifest using the flat `publish_to:`/`publish_tree:` keys **fails at load** with the replacement (`use publish: { to: [...] }` / `{ tree: "..." }`). This is grouping/extensibility, not a new invariant: a block with both `to:` and `tree:` is still caught by the one exclusivity guard in `Publish.resolve`.

### Removed

- **BREAKING (pre-1.0): the `index_filename:` enumeration feature is removed ([ADR 0053](docs/architecture/decisions/0053-remove-index-filename.md)).** `index_filename:` let a nested entry enumerate *directories* as addressable keys via a fixed index file (e.g. `SKILL.md`). It had zero real usage, its only motivating consumer (`EachDir` per-leaf publish) was removed in 0.42.0, and it could not compose with `publish_tree` (mutually exclusive). A nested entry now always enumerates each file under its tree as a key (key segments derived from the path, extension stripped). A manifest declaring `index_filename:` **fails at load** with a migration message; to mirror a directory of files to a consumer path without enumerating them as keys, use `publish: { tree: "..." }`. Native skill authoring (ADR 0050) is unaffected — it rides `publish_tree`, which never enumerated an index. The shallowest-index-wins claiming logic (ADR 0046 D5) and the `index_filename ⊥ publish_tree` guard go with it.

No `textus/3` wire-format change — repo-local publish behaviour only.

### Fixed

- **`publish_tree` files are now opaque in *every* path, not just the Publisher ([ADR 0047](docs/architecture/decisions/0047-publish-tree-keyless-subtree-mirror.md)).** A keyless subtree mirror carrying non-key-legal filenames (uppercase `SKILL.md`, `README`) tripped `doctor`'s `key.illegal` and red-gated commits, even though publish itself mirrored the files correctly — `doctor`'s `IllegalKeys` and `Resolver#enumerate_nested` still key-walked them, contradicting ADR 0047's "no keys" contract. The resolved publish mode now answers `Publish::Mode#keyless?` (true only for `Tree`); both paths consult it and skip enumerating a keyless mirror's files. A `publish_tree` subtree with uppercase filenames stays `doctor`-green and still mirrors; a non-publish nested entry still flags illegal segments as before.

## 0.42.0 — 2026-06-02 — Remove `publish_each`: collapse publish to two modes ([ADR 0051](docs/architecture/decisions/0051-remove-publish-each.md))

No `textus/3` wire-format change. **Breaking (pre-1.0):** the `publish_each:` manifest key is removed; a manifest declaring it now fails at load. The publish surface collapses to two modes — `publish_to:` (fixed paths) and `publish_tree:` (whole-subtree mirror) — plus `None`.

### Removed

- **BREAKING (pre-1.0): the `publish_each:` publish mode is removed ([ADR 0051](docs/architecture/decisions/0051-remove-publish-each.md)).** Both the file-leaf and directory-leaf (`index_filename`-driven) forms of `publish_each` are gone, along with the `Publish::Each` / `EachFile` / `EachDir` modes and their `{leaf}`/`{basename}`/`{key}`/`{ext}` template vocabulary. The mode had zero real-world usage (dogfood, example, and `init` scaffold all publish via `publish_to`), and its one niche — a leaf that is both an addressable key *and* published to a per-leaf templated path — never materialized, including in the native skill-authoring pipeline (ADR 0050), which rides `publish_tree`. A manifest declaring `publish_each:` now **fails at load** with a migration message ("publish_each was removed in 0.42.0 (ADR 0051) — mirror the subtree with publish_tree (and index_filename to keep the index addressable)"). **Migration:** a directory-leaf `publish_each: "skills/{leaf}"` over a `nested` skills entry becomes `publish_tree: "skills"` over the parent entry (layout preserved). `index_filename:` is **kept** — it survives as a pure *enumeration* feature, independent of publish. The ADR 0049 sum type makes re-adding one subtree mode (or lifting `index_filename` ⊥ `publish_tree` so the two compose) a cheap one-arm change if the niche ever appears.

## 0.41.0 — 2026-06-02 — `publish_tree` subtree mirror + content-identical publish adoption ([ADR 0047](docs/architecture/decisions/0047-publish-tree-keyless-subtree-mirror.md), [0050](docs/architecture/decisions/0050-native-authoring-and-content-identical-adoption.md))

No `textus/3` wire-format change — every change here is repo-local publish behaviour or internal re-layering. Headlines: a key-less `publish_tree:` subtree mirror (ADR 0047), and publish now *adopts* a byte-identical pre-existing target instead of refusing (ADR 0050), so an artifact tree already on disk onboards without a manual delete. Internals were re-cut along the way (fetch subsystem, ADR 0048; publish modes as a sum type, ADR 0049) with no contract change.

### Added

- **`publish_tree:`** — a key-less, path-driven subtree mirror for `nested` entries: copies a whole stored directory to one target dir (layout preserved, per-file sentinels, `ignore`-filtered, whole-target prune). Unblocks publishing the sibling tree of a leaf whose index file is *derived* (issue #132 item #4). Additive; no protocol change. New `doctor` check `publish.tree_index_overlap`. See [ADR 0047](docs/architecture/decisions/0047-publish-tree-keyless-subtree-mirror.md).

### Changed

- **Fetch subsystem re-layered so its three concerns each have one home ([ADR 0048](docs/architecture/decisions/0048-fetch-subsystem-three-concerns.md)).** Internal refactor, no wire or hook-contract change: the before-etag now routes through the `FileStore` port (a guard spec keeps `read/`+`write/` from regressing); a single `IntakeFetch` kernel owns "invoke the intake handler under a deadline" and always passes a uniform `caps: <Container>` to `:resolve_intake`; the fetch lifecycle event vocabulary moves into one `FetchEvents` seam shared by `FetchWorker` and `FetchOrchestrator`. Public verbs, hook events, and the `textus/3` wire contract are unchanged.
- **Publish modes re-cut into a resolved sum type ([ADR 0049](docs/architecture/decisions/0049-publish-modes-as-sum-type.md)).** Internal refactor, no manifest key, wire, event, or `doctor` change: each entry now resolves once to one `Manifest::Entry::Publish::*` mode (`None` / `ToPaths` / `EachFile` / `EachDir` / `Tree`) that owns its publish algorithm, replacing the nil-cascade selector on `Nested`. Mode exclusivity is structural — one `UsageError` naming the conflicting keys, in place of the four scattered pairwise guards across two validators. `EachDir` and `Tree` share one `SubtreeMirror` (one walk, one prune) whose `ignore`-in-prune difference (ADR 0047 D4) is now the explicit `prune_honors_ignore:` parameter. The three manifest keys and every published-leaf / `:file_published` shape are unchanged.
- **Publish adopts a byte-identical pre-existing target instead of refusing ([ADR 0050](docs/architecture/decisions/0050-native-authoring-and-content-identical-adoption.md)).** The clobber guard now fires only when an unmanaged target's content **differs** from the source (or it's an unmanaged symlink); an identical target is *adopted* — its sentinel is written, the file is untouched — so an artifact tree already on disk (e.g. an Agent Skill authored in its native shape, issue #132) onboards to textus without a manual delete. Narrows `SPEC.md` §491; reuses the sha already stored in the sentinel; no new manifest key, CLI flag, hook event, or build-envelope field, and no protocol change.

## 0.40.0 — 2026-06-02 — `publish_each` owns multi-file leaf subtrees ([ADR 0046](docs/architecture/decisions/0046-publish-leaf-subtrees.md))

No `textus/3` wire-format change — publish is repo-local materialization. The
publish *unit* is derived from the entry's existing `index_filename`, not a new
manifest key (SPEC §4, §5.3).

### Added

- **`publish_each` copies a leaf's whole subtree when the entry declares `index_filename` ([ADR 0046](docs/architecture/decisions/0046-publish-leaf-subtrees.md)).** textus can now own a prose-heavy, multi-file artifact (e.g. a Claude Code Agent Skill: `SKILL.md` + `commands.md` + `references/*`) as a single addressable unit. An entry *without* `index_filename` still publishes one file per leaf (unchanged); an entry *with* `index_filename` treats each leaf as a directory and copies the whole subtree — ignore-filtered (ADR 0042), preserving in-leaf layout, one sentinel per file. Siblings ride along at publish time only: they are never enumerated, addressable, or proposable (the key↔path bijection is preserved). On rebuild, managed orphans under a leaf are pruned (file + sentinel); **unmanaged files are never deleted**. The build envelope grows a `pruned` array.
- **`doctor` flags orphaned publish targets.** A new `orphaned_publish_targets` check reports a published file whose recorded source no longer exists in the store (a renamed or removed whole leaf) — drift that per-entry `build` won't revisit.

### Changed

- **BREAKING (pre-1.0): directory-leaf `publish_each` semantics ([ADR 0046](docs/architecture/decisions/0046-publish-leaf-subtrees.md)).** An entry with `index_filename` + `publish_each` whose leaf directories contain siblings previously published *only the index file*; it now publishes the whole subtree. This breaks no correct usage — it is either the dropped-siblings defect this fixes, or a template that named a file rather than a directory, which the validator now **rejects loudly** at manifest load. **Migration:** a directory-leaf `publish_each` template must name the target *directory* — drop a trailing index filename (`.../{leaf}/SKILL.md` → `.../{leaf}`) or any file extension (`.../{leaf}.md` → `.../{leaf}`), and use `{leaf}` or `{key}` (not `{basename}`/`{ext}`, which are file-only).
- **Role names are now a closed set `{human, agent, automation}` ([ADR 0045](docs/architecture/decisions/0045-close-role-name-set.md)).** A manifest declaring any other role name is rejected at load with `unknown role name '<x>' (allowed: human, agent, automation)`. `Role::NAMES` is the single source of truth; each role's `can:` capabilities remain fully tunable. Principal multiplicity moves to the `owner:` field (`owner: human:patrick`). Stricter `textus/3` validation in `Schema.validate_roles!` — no protocol bump; all shipped manifests already comply.
- **Hook event tables consolidated into `Textus::Hooks::Catalog` (single source
  of truth).** `EventBus` and `RpcRegistry` no longer keep their own event
  tables; both registries, the Loader DSL router, and internal consumers read
  `Catalog::PUBSUB` / `Catalog::RPC` directly. This removes the drift-prone
  `EventBus::RPC_EVENTS` literal that could silently fall out of sync with
  `RpcRegistry`'s events and weaken the cross-registry guards. Internal
  refactor — no `textus/3` wire-format change.

## 0.39.1 — 2026-06-01 — Feed ergonomics: `feeds.machine` env snapshot + intake cookbook ([ADR 0043](docs/architecture/decisions/0043-feed-ergonomics-without-breaking-core-purity.md))

No `textus/3` wire-format change. `textus init` scaffolds an additional
`nested` feed entry; core intake still makes no implicit network calls
(SPEC §5.4).

### Added

- **`textus init` scaffolds `feeds.machines.*` with a local env snapshot
  (ADR 0043).** Generated stores get a `nested` feed entry capturing ambient
  machine context (git HEAD/branch/dirty state, `now`, versions) as an explicit,
  user-owned snapshot — keeping ambient state out of `boot`/`pulse` (which stay
  side-effect-free per ADR 0037) and out of `quarantine` (which means external
  bytes pending validation, where the freshness model does not apply).

### Documentation

- **Multi-machine environment-scan cookbook recipe** demonstrating the nested
  `feeds.machines.*` pattern.
- **Examples** updated to use the `feeds.machine` env snapshot, matching
  `textus init` output.
- **README flow diagram** redesigned to group writers and colour-code roles.
- **How-to fixes** for zone-rename drift in the agents-mcp guide and the
  `:publish` event name.

### Internal

- Removed the legacy `ARCHITECTURE.md` redirect stub.

## 0.39.0 — 2026-06-01 — Native ignore patterns for entry enumeration ([ADR 0042](docs/architecture/decisions/0042-native-ignore-patterns-for-entry-enumeration.md))

No `textus/3` wire-format change. Manifest schema gains one optional, backward-compatible key (`ignore:`); existing manifests are unaffected.

### Added

- **Per-entry `ignore:` globs on `nested` entries (ADR 0042).** A `nested`
  entry may declare a list of gitignore-style globs (e.g.
  `["**/node_modules/**", "**/dist/**"]`) to keep vendored or generated
  subtrees out of the store. Patterns are honoured by **one shared filter
  seam** consulted by both resolver enumeration (`list`, `build`) and
  `textus doctor`, evaluated *above* key-legality: an ignored path is excluded,
  never judged. This closes the prior divergence where a store could `list`
  cleanly while `doctor` was red on the same vendored paths. Matching is
  segment-wise globstar — `**` spans zero or more path segments; within a
  segment `*` is anchored and `{a,b}` alternates (stdlib `File.fnmatch`,
  no new dependency). Documented in
  [`docs/reference/zones.md`](docs/reference/zones.md#nested-entries).

### Internal

- **Dogfood textus in its own repo ([ADR 0041](docs/architecture/decisions/0041-dogfood-textus-in-its-own-repo.md)).**
  A self-development store and MCP wiring for textus's own repository. No change
  to the published gem's behavior.

## 0.38.0 — 2026-05-31 — MCP serve acts as agent by default ([ADR 0040](docs/architecture/decisions/0040-mcp-connection-role-and-two-channels.md))

No `textus/3` wire-format change; no manifest-schema change.

### Changed

- **The MCP connection acts as the `agent` role by default (ADR 0040).**
  `textus mcp serve` now resolves its acting role through the standard chain
  (`--as` → `TEXTUS_ROLE` → `.textus/role`) with an `agent` transport default,
  instead of silently inheriting the global `human` default. The agent channel
  proposes; human authority (accept/reject, direct writes) is exercised through
  the human's own CLI.

### Breaking

- **MCP writes that relied on human authority now require `propose` + `accept`,
  or an explicit `--as=human`.** A connection that previously `put` straight into
  `working/`/`identity/` over MCP will get `write_forbidden`. Launch
  `textus mcp serve --as=human` (or set `TEXTUS_ROLE`/`.textus/role`) to restore
  the old behavior knowingly; the gate is then advisory.

## 0.37.0 — 2026-05-31 — MCP catalog derive-or-guard ([ADR 0039](docs/architecture/decisions/0039-mcp-catalog-derive-or-guard.md))

No `textus/3` wire-format change; no manifest-schema change.

### Changed

- **MCP catalog is now derived from one per-verb contract (ADR 0039).** Each
  use-case declares its interface once (`verb`/`summary`/`surfaces`/`arg`/`response`);
  the MCP `tools/list` schemas and `tools/call` dispatch are generated from it.
  The hand-written `Tools::REGISTRY` and `ToolSchemas` array are gone — a core
  interface change can no longer leave MCP silently stale (it is derived, or a
  guard spec fails the build).

### Added

- **`propose` and `rules` are first-class verbs** (Ruby/MCP; `propose` also CLI),
  no longer MCP-only composed tools. MCP is now a pure projection of the core
  verb set filtered by `surfaces(:mcp)`.

### Removed

- **Examples consolidated to a single reference.** Removed `examples/hello/` and
  `examples/claude-plugin/`, keeping `examples/project/` as the one worked example —
  the role gate (propose → accept), build/publish to `CLAUDE.md`/`AGENTS.md`, schemas,
  a template, and a `:transform_rows` hook in one place. The `skill_fanout` recipe
  sidecar, its spec, and the `docs/recipes/` page that existed only to document it are
  removed alongside. All living docs and `boot`'s `docs.example` now point at
  `examples/project/`.

### Breaking

- **MCP `schema` tool is keyed by entry `key`, not `family`.** It routes through
  the `schema` (SchemaEnvelope) verb. Callers passing `{ "family": "..." }` must
  pass `{ "key": "..." }` instead.
- **The dispatcher verb `schema_envelope` is renamed `schema`.** Ruby callers
  using `store.as(role).schema_envelope(key)` must use `store.as(role).schema(key)`.

## 0.36.0 — 2026-05-31 — Transports as pure framings: one verb vocabulary, one session, lifted to core ([ADR 0036](docs/architecture/decisions/0036-transports-as-pure-framings.md))

No `textus/3` wire-format change; no manifest-schema change.

### Changed (BREAKING)

- **MCP tool names aligned with the CLI/Ruby verb vocabulary.** The five renamed tools adopt
  the canonical core names: `tick`→`pulse`, `find`→`list`, `read`→`get`, `write`→`put`,
  `fetch_stale`→`fetch_all`. The `textus/3` wire format is unchanged; agents that discover
  tools via `tools/list` (the documented pattern) adapt automatically. Hardcoded tool names
  in `.mcp.json` files, prompts, or scripts must be updated.

### Added

- **First-class CLI `propose` verb** — `textus propose KEY --as=ROLE [--stdin]` auto-prefixes
  the manifest's `propose_zone`, matching what the MCP `propose` tool has always done. The
  previous workaround (`textus put proposals.KEY --as=ROLE`) still works but the caller no
  longer needs to know the queue zone name.
- **Stateful `textus pulse` (no `--since`)** — when `--since` is omitted, `pulse` reads and
  updates a per-role cursor from `.textus/.state/cursor.<role>` (gitignored). Successive
  invocations see only what changed since the last look, without hand-tracking a sequence
  number. `--since=N` remains the explicit, stateless override.
- **`Textus::Session`** — the agent session (role + cursor + propose_zone + manifest_etag,
  with cursor-advance, `ContractDrift` / `CursorExpired` detection) is now a core value
  object, not MCP-internal state. `MCP::Session` is now an alias to it.
- **`Store#session(role:)`** — returns a `Textus::Session` for Ruby embedders; the
  documented Ruby agent loop uses it instead of hand-tracking `since:`.

## 0.35.2 — 2026-05-31 — Evaluation field rename + Container doc fix (internal)

No `textus/3` wire-format change; no manifest-schema change; no library behavior
change. Internal refactor and documentation correction only.

### Changed

- `Domain::Policy::Evaluation` now names its manifest member `manifest` directly
  instead of declaring it `snapshot` and exposing it through a `def manifest =
  snapshot` alias. Every predicate already read `eval.manifest`; the field now
  matches its only call name.
- Dropped the unused `def role = actor` alias on `Evaluation` (zero readers; the
  real field `actor` is used everywhere).

### Fixed

- Architecture doc (`docs/architecture/README.md`) listed an `:authorizer` member
  on `Container` that the code does not have. Removed it so the doc matches
  `lib/textus/container.rb` (7 fields).



No `textus/3` wire-format change; no manifest-schema change; no library behavior change.
Test-suite maintenance only.

### Changed

- Removed redundant per-file `include TextusSpecHelpers` lines (the module is
  globally included via `spec/support/fixtures.rb`).
- Envelope-writer specs now assert audit side-effects through the shared
  `have_audit_verb` / `last_audit_row` helpers instead of raw `audit.log`
  JSON substring matching.

### Fixed

- `pulse_queue_zone` spec no longer leaks a temp directory per run (its second
  store now builds under the `textus_store_fixture` tmp tree, which is cleaned up).

## 0.35.0 — 2026-05-31 — Proposal target-zone constraint + `author_held` ([ADR 0035](docs/architecture/decisions/0035-proposal-target-zone-constraint.md))

No `textus/3` wire-format change; no manifest-schema change.

### Changed (BREAKING)

- **`accept` now refuses a proposal whose `target_key` is not a `canon` zone** (new floor
  predicate `target_is_canon`). Previously such a proposal failed confusingly downstream
  (accept-into-derived) or incoherently "succeeded" (accept-into-workspace). Refusals surface
  as `guard_failed` naming `target_is_canon`.
- **Predicate `author_signed` renamed to `author_held`** — it checks possession of the `author`
  capability, not a signing gesture. `guard_failed` output and any `rules[].guard` referencing
  the old name change accordingly.

### Added

- **`doctor` check `proposal_targets`** — warns on queued proposals whose `target_key` is
  non-canon (`proposal.target_not_canon`) or unresolvable (`proposal.target_unresolved`).

## 0.34.0 — 2026-05-31 — Unify the Lane vocabulary + finish boot's kind-derived zone naming ([ADR 0034](docs/architecture/decisions/0034-unify-lane-vocabulary.md))

No `textus/3` wire-format change; no manifest-schema change. The five zone-kinds and five
capabilities, their names, and their mapping are identical to 0.33.0.

### Changed

- **One `Schema::LANES` table is now the source of truth** for the closed coordination
  vocabulary; `ZONE_KINDS`, `CAPABILITIES`, and `KIND_REQUIRES_VERB` are derived from it, so a
  zone-kind and its required capability can no longer drift. (`CAPABILITIES` array ordering
  now follows `LANES.values`; no behaviour depends on it.)
- **`boot` names zones by kind, not by hardcoded instance.** `write_flows`, the
  `agent_protocol` recipes, and the CLI verb catalog now reflect the live store
  (`knowledge`/`notebook`/`feeds`/`proposals`/`artifacts`) and survive zone renames —
  completing the rename-fragility fix [ADR 0033](docs/architecture/decisions/0033-complete-primitives-and-vocabulary.md) §6 began for `ZONE_PURPOSES`.
- **`keep`-holders now get a `notebook` write-flow in `boot`.** 0.33 added the `keep`
  capability but no boot guidance for it; the agent's durable-lane flow was silently omitted.

### Fixed

- **`pulse` `pending_review` was silently empty on default stores since 0.33.** It hardcoded
  the pre-0.33 zone name `review`; it now derives the queue zone from the manifest, so it
  surfaces pending proposals from the (default-named) `proposals` zone again.

### Removed (BREAKING, internal)

- **`Manifest::Data#zones`** (the unused `name => []` map) is removed; the four internal
  readers now use `Manifest::Data#declared_zone_kinds`. No manifest-schema or wire change.

## 0.33.0 — Complete primitives + vocabulary (ADR 0033) — 2026-05-31

**BREAKING (manifest schema + default scaffold + predicate/error names; `textus/3` wire format UNCHANGED):**
- New coordination primitive: `workspace` zone-kind + `keep` capability — agents get a durable self-owned lane (`notebook` in the default scaffold). Closes the agent-memory gap.
- Renamed capability `accept` → `author` (the `accept` *transition* / CLI verb is unchanged); predicate `accept_signed` → `author_signed`; zone-kind `origin` → `canon`.
- Default scaffold renamed: `identity` + `working` → `knowledge` (identity is now the `knowledge.identity.*` key prefix), `intake` → `feeds`, `review` → `proposals`, `output` → `artifacts`; new `notebook` workspace zone.
- Zones may declare optional `owner:` (informational) and `desc:` (surfaced as the boot zone purpose).
- Manifests using `origin` / `accept` (capability) / `accept_signed` get an unknown-value rejection at load — no aliasing.
- The `textus/3` envelope, audit-log, and key-grammar wire formats are unchanged.

## 0.32.1 — 2026-05-30

### Internal

- Test-suite cleanup for the unified-Guard specs (no `lib/` change): the new Guard/predicate/write specs now use the shared `textus_store_fixture` context plus a single `store_from_manifest` helper (replacing 9 per-file `build_*_store` methods and hand-rolled `Dir.mktmpdir` nesting), a `fail_guard_with` matcher for `GuardFailed` assertions, and uniformly mockist predicate unit specs (`zone_writable_by_spec` joins `accept_signed_spec`/`schema_valid_spec`).

## 0.32.0 — 2026-05-30

Unified Guard engine ([ADR 0031](docs/architecture/decisions/0031-unified-guard.md), moves 2 & 3 of [ADR 0028](docs/architecture/decisions/0028-coordination-planes.md)), plus dropping the never-enforced read gate ([ADR 0032](docs/architecture/decisions/0032-drop-read-policy.md)). Every write transition now authorizes through **one Guard** — an ordered list of pure predicates over a single `Evaluation` context. No wire format (`textus/3`) change; the manifest schema and error envelopes change (breaking).

### Changed (BREAKING)

- **Manifest `rules[].promotion: { requires: [...] }` is removed; use `rules[].guard: { accept: [...] }`.** A `guard:` block is a map of transition (`put`/`delete`/`mv`/`accept`/`reject`/`fetch`) → predicate list, composed (AND) onto each transition's built-in base guard. A stale `promotion:` key is now rejected at load (unknown key).
- **Authorization is unified into one Guard** (ADR 0031). Promotion / accept-authority / schema failures now surface as `guard_failed` naming the unmet predicate(s); the topology refusal keeps the `write_forbidden` code and `--as=<role>` hint. Custom/vendored predicates must use the `#call(Evaluation)` signature.
- **`read_policy` is removed from the manifest** (ADR 0032): textus gates writes, not reads. `Domain::Authorizer` and `ReadForbidden` are gone. Reads are unrestricted at the protocol layer (the `.textus/` files are on disk); per-role read-scoping, if needed, is an agent-surface projection, not a manifest field.

### Internal

- New `Domain::Policy::{Evaluation, Guard, GuardFactory, BaseGuards}` and `Predicates::{Registry, ZoneWritableBy, EtagMatch, FreshWithin}`; `Predicates::{AcceptSigned, SchemaValid}` reshaped to `#call(Evaluation)`. `Domain::Policy::{Promotion, Promote}` and `Write::AuthorityGate` are deleted (folded into the Guard + single `Predicates::REGISTRY`). `Manifest::Rules` `RuleSet` gains `guard`, loses `promote`. `Permission` collapses to `(zone, writers)`.

## 0.31.0 — 2026-05-30

Capability-based roles and the `refresh`→`fetch` transition rename ([ADR 0030](docs/architecture/decisions/0030-capability-based-roles.md)). No wire format (`textus/3`) change; the manifest schema changes (breaking) and the data-in transition is renamed.

### Changed (BREAKING)

- **Roles are now capability-based.** A role declares `can: [verbs]` over a closed 4-verb set — `propose`, `accept`, `fetch`, `build` — replacing the 1:1 `role → kind` model. The role-kinds `accept_authority`/`proposer`/`generator`/`runner` are gone, as are the role names `runner` and `builder` (the umbrella automated role is now `automation`). Default mapping (when no `roles:` block is declared): `human=[accept, propose]`, `agent=[propose]`, `automation=[fetch, build]`.
- **Per-zone `write_policy:` is removed.** Write authority is **derived** from the role's capabilities × the zone's kind: a role may write a zone iff it holds the verb that kind requires — `queue→propose`, `origin→accept`, `quarantine→fetch`, `derived→build`. Zones now declare only `kind:` (and optional `read_policy:`). A manifest carrying `write_policy:` is rejected at load (unknown key).
- **`accept` is the single trust anchor:** at most one role may hold the `accept` capability. The `accept`/`reject` gate and the `maintained_by` override key on the `accept` capability rather than a hard-coded role kind. The promotion predicate `:accept_authority_signed` (and the older `:human_accept`) is renamed `:accept_signed`.
- **The `refresh` transition is renamed `fetch`.** CLI `textus fetch` / `textus fetch stale` (was `refresh` / `refresh stale`); the rule block `refresh:` is now `fetch:`; events `:refresh_started`/`:refresh_failed`/`:refresh_backgrounded`/`:entry_refreshed` are `:fetch_started`/`:fetch_failed`/`:fetch_backgrounded`/`:entry_fetched`; the freshness meta field `last_refreshed_at` is `last_fetched_at`, the freshness verdict `never_refreshed` is `never_fetched`, and the envelope's `refreshing?`/`fetching` field is `fetching`. The MCP tools `refresh`/`refresh_stale` are `fetch`/`fetch_stale`.
- `WriteForbidden` now reports the missing capability: `writing '<key>' (zone '<zone>') needs capability '<verb>'`, with a hint naming the roles that hold it (or `no declared role`).

### Internal

- `Manifest::Capabilities` (was `RoleKinds`) resolves `roles:` to `{ name => [verbs] }`; `Manifest::Data#role_caps` replaces `#role_mapping`. `Manifest::Policy` gains `verb_for_zone`, `roles_with_capability`, `proposer_role`, and derives `zone_writers` from capabilities × zone-kind; `role_kind`/`roles_with_kind`/`role_mapping` are removed. Schema validates the capability vocabulary, the ≤1-`accept` invariant, and that every declared zone-kind's required verb is held by some role.
- The `refresh`→`fetch` rename is mechanical across the engine: `Write::{FetchWorker,FetchAll,FetchOrchestrator}`, `Read::GetOrFetch`, `Domain::Policy::Fetch`, `Ports::Fetch::{Lock,Detached}`, `Domain::Policy::Predicates::AcceptSigned`, `Outcome::Fetched`, and the dispatcher verb keys.

## 0.30.0 — 2026-05-29

Explicit zone kind (strict) and entry retention (ADR 0028, moves 1 & 4). No wire format (`textus/3`) change.

### Changed (BREAKING)

- Zone `kind:` is now **required** on every zone (`origin | quarantine | queue | derived`); a manifest with a kind-less zone is rejected at load. The kind is authoritative: a zone is `derived` only if it declares `kind: derived`, and proposals route only to the zone declaring `kind: queue`. The previous writers→kind inference, the `"review"`-name proposal fallback, and boot's arbitrary-zone propose default were removed. No `textus/3` wire-format change; existing manifests must add `kind:` to every zone.

### Added

- `Manifest::Policy#declared_kind`, `#queue_zone`, `#derived_zone?`. `propose_zone_for` now resolves through the declared `queue` zone exclusively.
- `retention:` rule block (`expire_after`, `archive_after`) parsed into `Domain::Policy::Retention`. New `textus retain --as=ROLE` sweep expires (deletes) or archives leaves past their window — `expire_after` deletes, `archive_after` copies to `.textus/archive/` then deletes; age is the leaf's mtime. `--prefix`/`--zone` narrow the sweep; rows whose zone the role can't write surface as failures. Retention appears in `textus rule explain`.
- `Textus::Domain::Duration.seconds` — shared duration parser (`30s`/`90m`/`12h`/`30d`/bare seconds), now also backing `Refresh#ttl_seconds`.

### Internal

- `Manifest::Entry::Base#in_generator_zone?` and `boot` derived/proposal detection route through `Policy#derived_zone?` / `#propose_zone_for`; all `"review"` substring matches and the `Policy#zone_kinds` inference method are removed.
- Dead `Policy#zone_kinds` method removed.

## 0.29.2 — 2026-05-29

Hook-registry convergence and MCP transport de-leak (ADR 0027). Every change is additive or internal — no wire format (`textus/3`) or manifest-schema change, no public class renamed or removed.

### Added

- `Textus::Hooks::Signature` — single home of callable keyword-introspection (`accepts_keyrest?`, `declared_keys`, `missing`, `filter`), shared by both `EventBus` and `RpcRegistry`.
- `Manifest::Policy#propose_zone_for(role)` — owns the "first writable zone whose name contains `review`" convention; `MCP::Server#handle_initialize` delegates to it instead of scanning `manifest.data.zones` inline.

### Internal

- `EventBus` and `RpcRegistry` both delegate callable introspection to `Hooks::Signature`; both `shape_check!` copies and the hand-rolled `filter_kwargs`/`invoke` derivations are deleted.
- Removed the `store:`→`caps:` legacy shim from `RpcRegistry`: a handler declaring `store:` (instead of `caps:`) is now rejected at registration time with an honest message, not at invoke time. Stale in-repo RPC hook fixtures and the `textus init` scaffold example are migrated to `caps:`.
- `MCP::Server#handle_initialize` no longer iterates `manifest.data.zones`; it calls `policy.propose_zone_for(proposer)`. No zone-selection logic remains in the JSON-RPC transport handler.
- `MCP::Session` converted from a hand-rolled immutable class to `Data.define(:role, :cursor, :propose_zone, :manifest_etag)`, matching the house convention used by all other value objects.

### Behavior change (non-breaking in practice)

- RPC handlers declaring `store:` previously registered successfully and failed only at first invocation (with a misleading message). They now fail at registration time with a message naming the correct kwarg (`caps:`). No handler using `store:` was valid before; only the timing and clarity of the error change.

## 0.29.1 — 2026-05-29

Construction-side cleanup of the use-case layer (ADR 0026). Every change is additive or internal — no public class renamed or removed, wire format (`textus/3`) and CLI unchanged.

### Added

- `Envelope::IO::Writer.from(container:, call:)` and `Envelope::IO::Reader.from(container:)` — named constructors that build the envelope IO collaborators from a `Container`. `Writer.new`/`Reader.new` are unchanged.
- `Write::IntakeFetch.invoke(rpc:, handler:, config:, args:, label:, timeout:)` — the transport-side "invoke a `:resolve_intake` handler under a timeout" kernel; now the canonical home of `FETCH_TIMEOUT_SECONDS`.
- `Dispatcher.invoke(verb, container:, call:, args:, kwargs:)` — single home for the uniform use-case invocation protocol.

### Internal

- `Write::{Put,Delete,Mv,RefreshWorker}` no longer hand-wire `Envelope::IO::Writer`/`Reader`; they call `Writer.from`. Removed ~60 lines of byte-identical construction boilerplate.
- `cli/verb/put.rb` (`--fetch`) and `cli/verb/hook_run.rb` no longer inline `Timeout.timeout { store.rpc.invoke(:resolve_intake, …) }`; both route through `Write::IntakeFetch`. No intake-fetch mechanics remain under `lib/textus/cli/`.
- `RoleScope`'s verb loop delegates the instantiate-and-call step to `Dispatcher.invoke`; it still builds the `Call`. `Store`'s role-selecting verb loop is unchanged.
- `RefreshWorker::FETCH_TIMEOUT_SECONDS` is now an alias of `IntakeFetch::FETCH_TIMEOUT_SECONDS`.

## 0.29.0 — 2026-05-29

A domain-purity pass that routes all filesystem and wall-clock I/O through injected ports. Breaking changes are Ruby-API only; the wire format (`textus/3`) and CLI are unchanged.

### Breaking

- `Domain::Staleness#initialize` now requires `file_stat:` and `clock:` (was `manifest:` only).
- `Domain::Staleness::IntakeCheck#initialize` now requires `file_stat:` and `clock:`.
- `Domain::Staleness::GeneratorCheck#initialize` now requires `file_stat:` (no clock — `GeneratorCheck` has no wall-clock dependency).
- `Domain::Sentinel` is now a pure value object. Its persistence class methods (`write!`, `load`, `sentinel_path`) and `SUFFIX`/`DIR` constants have moved to the new `Ports::SentinelStore`.
- `Domain::Sentinel#orphan?` and `#drift?` now take a `file_stat` argument.
- `Textus::Boot.run_via(container:, role:)` → `Textus::Boot.build(container:)` (the `role:` parameter was unused).
- `Textus::Doctor.run_via(container:, role:, checks:)` → `Textus::Doctor.build(container:, checks:)` (the `role:` parameter was unused).
- `RoleScope#boot` / `#doctor` are removed as special cases; `boot` and `doctor` are now entries in `Dispatcher::VERBS`. `store.boot`, `store.doctor`, and `store.as(role).boot` are unchanged.

### Added

- `Ports::Storage::FileStat` — read-only filesystem query port (`exists?`, `directory?`, `read`, `mtime`, `glob`); the narrow interface pure domain logic depends on (distinct from the write-side `FileStore`).
- `Ports::SentinelStore` — sentinel persistence + path-layout adapter, extracted from `Domain::Sentinel`.
- `Read::Boot` and `Read::Doctor` — dispatched use-case classes on the uniform `(container:, call:)` shape.

### Changed

- `manifest_etag` (in `pulse` output and the MCP session drift token) is now the system-standard `sha256:`-prefixed etag, computed via `FileStore#etag`, instead of a bare SHA-256 hex digest. The token is opaque (compared for equality, never parsed).

### Internal

- The domain layer no longer performs direct filesystem or wall-clock I/O; all disk/clock access is routed through injected ports (`FileStat`, `Clock`). Enforced by a new `spec/domain_purity_spec.rb` that fails on any regression.
- Freshness request timestamps now originate from `Ports::Clock` (via `Call.build`) rather than a bare `Time.now`.
- Cosmetic refactors: deduped the audit limit guard; made `RefreshWorker.normalize_action_result` a public class method (dropped a `send`); extracted staleness guard helpers.
- New guard spec `spec/no_handrolled_manifest_etag_spec.rb` forbids `Digest::SHA256.hexdigest(File.read(...))` from reappearing in `lib/` (exempt: `etag.rb` and `sentinel_store.rb`, the latter being a wire-pinned integrity checksum, not an etag).
- See [ADR 0024](docs/architecture/decisions/0024-domain-purity-ports.md) for the design rationale.

## 0.28.0 — 2026-05-29

A consistency-and-cleanup pass that finishes the seams [ADR 0022](docs/architecture/decisions/0022-container-call-dispatcher.md) left behind. Breaking changes are Ruby-API only.

### Breaking

- Use-case constructors no longer accept `hook_context:`. Use cases that emit events derive their `Hooks::Context` internally from `(container, call)` via the new `Textus::Hooks::Context.for(container:, call:)` factory. Every use case now has the uniform shape `def initialize(container:, call:)`.
- `Textus::Envelope::IO::Writer` and `Textus::Write::RefreshOrchestrator` constructors take `call:` instead of `ctx:` (both received a `Call` already; the kwarg name is corrected).
- `Read::Audit#call` now accepts filter keywords and builds a `Read::Audit::Query` value object internally — keyword callers (`store.audit(key:, limit:)`) are unchanged.
- `Builder::Pipeline.run` takes `(mentry:, deps:)` where `deps` is a `Builder::Pipeline::Deps` record, instead of eight loose keyword collaborators.
- Removed the `CLI::VERBS` const-missing shim (use `CLI.verbs`).
- Removed the `Manifest::Entry::PUBLISH_EACH_VARS` / `PUBLISH_EACH_VAR_RE` re-exports (use `Manifest::Entry::Validators::PublishEach::KNOWN_VARS` / `::VAR_RE`).

### Internal

- Removed the runtime `initialize`-parameter reflection from both `RoleScope` and `Doctor::Check`; verb dispatch is now an unconditional `klass.new(container:, call:).call(...)`.
- `Lint/UnusedMethodArgument` disables dropped from 27 to 20; two `Metrics/ParameterLists` (and two complexity) disables removed by the value-object refactors. `Metrics/ParameterLists` ceiling documented and kept at `Max 6` (the honest ceiling for value-object constructors, `AuditLog#append`, and the public `put` API).
- `ARCHITECTURE.md`'s "uniform `(container:, call:)`" claim is now accurate; active docs refreshed to the 0.27/0.28 vocabulary.
- No wire-format change. Protocol stays at `textus/3`. CLI verb signatures unchanged. Hook callable surfaces (`ctx:` for pub-sub, `caps:` for RPC) unchanged.
- See [ADR 0023](docs/architecture/decisions/0023-uniform-use-case-shape.md) for the design rationale.

## 0.27.0 — 2026-05-29

### Breaking

- Removed `Textus::Session`. Use `store.as(role).put(...)` or `store.put(..., role:)` instead of `store.session(role:).put(...)`.
- Removed `Textus::Application::UseCase` registry. Verb dispatch is now via the static `Textus::Dispatcher::VERBS` table.
- Replaced `Textus::Application::ReadCaps` / `WriteCaps` / `HookCaps` with a single `Textus::Container` record (field names preserved: `manifest`, `file_store`, `schemas`, `root`, `audit_log`, `events`, `rpc`, `authorizer`).
- Renamed `Textus::Application::Context` to `Textus::Call`. Field shape identical.
- Use-case classes are no longer `module Foo; def self.call; Impl.new(...).call; end`. They are plain classes: `class Foo; def initialize(container:, call:); def call(...); end`.
- Flattened `Textus::Application::Write::*` → `Textus::Write::*`, `Application::Read::*` → `Read::*`, `Application::Envelope::*` → `Envelope::IO::*`, `Application::Maintenance::*` → `Maintenance::*`, `Application::Projection` → `Projection`.
- Renamed `Textus::Infra::*` → `Textus::Ports::*`.
- `Manifest::Entry::Base#zone_writers` / `#in_generator_zone?` / `#in_proposal_zone?` now take an explicit `policy` argument; entries no longer carry an `@manifest` back-reference.
- `PublishContext` shrunk from 12 fields to `(container, call, reader)` with derived accessors. Custom derived entries that destructured `pctx.caps` / `pctx.session` / `pctx.ctx` / `pctx.bus` need to use `pctx.container` / construct a `RoleScope` / `pctx.call` / `pctx.events`.
- Hook RPC callables (`:resolve_intake`, `:transform_rows`, `:validate`) receive `caps: container` (a `Textus::Container`) instead of `caps: <WriteCaps>`. Field names preserved, so handlers reading `caps.manifest` / `caps.events` / etc. continue to work.

### Internal

- ~600 LOC removed net across ~60 files.
- No wire-format change. Protocol stays at `textus/3`.
- CLI verb signatures unchanged. No envelope shape changes.
- See [ADR 0022](docs/architecture/decisions/0022-container-call-dispatcher.md) for the design rationale.

## 0.26.0 — 2026-05-28

### Breaking
- Split `Textus::Hooks::Bus` into `Textus::Hooks::EventBus` (pubsub) and `Textus::Hooks::RpcRegistry` (named callables). The `Hooks::Bus` constant is removed.
- Replaced `Textus::Application::Ports` with three capability records: `Textus::Application::ReadCaps`, `WriteCaps`, `HookCaps`.
- Renamed `Textus::Operations` to `Textus::Session`. Access via `store.session(role:)`. `Operations.for(store, ...)` is removed.
- Hook RPC callables (`resolve_intake`, `transform_rows`, `validate`) no longer accept `store:` — declare `caps:` (a `WriteCaps` for `resolve_intake`/`validate`, `ReadCaps` for `transform_rows`).
- Removed all `Manifest` top-level deprecation shims (`zones`, `entries`, `zone_writers`, `permission_for`, etc.). Use `manifest.data.*` / `manifest.policy.*` / `manifest.resolver.*` / `manifest.rules.*`.
- Moved `Textus::Application::Writes::EnvelopeReader`/`EnvelopeWriter` to `Textus::Application::Envelope::Reader`/`Writer`.
- Renamed `Textus::Application::Writes` → `Textus::Application::Write`; `Textus::Application::Reads` → `Textus::Application::Read`; `Textus::Application::Restructure` → `Textus::Application::Maintenance`.
- Merged `Textus::Application::Refresh::*` into `Textus::Application::Write::Refresh{Worker,Orchestrator,All}`.
- Moved `Textus::Application::Policy::Promotion` and predicates to `Textus::Domain::Policy::Promotion`/`Predicates`.

## 0.25.1 — 2026-05-28

### Internal refactors

- **ADR 0018**: `Manifest` is now a composition record over `Data`,
  `Resolver`, `Policy`, `Rules`. Top-level methods like
  `Manifest#permission_for` are deprecated; use
  `manifest.policy.permission_for(zone)`. One-cycle bridge — shims
  warn until 0.26.0.

- **ADR 0016**: Application use cases take a single `ports:` kwarg
  bundling six adapters + the store root. Hook DSL callables that
  declare `|store:|` continue to work with a one-shot deprecation
  warning per (event, hook_name); declare `|ports:|` to silence it.

- **ADR 0017**: `Application::Writes::EnvelopeIO` split into
  `EnvelopeReader` (parse) and `EnvelopeWriter` (put/delete/move
  + audit). Every public `EnvelopeWriter` method now ends with an
  audit-row append — the write-without-audit failure mode is gone.

### Breaking (internal)

- `Operations#store` accessor removed. There is no clean deprecation
  shim because `Ports` cannot reconstruct a `Store`. External
  callers should use `ops.ports.X` directly.

- `Textus::Manifest::Entry::Base::PublishContext` struct shape
  changed: `:store` removed, `:ports` + `:boot` added. Affects
  third-party plugins that build custom derived entries.

- `transform_context` passed to `transform_rows` RPC callables is
  now an `Application::Ports`, not a `Store`. Transforms that treat
  it as opaque continue to work; transforms that reach `.x` need
  updates.

No CLI verb signatures changed. No wire envelopes changed.
Protocol remains `textus/3`.

## 0.25.0 — 2026-05-28

### Added (additive — backward-compatible pulse fields)
- `pulse.manifest_etag` — sha256 of `manifest.yaml`; lets agents detect contract drift without a second verb.
- `pulse.next_due_at` — soonest `next_due_at` across all entries with a refresh policy. Schedulers sleep until this timestamp instead of polling.
- `pulse.hook_errors` — recent hook failures since cursor; bounded in-memory ring on `Hooks::Bus#error_log` (default 256).

### Changed
- `Application::Reads::Freshness` memoizes the evaluator verdict by `(key, last_refreshed_at)` per request — pulse no longer pays O(N) evaluator calls when nothing has changed.
- `Application::Refresh::Orchestrator` gains a cooperative-cancel fallback for `RefreshTimed` when `fork(2)` is unavailable (Windows). Previously degraded to `Failed("timed_sync requires fork")`; now executes within the budget on a Thread, killing it on budget exceeded.

### Protocol
- No wire-format change. `textus/3` envelopes are unchanged. Pulse fields are additive — existing consumers ignoring unknown keys continue to work.

## 0.24.0 — 2026-05-28

### Added
- **Context-structure ergonomics** (ADR 0015 Phase 2):
  - `textus key mv --prefix OLD NEW` — bulk rename leaves under a prefix; preserves UIDs.
  - `textus key delete --prefix P` — bulk delete leaves.
  - `textus zone mv FROM TO` — rename a zone; refuses if destination exists; rewrites manifest + moves files.
  - `textus rule lint --against=FILE` — diff candidate manifest YAML's `rules:` block against the live manifest.
  - `textus migrate PLAN.yaml` — run a multi-op declarative migration plan (ops: `key_mv_prefix`, `key_delete_prefix`, `zone_mv`).
  - All five operations also surface as MCP tools (`key_mv_prefix`, `key_delete_prefix`, `zone_mv`, `rule_lint`, `migrate`).
- `Textus::Application::Restructure` module with `Plan` value object and one use case per operation.

### Protocol
- No wire-format change. `textus/3` envelopes are unchanged.

## 0.23.0 — 2026-05-28

### Added
- **Agent gate (MCP transport).** `textus mcp serve` — stdio JSON-RPC 2.0
  server speaking MCP draft 2024-11-05. Wraps `Textus::Operations` as ten
  auto-derived tools (`boot`, `tick`, `find`, `read`, `write`, `propose`,
  `refresh`, `refresh_stale`, `schema`, `rules`). Session state (cursor,
  role, manifest_etag) held server-side. Manifest drift surfaces as
  `ContractDrift` (-32001); cursor expiry as `CursorExpired` (-32002).
  See [`docs/reference/mcp.md`](docs/reference/mcp.md) and [ADR 0015](docs/architecture/decisions/0015-agent-gate-mcp.md).
- `examples/claude-plugin/.mcp.json` and migrated skills/commands/agents —
  zero `textus <verb>` shell strings remain in plugin markdown.

### Changed (docs)
- `ARCHITECTURE.md`: fixed stale `registry` references (now `bus`),
  added Agent Surface section and complete Hooks::Bus event catalog.
- `docs/agent-integration.md`: documents three transports (CLI, Ruby API,
  MCP); points agent authors at the MCP transport by default.

### Protocol
- No wire-format change. `textus/3` envelopes are unchanged.

## 0.22.0 — 2026-05-28

### Changed (internal — no manifest-schema impact)
- **Entry polymorphism pass.** Behavior-preserving refactor that
  consolidates cross-cutting fields on `Manifest::Entry::Base` and
  replaces case-statement dispatch with polymorphic methods. Adding
  a new entry kind now costs ~1 file edit instead of ~5–10.
  - `publish_to` is now owned by `Base` (was declared four separate
    times across Leaf/Derived/Nested/Intake).
  - `Base` exposes nil-returning stubs for `template`, `inject_boot`,
    `events`, `publish_each`, `index_filename` — validators and
    serializers no longer need `respond_to?` guards.
  - `Publish#call` dispatches via `entry.publish_via(context)` instead
    of a 4-branch case-statement. The byte-identical
    `publish_leaf_entry` / `publish_intake_entry` helpers are gone.
  - Each `Entry` subclass declares a `KIND` constant and a
    `self.from_raw(common, raw)` factory; `Parser` dispatches via
    `Entry::REGISTRY` instead of a closed `case kind`.
  - Dead `Base#kind` method removed.

No public API or manifest YAML changes. All existing manifests load
identically.

Remaining `is_a?(Entry::Derived)` callsites in `builder/`, `renderer/`,
`application/reads/`, and `domain/staleness/` are out of scope for this
pass — they touch a different polymorphism axis (what data the entry
contributes to a build) and will be addressed in a follow-up.

Known follow-up: `Intake#nested?` still reads `@raw["nested"]` to
preserve the `kind: intake, nested: true` YAML overlay used by nested
intake handlers. This dual discriminator (`kind:` + `nested:`) is a
design tension worth revisiting alongside the broader is_a? cleanup.

## 0.21.1 — 2026-05-27

### Fixed
- **Intake entries can now act as builder outputs.** Two related gaps closed:
  - `FormatMatrix` validator no longer rejects `kind: intake` entries in
    generator zones for missing a template. Intake bodies come from a
    `:resolve_intake` handler, so the "derived format requires template"
    rule never applied. (Error message widened from "derived #{format}"
    to "#{format} entries in a generator zone require a template".)
  - `Manifest::Entry::Intake` now parses `publish_to:` from YAML (was
    hardcoded to `[]`).
  - `textus publish` / `textus build` now fan out intake bodies to each
    `publish_to` target, mirroring the Leaf fan-out path. Refresh-time
    fan-out is unchanged — bodies still publish on the next publish/build
    run.

  Closes #80. Lets consumers replace `kind: derived, compute: { kind:
  external }` runner glue with `kind: intake` + `Textus.on(:resolve_intake)`
  hooks for builder-produced outputs.

## 0.21.0 — 2026-05-27

### BREAKING
- `textus intro` is removed. Use `textus boot` instead — same envelope, same
  use case, better name (pairs with the new `pulse` verb to form the agent
  lifecycle: `boot` for static contract, `pulse` for dynamic state).
- The `Textus::Intro` module is now `Textus::Boot`. The manifest entry field
  `inject_intro:` is now `inject_boot:`. Builder template variable
  `{{intro.*}}` is now `{{boot.*}}`. Pre-1.0; no compatibility alias.

### Added
- **`textus pulse [--since=N]`** — agent heartbeat verb. Returns an envelope
  with `cursor` (current `latest_seq`), `changed` (audit rows since N),
  `stale` (entries past refresh policy), `pending_review` (keys in review
  zone), and `doctor` (ok/warn/fail counts). One round-trip replaces what
  was previously four separate verbs.
- **`agent_quickstart` block in `textus boot`** — names the read verbs,
  write verbs, writable zones, default propose zone, and current
  `latest_seq` (the starting cursor for `pulse`). Lets an agent boot once
  and immediately know how to talk and where to start polling.
- **Audit log rotation.** Active `audit.log` rotates to `audit.log.1` when
  it exceeds `audit.max_size` (default 10MB), keeping the last
  `audit.keep` files (default 5). Each rotated file has a sidecar
  `audit.log.N.meta.json` with `min_seq`/`max_seq`/`rotated_at`. Configure
  via the new top-level `audit:` block in `manifest.yaml`.
- **Monotonic `seq` on every audit row.** Foundation for cursor-based
  queries; `audit --seq-since=N` and `pulse --since=N` both use it.
- **`Textus::CursorExpired`** error class, raised by `pulse` and
  `audit --seq-since` when the requested seq has rotated off disk. The
  message names the oldest still-available seq and tells the agent to
  re-orient via `textus boot`.
- `docs/agent-integration.md` — boot → pulse → work loop reference, with
  an example agent loop and cursor-expiry handling.

### Changed
- Audit rows now include a `seq` integer field (existing fields unchanged).
- `textus boot` envelope gains `agent_quickstart` (additive — existing
  consumers unaffected).

## 0.20.2 — 2026-05-27

### Fixed
- Promotion predicate `accept_authority_signed` now checks the role's *kind*
  via `manifest.role_kind`, so manifests with a renamed authority role (e.g.
  `owner` instead of `human`) pass the promotion gate. The internal class
  `Predicates::HumanAccept` was renamed to `Predicates::AcceptAuthoritySigned`.
- `textus schema migrate` now writes as the manifest's declared
  `accept_authority` role instead of the literal `"human"`, and raises a
  clear `UsageError` (with a YAML hint) when no `accept_authority` role is
  declared.
- `textus accept` / `textus reject` no longer claim "only human role can
  accept" when the manifest declares zero `accept_authority` roles — the
  error now says "no role with accept_authority kind is declared in this
  manifest; accept/reject is disabled".
- `textus build` now resolves the build role from the manifest's declared
  `generator` kind instead of hardcoding `"builder"`, so renamed generator
  roles work correctly.
- Manifest validator's "exactly one accept_authority" error message now
  matches what the schema actually enforces.

### Removed
- Legacy `human_accept` promotion-predicate alias (string and symbol forms).
  Manifests using `rules[].promotion.requires: [human_accept]` must change
  to `[accept_authority_signed]`. The error on the old form is actionable:
  `unknown promotion predicate: 'human_accept' (known: schema_valid,
  accept_authority_signed)`.
- `textus key normalize` verb and the underlying
  `Textus::Application::Tools::MigrateKeys` module. Files dropped into nested
  zones with illegal basenames are still reported by `textus doctor` with a
  `key.illegal` finding; fix them by hand. The `--upgrade-manifest` flag and
  its `Textus::Application::Tools::MigrateManifestToKinds` module (one-shot
  0.19→0.20 manifest upgrader) are removed for the same reason — dead weight.
- The `migrate-keys` audit-log payload string is no longer emitted (no writer
  produces it).

### Internal
- Final cleanup of role-name leaks identified by the 0.20.2 architecture
  audit (follow-on to 0.20.1 role-kinds refactor).

## 0.20.1 — 2026-05-27

### Added
- Optional `roles:` block in `manifest.yaml` lets users rename roles without
  breaking engine semantics. Each declared role maps to one of four engine
  kinds: `accept_authority`, `generator`, `proposer`, `runner`. (#72)
- `Manifest#role_kind`, `Manifest#roles_with_kind`, `Manifest#zone_kinds`
  accessors for engine integrations.

### Changed
- `accept` / `reject` now gate on `accept_authority` kind, not the literal
  `"human"` role. Error messages cite the configured role name.
- `validator` last-writer trust check uses `accept_authority` kind.
- Entry `in_generator_zone?` / `in_proposal_zone?` query `zone_kinds`.
- `Intro` derives `write_flows` and `agent_protocol.role_resolution.roles`
  from the manifest's role mapping.
- Promote DSL predicate `:human_accept` renamed to `:accept_authority_signed`;
  the old symbol still works as an alias.
- Schema rejects zone writers that reference an undeclared role when `roles:`
  is declared.

### Compatibility
- No wire protocol change (`textus/3`).
- Existing manifests without a `roles:` block behave identically to 0.20.0.

## 0.20.0 — architecture redesign (2026-05-27)

**BREAKING (pre-1.0):** Public top-level utility modules removed,
`Manifest` routing methods extracted into a dedicated resolver,
`Hooks::Dispatcher`/`Hooks::Registry` collapsed into a single bus, and
pubsub hook payloads now ship `ctx:` (a `Textus::Hooks::Context`)
instead of the raw store. External hook files written against the 0.19
`register(event, name, ...)` API continue to work unchanged; pubsub
hook bodies must update signatures from `|store:, ...|` to `|ctx:, ...|`
and use `ctx.put`/`ctx.get`/`ctx.audit`/`ctx.publish_followup` in place
of direct `store.*` access. RPC events (`transform_rows`, `resolve_intake`,
`validate`) keep `store:`.

### Added
- `Textus::Hooks::Context` — narrow handle for user pubsub hooks. Exposes
  `role`, `correlation_id`, `get`, `list`, `deps`, `freshness`, `put`,
  `delete`, `audit`, and `publish_followup`. All writes route back through
  `Operations` so authorization, audit, and validation cannot be bypassed.

### Removed
- `Textus::Dependencies` — use `Operations#deps`, `#rdeps`, `#published`.
- `Textus::Refresh` — use `Operations#refresh`. The `normalize_action_result`
  helper is now a private class method on `Application::Refresh::Worker`.
- `Textus::Hooks::Dispatcher` and `Textus::Hooks::Registry` classes.

### Changed
- `Textus::Projection` moved to `Textus::Application::Projection`.
- `Textus::MigrateKeys` moved to `Textus::Application::Tools::MigrateKeys`.
- `Manifest#resolve`, `#enumerate`, and `#suggestions_for` removed from
  the public `Manifest` API. Use `manifest.resolver.resolve(key)` etc.
  via the new `Manifest::Resolver`. `Manifest` retains the data accessors
  (`entries`, `zones`, `rules`, `permissions`, `validate_key!`).
- `Store` constructs one `Hooks::Bus`; `Store#registry` removed (use
  `Store#bus`). `Hooks::Builtin.register_all(bus)` and
  `Hooks::Loader.new(bus:)` now take a Bus instead of a Registry.
  `Operations.for` no longer accepts `registry:`. Use cases
  (`Refresh::Worker`, `Refresh::All`) take `bus:`.
- All pubsub events declare `ctx:` instead of `store:` in their kwargs
  schema. Every `bus.publish` call site passes `ctx: hook_context`.
  `Operations#hook_context` builds the per-`Operations` `Hooks::Context`.
- Manifest entries gain a required `kind:` field
  (`leaf | nested | derived | intake`). Run
  `textus key normalize --upgrade-manifest` to add it to existing
  manifests — the inference is deterministic and lossless.
- Internal: `Manifest::Entry` is now an abstract namespace; concrete
  classes are `Entry::Leaf`, `Entry::Nested`, `Entry::Derived`,
  `Entry::Intake`. The fields `projection`, `generator`, `compute`,
  `intake_handler`, `intake_config` are removed from the entry
  interface; `Entry::Derived` carries a typed `source`
  (`Projection` or `External`) and `Entry::Intake` carries `handler`
  / `config`. Use-case code dispatches on entry type rather than
  probing optional fields.
- `Application::Writes::Build` removed. `Application::Writes::Publish` now
  materializes derived entries (template + projection + external runner)
  AND copies leaf/nested entries to their publish targets in a single pass.
  `Operations#build` is gone; use `Operations#publish` — the `textus build`
  CLI verb is unchanged and produces the same
  `{protocol, built, published_leaves}` JSON shape.

## 0.19.1 — drop textus/2 migration hint (2026-05-27)

**BREAKING (pre-1.0):** Users on gem ≤0.10 (manifest protocol `textus/2`)
no longer receive a stepping-stone hint pointing at 0.11.x. The manifest
parser and `textus doctor` now emit the generic "unsupported version"
error. Users on ≤0.10 should install 0.11.x first (still on RubyGems)
to run the migrator, then upgrade to 0.19.1+.

### Changed
- `Textus::Manifest` no longer special-cases `textus/2`; `TEXTUS_2_HINT`
  and `version_hint_for` removed.
- `Doctor::Check::ProtocolVersion` hint/fix text simplified; no longer
  links to the 0.11.x CHANGELOG anchor.

### Removed
- Two redundant manifest specs (the `Manifest.load` duplicate and the
  `textus/2`-specific hint assertion) collapsed into one generic case.

## 0.19.0 — 2026-05-27

### Breaking

- `Application::Context` is now a slim value object (`role`,
  `correlation_id`, `now`, `dry_run`). Migration table:

  | Was | Now |
  |-----|-----|
  | `Application::Context.new(store:, role:)` | `Operations.for(store, role:)` (common case) or `Application::Context.build(role:)` (pure call state) |
  | `Application::Context.system(store)` | Pass `store` directly to hooks |
  | `ctx.store` / `ctx.manifest` / `ctx.file_store` etc. | Construct use cases with the explicit port kwargs |
  | `ctx.authorize_write!(mentry)` | `Domain::Authorizer.new(manifest:).authorize_write!(mentry, role:)` |
  | `Put.new(ctx:).call(..., suppress_events: true)` | Use `EnvelopeIO#write` directly |
  | `store.role` inside a hook | Read `role:` from the event payload |

- `Operations.new(ctx:, manifest:, file_store:, schemas:, audit_log:, bus:, registry:, root:, store:)`
  is the primary constructor. `Operations.for(store, role:)` remains
  a convenience.

- `Application::Writes::Put#call` no longer accepts `suppress_events:`.

- `Domain::Policy::Predicates::*` moved to `Application::Policy::Predicates::*`.
  `Domain::Policy::Promotion` moved to `Application::Policy::Promotion`.
  `Promotion#evaluate` now takes `entry:, schemas:, manifest:, role:`
  instead of `store:`.

- Hooks/intakes/transforms receive the actual `Store` as `store:`
  (previously a Context impersonating one). Event payloads
  (`:entry_put`, `:entry_deleted`, `:entry_renamed`, `:proposal_accepted`,
  `:proposal_rejected`, `:entry_refreshed`, `:refresh_started`,
  `:refresh_failed`, `:refresh_backgrounded`, `:file_published`,
  `:build_completed`) now carry `role:` directly so hooks can observe
  the actor without reaching through the `store:` handle.

- `Application::Refresh::All` is a class, not a module function. Callers
  go through `Operations#refresh_all`.

### Added

- `Domain::Authorizer` — single source of truth for permission checks.
- `Application::Policy::Promotion` and `Application::Policy::Predicates::*` —
  the policy evaluator and predicates now live with the Application code
  that loads envelope bytes off disk to evaluate them.
- `Application::Writes::EnvelopeIO#move` — full move pipeline (replaces
  the in-`Mv` file move + audit).
- `Application::Writes::EnvelopeIO#read_envelope(key)` — internal
  convenience for callers that need to inspect a pre-move envelope.

### Internal

- `Builder::Pipeline` no longer re-enters `Operations.for(store)`; it
  takes reader/lister callables from the caller.
- CLI verbs construct `Operations`, never `Context` directly.
- `Operations` no longer memoizes per-use-case factories; only
  `envelope_io`, `refresh_worker`, and `orchestrator` are shared.
- Wire format `textus/3` unchanged. Audit-log NDJSON unchanged.

### Known follow-ups

- CLI verbs `hook run`, `put --fetch`, `hooks list`, and `rule list`
  still reach into `store.manifest` / `store.registry` directly. A
  future release adds `Operations` projections (e.g. `manifest_view`,
  `hooks_view`, `run_intake`) so these verbs route through the
  Operations boundary.
- `Application::Writes::Delete#call` retains a `suppress_events:` kwarg
  (used internally by `Reject`). A future release either lifts the
  suppression into `EnvelopeIO`-direct usage (matching the `Mv` path)
  or formalizes per-event suppression as part of the public hook API.

## 0.18.1 — 2026-05-27

### Fixed

- `Hooks::Dispatcher` no longer uses `Timeout.timeout`, which can interrupt a
  hook mid-syscall or mid-`ensure` and leave Ruby state corrupted. Each
  subscriber now runs in a worker thread joined with a deadline; on overrun
  the thread is killed and the hook is recorded as `timed_out` (distinct
  from `errored`).

### Added

- `Hooks::FireReport` — value object returned from `bus.publish`. Lists
  `fired`, `errored`, and `timed_out` subscriber names; exposes `#ok?` and
  `#failures`. Backwards-compatible: callers that ignore the return value
  (the entire current codebase) keep working.
- `Hooks::Dispatcher#publish` accepts `strict: true`, which re-raises the
  first failure after every subscriber has been attempted. Intended for
  test setups that want loud hooks; default remains `false`.

### Internal

- No public API surface changes. CLI behavior, `Operations` methods, wire
  format `textus/3`, and the audit-log NDJSON shape are unchanged. Stores
  written by 0.18.0 round-trip through 0.18.1 byte-for-byte.

## 0.18.0 — 2026-05-27

Port extraction finishes the hexagonal trajectory. `Store::Reader` and
`Store::Writer` were disguised application code under an infra
namespace; this release replaces them with a true I/O port
(`Infra::Storage::FileStore`, bytes only) and lifts their orchestration
into `Application::Writes::EnvelopeIO` and the existing
`Application::Reads::*`. `Store` becomes a composition root: nothing
else. Wire format (`textus/3`) and audit log NDJSON line format are
byte-identical to 0.17.0 — every change is gem-side.

### Breaking (Ruby API)

- **`Store::Reader` and `Store::Writer` are deleted.** Both classes
  were doing application work (serialize, UID inject, name-match,
  schema validate, etag negotiate, audit append, event publish) under
  an infra label. Their methods move to flat `Operations` calls:
  ```
  store.reader.get(key)                  →  Textus::Operations#get(key)
  store.reader.read_raw_envelope(key)    →  Textus::Operations#get(key)
  store.reader.list(prefix:, zone:)      →  Textus::Operations#list(prefix:, zone:)
  store.reader.where(key)                →  Textus::Operations#where(key)
  store.reader.uid(key)                  →  Textus::Operations#uid(key)
  store.reader.schema_envelope(key)      →  Textus::Operations#schema_envelope(key)
  store.reader.published                 →  Textus::Operations#published
  store.reader.stale(...)                →  Textus::Operations#stale(...)
  store.reader.deps(key)                 →  Textus::Operations#deps(key)
  store.reader.rdeps(key)                →  Textus::Operations#rdeps(key)
  store.reader.validate_all              →  Textus::Operations#validate_all

  store.writer.write_envelope_to_disk    →  Textus::Operations#put(key, ...)
  store.writer.delete_envelope_from_disk →  Textus::Operations#delete(key, ...)
  ```
- **`Store#schema_for(name)` is deleted.** Schemas live on a dedicated
  cache:
  ```
  store.schema_for(name)                 →  store.schemas.fetch(name)
  ```
- **Infra/Domain relocations.** Files that were `Store::*` because the
  namespace was a catch-all now live in the layer they belong to:
  ```
  Textus::Store::AuditLog                →  Textus::Infra::AuditLog
  Textus::Store::Sentinel                →  Textus::Domain::Sentinel
  Textus::Store::Staleness               →  Textus::Domain::Staleness
  Textus::Store::Validator               →  Textus::Application::Reads::Validator
  ```
- **Write use-case constructors take `envelope_io:`.**
  `Application::Writes::Put.new(ctx:, envelope_io:)` — same for
  `Delete` and `Mv`. External code that constructed write use cases
  directly adds the kwarg.
- **Note.** Most embedders construct use cases via
  `Textus::Operations.for(store)`. That constructor still works
  without changes — `Operations#for` wires `envelope_io:` from the
  store. Embedders on the recommended path see no breakage.

### Added

- **`Textus::Infra::Storage::FileStore`** — pure I/O port. `read`,
  `write`, `delete`, `exists?`, `etag` — bytes in, bytes out. No
  serialization, no schema, no manifest, no events. The seam that
  makes non-file storage backends possible.
- **`Textus::Schemas`** — eager-loading schema cache. Reads the
  `_schemas/**` zone at boot, exposes `fetch(name)` and `each`.
  Replaces the on-demand `Store#schema_for` lookup.
- **`Textus::Application::Writes::EnvelopeIO`** — the write pipeline
  collaborator. Serializes the envelope, validates against its
  schema, negotiates etag, writes via `FileStore`, appends to audit,
  publishes the event. The shared orchestration that `Put`,
  `Delete`, and `Mv` previously duplicated through `Store::Writer`.

### Internal

- **`Store` is a composition root.** Its responsibilities are
  construction and exposure: `manifest`, `schemas`, `file_store`,
  `audit_log`, `bus`, `registry`, `root`. No `reader`, no `writer`,
  no `schema_for`. Hook loading (`load_hooks`) and operations
  exposure (`operations`) remain — both delegate to dedicated
  collaborators.
- **Read use cases read from `file_store`/`manifest`/`schemas`
  directly.** `Reads::Get`, `Reads::List`, `Reads::Where`,
  `Reads::Stale`, `Reads::Deps`, etc., no longer route through a
  reader facade. The path is `Operations → use case → ports`.

### Wire format / audit format

Unchanged. `textus/3` envelopes written by 0.17.0 round-trip through
0.18.0 byte-for-byte; audit log NDJSON lines are bidirectionally
compatible.

### Migrating from 0.17

Mechanical for embedders; transparent for CLI users.

```
# Reads
store.reader.get(key)        →  ops.get(key)
store.reader.list(prefix: x) →  ops.list(prefix: x)
store.reader.stale(...)      →  ops.stale(...)
# (and the rest of the table above)

# Writes — recommended path stays the same
ops.put(key, body: x)        # unchanged

# Schemas
store.schema_for(name)       →  store.schemas.fetch(name)

# Renames
Textus::Store::AuditLog      →  Textus::Infra::AuditLog
Textus::Store::Sentinel      →  Textus::Domain::Sentinel
Textus::Store::Staleness     →  Textus::Domain::Staleness
Textus::Store::Validator     →  Textus::Application::Reads::Validator
```

## 0.17.0 — 2026-05-27

API and policy reshape. The public Ruby surface flattens, authorization
moves from seven duplicated blocks into one helper on `Application::Context`,
and the only thread-local in the library is gone. Wire format (`textus/3`)
and CLI JSON output are byte-identical to 0.16.0. Every change is gem-side.

### Breaking (Ruby API)

- **`Operations` is flat.** The `Operations#reads`, `Operations#writes`,
  and `Operations#refresh` namespace shells are removed; every use case
  is now a directly-named method on `Operations` itself. Callers that
  typed three levels of indirection plus `.call` switch to a single
  method call:
  ```ruby
  ops.writes.put.call(key, body: x)   →   ops.put(key, body: x)
  ops.reads.get.call(key)             →   ops.get(key)
  ops.reads.get_or_refresh.call(key)  →   ops.get_or_refresh(key)
  ops.refresh.worker.call(key)        →   ops.refresh(key)
  ops.refresh.all.call(prefix:, …)    →   ops.refresh_all(prefix:, …)
  ```
  Internal use-case instances are memoized via `||=`. `Operations#with_role`
  returns a fresh `Operations` with no shared memoization.
- **`Operations::Reads`, `Operations::Writes`, `Operations::Refresh`** —
  the shell classes — are deleted. External code that named them
  directly (rare) must move to the flat methods on `Operations`.
- **Top-level `Textus.on(event, name) { ... }` is removed.** Hook files
  now wrap registration in a `Textus.hook` block that receives the
  store's registry:
  ```ruby
  # before
  Textus.on(:entry_put, "audit") { |store:, key:, **| ... }
  # after
  Textus.hook do |reg|
    reg.on(:entry_put, "audit") { |store:, key:, **| ... }
  end
  ```
  Multiple `reg.on` lines under one `Textus.hook` block is idiomatic.
- **`Textus.with_registry` is removed.** Tests instantiate
  `Textus::Hooks::Registry.new` and call `reg.on(...)` directly — no
  `around` block, no thread-local cleanup.
- **`Textus::Hooks::Loader.current_registry` is removed.** It was the
  thread-local read accessor; nothing replaces it because no thread-
  local remains.
- **Write use-case constructors lose `bus:`.** `Application::Writes::*`
  classes pull the bus from `@ctx.bus` instead of taking it as a kwarg.
  External code that constructed `Writes::Put.new(ctx:, bus:)` directly
  drops the `bus:` argument.

### Added

- **`Application::Context#authorize_write!(mentry)`** — raises
  `WriteForbidden` (with the zone's writers list in `details`) when the
  bound role lacks write permission. Returns `nil` on success. Replaces
  the seven duplicated `unless can_write? ... raise WriteForbidden`
  blocks across `Writes::{Put,Delete,Mv,Accept,Reject,Build,Publish}`.
- **`Application::Context#authorize_read!(mentry)`** — mirror of
  `authorize_write!`. Raises a new `ReadForbidden` (code `read_forbidden`,
  exit 1, details: `key`, `zone`, `readers`).
- **`Application::Context#bus`** — returns `store.bus`. Use cases publish
  events through `@ctx.bus`; the prior `@ctx.store.bus` reach-through is
  no longer used in-tree.
- **`Textus::ReadForbidden`** error class. Symmetric with `WriteForbidden`.
- **`Textus.hook(&blk)`** — appends the supplied block to a mutex-
  guarded module-level queue. The store-scoped loader drains and invokes
  each block with its registry.
- **`Textus.drain_hook_blocks`** — public for tests; returns and clears
  the queued blocks under the same mutex.
- **`Textus::Hooks::Registry#on`** — already the canonical instance API
  since 0.11; explicitly documented as the registration primitive now
  that the top-level shim is gone.

### Internal

- **`Application::Writes::Mv`** now authorizes both source and
  destination zones. The prior code authorized only the source; the
  centralized `authorize_write!` made the second call a one-liner and
  the gap obvious.
- **`Hooks::Builtin.register_all`** takes a `registry:` argument and
  calls `registry.on(...)` directly. No thread-local read.
- **`Hooks::Loader`** is now a per-store class constructed with
  `registry:`. `#load_dir(path)` walks the directory, `load`s each
  `.rb`, then drains `Textus.drain_hook_blocks` and invokes each with
  the registry. Two threads loading two stores concurrently are safe
  because each `load_dir` drains around its own file walk under the
  module-level mutex.
- **`Doctor::Check::Hooks`** reads `store.registry` directly; no
  thread-local indirection.
- **`Store#load_hooks`** is a two-liner: construct a `Loader` with
  `@registry`, call `load_dir` against `.textus/hooks/`.
- **Reads/refresh paths** use `@ctx.bus` instead of `@ctx.store.bus`.
  Same object; the indirection is gone.

### Migrating from 0.16

Mechanical, sed-friendly. The CLI shape is unchanged — only embedders
and hook authors need to do anything.

```
# Operations: flat surface
ops.writes.put.call(key, body: x)   →   ops.put(key, body: x)
ops.reads.get.call(key)             →   ops.get(key)
ops.reads.get_or_refresh.call(key)  →   ops.get_or_refresh(key)
ops.refresh.worker.call(key)        →   ops.refresh(key)        # via Operations#refresh
ops.refresh.all.call(...)           →   ops.refresh_all(...)

# Hooks: explicit registration
Textus.on(:entry_put, "x") { |e| ... }
  →
Textus.hook do |reg|
  reg.on(:entry_put, "x") { |e| ... }
end

# Tests: no more thread-local scope
around { |ex| Textus.with_registry(reg) { ex.run } }   # delete
Textus.on(:resolve_intake, :x) { ... }                 # → reg.on(:resolve_intake, :x) { ... }
```

If you constructed `Writes::Put` (or any other write use case)
directly, drop the `bus:` kwarg from the constructor call. If you
constructed `Hooks::Loader` directly, the new signature is
`Loader.new(registry:)` and the API is `loader.load_dir(path)`.

### ADRs

- [ADR 0010 — Flat Operations API](docs/architecture/decisions/0010-flat-operations-api.md)
- [ADR 0011 — Authorize-bang in Context](docs/architecture/decisions/0011-authorize-bang-in-context.md)
- [ADR 0012 — Explicit hook registration](docs/architecture/decisions/0012-explicit-hook-registration.md)

## 0.16.0 — 2026-05-26

Type cleanup and infra glue. Wire format (`textus/3`) and CLI JSON output
are byte-identical to 0.15.0. Every change is gem-side.

### Breaking (Ruby API)

- **`Envelope#freshness`** is now a `Textus::Domain::Freshness` value (a
  `Data.define(:stale, :refreshing, :reason, :refresh_error, :checked_at,
  :ttl_remaining_ms)`), not a `Hash`. Field access replaces string-key
  lookup: `env.freshness.stale` (was `env.freshness["stale"]`). The
  field formerly emitted as `"stale_reason"` on the wire is named
  `:reason` on the value object; `Freshness#to_h_for_wire` still emits
  `"stale_reason"`, so JSON output is unchanged. New fields
  (`:checked_at`, `:ttl_remaining_ms`) are gem-side only and not on the
  wire.
- **`Manifest#resolve(key)`** now returns a `Textus::Manifest::Resolution`
  value (`Data.define(:entry, :path, :remaining)`) instead of an
  `[entry, path, remaining]` tuple. Callers that destructured the array
  must switch to field access: `res = manifest.resolve(key); res.entry`.
  Raises `UnknownKey` on miss (unchanged).
- **`Textus::Store.mint_uid`** is removed. Use `Textus::Uid.mint`. A
  companion `Textus::Uid.valid?(str)` predicate is added.
- **`Hooks::Dispatcher.new(audit_log:)`** no longer accepts
  `audit_log:`. The dispatcher is now a pure pub/sub. Hook-error audit
  rows are written by `Textus::Infra::AuditSubscriber`, which `Store`
  attaches at boot. The NDJSON audit line format is unchanged
  byte-for-byte.

### Added

- `Textus::Domain::Freshness` — typed envelope-annotation value object.
- `Textus::Manifest::Resolution` — typed key-resolution value object.
- `Textus::Uid` — `.mint` / `.valid?` for the 16-hex UID format.
- `Textus::Infra::AuditSubscriber` — attaches to the event bus and
  writes the `verb: "event_error"` audit row when a user hook raises.
- `CLI::Verb.command_name "X"` and `CLI::Verb.parent_group Group::Y`
  DSL. Adding a new CLI verb is now a single declaration in the verb's
  own file; the top-level `VERBS` table and group subcommand maps are
  auto-derived from descendants. Help-output ordering is alphabetical
  by command name.

### Changed

- `CLI::Group` no longer exposes the `cli_name` writer — use
  `command_name` (the prior `cli_name` reader is removed).
- `Application::Reads::Get` and `Reads::GetOrRefresh` construct
  `Freshness` values directly; their public signatures are unchanged.

### Deprecated

- `Textus::CLI::VERBS` constant. Still resolves (via `const_missing` to
  the auto-derived table) for backward compatibility; will be removed
  in a future minor. Prefer `Textus::CLI.verbs`.

### Notes for embedders

- Group subcommand error messages now list subcommands alphabetically
  (e.g., `key requires a subcommand: mv, normalize, uid` rather than
  `mv, uid, normalize`).
- Lifecycle audit appends for `verb: "put"` / `"delete"` / `"rename"`
  still flow through `Store::Writer` and `Application::Writes::Mv`.
  Centralizing those in a lifecycle subscriber is deferred to 0.18
  port-extraction; it requires event payloads to carry
  `etag_before`/`etag_after`, which they don't yet.

### ADRs

- [ADR 0008 — Freshness and Resolution value objects](docs/architecture/decisions/0008-freshness-and-resolution-types.md)
- [ADR 0009 — AuditSubscriber split from Hooks::Dispatcher](docs/architecture/decisions/0009-audit-subscriber-split.md)

## 0.15.0 — 2026-05-26

### Breaking

- `Application::Reads::Get#call` is now a **pure read**: it returns the
  on-disk envelope annotated with a freshness verdict, and never
  triggers refresh. `Reads::Get.new` no longer accepts `orchestrator:`.
  Callers that relied on refresh-on-read should switch to
  `Application::Reads::GetOrRefresh` (new), accessible via
  `ops.reads.get_or_refresh`. The CLI verb `textus get` is migrated
  internally; users of `textus get` see no behavior change.
- `Application::Context#bypass_freshness?` and the `bypass_freshness:`
  kwarg on `Context.new` / `Operations.for` are **removed**. They
  shipped in 0.14.4 as a workaround; with `Reads::Get` now pure by
  default, the flag is dead code. Callers passing `bypass_freshness:`
  will see `ArgumentError`.
- `Projection.new` signature is **breaking**: now
  `Projection.new(reader:, spec:, lister:, transform_resolver:, transform_context:)`.
  `Projection` no longer constructs its own `Operations` chain. Callers
  inject collaborators. `Builder::Pipeline` is migrated internally.
- Intake handlers now receive `args: { trigger_key:, leaf_segments: }`
  instead of `args: {}`. Handlers that destructure `args` should
  expect the new keys. Handlers that pass `args` through unchanged
  are unaffected.

### Fixed

- **Bug 1 / single-flight.** `Refresh::Orchestrator#run_timed` now
  probes the per-leaf lock before forking the detached refresh
  worker. If the lock is held (by a sibling process or earlier fork),
  the orchestrator returns `Outcome::Detached` without spawning a
  redundant worker. Prevents wasted forks when the same key is read
  concurrently across processes.
- **Bug 2 / leaf-aware intake.** `Refresh::Worker` now keeps the
  `remaining` segments from `Manifest#resolve(key)` and passes them
  to the intake handler as `args: { trigger_key:, leaf_segments: }`.
  Handlers can scope to one leaf instead of re-processing the full
  parent `intake_config` for every leaf refresh.
- **`textus refresh stale` now exits 0 on success.** Previously the
  verb fell off the end returning `nil`, which propagated up through
  `CLI.run` to `exe/textus:4`'s `exit nil` and raised `TypeError`,
  exit-coding 1 on every successful refresh. Fixed by returning an
  explicit Integer from the verb. The verb return-value contract is
  now codified: every verb's `#call` returns Integer (or `nil` →
  treated as 0); `CLI.run` coerces. (#61)

### Added

- `Application::Reads::GetOrRefresh` — explicit composition of pure
  `Reads::Get` with the refresh orchestrator. Use for interactive
  reads that want freshest-obtainable envelopes.
- `ops.reads.get_or_refresh` accessor.

### Migration

If your code (or hook / handler / extension) called:

| Old | New |
|---|---|
| `ops.reads.get.call(key)` to get the freshest envelope | `ops.reads.get_or_refresh.call(key)` |
| `ops.reads.get.call(key)` for pure read | unchanged; now also pure semantics |
| `Operations.for(store, bypass_freshness: true)` | `Operations.for(store)` |
| `Projection.new(store, spec)` | `Projection.new(reader:, spec:, lister:, transform_resolver:, transform_context:)` — see `builder/pipeline.rb` for canonical wiring |
| Handler signature `lambda { \|store:, config:, args:\| ... }` with `args == {}` | unchanged — `args` is now populated with `:trigger_key` and `:leaf_segments`; handlers that ignore them keep working |

## 0.14.4 — 2026-05-26

### Fixed

- `textus build` no longer triggers per-leaf refresh fan-out when
  projection reads encounter stale entries under `on_stale: timed_sync`
  / `on_stale: sync`. Build is a downstream materialization step over
  current store state; freshness is an inflow concern, and they
  shouldn't compose. Previously, building a marketplace-style output
  whose projection selected `intake.vendor.**` against ~400 stale
  leaves spawned ~400 concurrent detached refresh workers, each
  re-running the full intake handler, exhausting the system. The
  build pipeline now reads through an `Application::Context` with
  `bypass_freshness: true`, so `Application::Reads::Get` returns the
  on-disk envelope annotated as fresh without consulting the
  orchestrator. Explicit freshness before build still works via
  `textus refresh stale`. (#59)

### Added

- `Application::Context#bypass_freshness?` — new flag for read paths
  that must not initiate refresh. Threaded through `Operations.for`
  and propagated across `Context#with_role`. Used by `Builder::Pipeline`
  via a `bypass_freshness:` constructor kwarg on `Projection`.
- `textus doctor` now reports stale per-key refresh lock files under
  `<root>/.locks/` whose recorded PID is no longer running, as an
  `info`-level `refresh_lock.stale` issue. The check is purely
  informational: `Refresh::Lock` uses `flock(2)`, which the kernel
  releases on process death, so stale `.lock` files on disk do not
  block subsequent refresh acquires. The check exists so users can
  clean up forensic clutter and notice unexpected accumulation. No
  read-path changes — adding a PID probe + unlink there would
  reintroduce the TOCTOU and PID-reuse hazards explicitly rejected
  in 0.14.3 / PR #57. (#58)

### Tested

- Added a regression spec that forks a child, takes a per-key
  `Refresh::Lock`, SIGKILLs the child, and asserts a fresh acquire
  on the same key succeeds without manual cleanup. Pins the
  flock-survives-SIGKILL contract.

## 0.14.3 — 2026-05-26

### Added

- Top-level `flock(2)` mutex at `<root>/.build.lock` prevents concurrent
  `textus build` invocations against the same store. A second build
  while one is already running exits with code `75` (`EX_TEMPFAIL`) and
  emits a `build_in_progress` error envelope, so wrappers like `rake
  update` and CI can distinguish "another build is busy" from "this
  build is broken". The lock is FD-bound and released by the kernel on
  process death (including SIGKILL/OOM), so no stale-lock takeover
  logic is needed. `close_on_exec` prevents the lock from leaking into
  `bundle exec` and lefthook child processes. Per-key locks under
  `.locks/` are unchanged. (#56)

## 0.14.2 — 2026-05-26

### Added

- Per-rule `fetch_timeout_seconds:` under `rules[].refresh` overrides the
  hardcoded 30s worker timeout that applies to intake handlers invoked
  via the refresh pipeline (`textus refresh <key>`, `textus refresh
  stale`, and read-path `on_stale: sync` / `timed_sync`). Default stays
  at 30s — opt-in only. Schema validates a positive integer ≤ 3600.
  Mirrors `sync_budget_ms` plumbing: schema → rules → policy → worker
  (#54).

### Notes

- `fetch_timeout_seconds` is the worker-side hard cap on the intake
  call; `sync_budget_ms` is the caller-side wait budget for `timed_sync`
  on the read path. Two separate concerns, two separate keys.
- The CLI verbs `textus put --fetch` and `textus hook run` still use the
  30s constant — only the refresh worker honors the per-rule override in
  this release.
- Long timeouts pair with `Timeout.timeout`, which raises in the Ruby
  thread but does not kill spawned subprocesses. Intake handlers that
  shell out (e.g. `git clone`) should write to a temp dir and atomically
  rename so mid-flight aborts leave no observable partial state.

## 0.14.1 — 2026-05-26

### Changed

- Build pipeline now skips rewriting a built artifact when the only
  difference from the existing file on disk would be the freshly-stamped
  `generated_at` (markdown: `generated.at`) timestamp. Stores under git
  versioning no longer churn on every `textus build` (#52).
- Strict policy: any other byte difference — changed `from`,
  `template`, `reduce`, body content — still triggers a write. Text
  format falls back to plain byte-equality (no timestamp to normalize).

### Internal

- Extracted `Manifest.check_version!` to dedupe the parse/load version
  guard (#51).

## 0.14.0 — 2026-05-26

### Breaking (Ruby API only — CLI JSON output unchanged)

- `Operations.reads.get.call(...)` and every other use case that returned
  an envelope Hash now returns `Textus::Envelope` (a `Data.define`
  instance). Call `envelope.to_h_for_wire` to recover the previous Hash
  shape for JSON serialization. The Hash shape itself is byte-identical.
- `Operations.writes.build.call(...)` return shape no longer includes
  `published_leaves`. Call `Operations.writes.publish.call(...)`
  separately for that. The CLI verb `textus build` runs both
  automatically, so CLI users see no change.

### Added

- `Textus::Application::Writes::Publish` — new use case that copies
  nested-leaf files to their `publish_each` targets. Fires
  `:file_published`.
- `Operations.writes.publish` — factory exposing the new use case.
- `Textus::Envelope` (now a class, was a module) — typed accessors for
  `protocol`, `key`, `zone`, `owner`, `path`, `format`, `uid`, `etag`,
  `schema_ref`, `meta`, `body`, `content`, `freshness`. Methods:
  `to_h_for_wire`, `stale?`, `refreshing?`.

### Internal

- `Application::Writes::Build` trimmed from 116 LOC to ~50 LOC; now
  only materializes generator-zone entries.
- All ~17 internal `env["..."]` call sites migrated to typed access.
- `Envelope.build` no longer carries `# rubocop:disable
  Metrics/ParameterLists` (the `Data.define` member list serves the
  same role more clearly).

### Reference

- See [ADR 0007](docs/architecture/decisions/0007-envelope-data-class.md).

## 0.13.1 — 2026-05-26

### Internal

- `Manifest::Entry` (260 LOC, 11 responsibilities) decomposed into:
  - `Manifest::Entry::Parser` — raw hash → Entry value object.
  - `Manifest::Entry::Validators::*` — one file per validation rule
    (events, publish_each, inject_intro, index_filename, format_matrix).
  - `Manifest::Entry` (~50 LOC) — value object with attr readers,
    zone-kind predicates, and `publish_target_for`.
- Each validation rule is now independently testable. Adding a new
  rule is one new file under `lib/textus/manifest/entry/validators/`
  plus one line in `Validators::REGISTERED`.
- Pattern matches the existing `doctor/check/*` (~15 files, same
  shape).

### Compatibility

- `Manifest::Entry` keeps all public attribute readers, predicates,
  and `publish_target_for`. External callers consuming `Entry`
  instances see no change. Embedders who subclassed `Entry` may
  need adjustment.

## 0.13.0 — 2026-05-26

### Added

- `Textus::Entry::Base` grows 7 abstract class methods that concrete
  strategies must implement: `nested_glob`, `inject_uid`,
  `enforce_name_match!`, `rewrite_name`, `serialize_for_put`,
  `validate_path_extension`.
- `Textus::Entry.infer_from_extension(ext)` — registry method
  replacing the deleted `Manifest::EXT_TO_FORMAT` constant.

### Changed

- Format-specific branches in `Manifest#nested_glob`,
  `Manifest::Entry#{validate_format_matrix!,resolve_format!,
  validate_index_filename!}`, `Store::Writer#{ensure_uid,
  enforce_name_match!,serialize_for_put}`, and
  `Application::Writes::Mv#rewrite_name_for_mv!` all collapse to
  single-line delegations to `Entry.for_format(fmt).<method>(...)`.
- The 3 rubocop `Metrics/*` disable comments in
  `Manifest::Entry#validate_format_matrix!` are removed; the method
  is now 3 lines.

### Removed

- `Textus::Manifest::EXT_TO_FORMAT` constant. Use
  `Textus::Entry.infer_from_extension(ext)` instead.

### Reference

- See [ADR 0006](docs/architecture/decisions/0006-format-strategy-extraction.md).

## 0.12.6 — 2026-05-26

### Examples

- New `examples/project/` — demonstrates textus as the context store
  for your own project (identity + runbooks + ADR proposal flow,
  projecting `CLAUDE.md` and `AGENTS.md` at the repo root). Staged as
  a fictional Rails service (`ledger`) so the entries read like a real
  codebase, and the pre-staged ADR proposal is `accept`-runnable
  end-to-end (carries a valid `frontmatter:` payload for its target).
- Refined `examples/claude-plugin/` — reduced to one entry of each kind
  (one agent, one skill, one command, one identity entry, one output,
  one intake recipe). Removed `bin/`, `Rakefile`, `lefthook.yml`, the
  duplicate `github_folder.rb` recipe, and the per-recipe README.
- Fixed `examples/claude-plugin/recipes/skill_fanout.rb` — the recipe
  routed inner writes through `store.list/put/delete`, which were
  removed in v0.12.2. Now uses `Operations.writes.{put,delete}` against
  the `Application::Context` that hooks actually receive.
- Updated `spec/examples/skill_fanout_hook_spec.rb` to test the recipe
  against a Context-like duck type, matching the runtime contract.

## 0.12.5 — 2026-05-26

### Documentation

- Rewrote `docs/events.md` to use the textus/3 event names from
  `Hooks::Registry::EVENTS` (`:entry_put`, `:entry_deleted`,
  `:build_completed`, `:entry_renamed`, `:proposal_accepted`,
  `:proposal_rejected`, `:file_published`, `:store_loaded`,
  `:entry_refreshed`, `:refresh_started`, `:refresh_failed`,
  `:refresh_backgrounded`). All hook examples now register against
  events that actually exist.
- Rewrote `docs/zones.md` to use textus/3 vocabulary (`intake` not
  `inbox`, `write_policy:` not `writable_by:`, `rules:` not
  `policies:`, `runner` role not `script`). Manifest fixtures bump
  to `version: textus/3`.
- Rewrote `ARCHITECTURE.md` to match the v0.12.4 layering:
  `Operations` facade replaces `Composition`, `Application::Reads/Writes`
  use cases replace direct `Store#get/#put` calls, `Store` is pure
  infrastructure.
- `SPEC.md` Composition → Operations sweep; removed references to
  deleted Store delegators.
- `docs/recipe-github-skill-bundle.md` updated to use the
  `Operations.writes.{put,delete}` inner-write surface.

## [0.12.4] — 2026-05-26

### Breaking

- Removed `Textus::Store#list`, `#where`, `#deps`, `#rdeps`, `#published`,
  `#stale`, `#validate_all`, `#uid`, `#schema_envelope`, and `#fire_event`.
  Use `Textus::Operations.for(store).reads.<name>.call(...)` instead.
- Removed `Textus::Store::Writer#delete`, `#accept`, `#reject`. Use
  `Textus::Operations.for(store, role:).writes.<verb>.call(...)`.
- Removed `Textus::Store::Mover`. The mv use case lives entirely in
  `Textus::Application::Writes::Mv` now.

### Added

- `Textus::Application::Reads::{List,Where,Uid,SchemaEnvelope,Deps,Rdeps,Published,Stale,ValidateAll}`.
- `Textus::Application::Writes::Reject`.
- `Textus::Application::Context.system(store)` for infrastructure-side
  hook dispatch.

### Internal

- Internal call sites (`Projection`, `Schema::Tools`, `Application::Refresh::All`,
  `Doctor::Check::SchemaViolations`) now route reads through `Operations`.

See [ADR 0005](docs/architecture/decisions/0005-store-facade-final-removal.md).

## [0.12.3] — 2026-05-26

### Added
- `textus intro` output now includes an `agent_protocol` block: envelope shape, role-resolution rules, and four canonical recipes (`read`, `write`, `propose`, `refresh`). One `textus intro` call is sufficient orientation for a fresh AI agent to operate the store without consulting `SPEC.md`.

### Compatibility
- Fully additive. All pre-0.12.3 fields on `Textus::Intro.run` retain their existing keys, types, and shapes. The wire `"protocol"` field continues to hold the string `"textus/3"`.

### Examples
- `examples/claude-plugin/.textus/templates/claude-root.mustache` now projects the new `agent_protocol` recipes into the rendered `CLAUDE.md` via the existing `inject_intro:` mechanism. A plugin's CLAUDE.md auto-projects the four recipes alongside zone authority — agents reading CLAUDE.md get full orientation without a separate `textus intro` call. This is the canonical pattern for plugin authors who want recipes inline.
- `examples/claude-plugin/` trimmed to one of each surface (one agent, one skill, one command, one identity entry, one JSON output). Removed: the duplicate `fact-checker` variants, the `marketplace.json` projection (the JSON-output lesson is already shown by `plugin.json`), the degenerate `local_file` intake demo (pulled a file from the same store), and unused demo hooks (`rank_by_recency`, `build-stamp`). File count drops from 51 to 33; manifest from 142 to 99 lines.

## [0.12.2] — 2026-05-26

### Breaking changes

- **Removed `Textus::Composition`.** All call sites now go through
  `Textus::Operations.for(store, role:)`. The new facade groups use-cases
  by kind: `ops.writes.put`, `ops.reads.get`, `ops.refresh.worker`, etc.
  No alias, no deprecation warning — internal callers update on upgrade.
- **Removed `Store#put / #get / #delete / #accept / #reject / #mv`.** These
  were thin shims over `Composition`. Use `Operations` directly.
- **Removed `Writer#put`** (the explicit "Backward-compat shim").

### Internal

- Added `Application::Writes::Mv` use-case wrapping `Store::Mover`.
- Internal Application callers (Accept, Build, Refresh::Worker, Refresh::All,
  Reads::Blame) no longer re-enter via the top-level facade.
- Audited `spec/` and removed redundant examples (~-48 LOC; most redundancy
  was already absorbed by call-site migration in earlier tasks).

See [ADR 0004](docs/architecture/decisions/0004-operations-rename-and-store-facade-removal.md).

### Migration

There is no migration path for `Composition` and the Store facade methods —
they were internal. External consumers (hooks, custom verbs, gem embedders)
that referenced these symbols must update:

```ruby
# Before
ctx = Textus::Composition.context(store, role: "agent")
Textus::Composition.writes_put(ctx).call(key, body: "...")
# or:
store.put(key, body: "...", as: "agent")

# After
Textus::Operations.for(store, role: "agent").writes.put.call(key, body: "...")
```

## 0.12.1 — textus/2 hint fix (2026-05-26)

### Fixed
- Manifest parser now points textus/2 stores at the 0.11.x stepping-stone
  migrator instead of the misleading "check YAML frontmatter for syntax errors"
  hint. The protocol_version doctor check carried the correct hint already, but
  was unreachable on textus/2 stores because `Store.discover` → `Manifest.load`
  raises before doctor checks run. Surfaced by v0.12.0 release smoke testing.

## 0.12.0 — legacy sweep (2026-05-25)

### Removed (breaking)
- `Role::LEGACY_RENAMES` (`ai`/`script`/`build` → friendly error). Legacy role
  names now fail with the generic `InvalidRole` error.
- `Manifest::LEGACY_ZONE_RENAMES` (`inbox` → friendly error).
- `Hooks::Registry::LEGACY_EVENT_RENAMES` (14 legacy event names → friendly
  error). Legacy events now fail with `unknown event: <name>`.
- `CLI::LEGACY_VERB_RENAMES` / `CLI::LEGACY_GROUP_RENAMES` and the
  `CommandRenamed` error class.
- `textus migrate --to=textus/3` verb and `lib/textus/migration/**` (eight
  files, ~924 lines).
- Eight ad-hoc legacy-key guards in `manifest.rb` / `manifest/entry.rb` /
  `manifest/rules.rb`.

### Added
- `Manifest::Schema.validate!` — strict-unknown-keys parser. Manifests with
  any unrecognized key fail uniformly with `unknown key 'X' at '<jsonpath>'`.
- ADR 0003 documenting the sweep and the 0.11.x stepping-stone path.

### Changed
- `Doctor::Check::ProtocolVersion` hint no longer suggests `textus migrate`
  (the verb is gone); points at 0.11.x docs instead.
- Test suite consolidated: five batches of disciplined deletions/merges
  (−4 files, −134 LOC from the post-P6 peak). Net effect across the release:
  test suite grew +8.2% LOC to cover new behavior (schema walker, permissive
  audit-log tolerance).

### Migration
- **From textus/2 (gem ≤0.10.x):** install textus 0.11.x first; run
  `textus migrate --to=textus/3`; then upgrade to 0.12.0.
- **From 0.11.x:** drop-in upgrade.

## 0.11.0 — textus/3 vocabulary redesign (2026-05-25)

**BREAKING:** Protocol bumps to `textus/3`. Stores authored on 0.10.x must run `textus migrate --to=textus/3` before installing 0.11.0. `textus doctor` refuses to operate on un-migrated stores.

### Renamed — actors

- `ai` → `agent`, `script` → `runner`, `build` → `builder`. `Role.resolve` rejects legacy names with a one-line migration hint pointing at `--as=<new>`.

### Renamed — zone

- `inbox` → `intake`. Directory rename + key prefix update + manifest field handled by the migrator.

### Renamed — manifest schema

- `writable_by:` → `write_policy:`; new explicit `read_policy:` on zones (default `[all]`).
- `policies:` (top-level) → `rules:`. Class rename: `Manifest::Policies` → `Manifest::Rules`.
- `projection:` and `generator:` unified under `compute: { kind: projection|external, ... }`.
- `reduce:` (inside compute/projection) → `transform:`.
- `handler_allowlist:` → `intake_handler_allowlist:`.
- `promote_requires:` (reserved in textus/2) → `promotion: { requires: [...] }` and is now **enforced** during `textus accept`.

### Renamed — hook events

- RPC: `:intake` → `:resolve_intake`, `:reduce` → `:transform_rows`, `:check` → `:validate`.
- Pub-sub (object_pasttense): `:put` → `:entry_put`, `:deleted` → `:entry_deleted`, `:built` → `:build_completed`, `:mv` → `:entry_renamed`, `:accepted` → `:proposal_accepted`, `:reject` → `:proposal_rejected`, `:published` → `:file_published`, `:loaded` → `:store_loaded`, `:refreshed` → `:entry_refreshed`, `:refresh_began` → `:refresh_started`, `:refresh_detached` → `:refresh_backgrounded`. `:refresh_failed` kept.
- DSL: single `Textus.on(event, name, **opts) { ... }`. Sugar methods (`Textus.intake`, `Textus.reduce`, `Textus.check`, etc.) and the generic `Textus.hook(...)` form removed.

### Renamed — CLI

- Namespaced: `textus key mv`, `textus key normalize` (was `key migrate`), `textus rule list` (was `policy list`), `textus rule explain` (was `policy explain`), `textus refresh stale` (was `refresh-stale`).
- Top-level mutator `textus mv` removed (use `textus key mv`).
- Envelope-render flag `--format=json` → `--output=json`. Entry-level `format:` in the manifest is unchanged.
- Legacy spellings emit a `CommandRenamed` envelope (`code: "command_renamed"`); legacy flags emit `FlagRenamed`.

### Added

- `textus migrate --to=textus/3`: idempotent one-shot migrator (manifest YAML rewrite, zone directory rename `inbox` → `intake`, frontmatter owner sweep across `.md`/`.json`/`.yaml`, audit-log marker, hook DSL scanner that reports old call sites).
- `textus doctor` check `protocol_version`: refuses textus/2 stores.
- `promotion.requires` predicates: `schema_valid`, `human_accept`. Enforced by `textus accept` for matching rules.

### Internal

- `Manifest::Policies` → `Manifest::Rules` (class + file + accessor + doctor check).
- New errors: `Textus::BadManifest`, `Textus::CommandRenamed`, `Textus::FlagRenamed`.
- Two new domain classes under `Textus::Domain::Policy::Predicates::` for promotion gating.
- Migration toolkit under `Textus::Migration::V3::`.

### Migration notes for 0.10.x users

1. Update `Gemfile`: `gem "textus", "~> 0.11"`.
2. `bundle update textus`.
3. `cd` to each textus store and run `textus migrate --to=textus/3`.
4. Review the hook-scanner findings printed at the end of the migrate output. For each call site, replace `Textus.X(:name) { ... }` with the canonical `Textus.on(:Y, :name) { ... }` per the event rename table above.
5. Run `textus doctor` — should report `ok: true`.
6. Commit the rewritten `.textus/` directory (manifest, audit marker, possibly renamed zone dir).

### Fixed

- **`Doctor::Check::IllegalKeys` now honors `index_filename:`.** Previously the doctor walked every file and directory under a nested entry and flagged any whose basename failed the `[a-z0-9][a-z0-9-]*` segment regex — including `SKILL.md` itself and unrelated siblings like `references/foo.md`. With this fix, when an entry declares `index_filename:`, only the parent-directory segments leading to each matching index file are validated; sibling files and unrelated subtrees are not enumerated and are not flagged. `manifest.enumerate` already filtered correctly via the new glob; this brings the doctor check into parity. Two new specs in `spec/doctor_spec.rb` cover (a) `SKILL.md` is not flagged, (b) sibling `references/` files are not flagged. The pre-existing illegal-parent-segment case (e.g. `Bad_Name/SKILL.md`) still reports `key.illegal`.

## 0.10.5 — tech-debt cleanup + `index_filename:` + docs polish (2026-05-25)

Patch release. One user-facing feature (`index_filename:` on nested manifest entries) plus internal refactors that remove 7 of 19 `rubocop:disable` suppressions. No protocol bump; existing manifests parse unchanged.

### Added

- **Per-entry `index_filename:` on nested manifest entries.** A nested entry MAY declare `index_filename: SKILL.md` (or any other bare basename) to surface that single file per directory as the row; the row's key segments come from the directory path, and siblings are not enumerated. Lets entries project spec-mandated filenames (e.g. agentskills.io's `SKILL.md`) whose uppercase casing would otherwise be rejected by the `[a-z0-9][a-z0-9-]*` key-segment grammar. `resolve(key)` returns the index-filename path for sub-directories. Validation: requires `nested: true`, basename only (no slashes), extension must match the entry's `format:`. New spec `spec/manifest_index_filename_spec.rb`. Documented in SPEC §4.

### Internal

- **`Store::Mover#call` refactor.** Replaces an 81-line method (suppressed `Metrics/AbcSize, Metrics/MethodLength`) with an 8-line orchestrator sequenced over four named private phases — `prepare_plan`, `ensure_uid!`, `perform_move`, `record_move` — coordinated through a `MovePlan` value object. The pre-read envelope is threaded separately so `MovePlan` describes only the planned operation.
- **`Store::Staleness#call` split.** Replaces a 70-line dual-loop method (the most aggressive suppression in the gem — `AbcSize, CyclomaticComplexity, MethodLength, PerceivedComplexity, BlockLength`) with a composer + two single-purpose checks (`GeneratorCheck`, `IntakeCheck`) and a private filter method on the composer. Each new unit fits default rubocop thresholds.
- **`Store::Writer` payload + ctx grouping.** Collapses `write_envelope_to_disk`'s 8 keyword args to 5 by introducing `Store::Writer::Payload = Data.define(:meta, :body, :content)` and reusing `Application::Context` for `role` + `correlation_id`. Applies the same `ctx:` pattern to the sibling `delete_envelope_from_disk`. The class-wide `Metrics/ParameterLists` disable is narrowed to a method-level disable on the `put` back-compat shim (which mirrors the user-facing `Store#put` 7-kwarg signature and cannot be changed).
- **Net suppression change:** 19 `rubocop:disable` lines → 17; 7 metric-cop suppressions removed; one `ParameterLists` disable narrowed in scope. Full suite unchanged.

### Documentation

- **SPEC.md §5.2.1 added.** Documents the `generator:` field — the externally-generated-derived-entry shape (build runner produces the file; textus tracks `sources:` for staleness via `_meta.generated.at`). The field was always parsed and tested but had no spec coverage. Clarifies that textus never executes `command:` — consistent with §2 "Not an executor."
- **README.md trimmed.** Removed the duplicated "CLI verbs" and "Zones and roles" tables; readers are pointed at SPEC §5 / §9 and `docs/zones.md` for the canonical surfaces. README narrative kept.
- **docs/conventions.md** now covers both derived-entry shapes (`projection:` for declarative compute inside textus; `generator:` for external build tools) and the current intake / freshness model (top-level `policies:` + `textus refresh-stale`). Replaces a stale section that described a pre-0.4 build-runner pattern.
- **CONTRIBUTING.md** sources-of-truth pointer updated. Per-release implementation plans are kept locally by maintainers and no longer signposted in public docs.

## 0.10.4 — GitHub folder intake recipe + skill-bundle deferral ADR (2026-05-24)

Patch release. Ships a working "pull a GitHub folder as a skill bundle, fan it out to derived entries" pattern as opt-in example hooks under `examples/claude-plugin/recipes/`, with hermetic specs and user-facing docs. Captures the design decision to defer first-class skill-bundle support to a future release. No `lib/` changes; CLI, wire protocol, event surface, manifest schema, and doctor checks are all unchanged.

### Added

- **`examples/claude-plugin/recipes/github_folder.rb`** — `Textus.intake(:github_folder)` handler that fetches a folder from a public GitHub repo via the REST tree + blob endpoints and returns a single entry whose `content.files` is a `{ relative_path => bytes }` hash. Uses Ruby stdlib (`net/http`, `json`, `base64`); no new gem dependencies. Fetcher is injectable for testability.
- **`examples/claude-plugin/recipes/skill_fanout.rb`** — `Textus.refreshed(:skill_fanout, keys: "intake.skills.*")` listener that fans a bundle out into `vendor.skills.<slug>.*` derived entries with reconciliation: orphaned children whose source path disappeared upstream are deleted. Inner writes use `suppress_events: true` to prevent recursion.
- **`examples/claude-plugin/recipes/README.md`** — explains that files in `recipes/` are opt-in and do not auto-load (they live outside `.textus/hooks/`).
- **`docs/recipe-github-skill-bundle.md`** — end-to-end recipe: manifest snippet, copy commands, caveats (30s timeout, recursion guard, public-repos-only, hook-not-bundled-with-content).
- **`docs/architecture/decisions/0001-skill-bundle-deferral.md`** — Architecture Decision Record documenting the friction in the current primitives, the three-option design space (status quo, intake-returns-N-entries, hooks-as-content), the choice to stay at status quo, and the explicit criteria for revisiting. First entry under the new `docs/architecture/decisions/` ADR home.
- **`spec/examples/`** — new spec subdirectory with hermetic unit tests for both recipe files. Tests use captured GitHub API fixtures under `spec/examples/fixtures/`; no network access in CI.

### Documentation

- The "Recipes" concept is introduced as a deliberately opt-in pattern: example code that demonstrates how to build on textus primitives without committing the core surface to the underlying responsibility. The ADR explains why this is preferable to promoting the recipe into a builtin or a new CLI verb today.

## 0.10.3 — Documentation refresh and legacy-code removal (2026-05-23)

Patch release. Two pieces of work: (1) docs describe current state only — every reference to pre-0.9.2 zone names, pre-0.10.2 sentinel layout, pre-0.5 audit-log format, and other version-history annotations is stripped from user-facing docs; (2) the corresponding backward-compatibility code paths are deleted from `lib/`. The wire protocol stays `textus/2`. Callers conforming to the current SPEC are unaffected; callers carrying obsolete config now hit silent drops or parse failures instead of helpful migration messages.

### Removed

- **`Doctor::Check::LegacyIntakeFields`** — deleted. Manifest parsing already rejected these fields at load; the doctor check was redundant.
- **TSV audit-log reader** in `Store::AuditLog#parse_row` and `#check_line` — pre-0.5 audit logs are no longer transparently read. Non-JSON lines surface as `invalid_json` integrity violations.
- **Legacy sibling sentinel migration** in `Infra::Publisher` and `Store::Sentinel.legacy_path` — pre-0.10.2 stores with sibling `<target>.textus-managed.json` files are no longer recognized as managed. Fix: `rm <target>.textus-managed.json && textus build`.
- **Manifest rename-migration rejections** — entries containing `source:`, `intake.fetch`, `intake.{ttl,on_stale,sync_budget_ms}`, or `projection.reducer` no longer raise migration hints. These obsolete fields are silently ignored by the parser.
- **`textus/1` helpful-message branch** in `Manifest.load` — unsupported versions now produce a single generic error.
- **`textus stale` CLI stub** — removed; calling it now returns `unknown verb: stale` like any other typo.
- **`Manifest::Entry#derived?`** alias — both internal callers now invoke `in_generator_zone?` directly.
- **Stale CLI help text** — `textus migrate {zones,policies}` (reverted in 0.9.2) and "`--format=json` accepted for back-compat" wording removed from `textus --help`.

### Documentation

- **`CONTRIBUTING.md`** now points readers at SPEC / ARCHITECTURE / `docs/` / CHANGELOG as the sources of truth. Per-release implementation plans are kept locally by maintainers and are no longer signposted in public docs.
- **README, SPEC, ARCHITECTURE, docs/zones, docs/events, docs/conventions, examples/claude-plugin/README** — stripped `(0.8.2+)`, `(0.9.0+)`, `(0.9.2)`, `(v1.0)`, `(v1.1)`, `(v1.2)`, `(v0.3)` annotations from headings, parentheticals, and inline notes. Removed "Renamed in 0.9.2" / "Pre-0.9.2 stores" / "New in 0.9.0" / "Backward compatibility (v0.5)" callouts. Example code that used pre-0.9.2 zone names (`canon`, `intake`, `pending`, `derived`) now uses current names (`identity`, `inbox`, `review`, `output`).
- **`docs/events.md`** — header count corrected to "15 events: 3 RPC and 12 pub-sub" (previously read "12 events", with refresh\_\* mentioned in subtext); stale Linear manifest example updated to use top-level `policies:` block.
- **SPEC.md §10.2** — removed `legacy_intake_fields` from the builtin doctor-check list.
- **SPEC.md §11** — dropped `textus/1` back-compat acceptance from the implementation checklist; the spec no longer mentions the legacy v0.1 zone-synthesis fallback.
- **CHANGELOG entries for past releases are unchanged** — historical record stays intact.

### Tests

- Removed `spec/doctor/check/legacy_intake_fields_spec.rb`.
- Removed 4 manifest-intake migration-rejection specs and 3 publisher/audit-log legacy-format specs.

## 0.10.2 — Doctor and store cleanup (2026-05-23)

Patch release. Internal cleanup: extracts `Store::Sentinel`, moves audit-log integrity into `Store::AuditLog`, surfaces previously-swallowed schema parse errors, and tidies two doctor checks. No CLI, wire-protocol, or behavioral changes for plugin authors. Sentinel JSON shape changes (repo-relative paths) are forward-compatible; legacy absolute paths are still read correctly.

### Added

- `Textus::Store::Sentinel` value object owning the sentinel JSON shape (`source`/`target`/`sha256`/`mode`) and the on-disk path layout. Repo-relative paths on write; legacy absolute paths still accepted on read.
- `Textus::Store::AuditLog#verify_integrity` returns line-by-line integrity violations as `{lineno, reason, detail}` hashes.
- `Textus::Schema#unowned_fields` returns field names whose spec lacks `maintained_by`.
- New doctor check `schema_parse_error` (error level) surfaces YAML parse failures on `schemas/*.yaml`. Previously these were silently rescued in `UnownedSchemaFields`, leaving operators with no signal.

### Changed

- `Infra::Publisher` delegates sentinel I/O to `Store::Sentinel`. The sentinel JSON now stores repo-relative `source`/`target` so example trees can be committed without leaking author paths.
- `Doctor::Check::Sentinels` delegates parse/orphan/drift detection to `Store::Sentinel`. Drops `rubocop:disable Metrics/BlockLength`.
- `Doctor::Check::AuditLog` delegates parsing to `Store::AuditLog#verify_integrity`. Drops `rubocop:disable Metrics/BlockLength`.
- `Doctor::Check::ManifestFiles` uses `Textus::Key::Path.resolve` instead of reimplementing leaf-path math.
- `Doctor::Check::UnownedSchemaFields` uses `Schema#unowned_fields` instead of reaching into `schema.fields` and the raw `maintained_by` Hash key.
- `examples/claude-plugin/.gitignore` no longer excludes `.textus/sentinels/`. The example's sentinels are now committed with repo-relative paths.

### Documentation

- `SPEC.md` builtin doctor-check list updated to include `schema_parse_error`, and brings the prose up to date with three checks shipped in 0.9.x/0.10.0 that were missing from the list (`policy_ambiguity`, `handler_allowlist`, `legacy_intake_fields`).

## 0.10.1 — Documentation refresh and spec hygiene (2026-05-22)

Lightweight maintenance release: documentation refresh plus spec-suite hygiene. No `lib/` changes; no CLI, wire-protocol, or behavioral changes.

### Changed

- `docs/architecture.md` deleted. `ARCHITECTURE.md` is now the single source of truth for the layered architecture. Inbound links in `docs/zones.md`, `docs/events.md`, and `textus.gemspec` updated.
- `SPEC.md` examples and CLI snippets refer to the post-0.9.2 default zone names (`identity` / `inbox` / `review` / `output`) instead of the pre-rename `canon` / `intake` / `pending` / `derived`. Prose that explicitly explains the 0.9.2 rename — including the v0.1 back-compat manifest example and the zone-rename table — is preserved.
- `README.md` `refresh-stale` examples switched to `--zone=inbox`; the `cat .textus/zones/...` example points at the `output` zone.
- `ARCHITECTURE.md` layer diagram references `Infra::Publisher` instead of bare `Publisher`.
- `docs/zones.md` references `Textus::Infra::Publisher` instead of bare `Publisher`.

### Testing

- Deleted redundant `spec/proposal_spec.rb` (the same `"2026-05-19-add-bob"` fixture is covered more thoroughly by `spec/application/writes/accept_spec.rb`, the canonical post-0.9.1 home for Application-layer write tests).
- Extracted `shared_context "textus_store_fixture"` into `spec/support/fixtures.rb`; 28 specs adopt it, replacing the repeated `let(:tmp)` / `let(:root)` / `after { FileUtils.remove_entry(tmp) }` triplet. `spec/spec_helper.rb` now autoloads `spec/support/**/*.rb`.
- Fixed an `instance_variable_set(:@intake_handler, nil)` anti-pattern in `spec/refresh_spec.rb` — the "no intake declared" case now uses a manifest entry that was never given an intake handler, instead of mutating a private ivar after construction.

## 0.10.0 — Shim removal, signal-based zone detection, Builder extraction (2026-05-22)

### Breaking — Ruby API

- `Textus::Publisher` constant removed. Use `Textus::Infra::Publisher`.
- `Textus::Store::View` class removed. Use `Textus::Application::Context`
  (constructed via `Composition.context(store, role:)`).
- `Textus::Builder` class removed as a public entry point. Build logic lives
  in `Textus::Application::Writes::Build`. External callers should use
  `Textus::Composition.writes_build(ctx).call` instead of
  `Textus::Builder.new(store).build`. The `Textus::Builder` namespace is
  retained internally only for nested helpers (`Builder::Pipeline`,
  `Builder::Renderer::*`).
- `Application::Context` no longer exposes `put` / `delete` / `get` / `list`
  / `where` shim methods. Hook callers that receive a Context via the
  `store:` hook keyword must call `ctx.store.put(...)` etc., and explicitly
  pass `as: ctx.role` for write operations.
- Intake handler return values must use `_meta:` for frontmatter. The
  previous `frontmatter:` legacy key is no longer accepted.

### Fixed

- `textus reject` and `textus refresh-stale` now work correctly for stores
  that use the post-0.9.2 default zone names (`review`, `output`).
  Zone-kind detection is now signal-based (driven by `writable_by:`
  membership), not name-based. Stores using the pre-0.9.2 names (`pending`,
  `derived`) continue to work.
- Event payloads' `store:` keyword now carries a Context whose
  `correlation_id` matches the event payload's top-level `correlation_id`
  key. Previously the `store:` Context received a fresh, unrelated
  `correlation_id`.

### Added

- `Textus::Manifest::Entry#in_generator_zone?` and `#in_proposal_zone?`
  predicates. Internal `derived?` retained as an alias of
  `in_generator_zone?`.
- `:built` and `:published` events now carry `correlation_id` in the
  payload, matching the existing pattern on `:put` / `:deleted` /
  `:accepted`.

### Removed

- Legacy zone-purpose annotations for `canon` / `intake` / `pending` /
  `derived` removed from `Textus::Intro::ZONE_PURPOSES`. Custom-named zones
  continue to get no purpose annotation (existing behavior). Stores still
  using the pre-rename default names will simply not get purpose
  annotations on those zones in `textus intro` output.
- Dead code: `Textus::Manifest#validate_keys!` removed (had no callers).

### Internal

- Builder logic fully extracted into `Application::Writes::Build`.
- CLI verbs now share `context_for(store)` / `resolved_role(store)`
  helpers on `CLI::Verb`.
- Internal helpers in `Manifest`, `Doctor`, and `Manifest::Entry` are
  properly marked private.

### Unchanged

- Wire protocol stays `textus/2`. Envelope shape unchanged.
- CLI verbs, their flags, and their JSON output shape — unchanged.
- Manifest YAML schema — unchanged.
- Event names — unchanged (payload gains `correlation_id` on `:built` /
  `:published`, but no existing key is removed or renamed).
- Hook DSL — unchanged in shape. The `store:` keyword still passes an
  object that responds to `.get`, `.list`, `.where`. The Context's
  role-aware `with_role` is the recommended construction site for hook
  contexts now.

### Migration recipe

```ruby
# Hook handlers — before 0.10.0
Textus.hook(:intake, :my_hook) do |store:, config:, args:|
  store.put("inbox.foo", meta: { ... }, body: "...")  # used Context shim
end

# Hook handlers — 0.10.0+
Textus.hook(:intake, :my_hook) do |store:, config:, args:|
  ctx = store  # rename for clarity if desired
  ctx.store.put("inbox.foo", meta: { ... }, body: "...", as: ctx.role)
end

# Intake handler returns — before 0.10.0
{ frontmatter: { ... }, body: "..." }  # legacy key

# Intake handler returns — 0.10.0+
{ _meta: { ... }, body: "..." }  # _meta is the canonical key
```

If you imported the removed constants directly:

```ruby
# Before
Textus::Publisher        # removed
Textus::Store::View      # removed
Textus::Builder.new(store).build(key, ...)  # removed

# After
Textus::Infra::Publisher
Textus::Application::Context  # via Composition.context(store, role:)
Textus::Composition.writes_build(ctx).call(key, ...)
```

## 0.9.2 — Policies, audit verbs, zone rename (2026-05-22)

### Breaking — manifest YAML

- **Top-level `policies:` block added.** Replaces entry-level `intake.ttl` and
  `intake.on_stale`. Hand-edit existing manifests (see migration recipe below);
  no migrator ships with 0.9.2 because the gem is pre-1.0 with no known
  outside upgraders.
- **Default zone names renamed.** `canon → identity`, `intake → inbox`,
  `pending → review`, `derived → output`. `working` unchanged. Hand-edit
  the manifest + `mv` the zone directories (see recipe below).
- Custom-named zones are unaffected.

### Breaking — CLI

- `textus stale` removed. Use `textus freshness`.

### Added — verbs

- `textus freshness [--prefix=K] [--zone=Z]` — per-entry status (ttl, age,
  next_due_at, status: fresh|stale|never_refreshed|no_policy).
- `textus audit [--key=K] [--zone=Z] [--role=R] [--verb=V] [--since=X]
  [--correlation-id=ID] [--limit=N]` — query `.textus/audit.log`.
- `textus blame KEY` — audit rows joined with git commit metadata.
- `textus policy list` — dump effective policies.
- `textus policy explain KEY` — show per-slot winners and matching blocks.

### Added — domain

- `Textus::Domain::Policy::Refresh` — ttl + on_stale value, exports to
  `Domain::Freshness::Policy`. `on_stale` vocab is `warn | sync | timed_sync`
  (unchanged from 0.9.0).
- `Textus::Domain::Policy::Promote` — promote_requires predicate.
- `Textus::Domain::Policy::HandlerAllowlist` — allowed intake handlers.
- `Textus::Domain::Policy::Matcher` — glob match + specificity ranking.
- `Textus::Manifest::Policies` — collection over policy blocks with
  most-specific-wins resolution.

### Added — doctor checks

- `policy_ambiguity` — two blocks of the same specificity matching one key.
- `handler_allowlist` — intake handler outside its policy's allowlist.
- `legacy_intake_fields` — `intake.ttl`/`intake.on_stale` still present in
  raw YAML.

### Unchanged

- Wire protocol stays `textus/2`. Envelope shape unchanged.
- Hook DSL, event names, role gate semantics, schema validation unchanged.
- `on_stale:` vocabulary (`warn | sync | timed_sync`) and its semantics
  (return-stale / block-and-refresh / try-with-deadline) are unchanged —
  policies merely change where the value lives.
- `:publish` hook (shipped 0.8.2) remains the extension point for custom
  publish targets.

### Migration recipe (hand-edit, no migrator ships)

```sh
# In your existing .textus/manifest.yaml:
#   1. Rename zones[].name fields: canon→identity, intake→inbox,
#      pending→review, derived→output.
#   2. Rewrite every entries[].zone and entries[].path prefix accordingly.
#   3. Move each entries[].intake.ttl / on_stale / sync_budget_ms into
#      a new top-level policies:[] block keyed by the entry's exact key:
#
#        policies:
#          - match: "inbox.news.hn"
#            refresh: { ttl: 6h, on_stale: sync }

# On disk:
mv .textus/zones/canon   .textus/zones/identity
mv .textus/zones/intake  .textus/zones/inbox
mv .textus/zones/pending .textus/zones/review
mv .textus/zones/derived .textus/zones/output

# Verify:
textus doctor
```

Find-and-replace tips for ad-hoc references in your own files:

```sh
# README snippets, CI yaml, shell scripts
sed -i.bak \
  -e 's/\bcanon\b/identity/g' \
  -e 's/\bintake\b/inbox/g' \
  -e 's/\bpending\b/review/g' \
  -e 's/\bderived\b/output/g' \
  -e 's/textus stale/textus freshness/g' \
  README.md CONTRIBUTING.md
```

## 0.9.1 — write-path layering + request Context (2026-05-22)

### Changed — internal architecture (no plugin-visible impact)

- Promoted `Store::View` to `Application::Context`. The new Context carries `store`, `role`, `correlation_id`, `clock`, and `dry_run`. It answers `can_read?(zone)` / `can_write?(zone)` via the new `Domain::Permission` value. `Store::View` remains as a deprecated alias for one release; slated for removal in 0.10.0.
- Extracted `Domain::Permission` from `Manifest#zone_writers`. Pure predicate value — `allows_read?(role)` / `allows_write?(role)`. Manifest gains `#permission_for(zone_name)` returning a `Permission`.
- Extracted write-path use cases under `Application::Writes::*`:
  - `Writes::Put` (was `Store::Writer#put` orchestration)
  - `Writes::Delete` (was `Store::Writer#delete` orchestration)
  - `Writes::Build` (was `Builder#build` orchestration)
  - `Writes::Accept` (was `Proposal.accept`)
  - `Writes::Publish` (was direct calls to `Publisher.publish`)
- `Store::Writer#put` and `#delete` reduced to pure I/O (`#write_envelope_to_disk`, `#delete_envelope_from_disk`). The original methods remain as backward-compat shims that delegate to the use cases.
- `Builder`, `Proposal`, `Publisher` become thin shims. `Publisher` also moved to `Textus::Infra::Publisher` (its prior location remains as an alias).
- `Store#get`, `#put`, `#delete` reduced to 2-line shims through the new `Composition` module. `Store` itself no longer imports from `Application::*`.
- New `Composition` factory module wires Contexts and use cases. CLI verbs construct via `Composition.context(store, role:)` then `Composition.<use_case>(ctx).call(...)`.
- `Refresh::Worker` and `Refresh::Orchestrator` migrated to take `Context` instead of `store:` + `as:`.

### Added

- Every event payload now includes `correlation_id` — a UUID generated once per Context. Hook authors can use this to correlate events within a single request (e.g., a `:refreshed` event and a downstream `:built` event share an ID).

### Deprecated

- `Textus::Store::View` — use `Textus::Application::Context`. Removed in 0.10.0.
- `Textus::Publisher` — use `Textus::Infra::Publisher` or `Textus::Application::Writes::Publish`. Removed in 0.10.0.

### Unchanged

- Plugin DSL, manifest YAML schema, CLI verb JSON output, envelope fields, event names, wire protocol — all identical to 0.9.0.
- No migration needed for plugin authors.

## 0.9.0 — intake, event standardization, read-time freshness, layered architecture (2026-05-22)

### Breaking — manifest schema
- The `source:` block is renamed to `intake:`. Its inner `fetch:` is renamed to `handler:`. Other inner fields (`config:`, `ttl:`) keep their names.
- Loading a manifest that still uses `source:` raises a clear migration error.

### Breaking — event names (pub-sub bus)
- `:fetch` → `:intake` (RPC)
- `:delete` → `:deleted`
- `:refresh` → `:refreshed`
- `:build` → `:built`
- `:publish` → `:published`
- `:accept` → `:accepted`
- `:put`, `:mv`, `:reject`, `:loaded` are unchanged (already past tense).

### Breaking — DSL sugar
- `Textus.fetch(:name)` → `Textus.intake(:name)`
- `Textus.refresh`, `.build`, `.publish`, `.delete`, `.accept` rename to past-tense equivalents.
- The primitive `Textus.hook(event, name)` is unchanged — event symbols update per above.

### Added — read-time freshness
- Every entry's manifest may declare `intake.on_stale: warn | sync | timed_sync` (default `warn`).
  - `warn` — return stale envelope with `stale: true`, `stale_reason: "…"`; no refresh.
  - `sync` — refresh inline, return fresh envelope.
  - `timed_sync` — attempt sync up to `sync_budget_ms` (default 500ms); if exceeded, fork+detach a child to complete the refresh and return stale + `refreshing: true` to the caller. Unix only; on Windows falls back to `warn`.
- New envelope fields on `textus get`: `stale`, `stale_reason`, `refreshing`.

### Added — refresh lifecycle events
- `:refresh_began { key, mode }` fires when refresh begins.
- `:refresh_failed { key, error_class, error_message }` fires on intake errors.
- `:refresh_detached { key, started_at, budget_ms }` fires when timed_sync gives up waiting and forks.

### Added — actuator
- `textus refresh-stale [--prefix=KEY] [--zone=Z]` — refreshes every entry whose TTL has expired. Returns `{ refreshed, failed, skipped }` JSON. Exits non-zero on any failure. Intended for cron / CI.

### Added — doctor check
- `textus doctor` now verifies every manifest `intake.handler:` resolves to a registered `Textus.intake(:name)`, reports missing handlers as errors, and orphan registrations as warnings.

### Changed — internal architecture (no plugin-visible impact)
- Internals reorganized into four layers: `domain/` (pure values), `application/` (use cases), `infra/` (adapters), and `cli/` (interface). Plugin DSL, manifest schema, CLI verbs, and envelope shape are unchanged.
- `Freshness` is split into `Domain::Freshness::Evaluator` (pure) + `Domain::Freshness::Policy#decide` (data-driven) + `Application::Refresh::Orchestrator` (effects).
- `Refresh.call` is now a one-line shim over `Application::Refresh::Worker.run`. `Refresh::Lock` and `Refresh::Detached` moved to `Infra::Refresh`.
- `Store#get` now routes through `Application::Reads::Get`. `Store::Reader#get` was reduced to pure I/O (`#read_raw_envelope`) — third-party code calling it directly should switch to `Store#get` for freshness annotations.

### Unchanged
- Wire protocol stays `textus/2`.
- `:reduce`, `:check`, `:put` unchanged.
- The recursive `hooks/**/*.rb` loader from 0.8.2.

### Migration
1. In `.textus/manifest.yaml`, replace every `source:` with `intake:` and every `fetch:` inside it with `handler:`. No other inner-field renames needed.
2. In hook files, replace `Textus.fetch(:name)` with `Textus.intake(:name)` and the other five pub-sub sugar names with their past-tense equivalents.
3. (Optional) Add `on_stale: timed_sync` to entries where you want self-healing reads.
4. Wire `textus refresh-stale` into cron / GH Actions for scheduled freshness.
5. If you subscribed to the `:refresh_started` event during 0.9.0 betas, rename your handler to `Textus.refresh_began(:name)`.
6. If you called `Textus::Refresh::Lock` or `Textus::Refresh::Detached` directly (you probably did not), update to `Textus::Infra::Refresh::Lock` / `Textus::Infra::Refresh::Detached`.

## 0.8.3 — :mv, :reject, :loaded events (2026-05-22)

### Added
- New `:mv` event — fires after a successful `store.mv`. Payload:
  `{ key:, from_key:, to_key:, envelope: }` where `key:` equals `to_key:`
  so `keys:` glob filters route against the entry's post-move home.
  `:put` and `:delete` remain suppressed for renames; `:mv` is the sole signal.
- New `:reject` event + `store.reject(pending_key, as: "human")` +
  `textus reject KEY --as=human` CLI verb. Counterpart to `:accept` —
  explicitly discards a proposal. Fires `:delete` then `:reject`.
- New `:loaded` event — fires exactly once at the tail of `Store#initialize`,
  after all hooks are registered and reader/writer are built. Use for cache
  warmups and one-shot setup. Payload: `store:` only.

## 0.8.2 — Hook DSL sugar + :publish event (2026-05-22)

### Added
- Per-event hook sugar: `Textus.fetch`, `.reduce`, `.check`, `.put`,
  `.delete`, `.refresh`, `.build`, `.accept`, `.publish`. Each takes
  `(name, **opts, &blk)` and delegates to the existing registry. Block
  signatures are per-event (use `**` to absorb unused kwargs).
- New `:publish` pub-sub event. Fires once per file written to a repo
  path (both for the fixed-list `publish_to:` case and the `publish_each:`
  per-leaf case). Payload: `{ key:, envelope:, source:, target: }`.
  Listeners can react per-file — e.g. `git add` each published file,
  notify on writes, compute checksums.
- `.textus/hooks/**/*.rb` — hook files in subdirectories are now loaded.
  Subdirectory names are organizational; the registered event and name
  come from the DSL call, not the file path. Files load in alphabetical
  order by full path.

### Unchanged
- `Textus.hook(:event, :name, &blk)` primitive — still works, still the
  authoritative entry point.
- `:build` event semantics — still fires once per derived entry.
- Registry shape, dispatcher behavior, audit log, wire protocol
  (`textus/2`), envelope shape.

### Example migrations
The bundled `examples/claude-plugin` was migrated to the new DSL
(snake_case names, sugar methods). No behavioral change; serves as the
canonical example.

## 0.8.1 — Terminology cleanup (2026-05-21)

### Breaking — intro output
- `textus intro` JSON: the `"extensions"` key is renamed to `"hooks"`. Consumers
  reading `env["extensions"]` must switch to `env["hooks"]`. Wire protocol
  remains `textus/2`; envelope shape on read/write is unchanged.

### Internal Ruby renames
- `Textus::Store#load_extensions` → `Textus::Store#load_hooks`.
- `Textus::Intro.extensions_for` → `Textus::Intro.hooks_for`.
- Error string `"failed loading extension <file>"` → `"failed loading hook <file>"`.

### Fixed
- `textus doctor` `:check`-hook failure hint pointed to `.textus/extensions/`,
  which has never existed in 0.6+. Now correctly points to `.textus/hooks/`.

### Docs
- SPEC.md §5.10: "single extension verb" → "single hook verb".
- Scaffolded `.textus/hooks/README.md` no longer mixes "hook" and "extension"
  terminology.

## 0.8.0 — Folder restructure & Zeitwerk autoload (2026-05-21)

### Breaking — internal Ruby renames
Internal Ruby constants renamed. No deprecation aliases; downstream code referencing internals must update directly.
- `Textus::EventBus` → `Textus::Hooks::Dispatcher`
- `Textus::HookRegistry` → `Textus::Hooks::Registry`
- `Textus::BuiltinHooks` → `Textus::Hooks::Builtin`
- `Textus::Extensions` (module) → `Textus::Hooks::Loader`
- `Textus::StoreView` → `Textus::Store::View`
- `Textus::AuditLog` → `Textus::Store::AuditLog`
- `Textus::ManifestEntry` → `Textus::Manifest::Entry`
- `Textus::KeyDistance` → `Textus::Key::Distance`
- `Textus::Path` → `Textus::Key::Path`
- `Textus::SchemaTools` → `Textus::Schema::Tools`
- `Textus::CLI::<Verb>` → `Textus::CLI::Verb::<Verb>` (all 23 verbs)
- `Textus::CLI::<Name>Group` → `Textus::CLI::Group::<Name>` (key, schema, hook)
- `Textus::Doctor::Check::Extensions` → `Textus::Doctor::Check::Hooks`
- `Hooks::Registry#initialize` keyword `bus:` renamed to `dispatcher:`.

### Breaking — doctor CLI surface
- `textus doctor --check=extensions` → `textus doctor --check=hooks`. The check name listed in `ALL_CHECKS` and the SPEC §10.2 enumeration changes from `"extensions"` to `"hooks"`, matching the hook subsystem rename in 0.6.
- Doctor issue `code` for broken hook files: `extension.load_failed` → `hook.load_failed`.
- Doctor::Check::Hooks now inspects `.textus/hooks/` (matches `Store#load_extensions`). Previously inspected `.textus/extensions/`, which was the pre-0.6 directory — the check was dead code on any store created with current `textus init`.

### Added
- `Textus::Entry::Base` — explicit strategy interface for entry formats. Concrete strategies inherit and override.
- `Textus::Builder::Renderer` — explicit base for output renderers.
- `Textus::Doctor::Check` — explicit base for doctor checks. Each builtin check (9 total) is now its own file under `lib/textus/doctor/check/`.

### Changed
- Per-format schema validation moved from `Store::Reader`/`Store::Writer` onto `Entry::Base#validate_against`. Reader/Writer no longer carry a `case mentry.format` switch.
- `Textus::Doctor` reduced to an orchestrator; the 9 builtin checks live under `Doctor::Check::*`.
- `lib/textus.rb` switched to Zeitwerk autoload. The manual `require_relative` tree (75 lines) is gone.
- `lib/textus/builder/renderers/` directory renamed to `renderer/` (singular) to match `Builder::Renderer::*` namespace.

### Migration
External code referencing the old internal constants must rename. `Textus.hook`, `Textus.with_registry`, the entire CLI surface, and the `textus/2` wire format are unchanged. The published API (`Store`, `Manifest`, `Envelope`, `Etag`, `Role`, `Error` hierarchy, `Builder`, `Doctor`, `Refresh`, `Init`, `CLI.run`) is unchanged.

## 0.7.0 — Reader/Writer split, EventBus, Builder pipeline (2026-05-21)

### Added
- `Textus::EventBus` is now the publish/subscribe core for lifecycle events. Embedded callers can `store.bus.subscribe(:put, :name) { ... }` outside the `.textus/hooks/` directory. Hook semantics, audit behavior, and the 2-second timeout are unchanged.

### Changed
- Internal: extracted `Textus::Path` and `Textus::Envelope` value modules; `Manifest`, `Store`, `Staleness`, and `Builder` now share the same path/envelope construction.
- Internal: split `Textus::Store` into `Store::Reader` and `Store::Writer`. Public API unchanged. `Mover`, `Validator`, and `Staleness` now take explicit collaborators instead of the full store.
- Internal: removed `Store::Events`; replaced by the bus.
- Internal: restructured `Textus::Builder` as a step pipeline (`LoadSources → Project → Render → Write`) with one renderer per format (`markdown/text/json/yaml`). Adding a new output format is now a single-file change.

## 0.6.1 — Deprecation cleanup

### Breaking
- Flat verb aliases promised "removed in 0.6" are now actually removed:
  - `textus mv` → `textus key mv`
  - `textus uid` → `textus key uid`
  - `textus migrate-keys` → `textus key migrate`
  - `textus schema-init` → `textus schema init`
  - `textus schema-diff` → `textus schema diff`
  - `textus schema-migrate` → `textus schema migrate`
  - `textus schema KEY` (positional) → `textus schema show KEY`
  - `textus action NAME` → `textus hook run NAME`
- `Textus::CLI::Action` class renamed to `Textus::CLI::HookRun`; file `cli/action.rb` → `cli/hook_run.rb`.
- `Textus::CLI::DeprecatedAliasMixin` module deleted (no remaining users).
- `textus migrate v2` command removed along with `Textus::MigrateV2` module and `Textus::CLI::Migrate` class. The migration was a one-line manifest rewrite (`version: textus/1` → `version: textus/2`); on-disk entry shapes never changed. To upgrade a `textus/1` manifest, edit `.textus/manifest.yaml` directly. `Manifest.load` still detects the old version and prints the exact edit in its error message.

## 0.6.0 — Hook unification

### Breaking
- Four DSL verbs (`Textus.action`, `Textus.reducer`, `Textus.hook`, `Textus.doctor_check`) collapsed into one: `Textus.hook(event, name, **opts) { ... }`.
- `ExtensionRegistry` class renamed to `HookRegistry`.
- `.textus/extensions/` directory renamed to `.textus/hooks/`. No back-compat read.
- Manifest: `source.action:` → `source.fetch:` (also renames the registry event from `:action` to `:fetch` and the `ManifestEntry#action`/`#action_config` accessors to `#fetch`/`#fetch_config`).
- Manifest: `projection.reducer:` → `projection.reduce:`.
- CLI: `textus extension list` → `textus hook list`; output rows keyed by `event`+`mode` instead of `kind`.
- CLI: `textus put --action=NAME` → `textus put --fetch=NAME`.
- Pub-sub hooks gain an optional `keys:` glob filter for per-key scoping.
- Hook signatures standardized: `store:` is now mandatory and first on every hook (`:reduce` previously had no `store:`). Event-specific kwargs follow.
- `:accept` event renames `pending_key:` → `key:` to match every other lifecycle event.
- All event names are now verbs in a uniform grammar (RPC verbs `:fetch :reduce :check`; pub-sub verbs `:put :delete :refresh :build :accept`).

### New
- `EVENTS` metadata table on `HookRegistry` is the single source of truth for event names, argument shapes, return shapes, and failure semantics (rpc vs pubsub).
- Shape-check at registration: callable kwargs are verified against the EVENTS table at load time; mismatched signatures raise `UsageError` immediately instead of surfacing at fire time.

## 0.5.0 — Wire protocol `textus/2`; CLI restructure; Store split (breaking)

This release reshapes the public surface ahead of 1.0. The wire protocol bumps to `textus/2`; the CLI grows nested subcommand groups; `Store` is decomposed into a thin facade plus four focused helpers; the audit log finally matches its documented NDJSON shape; and a pile of pre-0.4 cruft gets cut.

### Wire protocol — `textus/1` → `textus/2`

- **Breaking:** every envelope now carries `"_meta"` instead of `"frontmatter"`. For json/yaml entries, envelope `content` no longer carries a duplicate `_meta` — the metadata lives only at the envelope's top level.
- **Breaking:** `Manifest.load` refuses `textus/1` manifests with a pointer at the new migration command. On-disk file shapes are unchanged — only the manifest version string changes.
- **New:** `textus migrate v2` flips `version: textus/1` to `version: textus/2` in `.textus/manifest.yaml`. One command, no file edits.
- **Internal cleanup:** `Store#extract_uid`, `enforce_name_match!`, `serialize_for_put`, `validate_all`, and `build_envelope` no longer format-switch — metadata access is uniform. Role-authority validation now works for json/yaml entries (was markdown-only).
- **API:** `Store#put` keyword renamed from `frontmatter:` to `meta:`. Action callbacks return `_meta:` (formerly `frontmatter:`).

### CLI — nested subcommand groups

- **New:** `textus key {mv, uid, migrate}`, `textus schema {show, init, diff, migrate}`, `textus extension {list, run}`. Discoverable, groupable, scales.
- **Deprecated (removed in 0.6):** the flat verbs `mv`, `uid`, `migrate-keys`, `schema-init`, `schema-diff`, `schema-migrate`, `extensions`, `action` still work but emit a stderr deprecation warning. `textus schema KEY` (positional dotted-key form) keeps working via a back-compat fallback in `SchemaGroup`.
- **New:** `textus list`, `textus get`, etc. default to JSON output. `--format=json` is still accepted; non-json values still raise.
- **CLI refactor:** `lib/textus/cli.rb` shrank from 434 LOC to ~100 LOC. Every verb is now a small command-object file under `lib/textus/cli/`. Dispatch is a frozen `VERBS` hash.

### Audit log — true NDJSON

- **Breaking:** `.textus/audit.log` rows are now one JSON object per line (`{"ts":..., "role":..., "verb":..., "key":..., "etag_before":..., "etag_after":...}`). Missing etags are `null`, not the string `"NULL"`.
- **Structural shape:** `from_key`, `to_key`, `uid` (mv rows) live at the top level; arbitrary contextual data goes into an `extras` sub-object that is omitted when empty.
- **Back-compat:** legacy TSV rows still parse during 0.5 — `AuditLog#last_writer_for` and `Doctor#check_audit_log` accept both formats. Legacy support removed in 0.6.

### Doctor

- **New:** `textus doctor --check=schema_violations[,name,…]` runs only the named built-in checks. The 9 built-ins are `manifest_files`, `schemas`, `templates`, `extensions`, `illegal_keys`, `sentinels`, `audit_log`, `unowned_schema_fields`, `schema_violations`. Extension checks always run.
- **Breaking:** the standalone `textus validate-all` verb is gone. Use `textus doctor --check=schema_violations` instead. The internal `Store#validate_all` Ruby method is unchanged.

### Manifest / store cleanup

- **Breaking:** `LEGACY_ZONES` fallback removed. Manifests must declare a `zones:` block explicitly (init scaffold does this).
- **Breaking:** legacy syntax errors removed for `source.parse` / `source.from` / `source.fetcher` / top-level `hooks:`. Those names were rejected with helpful errors in 0.4; in 0.5 they get the generic "unknown key" error from YAML parsing.
- **Internal:** `ManifestEntry` moved to its own file (`lib/textus/manifest_entry.rb`).

### Store split

- **Internal:** `lib/textus/store.rb` shrank from 617 LOC to ~312 LOC. Four focused helpers live under `lib/textus/store/`:
  - `events.rb` (31 LOC) — `fire_event` hook plumbing
  - `validator.rb` (53 LOC) — `validate_all` body
  - `staleness.rb` (142 LOC) — `stale` body (was 5 rubocop disables)
  - `mover.rb` (118 LOC) — `mv` body
- No public-API change. `Store` facade delegates to each helper one-line.

### Migration cheat-sheet

```sh
# 1. Upgrade the gem
gem update textus           # ≥ 0.5.0

# 2. Upgrade the store
cd /path/to/your/store
textus migrate v2           # flips manifest version

# 3. Anything else?
#    - Audit log: existing TSV rows still readable; new rows are NDJSON.
#    - CLI scripts: replace `textus mv ...` with `textus key mv ...`
#      (and 7 similar aliases). Old forms work through 0.5 with a stderr warning.
#    - Ruby callers of Store#put: pass `meta:` instead of `frontmatter:`.
#    - Anything reading envelope["frontmatter"]: read envelope["_meta"] instead.
```

## 0.4.0 — Extension API redesign (breaking)

- **Breaking:** `Textus.fetcher` removed. Use `Textus.action` instead. The block signature changes from `|config:, store:|` to `|config:, store:, args:|`.
- **Breaking:** Manifest field `source.fetcher` renamed to `source.action`. Legacy field is rejected with a migration error.
- **Breaking:** CLI flag `textus put --fetcher=NAME` renamed to `textus put --action=NAME`.
- **Breaking:** `BuiltinFetchers` module renamed to `BuiltinActions`.
- **Breaking:** Synthesized frontmatter key `fetched_with` renamed to `actioned_with` on `put --action`.
- **New:** `Textus.action` works in three invocation modes — intake refresh, the new `textus action NAME` verb, and `put --action`. See SPEC §5.11.
- **New:** `Textus.doctor_check(:name) { |store:| ... }` primitive; contributed checks merge into the doctor report.
- **New:** `textus action NAME [--key=val ...] [--as=ROLE]` CLI verb for invoking actions in verb mode.
- **New:** `StoreView` gains a writable mode (`writable: true, as: ROLE`); intake and verb-mode actions receive a writable view bound to the calling role.
- **New:** `extensions list` enumerates actions and doctor_checks.

Migration: in every `.textus/extensions/*.rb`, rename `Textus.fetcher(:x)` to `Textus.action(:x)` and add `args:` to the block signature. In every manifest, rename `source.fetcher:` to `source.action:`. In CI/scripts using `textus put --fetcher=`, switch to `--action=`.

## [0.3.0] — 2026-05-20 — Configurable store root

### Added

- `--root <path>` CLI flag and `TEXTUS_ROOT` environment variable for store
  discovery. `Textus::Store.discover` now accepts an optional `root:` kwarg.
  Unblocks embedding a textus store at non-default paths (e.g. nested under a
  plugin directory like `plugins/<name>/.textus/`) where walking up from cwd
  to find `.textus/` is undesirable or ambiguous.

### Documentation

- SPEC.md §3.1 documents the new store-location precedence:
  1. `--root` / `root:` kwarg, 2. `TEXTUS_ROOT`, 3. cwd walk.

## [0.2.0] — 2026-05-20 — Storage rewrite, agent surface, extension DSL (BREAKING)

This release reshapes textus from a markdown-only frontmatter store into a
multi-format, agent-introspectable context layer.

### Breaking changes
- **Per-entry formats.** Markdown is no longer the only storage shape. Manifest
  entries declare `format: markdown|json|yaml|text`; format is inferred from
  the path extension when omitted. JSON/YAML entries store `_meta` at the top
  level (`generated_at`, `from`, `template`, `reducer`).
- **Strict key grammar.** Segments must match `/^[a-z0-9][a-z0-9-]*$/`. No
  underscores, no uppercase, no dots-in-segments. Max 8 segments × 64 chars.
  Enforced at manifest load, `put`, and `mv`. Existing stores with illegal
  segments migrate via `textus migrate-keys --dry-run|--write`.
- **Publisher rename.** `Textus::Symlink` is now `Textus::Publisher`. Symlink
  mode is gone; publish is `FileUtils.cp` + sentinel.
- **Sentinels relocated.** `.textus-managed.json` files move from beside the
  published file to `<store_root>/sentinels/<target_rel>.textus-managed.json`.
  Legacy sibling sentinels are auto-migrated on next publish.
- **Init profiles removed.** `textus init --profile=…` and
  `lib/textus/profiles/*.yaml` are gone. `textus init` writes a single default
  manifest declaring all five SPEC zones and pre-creates `zones/<name>/`
  subdirectories.
- **Extension surface (carried over from earlier 0.2 work).** `.textus/parsers/`
  and `.textus/calculators/` are gone — drop `.rb` files into
  `.textus/extensions/`. `Textus::Parsers` and `Textus::Calculators` modules
  removed. Manifest `source.parse`/`source.from` → `source.fetcher` +
  `source.config`; projection `transform:` → `reducer:`; `hooks:` → `events:`
  (no `on_` prefix; `on_stale` removed entirely). CLI: `--parse=NAME` removed;
  `textus hooks list` removed (use `textus extensions list --kind=hook`).

### Added
- **`textus intro`** — single-call orientation envelope (`zones`, `entries`,
  `extensions`, `write_flows`, `cli_verbs`) for agents landing in a textus-
  managed project.
- **`inject_intro: true`** flag on derived markdown/text entries — merges the
  intro envelope into the template data so `CLAUDE.md` (or any boot doc) can
  render an orientation preamble.
- **`textus doctor`** — health check with 8 categories (missing schemas /
  templates / extensions, illegal nested keys, sentinel orphan/drift, audit log
  readability, unowned schema fields). `ok: true` only when zero error-level
  issues; warnings/info don't flip the bit.
- **`textus mv <old> <new>`** — same-zone, same-format rename. Preserves uid,
  writes an `mv` audit row with `from_key`, `to_key`, `from_path`, `to_path`,
  `uid`. `--dry-run` plans without writing.
- **`uid:`** field — 16-char hex stable identity (`SecureRandom.hex(8)`),
  auto-minted on first `Store#put`, preserved across writes and moves. Lives
  in frontmatter for markdown, `_meta.uid` for json/yaml. Surfaced on the
  envelope.
- **`publish_each:`** template on nested entries — each leaf byte-copies to a
  per-leaf target derived from `{leaf}`, `{basename}`, `{key}`, `{ext}`. Closes
  the per-file publish loop for plugins that mirror `working.*` into
  `agents/`, `skills/<name>/SKILL.md`, `commands/`.
- **`textus migrate-keys`** — run-once helper renaming files whose basenames
  violate the new strict key grammar. `--dry-run` reports proposed renames and
  collisions; `--write` applies them bottom-up and writes `migrate-keys` audit
  rows.
- **Per-format strategies** under `lib/textus/entry/{markdown,json,yaml,text}.rb`
  with a uniform parse/serialize contract. `Entry.for_format(name)` dispatcher.
- **`textus.intro` + CLAUDE.md preamble** — the example's CLAUDE.md now opens
  with auto-generated zone-and-write-flow orientation for the agent.
- **Actionable error hints.** Every `Textus::Error` exposes `code`, `message`,
  and `hint`. `UnknownKey` carries up to 5 ranked "did you mean" suggestions
  (shared-prefix + bounded Levenshtein). The CLI prints
  `code: msg\n  → hint` to stderr alongside the JSON envelope on stdout.
- **Extension surface (carried over from earlier 0.2 work).**
  `Textus.fetcher`, `Textus.reducer`, `Textus.hook` DSL verbs. Per-`Store`
  `ExtensionRegistry` (no global state). `textus refresh KEY --as=script`.
  `textus extensions list [--kind=fetcher|reducer|hook]`. In-process lifecycle
  events (`:put`, `:delete`, `:refresh`, `:build`, `:accept`). `Textus::Refresh`
  driver with 2 s timeout. `Textus::StoreView` read-only proxy. Audit log gains
  a 7th JSON-extras column. `Init.run` scaffolds `.textus/extensions/` with a
  README stub.

### Fixed
- `Projection#run` no longer stamps `generated_at` onto Hash reducer results —
  `_meta.generated_at` is the single source of truth for structured outputs
  (avoids duplicate timestamps in `marketplace.json`-style files).
- `UnknownKey` raised from `Store#get`/`put`/`mv` (nested-tree file misses) now
  carries suggestions, matching `Manifest#resolve`.

### Example
- `examples/claude-plugin/` rewritten as a real Claude Code plugin
  (`voice-tools`) entirely managed by textus: `.claude-plugin/{plugin,
  marketplace}.json` and `CLAUDE.md` derived; `agents/`, `skills/<name>/
  SKILL.md`, `commands/` mirrored via `publish_each:`; pending-zone walkthrough
  exercising the AI propose → human accept loop; intake fetcher, in-process
  reducer / hook, deep-nested key demos.

### SPEC
- Rewritten for §1–§5 (layers, manifest, formats, publish), §10 (envelope adds
  `format`, `content`, `uid`), audit verb table (`mv`, `migrate-keys`), CLI
  verb table, Fixture G.

## [0.1.0] — 2026-05-19

First public release. Implements protocol `textus/1`.

### Added — storage and model
- Zone-based storage layout under `.textus/zones/`: `canon`, `working`, `intake`,
  `pending`, `derived`. Each zone declares `writable_by` roles in the manifest.
- Role resolution order: `--as` flag → `TEXTUS_ROLE` env → `.textus/role` file →
  default `human`. Recognized roles: `human`, `ai`, `script`, `build`.
- Append-only TSV audit log at `.textus/audit.log`, file-locked on every write.
- Schemas with required/optional fields, type checking, and per-field
  `maintained_by` ownership plus `evolution` metadata (`added_in`,
  `migrate_from`).
- Manifest backwards compatibility: a manifest without `zones:` synthesizes the
  legacy `fixed` / `state` / `derived` zones.

### Added — compute and publish
- Vendored Mustache renderer (~120 LOC, depth-bounded at 8).
- Projection engine: `select` / `pluck` / `sort_by` / `limit` / `transform`
  (1000-row cap, single 2 s timeout on transforms).
- `textus build` materializes derived entries from `projection:` + `template:`
  declarations.
- Atomic symlink publish via `publish_to:`, with copy-mode fallback and a
  `.textus-managed.json` sentinel for filesystems without symlinks.

### Added — extension points
- **Parsers** — built-ins for `json`, `csv`, `markdown-links`, `ical-events`,
  `rss`. Auto-load from `.textus/parsers/<name>.rb`, 2 s timeout.
- **Calculators** — pure projection-row transforms registered via
  `Textus::Calculators.register`. Auto-load from `.textus/calculators/<name>.rb`,
  2 s timeout.
- **Hooks** — manifest entries declare `hooks:` keyed by lifecycle event
  (`on_put`, `on_delete`, `on_refresh`, `on_stale`, `on_accept`, `on_build`).
  textus enumerates hooks via `textus hooks list`; external runners execute.

### Added — CLI verbs
- Read: `list`, `where`, `get`, `schema`, `stale`, `deps`, `rdeps`, `published`,
  `validate-all`, `hooks list`.
- Write: `put`, `delete`, `build`, `accept`.
- Scaffolding: `init` (profiles: `personal`, `claude-plugin`), `schema-init`,
  `schema-diff`, `schema-migrate`.
- Flags: `--as=ROLE`, `--zone=Z`, `--prefix=KEY`, `--parse=NAME`, `--if-etag=E`,
  `--stale`, `--strict`, `--format=json`.

### Added — examples
- `examples/claude-plugin/` — a working `.textus/` tree that publishes a
  Claude Code `CLAUDE.md` and a `marketplace.json` via projection + Mustache.
  Demonstrates intake, parsers, calculators, hooks, and schema field ownership.
- `examples/mcp-server/` — 50-line MCP server wrapping `textus get` / `list` /
  `put` as tools.

### Added — quality tooling
- RuboCop config with rubocop-rspec; codebase passes with zero offenses.
- Lefthook hooks (`pre-commit` runs rubocop on staged Ruby; `pre-push` runs
  rspec + rubocop). Install via `brew bundle install`.
- `gemspec` packages only `lib/`, `exe/`, `README.md`, `SPEC.md`, and two
  curated `docs/` files. Internal plan documents stay out of the gem.
