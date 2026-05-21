# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The **gem version** (`0.x.y`) is distinct from the **protocol version**
(currently `textus/2`, embedded in every envelope as `protocol`). The protocol
is additive within a major; a new major would change the wire string.

## [Unreleased]

### Changed
- Internal: extracted `Textus::Path` and `Textus::Envelope` value modules; `Manifest`, `Store`, `Staleness`, and `Builder` now share the same path/envelope construction.
- Internal: split `Textus::Store` into `Store::Reader` and `Store::Writer`. Public API unchanged. `Mover`, `Validator`, and `Staleness` now take explicit collaborators instead of the full store.

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
