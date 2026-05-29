# textus

[![CI](https://github.com/patrick204nqh/textus/actions/workflows/ci.yml/badge.svg)](https://github.com/patrick204nqh/textus/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/textus.svg)](https://rubygems.org/gems/textus)
[![Ruby](https://img.shields.io/badge/ruby-%E2%89%A53.3-CC342D.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Durable, multi-writer context for codebases that humans and AI agents both touch.** Your agent forgets everything between sessions; your runbooks and `CLAUDE.md` get edited by whoever ran last; nobody can reconstruct who wrote what. textus is the memory that survives the model, the session, and the vendor — a shared workspace where humans, agents, and runners write into separate lanes, propose changes through a review queue, and leave an audit trail behind every byte.

*textus* is Latin for "the fabric a text is woven from" — same root as *context*, from *con-texere*, "to weave together." The protocol weaves human edits, agent proposals, and runner intake into one durable fabric. The shape of that fabric is yours; the rules for writing into it are textus's.

## The idea

Three actors write to your repo today:

- **Humans** — you, your team. Authoritative on identity, decisions, voice.
- **Agents** — Claude, Cursor, custom assistants. Smart, fast, forgetful, and not always right.
- **Runners** — cron jobs, fetchers, CI. Bring outside data in.

Without coordination, they overwrite each other and nothing remembers why. textus gives each actor a **lane** (a zone), routes everything they can't write directly through a **review queue**, and writes every successful change to an **append-only audit log**. The lanes are enforced at the protocol level, not by convention.

```
identity/   human only          — who you are, what you decide, how you sound
working/    human only          — day-to-day catalog (agents propose via review/, runners feed via intake/)
intake/     runner only         — declared external inputs
review/     agent + human       — proposals waiting on a human accept
output/     builder only        — computed, published artifacts
```

An agent that tries to write directly into `working/` or `identity/` gets `write_forbidden`. It writes to `review/` instead. You accept the good proposals; textus promotes them, records the move, and audits both halves. Stable per-entry `uid:` means a reorganization doesn't break references. A monotonic audit cursor (`textus pulse --since=N`) means the next session — possibly a different agent, possibly a different model — picks up exactly where the last one left off.

That's the load-bearing claim: **coordination is a protocol invariant, not a library convenience.**

## See it in four commands

```sh
gem install textus
textus init                          # creates .textus/ with zones + schemas
# agent proposes a change to review/
printf '%s' '{"_meta":{"name":"oncall","proposal":{"target_key":"working.notes.oncall","action":"put"}},"body":"Patrick on call.\n"}' \
  | textus put review.notes.oncall --as=agent --stdin
# you accept it — textus promotes to working/ and audits the move
textus accept review.notes.oncall --as=human
```

Try the gate the other way (`textus put working.notes.X --as=agent`) and you get `write_forbidden`, with the role that *would* be allowed named in the error. That refusal is the whole point.

## Try it

- **5-command worked demo** — single terminal scroll, no MCP, no schemas: [`examples/hello/`](examples/hello/)
- **Wire textus into Claude Code via MCP** — 4 steps, ~5 minutes: [`INTEGRATE_WITH_CLAUDE.md`](INTEGRATE_WITH_CLAUDE.md)
- **Use textus as your own project's context store**: [`examples/project/`](examples/project/)
- **Use textus to author a Claude plugin** (textus is the source-of-truth, build publishes to `agents/`, `skills/`, `commands/`): [`examples/claude-plugin/`](examples/claude-plugin/)

## Protocol, not just a gem

This Ruby gem is the reference implementation of **`textus/3`** — a wire format and storage convention any language can speak. The protocol owns the envelope shape, the role/zone gate, the audit log format, and the key grammar. The gem version (semver, see badge) and the protocol version (`textus/3`) move independently; envelopes carry the `protocol` field so consumers can pin to the contract, not the implementation.

- Specification: [`SPEC.md`](SPEC.md)
- Architecture: [`ARCHITECTURE.md`](ARCHITECTURE.md)
- Per-release notes: [`CHANGELOG.md`](CHANGELOG.md)

A second implementation in another language would share the same `.textus/` directory and the same audit log. That's deliberate.

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

Manifest `path:` fields are relative to `.textus/zones/`. So `working.notes.org.jane` lives at `.textus/zones/working/notes/org/jane.md`.

Read and write:

```sh
textus get working.notes.org.jane
textus list --zone=working
printf '%s' '{"_meta":{"name":"bob","org":"acme"},"body":"hi\n"}' \
  | textus put working.notes.bob --as=human --stdin
textus freshness --zone=output       # per-entry fresh/stale/never_refreshed/no_policy
textus rule list                     # show every rule block
textus audit --limit=20              # query the audit log
```

(All verbs return JSON envelopes by default; pass `--output=json` explicitly if you prefer.)

For the full shape — Claude plugin with agents, skills, commands, pending walkthrough, intake action — see [`examples/claude-plugin/`](examples/claude-plugin/).

## What's shipped

- **Per-entry formats.** `format: markdown | json | yaml | text` on a manifest entry. `cat .textus/zones/output/marketplace.json | jq .` works without going through textus — the in-store file *is* the consumer-shaped artifact. Structured outputs carry `_meta` at the top level (`generated_at`, `from`, `template`, `transform`).
- **Per-leaf publishing.** Nested entries declare `publish_each: "skills/{basename}/SKILL.md"`. Every leaf byte-copies to its consumer location on `textus build`. No more hand-mirrored `agents/` / `skills/` / `commands/` directories.
- **Build and publish in one pass.** `Textus::Write::Publish` materializes generator-zone entries and copies nested leaves to their `publish_each` targets. The `textus build` CLI verb dispatches to it; the wire envelope is unchanged.
- **Typed envelopes.** `Textus::Envelope` is a `Data.define` value object with typed accessors (`.meta`, `.body`, `.etag`, `.uid`, `.freshness`, …). Ruby API callers get IDE help and `NoMethodError` on typos. The CLI JSON wire format is preserved byte-for-byte via `envelope.to_h_for_wire`.
- **Stable identity (`uid:`).** 16-char hex, auto-minted on first `put`, preserved across writes and moves. `textus key mv old.key new.key` renames in place — uid survives, audit row records `from_key`, `to_key`, `uid`. Reorganising a tree no longer breaks references.
- **Strict key grammar.** `/^[a-z0-9][a-z0-9-]*$/`, max 8 segments × 64 chars. `textus doctor` flags any illegal segments with a rename hint; `textus key mv old.key new.key` renames in place (uid survives).
- **`textus boot`.** One-shot store orientation: zones with writers + purposes, entry families with schemas and publish targets, loaded hooks, write flows per role, the full CLI verb table, and an `agent_quickstart` block (read/write verbs, writable zones, propose zone, latest audit seq).
- **`textus pulse [--since=N]`.** Per-turn heartbeat for agents: changed entries since cursor N, stale keys, pending review proposals, and a doctor summary. Cursor is a monotonic seq stamped on every audit row; rotation keeps the last 5 files (configurable via `audit:` in the manifest) and raises `CursorExpired` when the requested cursor has fallen off disk.
- **`textus doctor`.** Health check across 15 checks — among them: missing schemas/templates, broken hooks, illegal nested keys, sentinel drift, audit log readability, unowned schema fields, schema violations, and missing manifest files. Returns `ok: true` only when nothing is wrong; warnings and info don't flip the bit.
- **Actionable hints on every error.** `UnknownKey` carries ranked "did you mean" suggestions. `WriteForbidden` names the role that *would* be allowed. `BadFrontmatter` tells you exactly what to rename. Printed to stderr alongside the JSON envelope on stdout.
- **Compute.** Derived entries declare `compute: { kind: projection, ... }` (declarative rows + template) or `compute: { kind: external, ... }` (build runner produces the file; textus tracks sources for staleness). Inside projection computes, `transform:` names the row-shaping hook.

Symlink-mode publish was removed; publish is `FileUtils.cp` + sentinel. Sentinels for published files live under `.textus/sentinels/<target_rel>.textus-managed.json` so consumer directories stay clean. Legacy sibling sentinels auto-migrate on next publish.

## CLI and zones

All verbs accept `--output=json` and return the envelope defined in [SPEC §8](SPEC.md). Write verbs require `--as=<role>` (role resolution: `--as` → `TEXTUS_ROLE` env → `.textus/role` file → default `human`). Recognized roles: `human`, `agent`, `runner`, `builder`.

- Full verb table — read, write, health, scaffolding — is in [SPEC §9](SPEC.md).
- Zone semantics and the role/`write_policy` mapping live in [SPEC §5](SPEC.md), with a tutorial expansion in [`docs/zones.md`](docs/zones.md).

`textus boot` prints the same information for the current store: zones, entry families with schemas, registered hooks, write flows, and the verb catalog. Run it inside a store and you get the live picture; reach for the SPEC when you want the contract.

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
Textus.hook do |reg|
  reg.on(:resolve_intake, :local_file) do |config:, args:, **|
    path = config["path"] or raise "local-file requires intake.config.path"
    {
      _meta: { "last_refreshed_at" => Time.now.utc.iso8601, "source_path" => path },
      body: File.read(File.expand_path(path)),
    }
  end
end
```

```ruby
Textus.hook do |reg|
  reg.on(:transform_rows, :rank_by_recency) do |rows:, **|
    rows.sort_by { |r| r["updated_at"].to_s }.reverse
  end
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

See [`docs/agent-integration.md`](docs/agent-integration.md) for the agent boot → pulse loop.

## Examples

[`examples/claude-plugin/`](examples/claude-plugin/) — a Claude Code plugin (`voice-tools`) whose entire content surface — agents, skills, commands, `CLAUDE.md`, `plugin.json`, `marketplace.json` — is textus-managed. Demonstrates per-entry formats, `publish_each`, intake actions, in-process transforms and hooks, the agent-propose / human-accept loop, and the `inject_boot:` flag that puts an orientation preamble at the top of `CLAUDE.md`.

## Tests

```sh
bundle exec rspec
```

~920 examples; includes conformance fixtures A–I from SPEC §12.

## Code quality

```sh
bundle exec rubocop      # lint
bundle exec rubocop -A   # lint + autocorrect
```

Lefthook hooks (`brew bundle install` then `lefthook install`) run rubocop on `pre-commit` and `rspec + rubocop` on `pre-push`. Bypass with `LEFTHOOK=0 git commit ...` when needed. CI runs `rspec` (Ruby 3.3 / 3.4) and `rubocop` via GitHub Actions.

## License

MIT.
