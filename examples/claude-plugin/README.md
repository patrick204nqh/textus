# voice-tools — a Claude Code plugin managed by textus

This example shows a real-shape Claude Code plugin (`voice-tools`) whose
authoring surface lives entirely under `.textus/`. The plugin ships:

- 2 agents (`voice-writer`, `fact-checker`)
- 2 skills (`voice-writer`, `fact-checker`)
- 1 command (`/rewrite`)
- a plugin manifest at `.claude-plugin/plugin.json`
- a marketplace listing at `.claude-plugin/marketplace.json`
- a `CLAUDE.md` loaded on session start

Every consumer-facing file in this plugin — the three output envelopes
*and* every agent/skill/command leaf under `agents/`, `skills/`, `commands/`
— is byte-copied from `.textus/zones/...` by `textus build`. The entire
plugin layout is end-to-end textus-managed; no file under `agents/`,
`skills/`, or `commands/` is hand-mirrored.

## Layout

```
voice-tools/
  .claude-plugin/
    plugin.json              # ← published from .textus/zones/output/plugin.json
    marketplace.json         # ← published from .textus/zones/output/marketplace.json
  CLAUDE.md                  # ← published from .textus/zones/output/claude-root.md

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
    hooks/
      plugin_envelope.rb     # reducer → plugin.json shape
      marketplace_envelope.rb# reducer → marketplace.json shape
      claude_root.rb         # reducer → CLAUDE.md template payload
      rank_by_recency.rb     # demo reducer (kept for reference)
      local_file.rb          # demo intake handler
      build-stamp.rb         # demo :build hook (in-process)
    templates/
      claude-root.mustache   # renders CLAUDE.md from the projection payload
    zones/
      identity/
        voice-tools.md         # plugin identity (name, version, description, author, repository)
        example-marketplace.md # marketplace identity (name, owner)
      working/
        agents/<name>.md       # one file per agent
        skills/<topic>/<name>.md  # nested ≥4 segments (e.g. working.skills.writing.voice-writer)
        commands/<name>.md
      inbox/
        upstream/notes.md      # action demo (local_file)
      output/
        plugin.json            # → publish_to .claude-plugin/plugin.json
        marketplace.json       # → publish_to .claude-plugin/marketplace.json
        claude-root.md         # → publish_to CLAUDE.md
  bin/notify-build             # external-runner stub for the :build event
  lefthook.yml                 # git hooks (unrelated to textus :build hook)
  Rakefile                     # rake textus:refresh / textus:update
```

## How textus manages the catalog

- **Identity** holds the slow-changing identity blocks (`identity.plugin`
  and `identity.marketplace`). The `identity` zone is `writable_by: [human]`
  — AI and scripts cannot touch it.
- **Working** holds the day-to-day catalog: every agent, skill, and command
  lives here as markdown with frontmatter. The schemas (`agent`, `skill`,
  `command`) validate the frontmatter on every read and write.
- **Inbox** is action-fed (script-only). The `inbox.upstream.notes` entry
  uses the project-local `local_file` action as a small demo. Its freshness
  rule and a per-zone handler allowlist both live in the manifest's top-level
  `policies:` block — see "Policies" below.
- **Review** is the AI proposal surface. The manifest's `review.**` policy
  declares `promote_requires: [schema_valid, human_accept]` — the contract a
  proposal must satisfy before it can be accepted.
