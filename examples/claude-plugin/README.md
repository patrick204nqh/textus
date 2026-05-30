# voice-tools — a Claude Code plugin managed by textus

> This example demonstrates the **distribution** use case: textus is the
> authoring source-of-truth for a Claude plugin that ships to end users.
> Identity → working/{agents,skills,commands} → published artifacts at
> `agents/*.md`, `skills/*.md`, etc. For the **internal project context**
> use case (textus inside your own project, not shipping anything), see
> `examples/project/`.

This example shows a minimal Claude Code plugin (`voice-tools`) whose
authoring surface lives entirely under `.textus/`. The plugin ships:

- 1 agent (`voice-writer`)
- 1 skill (`voice-writer`)
- 1 command (`/rewrite`)
- a plugin manifest at `.claude-plugin/plugin.json`
- a `CLAUDE.md` loaded on session start
- a `.mcp.json` that wires Claude Code to the textus MCP server

Every consumer-facing file — the two output envelopes *and* every
agent/skill/command leaf under `agents/`, `skills/`, `commands/` — is
byte-copied from `.textus/zones/...` by a textus build. No file under
`agents/`, `skills/`, or `commands/` is hand-mirrored.

The example is deliberately small. It demonstrates three load-bearing
patterns once each: zone separation by role, `publish_each` byte-copy,
and `inject_boot` orientation projection.

## Wiring

This plugin declares the textus MCP server in `.mcp.json`. Claude Code
launches it automatically when the plugin is loaded. The plugin's
agents and skills reference textus *tools* (boot, tick, find, read,
write, propose, ...), not CLI verbs.

If you want to drive textus from a terminal, the human CLI surface
(`textus boot` / `textus get` / `textus put`) still works — but skills
do not use it.

## Layout

```
voice-tools/
  .claude-plugin/
    plugin.json              # ← published from .textus/zones/output/plugin.json
  CLAUDE.md                  # ← published from .textus/zones/output/claude-root.md
  .mcp.json                  # declares the textus MCP server

  agents/
    voice-writer.md          # ← publish_each from working.agents.voice-writer
  skills/
    voice-writer/SKILL.md    # ← publish_each from working.skills.writing.voice-writer
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
      plugin_envelope.rb     # transform → plugin.json shape
      claude_root.rb         # transform → CLAUDE.md template payload
    templates/
      claude-root.mustache   # renders CLAUDE.md from the compute payload
    zones/
      identity/
        voice-tools.md         # plugin identity
      working/
        agents/<name>.md
        skills/<topic>/<name>.md  # nested ≥4 segments
        commands/<name>.md
      review/
        suggestion/<name>.md   # AI proposals awaiting human accept
      output/
        plugin.json            # → publish_to .claude-plugin/plugin.json
        claude-root.md         # → publish_to CLAUDE.md
  recipes/                     # optional advanced patterns; see recipes/README.md
```

## How textus manages the catalog

- **Identity** holds the slow-changing plugin identity (`identity.plugin`).
  The `identity` zone is a `canon` zone, so writing it needs the `author`
  capability — only the human holds it; agents and automation cannot touch it.
- **Working** holds the day-to-day catalog: every agent, skill, and command
  lives here as markdown with frontmatter. The schemas (`agent`, `skill`,
  `command`) validate the frontmatter on every read and write.
- **Review** is the AI proposal surface. The manifest's `review.**` rule
  declares `guard: { accept: [schema_valid, author_signed] }` — the
  contract a proposal must satisfy before it can be accepted (`author_signed`
  is satisfied only by a role holding the `author` capability).
- **Output** is owned by `automation:auto`. Two output entries assemble the
  shipped surface:
  - `output.plugin` → `plugin_envelope` transform → `.claude-plugin/plugin.json`
  - `output.claude-root` → `claude_root` transform + `claude-root.mustache`
    template (with `inject_boot: true`) → `CLAUDE.md`

The `inject_boot: true` flag on `output.claude-root` makes the `store.boot`
envelope available inside the template as `{{boot.*}}` — the rendered `CLAUDE.md`
auto-projects zone authority and the tool surface straight from textus's
own boot envelope. The template instructs agents to call `boot()` once
per session and `tick()` per turn via the textus MCP server, teaching
the boot+pulse pattern for keeping context fresh in long-running
interactions. Agents reading `CLAUDE.md` get full orientation without
an extra round trip.

The deep-nested skill path (`working.skills.writing.voice-writer` —
four key segments below `working`) exercises textus's nested-tree resolver.

## Policies

The manifest's top-level `rules:` block declares rules that apply across
multiple entries, matched by glob and resolved most-specific-wins per slot.
This example ships one block:

```yaml
rules:
  # Contract for AI proposals.
  - match: review.**
    guard: { accept: [schema_valid, author_signed] }
```

The `rules({key})` MCP tool returns the effective rules for any key.

## AI proposals (`review` zone)

The `review` zone is the canonical write path for AI agents. The agent
calls `propose({key, meta, body})` via the MCP server — the proposal
carries the target key and the payload it would write. A human reviews
the file like any diff, then accepts it (which writes to the real target
and deletes the review entry). The whole exchange is in `.textus/audit.log`.

The manifest declares a nested review entry so any agent can drop a
proposal under it:

```yaml
- key: review.suggestion
  path: review/suggestion
  zone: review
  schema: null
  owner: agent:catalog
  nested: true
```

A live fixture lives at `.textus/zones/review/suggestion/001.md` —
open it to see the proposal envelope shape.

End-to-end via MCP, the loop is:

1. Agent calls `propose({key: "suggestion.001", meta: {...}, body: "..."})` —
   the session's `propose_zone` (`review`) auto-prefixes the key.
2. Human reviews: `find({prefix: "review"})` → `read({key: "review.suggestion.001"})`.
3. Human accepts. The MCP server writes `target_key` as the human role,
   then deletes the review entry. The next build picks it up via `publish_each`.

Only humans can accept a proposal — agents can only propose.

## Project-local hooks

Every `.rb` file in `.textus/hooks/` is auto-loaded on store boot and
registers into an isolated per-store registry. This example wires up:

- `plugin_envelope` — turns the `identity.plugin` row into a Claude
  `plugin.json` envelope.
- `claude_root` — groups compute rows by source prefix for the CLAUDE.md
  template payload.

For richer patterns (external intake handlers, fan-out from one intake
to many derived entries), see the optional copy-paste recipes in `recipes/`.
