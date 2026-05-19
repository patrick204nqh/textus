# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The **gem version** (`0.x.y`) is distinct from the **protocol version**
(currently `textus/1`, embedded in every envelope as `protocol`). The protocol
is additive within a major; a new major would change the wire string.

## [Unreleased]

## [0.2.0] — 2026-05-19 — Extension surface rewrite (BREAKING)

### Breaking changes
- `.textus/parsers/` and `.textus/calculators/` directories removed. Replace with
  `.textus/extensions/*.rb`.
- `Textus::Parsers` and `Textus::Calculators` modules removed.
- Manifest: `source.parse` and `source.from` removed — use `source.fetcher` and
  `source.config` (URL moves into `source.config.url`).
- Manifest: projection `transform:` → `reducer:`.
- Manifest: `hooks:` → `events:`; event names drop the `on_` prefix (`on_put` →
  `put`, etc.).
- Event `on_stale` removed entirely (staleness is observed via `textus stale`).
- CLI: `--parse=NAME` flag removed — use `--fetcher=NAME` on `textus put`.
- CLI: `textus hooks list` removed — use `textus extensions list --kind=hook`.

### Added
- `Textus.fetcher`, `Textus.reducer`, `Textus.hook` DSL verbs.
- Per-Store `Textus::ExtensionRegistry` (no global state).
- CLI: `textus refresh KEY --as=script` invokes a registered fetcher in-process.
- CLI: `textus extensions list [--kind=fetcher|reducer|hook]`.
- Lifecycle events fire in-process: `:put`, `:delete`, `:refresh`, `:build`,
  `:accept`.
- `Textus::Refresh.call(store, key, as:)` driver with 2s timeout and exception
  wrapping.
- `Textus::StoreView` — read-only store proxy passed to fetchers/reducers/hooks.
- Audit log gains an optional 7th column for JSON-encoded event extras (e.g.,
  `event_error` rows when a hook fails).
- `Init.run` scaffolds `.textus/extensions/` with a README stub.

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
