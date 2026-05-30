# examples/project — textus as your project's context store

This example shows how to use textus to manage *your own project's*
AI-collaboration context: the orientation file agents read on session
start (`CLAUDE.md` / `AGENTS.md`), your runbooks, your ADRs. Nothing in
this example ships to end users — the store is for the project's
internal use.

The example is staged as a fictional Rails service called **ledger** so
the content reads like a real codebase. Replace it with your own.

For the **distribution** use case (shipping a plugin to end users where
textus is the authoring source-of-truth), see `examples/claude-plugin/`.

## Layout

```
project/
  CLAUDE.md                          # ← generated, read by Claude Code on session start
  AGENTS.md                          # ← generated, read by Cursor / other agents
  .textus/
    manifest.yaml                    # 3 zones, 4 entries
    schemas/
      project.yaml                   # frontmatter shape for knowledge.project
      runbook.yaml                   # frontmatter shape for knowledge.runbooks.*
      decision.yaml                  # frontmatter shape for proposals.decisions.*
    templates/
      orientation.mustache           # renders CLAUDE.md/AGENTS.md
    hooks/
      orientation_reducer.rb         # reshapes projection rows for the template
    zones/
      knowledge/
        project.md                   # slow-changing project facts (humans only)
        runbooks/
          deploy.md                  # how to ship a release
          oncall.md                  # first response when the service pages
      proposals/decisions/
        0001-example.md              # pre-staged ADR proposal (agent → human)
      artifacts/orientation.md       # ← published to CLAUDE.md and AGENTS.md
```

## Try it

```bash
cd examples/project

# Discover what's in the store.
bundle exec ../../exe/textus list

# Read an entry.
bundle exec ../../exe/textus get knowledge.runbooks.deploy

# Re-render CLAUDE.md and AGENTS.md from the knowledge entries.
bundle exec ../../exe/textus build

# Health check (manifest + schemas + sentinel drift + audit log).
bundle exec ../../exe/textus doctor

# Inspect the pre-staged ADR proposal. Running `accept` would create the
# proposal's target_key (knowledge.runbooks.sidekiq-pro-upgrade) and
# delete the proposals entry — one audit-logged operation.
bundle exec ../../exe/textus get proposals.decisions.0001-switch-to-sidekiq-pro
# bundle exec ../../exe/textus accept proposals.decisions.0001-switch-to-sidekiq-pro --as=human
```

## Adoption recipe for your project

```bash
cd path/to/your/project
gem install textus
textus init                                          # scaffolds an empty .textus/

# Use this example as a starter — copy the manifest, schemas, template, and reducer.
cp examples/project/.textus/manifest.yaml your/.textus/
cp -r examples/project/.textus/{schemas,templates,hooks} your/.textus/

# Replace the example knowledge/ content with your own.
edit your/.textus/zones/knowledge/project.md
edit your/.textus/zones/knowledge/runbooks/*.md

textus build                                         # generates CLAUDE.md, AGENTS.md
git add CLAUDE.md AGENTS.md .textus/
git commit -m "Adopt textus context store"
```

## The pattern

| Use case | Zone | Writers | Example here |
|---|---|---|---|
| Project facts and operational knowledge | `knowledge` | human only | `knowledge.project` — the `ledger` service description; `knowledge.runbooks.*` |
| Agent suggests a change for human approval | `proposals` | agent → human accept | `proposals.decisions.0001-…` |
| Build-computed projection of all of the above | `artifacts` | automation only | `artifacts.orientation` → `CLAUDE.md` + `AGENTS.md` |

The `proposals` flow is the load-bearing piece for AI-assisted edits: agents
never write directly to knowledge zones — they write a
*proposal* under `proposals.**` with a `proposal:` frontmatter block naming
the `target_key` and `action`. A human reviews the diff, then runs
`textus accept` to apply it. The whole exchange is in `.textus/audit.log`.
