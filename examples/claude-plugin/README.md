# claude-plugin example

A minimal but real `.textus/` tree that compiles a Claude Code plugin's
`CLAUDE.md` and `marketplace.json` from structured, hand-edited content.

## Layout

```
.textus/
  manifest.yaml              # declares zones + entries
  templates/                 # Mustache templates used by markdown derived entries
    claude-root.mustache       # used by derived.claude.root
  extensions/                # project-local DSL code (auto-loaded)
    local-file.rb              # Textus.fetcher — for intake refresh
    rank-by-recency.rb         # Textus.reducer — orders projects by updated_at
    marketplace-envelope.rb    # Textus.reducer — wraps skill rows into { protocol, skills }
    build-stamp.rb             # Textus.hook   — :build event observer
  schemas/
    project.yaml             # field validation + maintained_by
    person.yaml              # used by the nested working.network tree
  zones/
    canon/voice.md           # author identity (slow-changing)
    working/
      projects/*.md          # one file per project
      skills/*.md            # one file per skill
      network/org/.../*.md   # deep-nested directory tree, schema: person
    derived/                 # build output (do not hand-edit)
      claude/root.md         # markdown (templated)
      marketplace.json       # json (templateless, reducer-shaped)
      marketplace.yaml       # yaml sibling, same reducer
  audit.log                  # append-only writer log
bin/notify-build             # external-runner stub for the :build event
CLAUDE.md                    # byte-copy of .textus/zones/derived/claude/root.md
marketplace.json             # byte-copy of .textus/zones/derived/marketplace.json
marketplace.yaml             # byte-copy of .textus/zones/derived/marketplace.yaml
Rakefile                     # `rake textus:refresh` / `rake textus:update`
```

## Tour — every extension point in one repo

This example exercises the full 0.2 surface end-to-end:

1. **Bootstrap.** `textus init --profile=claude-plugin` lays down `.textus/`
   with zones, templates, schemas, and an `extensions/` directory.
2. **Human authority on canon.** Edit `.textus/zones/canon/voice.md`. The
   `canon` zone is `writable_by: [human]` — AI and scripts cannot touch it.
3. **AI-assisted updates via pending.** AI proposes a patch:
   `textus put pending.suggestion.001 --as=ai` and a human accepts it with
   `textus accept pending.suggestion.001`.
4. **Intake refresh via in-process fetcher.**
   `.textus/extensions/local-file.rb` registers `Textus.fetcher(:"local-file")`.
   Manifest entry `intake.upstream.notes` declares
   `source: { fetcher: local-file, config: { path: ... }, ttl: 12h }`.
   `textus refresh intake.upstream.notes --as=script` calls the fetcher,
   validates the result, and writes it back through `put` — audit + events
   apply automatically.
5. **Project-local reducer.** `.textus/extensions/rank-by-recency.rb`
   registers a pure `rows -> rows` transform via `Textus.reducer(...)`. The
   `derived.claude.root` projection declares `reducer: rank-by-recency`, so
   `textus build` orders projects by `updated_at` before rendering `CLAUDE.md`.
6. **In-process hook.** `.textus/extensions/build-stamp.rb` subscribes to the
   `:build` event via `Textus.hook(:build, :stamp_log)`. Every time
   `textus build` materializes a derived entry, the hook appends a line to
   `.textus/last-build.log` showing the key, sources, and short etag. Hook
   failures land in `audit.log` as `event_error` rows — they never abort
   the build.
7. **External-runner hook (declarative).** `derived.claude.root` also
   declares `events: { build: [{ exec: bin/notify-build, as: script }] }`.
   Textus does NOT invoke this — it surfaces it via
   `textus extensions list --kind=hook --format=json` so external runners
   (cron, lefthook, CI) can dispatch. The `Rakefile`'s `textus:update` task
   demonstrates one such dispatcher: after `textus build`, it reads the
   listing and runs each `exec:` with the affected key. The bundled
   `bin/notify-build` is a 5-line stub that appends to `.textus/notify.log`
   — swap for a Slack webhook or pipeline trigger.
8. **Schema-as-contract.** `.textus/schemas/project.yaml` declares each field's
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
tail .textus/last-build.log    # :build hook recorded each one
```

The `derived/` zone is owned by `build:auto` — humans never write to it.
`publish_to` instructs textus to copy the rendered output byte-for-byte to a
repo-root path (with a `.textus-managed.json` sentinel next to it) so external
consumers (Claude Code, marketplace tools) see a plain file in the format the
entry was authored in — markdown for `CLAUDE.md`, JSON for `marketplace.json`,
YAML for `marketplace.yaml`.

## How intake refresh works

1. You declare intake entries in `.textus/manifest.yaml` with
   `source: { fetcher: NAME, config: { ... }, ttl: 12h }`.
2. `textus stale --zone=intake --format=json` lists entries past their TTL.
3. `textus refresh KEY --as=script` calls KEY's registered fetcher
   (built-in or project-local) with `(config:, store:)` where `store` is a
   read-only `StoreView`. The fetcher returns one of `{ frontmatter:, body: }`,
   `{ content: }` (for `format: json|yaml` entries), or `{ body: }` (raw bytes);
   the store normalizes all three and writes via `put` — audit, events, and
   schema validation all apply. The fetcher is bounded by a 2 s timeout.
4. There is no bulk-refresh CLI verb. `rake textus:refresh` walks the stale
   list and calls `textus refresh` per key (see `Rakefile`).
5. Promotion from intake to working is a human/PR decision (or another
   script that calls `textus accept`).

## Project-local extensions

Drop a Ruby file into `.textus/extensions/` to register a fetcher, reducer,
or hook. The store auto-loads every `.rb` in that directory on boot, in
lexical order, with each store getting its own isolated registry.

```ruby
# .textus/extensions/local-file.rb
Textus.fetcher(:"local-file") do |config:, store:|
  path = config["path"] or raise "local-file fetcher requires source.config.path"
  abs  = File.absolute_path?(path) ? path : File.expand_path(path)
  raise "local-file: not found: #{abs}" unless File.exist?(abs)
  {
    frontmatter: { "fetched_at" => Time.now.utc.iso8601, "source_path" => path },
    body: File.read(abs),
  }
end
```

```ruby
# .textus/extensions/rank-by-recency.rb
Textus.reducer(:"rank-by-recency") do |rows:, config:|
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
```

```ruby
# .textus/extensions/build-stamp.rb
Textus.hook(:build, :stamp_log) do |key:, envelope:, store:, sources:|
  line = "#{Time.now.utc.iso8601} #{key} from=#{sources.join(',')} etag=#{envelope['etag'][0..11]}\n"
  File.write(File.expand_path(".textus/last-build.log"), line, mode: "a")
end
```

Inspect what's loaded with `textus extensions list --format=json`. Every
fetcher/reducer/hook invocation is bounded by a 2 s timeout so a hung
extension cannot stall the store.

## Git hooks

`lefthook.yml` runs `rubocop` pre-commit and the test suite pre-push. The
`textus`-side build hook (point 6 above) is unrelated — it's the
`Textus.hook(:build, ...)` Ruby DSL, fired in-process by `textus build`.

`Rakefile` exposes `rake textus:refresh` (walk stale + refresh each key) and
`rake textus:update` (refresh + build).
