# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The **gem version** (`0.x.y`) is distinct from the **protocol version**
(currently `textus/2`, embedded in every envelope as `protocol`). The protocol
is additive within a major; a new major would change the wire string.

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
