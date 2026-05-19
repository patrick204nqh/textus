# claude-plugin example

A minimal but real `.textus/` tree that compiles a Claude Code plugin's
`CLAUDE.md` and `marketplace.json` from structured, hand-edited content.

## Layout

```
.textus/
  manifest.yaml              # declares zones + entries
  templates/                 # Mustache templates used by derived entries
    claude-root.mustache
    marketplace.mustache
  zones/
    canon/voice.md           # author identity (slow-changing)
    working/
      projects/*.md          # one file per project
      skills/*.md            # one file per skill
    derived/                 # build output (do not hand-edit)
CLAUDE.md                    # symlink into .textus/zones/derived/claude/root.md
marketplace.json             # symlink into .textus/zones/derived/marketplace.md
```

## Tour — every extension point in one repo

This example exercises the full v1.1 surface end-to-end:

1. **Bootstrap.** `textus init --profile=claude-plugin` lays down `.textus/`
   with zones, templates, schemas, parsers, and calculators.
2. **Human authority on canon.** Edit `.textus/zones/canon/voice.md`. The
   `canon` zone is `writable_by: [human]` — AI and scripts cannot touch it.
3. **AI-assisted updates via pending.** AI proposes a patch:
   `textus put pending.suggestion.001 --as=ai` and a human accepts it with
   `textus accept pending.suggestion.001 --to=working.projects.textus`.
4. **Intake refresh via TTL + hooks.** `textus stale --zone=intake` reports
   entries past their `source.ttl`. Then
   `textus hooks list --event=on_stale --format=json` shows the registered
   runner (`scripts/refresh-intake.sh`), which fetches the RSS feed and pipes
   it through `textus put --parse=rss`. Textus never executes the hook itself.
5. **Project-local parser.** `.textus/parsers/lowercase.rb` registers
   `Textus::Parsers.register("lowercase", ...)` and is auto-loaded on store
   boot. Used when an intake entry declares `source.parse: lowercase`.
6. **Project-local calculator.** `.textus/calculators/rank-by-recency.rb`
   registers a pure `rows -> rows` transform. The `derived.claude.root`
   projection declares `transform: rank-by-recency`, so `textus build`
   orders projects by `updated_at` before rendering `CLAUDE.md` via Mustache.
7. **Schema-as-contract.** `.textus/schemas/project.yaml` declares each field's
   `maintained_by` (human / ai / script). `textus validate-all` cross-checks
   that the last writer of every field had authority — humans always override.

## Walkthrough

```bash
# 1. Bootstrap (already done in this example)
textus init --profile=claude-plugin

# 2. Edit canon and working entries
$EDITOR .textus/zones/canon/voice.md
$EDITOR .textus/zones/working/projects/textus.md

# 3. Rebuild derived
textus build --format=json

# 4. CLAUDE.md and marketplace.json now point at the freshly-rendered files.
cat CLAUDE.md
```

The `derived/` zone is owned by `build:auto` — humans never write to it. The
manifest's `publish_to` instructs textus to symlink the rendered output to a
repo-root path so external consumers (Claude Code, marketplace tools) see a
plain file.

## How intake refresh works

> Reserved for projects that add an `intake` zone (see plan Phase 5).

1. You declare intake entries in `.textus/manifest.yaml` with
   `source: { from, parse, ttl }`.
2. `textus stale --zone=intake` reports entries past their TTL.
3. `scripts/refresh-intake.sh` (or your own runner) reads that list, fetches
   each URL, and pipes through `textus put --parse=NAME`.
4. textus controls parsing, validation, audit logging — the runner only does
   HTTP.
5. Promotion from intake to working is a human/PR decision (or another script).

## Project-local parsers

Drop a Ruby file into `.textus/parsers/` to register a named parser. The store
auto-loads every `.rb` in that directory on boot.

```ruby
# .textus/parsers/lowercase.rb
Textus::Parsers.register("lowercase", ->(content) { content.downcase })
```

Parsers are invoked whenever an intake entry declares `source.parse: NAME` (or
when a CLI caller passes `--parse=NAME`). Each call is bounded by a 2s timeout
so a hung parser cannot stall the store.

## Project-local calculators

`.textus/calculators/*.rb` works the same way, but for projection transforms.
Calculators take `rows -> rows` and run inside a 2s timeout. Wire one into a
projection via `transform: NAME`. See `.textus/calculators/rank-by-recency.rb`
for the example used by `derived.claude.root`.

## Hooks

`lefthook.yml` rebuilds derived on every commit so `CLAUDE.md` is never stale
relative to the working entries it summarises.

`Rakefile` exposes `rake textus:refresh` (intake refresh) and
`rake textus:update` (refresh + build).
