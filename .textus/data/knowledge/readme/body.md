<!-- This is a fragment of the README. Edit here; the README is composed from fragments by a workflow. -->
## See it in four commands

```sh
gem install textus
textus init                          # creates .textus/ with lanes + schemas

# an agent proposes a change — it targets a knowledge entry, but lands in proposals/
textus propose notes.oncall --as=agent --stdin <<'JSON'
{
  "_meta": { "name": "oncall",
             "proposal": { "target_key": "knowledge.notes.oncall", "action": "put" } },
  "body": "Patrick on call.\n"
}
JSON

# you accept it — textus promotes to knowledge/ and audits the move
textus accept proposals.notes.oncall --as=human
```

Try the gate the other way (`textus put knowledge.notes.X --as=agent`) and you get `write_forbidden`, with the role that *would* be allowed named in the error. That refusal is the whole point.

## Try it

- **Worked end-to-end store** — the role gate (propose → accept), drain/publish (`CLAUDE.md` / `AGENTS.md` generated from knowledge entries), schemas, ERB templates, and workflows: [`.textus/`](.textus/)
- **Wire textus into Claude Code via MCP** — 4 steps, ~5 minutes: [`docs/how-to/agents-mcp.md`](docs/how-to/agents-mcp.md)

## Protocol, not just a gem

This Ruby gem is the reference implementation of **`textus/4`** — a wire format and storage convention any language can speak. The protocol owns the envelope shape, the role/lane gate, the audit log format, and the key grammar. The gem version (semver, see badge) and the protocol version (`textus/4`) move independently; envelopes carry the `protocol` field so consumers can pin to the contract, not the implementation.

- Specification: [`SPEC.md`](SPEC.md)
- Architecture: [`docs/architecture/README.md`](docs/architecture/README.md)
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

## What `textus init` gives you

You get `.textus/` with all five lane directories under `data/`, baseline schemas, a starter manifest, and a gitignored `.state/` for disposable runtime state (the audit log, per-role cursors, produce locks). Roles declare capabilities; each lane declares a `kind:`, and write authority is derived from the role's capabilities crossed with the lane's kind:

```yaml
roles:
  - { name: human,      can: [author, propose] }
  - { name: agent,      can: [propose, keep] }
  - { name: automation, can: [converge] }

lanes:
  - { name: knowledge, kind: canon }      # author   — canonical truth
  - { name: scratchpad,  kind: workspace }  # keep     — agent's own durable lane
  - { name: proposals, kind: queue }      # propose  — proposals awaiting accept
  - { name: artifacts, kind: machine }    # converge — computed outputs + external inputs
```

```
.textus/
  manifest.yaml          # role capabilities + lane kinds + key-to-path mapping
  schemas/               # YAML field shapes per entry family
  templates/             # ERB templates for produced entries
  workflows/             # Ruby workflow files (Textus.workflow DSL) for data acquisition
  .gitignore             # generated — ignores .state/ and any tracked:false entries
  data/                  # one dir per lane; kinds + capabilities are in the manifest above
    knowledge/           # e.g. identity (knowledge.identity.*), voice, decisions, notes
    scratchpad/
    proposals/
    artifacts/           # machine lane: computed outputs + external inputs
  .state/                  # disposable runtime state — gitignored, safe to delete (ADR 0038)
    audit/audit.log      # append-only NDJSON event ledger, every write (rotates at ~10 MB)
    cursors/<role>       # per-role pulse cursor — where `pulse --since` resumes
    locks/               # per-key produce locks + the produce mutex
    sentinels/           # publish bookkeeping (target sha) — regenerated on drain (ADR 0070)
    indexes/raw.yaml     # raw lane content-hash/URL index — regenerable cache
```

Manifest `path:` fields are relative to `.textus/data/`. So `knowledge.notes.org.jane` lives at `.textus/data/knowledge/notes/org/jane.md`.

Read and write:

