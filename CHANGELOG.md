# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The **gem version** (`0.x.y`) is distinct from the **protocol version**
(currently `textus/3`, embedded in every envelope as `protocol`). A protocol
bump is a breaking change that requires a store migration; the gem version
tracks both additive improvements and breaking protocol bumps independently.

## 0.12.6 — 2026-05-26

### Examples

- New `examples/project/` — demonstrates textus as the context store
  for your own project (identity + runbooks + ADR proposal flow,
  projecting `CLAUDE.md` and `AGENTS.md` at the repo root).
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
