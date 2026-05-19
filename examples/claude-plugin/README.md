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

## Hooks

`lefthook.yml` rebuilds derived on every commit so `CLAUDE.md` is never stale
relative to the working entries it summarises.

`Rakefile` exposes `rake textus:refresh` (intake refresh) and
`rake textus:update` (refresh + build).
