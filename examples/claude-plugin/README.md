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
  extensions/                # project-local fetchers + reducers (auto-loaded)
    lowercase.rb
    rank-by-recency.rb
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

This example exercises the full 0.2 surface end-to-end:

1. **Bootstrap.** `textus init --profile=claude-plugin` lays down `.textus/`
   with zones, templates, schemas, and an `extensions/` directory.
2. **Human authority on canon.** Edit `.textus/zones/canon/voice.md`. The
   `canon` zone is `writable_by: [human]` — AI and scripts cannot touch it.
3. **AI-assisted updates via pending.** AI proposes a patch:
   `textus put pending.suggestion.001 --as=ai` and a human accepts it with
   `textus accept pending.suggestion.001 --to=working.projects.textus`.
4. **Intake refresh via TTL + fetchers.** `textus stale --zone=intake`
   reports entries past their `source.ttl`. `textus refresh` then calls the
   registered fetcher for each stale entry and writes the result back through
   `put`. Textus owns the fetch — extensions just describe how.
5. **Project-local fetcher.** `.textus/extensions/lowercase.rb` calls
   `Textus.fetcher(:lowercase) { |config:, store:| ... }` and is auto-loaded
   on store boot. Used when an intake entry declares `source.fetcher: lowercase`.
6. **Project-local reducer.** `.textus/extensions/rank-by-recency.rb`
   registers a pure `rows -> rows` transform via `Textus.reducer(...)`. The
   `derived.claude.root` projection declares `reducer: rank-by-recency`, so
   `textus build` orders projects by `updated_at` before rendering `CLAUDE.md`
   via Mustache.
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

1. You declare intake entries in `.textus/manifest.yaml` with
   `source: { fetcher: NAME, config: { ... }, ttl: 6h }`.
2. `textus stale --zone=intake` reports entries past their TTL.
3. `textus refresh` calls each entry's registered fetcher (with `config:` and
   a read-only `store:` view), validates the result, and writes it through
   the normal `put` path so audit + events + schema all apply.
4. Promotion from intake to working is a human/PR decision (or another
   script that calls `textus accept`).

## Project-local extensions

Drop a Ruby file into `.textus/extensions/` to register a named fetcher or
reducer. The store auto-loads every `.rb` in that directory on boot.

```ruby
# .textus/extensions/lowercase.rb
Textus.fetcher(:lowercase) do |config:, store:|
  { frontmatter: {}, body: config["bytes"].to_s.downcase }
end
```

```ruby
# .textus/extensions/rank-by-recency.rb
Textus.reducer(:"rank-by-recency") do |rows:, config:|
  rows.sort_by { |r| r["updated_at"].to_s }.reverse
end
```

Inspect what's loaded with `textus extensions list --format=json`. Each
fetcher / reducer call is bounded by a 2s timeout so a hung extension cannot
stall the store.

## Hooks

`lefthook.yml` rebuilds derived on every commit so `CLAUDE.md` is never stale
relative to the working entries it summarises.

`Rakefile` exposes `rake textus:refresh` (intake refresh) and
`rake textus:update` (refresh + build).
