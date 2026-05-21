# textus

[![CI](https://github.com/patrick204nqh/textus/actions/workflows/ci.yml/badge.svg)](https://github.com/patrick204nqh/textus/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/textus.svg)](https://rubygems.org/gems/textus)
[![Ruby](https://img.shields.io/badge/ruby-%E2%89%A53.3-CC342D.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A context store for codebases that humans and AI agents both have to read and write. Dotted keys, schema-validated entries, role-gated writes, byte-copy publish, an audit log of every change. Built so an agent landing in your repo can run one command (`textus intro`) and know what to read, what to write, and what's off-limits.

Reference implementation in Ruby. Wire format `textus/1`. SPEC: [`SPEC.md`](SPEC.md). Implementation notes: [`docs/`](docs/).

## Versioning

Two versions, deliberately independent:

- **Protocol wire string:** `textus/1`. Stable; breaking changes require `textus/2`.
- **Gem version:** semver, currently `0.2.0`. Gem `0.x.y` and `1.x` both speak `textus/1`.

Envelope payloads carry the `protocol` field. The gem version is irrelevant to the wire format.

## Install

```sh
gem install textus
```

Or from this repo:

```sh
bundle install
bundle exec exe/textus --help
```

## Quick start

```sh
textus init
```

You get `.textus/` with all five zone directories, baseline schemas, an empty audit log, and a starter manifest:

```
.textus/
  manifest.yaml       # zone declarations + key-to-path mapping
  audit.log           # append-only NDJSON, every write
  schemas/            # YAML field shapes per entry family
  templates/          # mustache templates for derived entries
  extensions/         # one .rb per action / reducer / hook / doctor_check
  sentinels/          # publish bookkeeping
  zones/
    canon/            # human-only — identity, voice, decisions
    working/          # human / ai / script — day-to-day catalog
    intake/           # script — declared external inputs (actions)
    pending/          # ai + human — proposals awaiting accept
    derived/          # build only — computed outputs
```

Manifest `path:` fields are relative to `.textus/zones/`. So `working.network.org.jane` lives at `.textus/zones/working/network/org/jane.md`.

Read and write:

```sh
textus get working.network.org.jane --format=json
textus list --zone=working --format=json
echo '{"frontmatter":{"name":"bob","org":"acme"},"body":"hi\n"}' \
  | textus put working.network.org.bob --as=human --stdin --format=json
textus stale --zone=derived --format=json
```

For the full shape — Claude plugin with agents, skills, commands, pending walkthrough, intake action — see [`examples/claude-plugin/`](examples/claude-plugin/).

## What 0.2 ships

- **Per-entry formats.** `format: markdown | json | yaml | text` on a manifest entry. `cat .textus/zones/derived/marketplace.json | jq .` works without going through textus — the in-store file *is* the consumer-shaped artifact. Structured outputs carry `_meta` at the top level (`generated_at`, `from`, `template`, `reducer`).
- **Per-leaf publishing.** Nested entries declare `publish_each: "skills/{basename}/SKILL.md"`. Every leaf byte-copies to its consumer location on `textus build`. No more hand-mirrored `agents/` / `skills/` / `commands/` directories.
- **Stable identity (`uid:`).** 16-char hex, auto-minted on first `put`, preserved across writes and moves. `textus key mv old.key new.key` renames in place — uid survives, audit row records `from_key`, `to_key`, `uid`. Reorganising a tree no longer breaks references.
- **Strict key grammar.** `/^[a-z0-9][a-z0-9-]*$/`, max 8 segments × 64 chars. `textus key migrate --dry-run|--write` rewrites existing stores with illegal segments deterministically.
- **`textus intro`.** One-shot store orientation: zones with writers + purposes, entry families with schemas and publish targets, loaded extensions, write flows per role, the full CLI verb table. The boot signal for any agent — one tool call and it knows your store.
- **`textus doctor`.** Health check across 8 categories: missing schemas/templates, broken extensions, illegal nested keys, sentinel drift, audit log readability. Returns `ok: true` only when nothing is wrong; warnings and info don't flip the bit.
- **Actionable hints on every error.** `UnknownKey` carries ranked "did you mean" suggestions. `WriteForbidden` names the role that *would* be allowed. `BadFrontmatter` tells you exactly what to rename. Printed to stderr alongside the JSON envelope on stdout.

Symlink-mode publish was removed; publish is `FileUtils.cp` + sentinel. Sentinels for published files live under `.textus/sentinels/<target_rel>.textus-managed.json` so consumer directories stay clean. Legacy sibling sentinels auto-migrate on next publish.

## CLI verbs

All verbs accept `--format=json` and return the envelope defined in SPEC §8. Write verbs require `--as=<role>` (role resolution: `--as` → `TEXTUS_ROLE` env → `.textus/role` file → default `human`).

**Read:**

| Verb | Purpose |
|---|---|
| `intro` | Store orientation: zones, entries, extensions, write flows, CLI map |
| `list [--prefix=K] [--zone=Z]` | Enumerate keys |
| `where K` | Resolve a key to its filesystem path |
| `get K` | Full envelope (frontmatter, body, uid, etag, format) |
| `schema show K` | Schema bound to an entry |
| `stale [--prefix=K] [--zone=Z]` | List stale derived/intake entries |
| `deps K` / `rdeps K` | Forward / reverse projection dependencies |
| `published` | List `publish_to:` targets and their backing keys |
| `doctor --check=schema_violations` | Validate every entry against its schema |
| `hook list [--event=E]` | Registered hooks grouped by event (fetch, reduce, check, put, delete, refresh, build, accept) |

**Write:**

| Verb | Role |
|---|---|
| `put K --stdin --as=R [--action=NAME]` | per zone |
| `extension run NAME [--key=val] [--as=R]` | per zone written (invoke a registered action) |
| `delete K --if-etag=E --as=R` | per zone |
| `refresh K --as=script` | per zone (typically `script`) |
| `key mv old new --as=R [--dry-run]` | per zone (same-zone moves; uid preserved) |
| `build [--prefix=K] [--dry-run]` | `build` |
| `accept K --as=human` | `human` only |

**Health & maintenance:**

| Verb | Purpose |
|---|---|
| `doctor` | 8 health checks; `ok: true` when clean |
| `key migrate [--dry-run]` | Rename files whose basenames violate the strict key grammar |

**Scaffolding (human-only):**

| Verb | Purpose |
|---|---|
| `init` | Scaffold a fresh `.textus/` |
| `schema init NAME` | Stub a schema |
| `schema diff NAME` | Compare a schema against entries that claim it |
| `schema migrate NAME [--rename=OLD:NEW]` | Rewrite frontmatter keys across affected entries |

**Deprecated (removed in 0.6):** `mv`, `uid`, `migrate-keys`, `schema-init`, `schema-diff`, `schema-migrate`, `extensions`, `action`.

## Zones and roles

| Zone | `writable_by` | Purpose |
|---|---|---|
| `canon` | `[human]` | Identity, voice, decisions — slow-changing |
| `working` | `[human, ai, script]` | Active project state |
| `intake` | `[script]` | Declared external inputs (actions) |
| `pending` | `[ai, human]` | AI proposals; humans run `textus accept` to apply |
| `derived` | `[build]` | Computed outputs from `textus build` |

Mismatches return `write_forbidden` with a hint naming the role that *would* be allowed. Every write records the resolved role in `.textus/audit.log`.

## Compute and publish

Derived entries declare a `projection:` (`select`, `pluck`, `sort_by`, `limit`, optional `reducer`) and either a template under `.textus/templates/` (markdown/text) or a templateless path that lets a reducer shape the output directly (json/yaml). Projections cap at 1000 rows; the vendored Mustache subset caps at depth 8. No partials, no lambdas, no HTML escaping.

`publish_to: [path]` byte-copies a single derived file to one target. `publish_each: "template/{basename}.md"` on a nested entry byte-copies every leaf to its templated target — substitutes `{leaf}`, `{basename}`, `{key}`, `{ext}`. Sentinels for every published file live under `.textus/sentinels/`. See SPEC §5.2, §5.3, §5.12.

## Extensions

Four DSL verbs, registered in `.textus/extensions/*.rb`. Each `Store` gets its own registry — no global state.

- **`Textus.action(:name) do |config:, store:, args:|`** — runs in three invocation modes (intake refresh, `textus action` verb, `put --action`). Returns `{frontmatter:, body:}`, `{content:}`, or `{body:}` when its return is consumed (intake and put-fetch); writes via `store.put` for side-effectful work (verb mode). The store normalizes all three return shapes. Configured via `source.action` in the manifest for intake. Five built-ins ship: `json`, `csv`, `markdown-links`, `ical-events`, `rss`.
- **`Textus.reducer(:name) do |rows:, config:|`** — shapes rows in a derived projection. Pure function. Configured via `projection.reducer`. May return an Array (templated builds) or a Hash (templateless json/yaml).
- **`Textus.hook(:event, :name) do |kwargs|`** — fires on `:put`, `:delete`, `:refresh`, `:build`, or `:accept`. In-process; 2 s timeout per hook; failures land in the audit log as `event_error` rows.
- **`Textus.doctor_check(:name) do |store:|`** — contributes whole-tree validators to `textus doctor`. Returns an array of issue hashes `{code, level, subject, message, fix}` that merge into the doctor report. Timeouts and exceptions surface as `doctor_check.*` issues; they do not abort the doctor run.

Schemas (`.textus/schemas/<name>.yaml`) declare field shapes, per-field `maintained_by:` ownership, and an `evolution:` block (`added_in`, `deprecated_at`, `migrate_from`). Full contract in SPEC §5.8 and §5.11.

## Examples

[`examples/claude-plugin/`](examples/claude-plugin/) — a Claude Code plugin (`voice-tools`) whose entire content surface — agents, skills, commands, `CLAUDE.md`, `plugin.json`, `marketplace.json` — is textus-managed. Demonstrates per-entry formats, `publish_each`, intake actions, in-process reducers and hooks, the AI-propose / human-accept loop, and the `inject_intro:` flag that puts an orientation preamble at the top of `CLAUDE.md`.

## Tests

```sh
bundle exec rspec
```

240 examples; includes conformance fixtures A–I from SPEC §12.

## Code quality

```sh
bundle exec rubocop      # lint
bundle exec rubocop -A   # lint + autocorrect
```

Lefthook hooks (`brew bundle install` then `lefthook install`) run rubocop on `pre-commit` and `rspec + rubocop` on `pre-push`. Bypass with `LEFTHOOK=0 git commit ...` when needed. CI runs `rspec` (Ruby 3.3 / 3.4) and `rubocop` via GitHub Actions.

## License

MIT.