- **Output** is owned by `build:auto`. Three output entries assemble the
  shipped surface:
  - `output.plugin` → `plugin_envelope` reducer → `.claude-plugin/plugin.json`
  - `output.marketplace` → `marketplace_envelope` reducer →
    `.claude-plugin/marketplace.json`
  - `output.claude-root` → `claude_root` reducer + `claude-root.mustache`
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
textus build
```

After the build, the three `publish_to` targets are byte-copies of the
generated files in `.textus/zones/output/`. For every published file
(at any path — `.claude-plugin/plugin.json`, `CLAUDE.md`, `agents/*.md`, …)
textus writes a sentinel under `.textus/sentinels/<target-rel>.textus-managed.json`
recording the source path, sha256, and publish mode. Sentinels live in
the store rather than beside the consumer file so consumer directories
stay clean.

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

## Policies

The manifest's top-level `policies:` block declares rules that apply across
multiple entries, matched by glob and resolved most-specific-wins per slot.
This example ships four blocks:

```yaml
policies:
  # Baseline: refresh every inbox.* once a day, warn on stale.
  - match: inbox.**
    refresh: { ttl: 24h, on_stale: warn }

  # More-specific override for one entry — 12h instead of 24h.
  - match: inbox.upstream.notes
    refresh: { ttl: 12h }

  # Guard-rail: every inbox.* must use a handler from this list.
  - match: inbox.**
    handler_allowlist: [local_file]

  # Contract for AI proposals.
  - match: review.**
    promote_requires: [schema_valid, human_accept]
```

`textus policy explain inbox.upstream.notes` walks the resolution: two blocks
contribute a `refresh` rule, the literal-match one wins; one contributes a
`handler_allowlist`. `textus doctor` runs the `policy_ambiguity` check (no
two blocks of equal specificity may fill the same slot) and the
`handler_allowlist` check (every intake handler must be in its policy's
allowlist).

## Visibility verbs (0.9.2)

Four read-only verbs surface the audit substrate and the policy resolution:

```bash
textus freshness                    # per-entry status (fresh/stale/never_refreshed/no_policy)
textus audit --since=7d             # query .textus/audit.log with filters
textus audit --correlation-id=<id>  # every row from a single request
textus blame KEY                    # audit rows × git commit metadata
textus policy list                  # dump the parsed policies block
textus policy explain KEY           # which blocks match, who wins per slot
```

The `correlation_id` in audit rows is generated once per CLI invocation and
threaded through `Application::Context` into every `put` / `delete` / `mv`
audit row, so a single `textus accept` (which writes the target, deletes the
review entry) leaves three rows that share one id.

## Operational verbs

Three verbs you'll reach for when the catalog moves around:

### `textus doctor`

Health-check the whole store. Reports missing schemas/templates, broken
hooks, illegal nested keys, sentinel drift (somebody hand-edited a
published file), and audit-log corruption.

```bash
textus doctor
# → { "protocol": "textus/2", "ok": true, "issues": [],
#     "summary": { "error": 0, "warning": 0, "info": 0 } }
```

If you edit `agents/voice-writer.md` by hand instead of editing
`.textus/zones/working/agents/voice-writer.md`, the next `doctor` will
surface a `sentinel.drift` warning with a `fix:` hint pointing you at
`textus build`.

### `textus key mv` — move with identity preserved

Each entry written through the API has an optional `uid:` field (16
hex chars, auto-minted on first `put`). `textus key mv` renames a key
without losing that identity, and writes an `mv` row to `.textus/audit.log`
recording both keys, both paths, and the uid.

```bash
# Move a skill between topics — uid survives, audit row written.
textus key mv working.skills.writing.voice-writer \
              working.skills.editorial.voice-writer \
              --as=human
```

This is how you handle real refactors: re-org an `org/` tree under
`working/network/`, retag a project, recategorize a skill. The audit
trail tells you *when* the move happened; the uid keeps cross-references
stable.

### `textus hook list`

Inspect the hooks the store has loaded from `.textus/hooks/` and the
manifest-declared exec hooks:

```bash
textus hook list
```

Useful when wiring up an external runner that needs to discover declared
`events: { build: [{ exec: ..., as: script }] }` hooks (this example's
`output.claude-root` declares one — see `Rakefile`'s `textus:update` task
for a working dispatcher).

## AI proposals (`review` zone)

The `review` zone is the canonical write path for AI agents. The agent
writes a *proposal* with `--as=ai` — the proposal carries the target key
and the payload it would write. A human reviews the file like any diff,
then runs `textus accept` to apply it. The accept step writes to the real
target (with `--as=human`, so any zone the human can write to is fair
game) and deletes the review entry. The whole exchange is in
`.textus/audit.log`: one `put` row by `ai` against the review key, one
`put` row by `human` against the real target, one `delete` row by
`human` against the review key.

The manifest declares a nested review entry so any agent can drop a
proposal under it:

```yaml
- key: review.suggestion
  path: review/suggestion
  zone: review
  schema: null
  owner: ai:catalog
  nested: true
```

A live fixture lives at
`.textus/zones/review/suggestion/001.md` — open it to see the proposal
envelope shape:

```yaml
---
name: 001
proposal:
  target_key: working.skills.editorial.copy-editor
  action: put              # or "delete"
frontmatter:               # what to write into target_key
  name: copy-editor
  description: ...
  version: 0.1.0
---

<body the proposal would write>
```

End-to-end, the loop is:

```bash
# 1. AI proposes (write into review) — replays the fixture.
textus put review.suggestion.001 --stdin --as=ai < proposal.json

# 2. Human reviews:
textus list --prefix=review
textus get  review.suggestion.001

# 3. Human accepts. textus writes target_key with --as=human, then
#    deletes the review entry. The build picks it up via publish_each.
textus accept review.suggestion.001 --as=human
textus build
```

`textus accept` enforces `--as=human` (an AI can propose, only a human
can accept). The on-disk fixture in this repo is committed for inspection
— don't `accept` it unless you actually want the `copy-editor` skill
added to the catalog (it isn't otherwise wired up).

## Did-you-mean on unknown keys

`textus get working.skills.editorail.voice-writer` (typo'd) reports the
top suggestions via the `did you mean:` hint, ranked by shared prefix and
Levenshtein distance against the actual key set. Same applies to `where`,
`put`, `delete`, and `mv`.

## Intake refresh

`inbox.upstream.notes` reads `.textus/zones/identity/voice-tools.md` through
the in-process `local_file` action. Walk it with:

```bash
rake textus:refresh    # refresh every stale inbox entry
rake textus:update     # refresh + build + dispatch external :build hooks
```

## Project-local hooks

Every `.rb` file in `.textus/hooks/` is auto-loaded on store boot and
registers into an isolated per-store registry. This example wires up:

- `plugin_envelope` — turns the `identity.plugin` row into a Claude
  `plugin.json` envelope.
- `marketplace_envelope` — assembles `identity.marketplace` + `identity.plugin` +
  the `working.skills.*` rows into a Claude `marketplace.json` envelope.
- `claude_root` — groups projection rows by source prefix for the CLAUDE.md
  template payload.
- `rank_by_recency`, `local_file`, `build-stamp` — kept as demos of the
  `:reduce` / `:intake` / `:built` / `:check` event surfaces (all expressed
  through the unified `Textus.hook(event, name)` DSL).

Inspect everything currently loaded with `textus hook list`.
