# textus

[![CI](https://github.com/patrick204nqh/textus/actions/workflows/ci.yml/badge.svg)](https://github.com/patrick204nqh/textus/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/textus.svg)](https://rubygems.org/gems/textus)
[![Ruby](https://img.shields.io/badge/ruby-%E2%89%A53.3-CC342D.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A context store for codebases that humans and AI agents both have to read and write. Dotted keys, schema-validated entries, role-gated writes, byte-copy publish, an audit log of every change. Built so an agent landing in your repo can run one command (`textus intro`) and know what to read, what to write, and what's off-limits.

Reference implementation in Ruby. Wire format `textus/3`. SPEC: [`SPEC.md`](SPEC.md). Implementation notes: [`docs/`](docs/).

## Versioning

Two versions, deliberately independent:

- **Protocol wire string:** `textus/3`. Stable; breaking changes require `textus/4`.
- **Gem version:** semver, currently `0.11.0`. The gem version is decoupled from the protocol string — internal refactors bump the gem; only wire-format changes bump the protocol.

Envelope payloads carry the `protocol` field. The gem version is irrelevant to the wire format.

### Upgrading from textus/2

textus 0.12.0 does not include a built-in migrator. If you are upgrading from
a textus/2 store (gem versions ≤ 0.10.x), first install textus 0.11.x and run:

    textus migrate --to=textus/3

Then upgrade to 0.12.0. Pre-0.11.0 audit-log rows with `role: ai|script|build`
are tolerated verbatim by the reader — no rewrite step required.

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
  hooks/              # one .rb per hook
  sentinels/          # publish bookkeeping
  zones/
    identity/         # human-only — identity, voice, decisions
    working/          # human / agent / runner — day-to-day catalog
    intake/           # runner — declared external inputs (actions)
    review/           # agent + human — proposals awaiting accept
    output/           # builder only — computed outputs
```

Manifest `path:` fields are relative to `.textus/zones/`. So `working.network.org.jane` lives at `.textus/zones/working/network/org/jane.md`.

Read and write:

```sh
textus get working.network.org.jane
textus list --zone=working
echo '{"_meta":{"name":"bob","org":"acme"},"body":"hi\n"}' \
  | textus put working.network.org.bob --as=human --stdin
textus freshness --zone=output       # per-entry fresh/stale/never_refreshed/no_policy
textus rule list                     # show every rule block
textus audit --limit=20              # query the audit log
```

(All verbs return JSON envelopes by default; pass `--output=json` explicitly if you prefer.)

For the full shape — Claude plugin with agents, skills, commands, pending walkthrough, intake action — see [`examples/claude-plugin/`](examples/claude-plugin/).

## What ships today

- **Per-entry formats.** `format: markdown | json | yaml | text` on a manifest entry. `cat .textus/zones/output/marketplace.json | jq .` works without going through textus — the in-store file *is* the consumer-shaped artifact. Structured outputs carry `_meta` at the top level (`generated_at`, `from`, `template`, `transform`).
- **Per-leaf publishing.** Nested entries declare `publish_each: "skills/{basename}/SKILL.md"`. Every leaf byte-copies to its consumer location on `textus build`. No more hand-mirrored `agents/` / `skills/` / `commands/` directories.
- **Stable identity (`uid:`).** 16-char hex, auto-minted on first `put`, preserved across writes and moves. `textus key mv old.key new.key` renames in place — uid survives, audit row records `from_key`, `to_key`, `uid`. Reorganising a tree no longer breaks references.
- **Strict key grammar.** `/^[a-z0-9][a-z0-9-]*$/`, max 8 segments × 64 chars. `textus key normalize --dry-run|--write` rewrites existing stores with illegal segments deterministically.
- **`textus intro`.** One-shot store orientation: zones with writers + purposes, entry families with schemas and publish targets, loaded hooks, write flows per role, the full CLI verb table. The boot signal for any agent — one tool call and it knows your store.
- **`textus doctor`.** Health check across 9 categories: missing schemas/templates, broken hooks, illegal nested keys, sentinel drift, audit log readability, unowned schema fields, schema violations, and missing manifest files. Returns `ok: true` only when nothing is wrong; warnings and info don't flip the bit.
- **Actionable hints on every error.** `UnknownKey` carries ranked "did you mean" suggestions. `WriteForbidden` names the role that *would* be allowed. `BadFrontmatter` tells you exactly what to rename. Printed to stderr alongside the JSON envelope on stdout.
- **Compute.** Derived entries declare `compute: { kind: projection, ... }` (declarative rows + template) or `compute: { kind: external, ... }` (build runner produces the file; textus tracks sources for staleness). Inside projection computes, `transform:` names the row-shaping hook.

Symlink-mode publish was removed; publish is `FileUtils.cp` + sentinel. Sentinels for published files live under `.textus/sentinels/<target_rel>.textus-managed.json` so consumer directories stay clean. Legacy sibling sentinels auto-migrate on next publish.

## CLI and zones

All verbs accept `--output=json` and return the envelope defined in [SPEC §8](SPEC.md). Write verbs require `--as=<role>` (role resolution: `--as` → `TEXTUS_ROLE` env → `.textus/role` file → default `human`). Recognized roles: `human`, `agent`, `runner`, `builder`.

- Full verb table — read, write, health, scaffolding — is in [SPEC §9](SPEC.md).
- Zone semantics and the role/`write_policy` mapping live in [SPEC §5](SPEC.md), with a tutorial expansion in [`docs/zones.md`](docs/zones.md).

`textus intro` prints the same information for the current store: zones, entry families with schemas, registered hooks, write flows, and the verb catalog. Run it inside a store and you get the live picture; reach for the SPEC when you want the contract.

## Compute and publish

Derived entries declare `compute: { kind: projection, select: ..., pluck: ..., sort_by: ..., limit: ..., transform: name }` and either a template under `.textus/templates/` (markdown/text) or a templateless path that lets a transform hook shape the output directly (json/yaml). Projections cap at 1000 rows; the vendored Mustache subset caps at depth 8. No partials, no lambdas, no HTML escaping.

For externally-generated entries, declare `compute: { kind: external, sources: [...] }` — textus tracks the declared sources for staleness; the build runner produces the file.

`publish_to: [path]` byte-copies a single derived file to one target. `publish_each: "template/{basename}.md"` on a nested entry byte-copies every leaf to its templated target — substitutes `{leaf}`, `{basename}`, `{key}`, `{ext}`. Sentinels for every published file live under `.textus/sentinels/`. See SPEC §5.2, §5.3, §5.12.

## Extension points

textus exposes a hook DSL. Drop `.rb` files into `.textus/hooks/` (subdirectories are fine; files load alphabetically by full path). Events:

- `:resolve_intake` — bring bytes in from elsewhere (returns `{_meta:, body:}`)
- `:transform_rows` — transform rows during projection (returns rows)
- `:validate` — custom doctor check (returns issues)
- `:entry_put`, `:entry_deleted`, `:entry_refreshed`, `:build_completed`, `:proposal_accepted`, `:file_published`, `:entry_renamed`, `:proposal_rejected`, `:store_loaded` — react to lifecycle events
- `:refresh_started`, `:refresh_failed`, `:refresh_backgrounded` — background-refresh lifecycle

```ruby
# Inside .textus/hooks/local_file.rb
Textus.on(:resolve_intake, :local_file) do |config:, args:, **|
  path = config["path"] or raise "local-file requires intake.config.path"
  {
    _meta: { "last_refreshed_at" => Time.now.utc.iso8601, "source_path" => path },
    body: File.read(File.expand_path(path)),
  }
end
```

```ruby
Textus.on(:transform_rows, :rank_by_recency) do |rows:, **|
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
```

To keep a batch of stale intake entries current in one shot:

```sh
textus refresh stale --prefix=working --zone=intake --as=runner
# or just refresh everything stale in the intake zone:
textus refresh stale --zone=intake --as=runner
```

See SPEC.md §5.10 for the full hook contract.

Schemas (`.textus/schemas/<name>.yaml`) declare field shapes, per-field `maintained_by:` ownership, and an `evolution:` block (`added_in`, `deprecated_at`, `migrate_from`). Full contract in SPEC §5.8.

## Examples

[`examples/claude-plugin/`](examples/claude-plugin/) — a Claude Code plugin (`voice-tools`) whose entire content surface — agents, skills, commands, `CLAUDE.md`, `plugin.json`, `marketplace.json` — is textus-managed. Demonstrates per-entry formats, `publish_each`, intake actions, in-process transforms and hooks, the agent-propose / human-accept loop, and the `inject_intro:` flag that puts an orientation preamble at the top of `CLAUDE.md`.

## Tests

```sh
bundle exec rspec
```

~490 examples; includes conformance fixtures A–I from SPEC §12.

## Code quality

```sh
bundle exec rubocop      # lint
bundle exec rubocop -A   # lint + autocorrect
```

Lefthook hooks (`brew bundle install` then `lefthook install`) run rubocop on `pre-commit` and `rspec + rubocop` on `pre-push`. Bypass with `LEFTHOOK=0 git commit ...` when needed. CI runs `rspec` (Ruby 3.3 / 3.4) and `rubocop` via GitHub Actions.

## License

MIT.