```sh
textus get knowledge.notes.org.jane
textus list --lane=knowledge
printf '%s' '{"_meta":{"name":"bob","org":"acme"},"body":"hi\n"}' \
  | textus put knowledge.notes.bob --as=human --stdin
textus drain --as=automation     # re-pull stale inputs + recompute derived outputs
textus rule list                  # show every rule block
textus audit --limit=20           # query the audit log
```

(All verbs return JSON envelopes; `--output=json` is the default and the only format.)

For a worked store — knowledge entries, a staged proposal, schemas, ERB templates, and a `drain` that publishes `CLAUDE.md` / `AGENTS.md` — see [`.textus/`](.textus/).

## What's shipped

- **Per-entry formats & publish.** `format: markdown|json|yaml|text` per entry; a typed `publish:` block (`to:` for file fan-out, `tree:` for a whole-subtree mirror) byte-copies derived files to their consumer paths. ([SPEC §5.2–5.3](SPEC.md))
- **Stable identity.** Auto-minted `uid:` survives writes and `textus key mv`; reorganising never breaks references.
- **Capability × lane-kind gate.** Writes carry `--as=<role>`; a role may write a lane iff it holds the capability the lane's `kind:` requires (`canon`→`author`, `workspace`→`keep`, `machine`→`converge`, `queue`→`propose`). The wrong role gets `write_forbidden` naming the capability needed and the roles that hold it. ([SPEC §5](SPEC.md))
- **Agent loop.** `textus boot` orients a fresh session; `textus pulse --since=N` is the per-turn heartbeat (changed entries, pending proposals, index etag for catalog drift detection). ([docs/how-to/agents-mcp.md](docs/how-to/agents-mcp.md))
- **MCP surface.** The official `mcp` Ruby SDK drives the stdio JSON-RPC server; protocol version auto-negotiated up to `2025-11-25`. Wire textus into Claude Code, Cursor, or any MCP host in one config block.
- **`textus doctor`.** Health checks across schemas, workflow registrations, keys, sentinels, and the audit log.
- **`raw` lane and `ingest` verb.** Write-once intake lane for external URL bookmarks, files, and binary assets. Three source kinds (`url`/`file`/`asset`); daily key derivation; scratchpad stub per ingest. See "Intake and ingest" section below.

## CLI and lanes

