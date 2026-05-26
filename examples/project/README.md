# examples/project — textus as your project's context store

This example shows how to use textus to manage *your own project's*
AI-collaboration context: the orientation file agents read on session
start (`CLAUDE.md` / `AGENTS.md`), your runbooks, your ADRs. Nothing in
this example ships to end users — the store is for the project's
internal use.

For the **distribution** use case (shipping a plugin to end users where
textus is the authoring source-of-truth), see `examples/claude-plugin/`.

## What's in here

- `.textus/manifest.yaml` — declares 4 zones (identity, working, review,
  output) and 4 entries.
- `.textus/schemas/{project,runbook,decision}.yaml` — schemas for each
  entry family.
- `.textus/zones/identity/project.md` — slow-changing project facts.
- `.textus/zones/working/runbooks/{deploy,oncall}.md` — operational
  guides agents and humans share.
- `.textus/zones/review/decisions/0001-example.md` — a pre-staged ADR
  proposal demonstrating the agent → human accept flow.
- `.textus/templates/orientation.mustache` — projects identity + runbooks
  into the orientation header at the repo root.
- `.textus/hooks/orientation_reducer.rb` — reshapes projection rows for
  the template.
- `CLAUDE.md`, `AGENTS.md` — generated. Agents read these on session
  start.

## Try it

```bash
cd examples/project

# List everything in the store
bundle exec ../../exe/textus list

# Read an entry
bundle exec ../../exe/textus get working.runbooks.deploy

# Re-build the orientation files
bundle exec ../../exe/textus build

# Health check
bundle exec ../../exe/textus doctor

# Accept the pre-staged ADR proposal (would promote it to its target)
# bundle exec ../../exe/textus accept review.decisions.0001-example --as=human
```

## Adoption recipe for your project

```bash
cd path/to/your/project
gem install textus
textus init                                          # scaffolds .textus/
# Copy this example's manifest, schemas, template, and reducer as a starting point.
cp -r examples/project/.textus/{schemas,templates,hooks} your/.textus/
# Edit .textus/manifest.yaml to match your domain.
textus build                                         # generates CLAUDE.md, AGENTS.md
git add CLAUDE.md AGENTS.md .textus/
git commit -m "Adopt textus context store"
```

## The pattern

| You want... | Pattern |
|---|---|
| Slow-changing project facts | `identity` zone, human-only writes |
| Shared runbooks / prompts | `working` zone, human + agent writes |
| Agent suggests a change | Write to `review.*` with a `proposal:` block; human runs `textus accept` |
| Build-computed orientation | `output` zone with `inject_intro: true` + a mustache template |
