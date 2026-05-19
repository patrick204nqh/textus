# voice-tools — a Claude Code plugin managed by textus

This example shows a real-shape Claude Code plugin (`voice-tools`) whose
authoring surface lives entirely under `.textus/`. The plugin ships:

- 2 agents (`voice-writer`, `fact-checker`)
- 2 skills (`voice-writer`, `fact-checker`)
- 1 command (`/rewrite`)
- a plugin manifest at `.claude-plugin/plugin.json`
- a marketplace listing at `.claude-plugin/marketplace.json`
- a `CLAUDE.md` loaded on session start

Every consumer-facing file in this plugin — the three derived envelopes
*and* every agent/skill/command leaf under `agents/`, `skills/`, `commands/`
— is byte-copied from `.textus/zones/...` by `textus build`. The entire
plugin layout is end-to-end textus-managed; no file under `agents/`,
`skills/`, or `commands/` is hand-mirrored.

## Layout

```
voice-tools/
  .claude-plugin/
    plugin.json              # ← published from .textus/zones/derived/plugin.json
    marketplace.json         # ← published from .textus/zones/derived/marketplace.json
  CLAUDE.md                  # ← published from .textus/zones/derived/claude-root.md

  agents/
    voice-writer.md          # ← publish_each from working.agents.voice-writer
    fact-checker.md          # ← publish_each from working.agents.fact-checker
  skills/
    voice-writer/SKILL.md    # ← publish_each from working.skills.writing.voice-writer
    fact-checker/SKILL.md    # ← publish_each from working.skills.research.fact-checker
  commands/
    rewrite.md               # ← publish_each from working.commands.rewrite

  .textus/
    manifest.yaml
    schemas/
      plugin.yaml            # name, version, description, author, repository
      agent.yaml             # name, description, model, tools
      skill.yaml             # name, description, version
      command.yaml           # name, description
    extensions/
      plugin-envelope.rb     # reducer → plugin.json shape
      marketplace-envelope.rb# reducer → marketplace.json shape
      claude-root.rb         # reducer → CLAUDE.md template payload
      rank-by-recency.rb     # demo reducer (kept for reference)
      local-file.rb          # demo fetcher (intake refresh)
      build-stamp.rb         # demo :build hook (in-process)
    templates/
      claude-root.mustache   # renders CLAUDE.md from the projection payload
    zones/
      canon/
        voice-tools.md         # plugin identity (name, version, description, author, repository)
        example-marketplace.md # marketplace identity (name, owner)
      working/
        agents/<name>.md       # one file per agent
        skills/<topic>/<name>.md  # nested ≥4 segments (e.g. working.skills.writing.voice-writer)
        commands/<name>.md
      intake/
        upstream/notes.md      # fetcher demo (local-file)
      derived/
        plugin.json            # → publish_to .claude-plugin/plugin.json
        marketplace.json       # → publish_to .claude-plugin/marketplace.json
        claude-root.md         # → publish_to CLAUDE.md
  bin/notify-build             # external-runner stub for the :build event
  lefthook.yml                 # git hooks (unrelated to textus :build hook)
  Rakefile                     # rake textus:refresh / textus:update
```

## How textus manages the catalog

- **Canon** holds the slow-changing identity blocks (`canon.plugin` and
  `canon.marketplace`). The `canon` zone is `writable_by: [human]` — AI and
  scripts cannot touch it.
- **Working** holds the day-to-day catalog: every agent, skill, and command
  lives here as markdown with frontmatter. The schemas (`agent`, `skill`,
  `command`) validate the frontmatter on every read and write.
- **Intake** is fetcher-fed (script-only). The `intake.upstream.notes` entry
  uses the project-local `local-file` fetcher as a small demo.
- **Derived** is owned by `build:auto`. Three derived entries assemble the
  shipped surface:
  - `derived.plugin` → `plugin-envelope` reducer → `.claude-plugin/plugin.json`
  - `derived.marketplace` → `marketplace-envelope` reducer →
    `.claude-plugin/marketplace.json`
  - `derived.claude-root` → `claude-root` reducer + `claude-root.mustache`
    template → `CLAUDE.md`

The deep-nested skill paths (`working.skills.writing.voice-writer` —
four key segments below `working`) exercise textus's nested-tree resolver.

## Build

```bash
ruby -I../../lib -rtextus -e \
  'store = Textus::Store.discover(Dir.pwd); puts JSON.pretty_generate(Textus::Builder.new(store).build)'
```

Or with the CLI on PATH:

```bash
textus build --format=json
```

After the build, the three `publish_to` targets are byte-copies of the
generated files in `.textus/zones/derived/`, each accompanied by a
`<file>.textus-managed.json` sentinel recording the source path, sha256, and
publish mode.

## Per-leaf publishing (`publish_each:`)

The files under `agents/`, `skills/`, and `commands/` are what Claude Code
loads on session start. They are not hand-mirrored — each one is byte-copied
by `textus build` from its source under `.textus/zones/working/...`. The
`working.agents`, `working.skills`, and `working.commands` entries declare
`publish_each:` templates:

```yaml
- key: working.agents
  publish_each: "agents/{basename}.md"

- key: working.skills
  publish_each: "skills/{basename}/SKILL.md"

- key: working.commands
  publish_each: "commands/{basename}.md"
```

Each leaf under those nested entries (e.g. `working.skills.writing.voice-writer`)
is published to its templated target. `{basename}` is the final dotted segment,
so deep authoring layouts (`skills/writing/voice-writer.md`) flatten to the
consumer's expected layout (`skills/voice-writer/SKILL.md`). Sentinels appear
under `.textus/sentinels/agents/...`, `.textus/sentinels/skills/...`, and so
on, mirroring the consumer paths.

Re-run `textus build` (or the `ruby -I../../lib` invocation above) after
editing any working-zone file and the consumer mirrors update automatically.

## Intake refresh

`intake.upstream.notes` reads `.textus/zones/canon/voice-tools.md` through
the in-process `local-file` fetcher. Walk it with:

```bash
rake textus:refresh    # refresh every stale intake entry
rake textus:update     # refresh + build + dispatch external :build hooks
```

## Project-local extensions

Every `.rb` file in `.textus/extensions/` is auto-loaded on store boot and
registers into an isolated per-store registry. This example wires up:

- `plugin-envelope` — turns the `canon.plugin` row into a Claude
  `plugin.json` envelope.
- `marketplace-envelope` — assembles `canon.marketplace` + `canon.plugin` +
  the `working.skills.*` rows into a Claude `marketplace.json` envelope.
- `claude-root` — groups projection rows by source prefix for the CLAUDE.md
  template payload.
- `rank-by-recency`, `local-file`, `build-stamp` — kept as demos of the
  reducer / fetcher / hook surfaces.

Inspect everything currently loaded with `textus extensions list --format=json`.