Every command operates on one store, located in this order: `--root <path>` flag → **`TEXTUS_ROOT`** env → walk up from the working directory for a `.textus/` ([SPEC §3.1](SPEC.md)). Write verbs require `--as=<role>`, resolved as: `--as` flag → **`TEXTUS_ROLE`** env → `.textus/role` file → default `human` ([SPEC §5.1](SPEC.md)). Default roles: `human`, `agent`, `automation` (rename or add your own in the manifest's `roles:` block). All verbs accept `--output=json` and return the envelope defined in [SPEC §8](SPEC.md).

- Full verb table — read, write, health, scaffolding — is in [SPEC §9](SPEC.md).
- Lane semantics and the capability × lane-kind mapping live in [SPEC §5](SPEC.md), with the reference in [`docs/reference/lanes.md`](docs/reference/lanes.md).

`textus boot` prints the same information for the current store: lanes, entry families with schemas, registered workflows, write flows, and the verb catalog. Run it inside a store and you get the live picture; reach for the SPEC when you want the contract.

## Produce and publish

Produced entries (`kind: produced`) declare how they're acquired in one `source:` block; `drain` materialises them. Two built-in modes, plus workflows for custom data acquisition:

- **`source: { from: external, command: "...", sources: [...] }`** — *externally managed*: an out-of-band command or workflow writes the file; textus tracks staleness via declared `sources`.
- **`source: { from: external, command: "true", sources: [] }` + a workflow** — *workflow-driven*: a `Textus.workflow` block (in `.textus/workflows/`) acquires and shapes the data on `drain`.

Publishing is one typed `publish:` block (ADR 0052/0094). Each target is either `{ to: path, template?: name }` for a single file (optionally rendered through an ERB template) or `{ tree: "dir" }` to mirror a whole stored subtree. Sentinels for every published file live under `.textus/.state/sentinels/` (git-ignored, regenerated on drain). See SPEC §5.2, §5.3, §5.12.

Templates live in `.textus/templates/` as ERB files (`.erb`). The template receives the entry's `content` hash as local variables via `ERB#result_with_hash`. If `inject_boot: true`, a `boot` variable is also available with the live orientation context.

## Workflows

textus extends through **workflows** — a `Textus.workflow` block placed in `.textus/workflows/**/*.rb`. Each workflow matches a produced entry by key glob, then runs one or more named steps to acquire its data:

```ruby
# .textus/workflows/docs/my_report.rb
Textus.workflow "my_report" do
  match "artifacts.my-report"

  step :build do |_, ctx|
    # read from knowledge, fetch external data, compute anything
    rows = ctx.container.manifest.resolver
              .enumerate(prefix: "knowledge.notes")
              .map { |r| { "key" => r[:key], "title" => r[:entry].schema } }
    { "content" => { "entries" => rows } }
  end
end
```

`drain` discovers all workflow files, matches them against produced entries, and runs the steps. The result is written back to the entry's data path; `publish:` then copies it to its consumer paths.

## Intake and ingest

The `raw` lane is the inbound counterpart to `artifacts`: where `drain` materialises
**outbound** computed outputs, `ingest` receives **inbound** external source material.

**The ingest principle:** prefer a reference over a copy. Store body or asset only when the
content itself is the value — human-authored notes, brainstorm outputs, context you want to
annotate. For everything else, the URL is enough. If the source is private or
access-restricted, set `access: private` in `source:` so downstream workflows can handle it
appropriately.

**Three source kinds:**

| Kind | Stores | Use when |
|------|--------|----------|
| `url` | URL reference only (`body: null`) | Bookmarking a page, skill, or doc for later annotation |
| `file` | File body text | Valuable human-authored content (brainstorm notes, meeting summaries) |
| `asset` | Binary at `assets/raw/` | Screenshots, PDFs — only when the asset itself is the artefact |

**Write-once** — the same slug on the same day cannot be overwritten. Delete and re-ingest to replace.

```sh
# bookmark a skill reference — URL only, body stays null
textus ingest url agentskills-io-brainstorming \
  --url=https://agentskills.io/skills/brainstorming \
  --label="brainstorming skill" \
  --as=agent

# see what landed in the raw lane
textus list --lane=raw

# a scratchpad stub was created alongside — annotate it
textus get scratchpad.notes.raw
```

Stale produced entries are re-materialised by `drain`, not by reads — `get` is a pure read (ADR 0089).

```sh
textus drain --as=automation                  # re-materialise every stale produced entry
textus drain artifacts.feeds.skills --as=automation # scope to one prefix
textus get artifacts.feeds.skills                  # a pure read; carries a freshness verdict
```

Schemas (`.textus/schemas/<name>.yaml`) declare field shapes, per-field `maintained_by:` ownership, and an `evolution:` block (`added_in`, `deprecated_at`, `migrate_from`). Full contract in SPEC §5.8.

See [`docs/how-to/agents-mcp.md`](docs/how-to/agents-mcp.md) for the agent boot → pulse loop.

## Examples

[`.textus/`](.textus/) — textus as a project's own context store. Human-authored `knowledge/` (project facts, runbooks, ADRs), a staged proposal showing the agent-propose / human-accept loop, schemas validating each family, ERB templates and workflows, and a `drain` that publishes the orientation artifact to `CLAUDE.md` and `AGENTS.md`. Includes a copy-paste adoption recipe for your own repo.

## Tests

```sh
bundle exec rspec
```

Includes conformance fixtures A–I from SPEC §12.

## Code quality

```sh
bundle exec rubocop      # lint
bundle exec rubocop -A   # lint + autocorrect
```

Lefthook hooks (`brew bundle install` then `lefthook install`) run rubocop on `pre-commit` and `rspec + rubocop` on `pre-push`. Bypass with `LEFTHOOK=0 git commit ...` when needed. CI runs `rspec` (Ruby 3.3 / 3.4) and `rubocop` via GitHub Actions.

## License

[MIT](LICENSE)
