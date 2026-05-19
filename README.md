# textus

Reference Ruby implementation of the **textus/1** protocol — a storage convention and JSON wire protocol for agent-readable project memory: addressable dotted keys, schema-validated Markdown entries, role-gated writes, declarative compute, and symlinked publish targets.

See [`SPEC.md`](SPEC.md) for the protocol. Implementation notes live in [`docs/`](docs/).

## Versioning

Two versions, deliberately independent:

- **Protocol wire string:** `textus/1`. Stable; breaking changes require `textus/2`.
- **Gem version:** semver, currently `0.1.0` (first release). Gem `0.x.y` and `1.x` both speak `textus/1`.

Envelope payloads carry the `protocol` field; the gem version is irrelevant to the wire format.

## Install

```sh
gem install textus     # when published
```

Or from this repo:

```sh
bundle install
bundle exec exe/textus --help
```

## Quick start

Bootstrap a fresh tree:

```sh
bundle exec exe/textus init --profile=personal
```

This scaffolds `.textus/` with a starter manifest, the five zone directories, baseline schemas, and an empty audit log. The resulting layout:

```
.textus/
  manifest.yaml
  audit.log
  role
  schemas/
  templates/
  parsers/
  zones/
    canon/       # human-only
    working/     # human, ai, script
    intake/      # script (declared external inputs)
    pending/     # ai (proposals awaiting accept)
    derived/     # build only (computed outputs)
```

A minimal `manifest.yaml`:

```yaml
version: textus/1

zones:
  - { name: canon,   writable_by: [human] }
  - { name: working, writable_by: [human, ai, script] }
  - { name: intake,  writable_by: [script] }
  - { name: pending, writable_by: [ai] }
  - { name: derived, writable_by: [build] }

entries:
  - key: canon.identity
    path: canon/identity.md
    zone: canon
    schema: identity

  - key: working.network.org
    path: working/network/org
    zone: working
    schema: person
    owner: textus:network
    nested: true
```

Manifest `path:` fields are relative to `.textus/zones/` — implementations prepend `zones/` when resolving. So `working.network.org.jane` lives at `.textus/zones/working/network/org/jane.md`.

Read and write:

```sh
textus get working.network.org.jane --format=json
textus list --zone=working --format=json
echo '{"frontmatter":{"name":"bob","relationship":"peer","org":"envato"},"body":"hi\n"}' \
  | textus put working.network.org.bob --as=human --stdin --format=json
textus stale --zone=derived --format=json
```

## CLI verbs

All verbs accept `--format=json` and emit the envelope defined in SPEC §8. Write verbs require `--as=<role>` (subject to role-resolution order, §5.1).

**Read verbs (no role required):**

| Verb | Purpose |
|---|---|
| `list [--prefix=K] [--zone=Z] [--stale]` | Enumerate keys, optionally filtered |
| `where K` | Resolve a key to its filesystem path |
| `get K` | Return the full envelope |
| `schema K` | Return the schema bound to an entry |
| `stale [--prefix=K] [--zone=Z] [--strict]` | List stale derived/intake entries |
| `deps K` / `rdeps K` | Forward/reverse projection dependencies |
| `published` | List `publish_to:` targets and their backing keys |
| `validate-all` | Validate every entry against its schema (incl. `maintained_by`) |
| `hooks list [--event=E]` | Enumerate declared lifecycle hooks |

**Write verbs (role-gated per zone):**

| Verb | Role |
|---|---|
| `put K --stdin --as=R [--parse=NAME]` | per zone |
| `delete K --if-etag=E --as=R` | per zone |
| `build [--prefix=K] [--dry-run]` | `build` |
| `accept K --as=human` | `human` only |

**Scaffolding (human-only):**

| Verb | Purpose |
|---|---|
| `init [--profile=P]` | Scaffold a fresh `.textus/` tree |
| `schema-init NAME` | Write a stub schema |
| `schema-diff NAME` | Compare on-disk schema against entries claiming it |
| `schema-migrate NAME [--rename=OLD:NEW]` | Rewrite frontmatter keys across affected entries |

## Zones and roles

| Zone | `writable_by` | Purpose |
|---|---|---|
| `canon` | `[human]` | Identity, voice, immutable principles |
| `working` | `[human, ai, script]` | Active project state — notes, decisions, network |
| `intake` | `[script]` | Declared external inputs (calendar, feeds, scraped pages) |
| `pending` | `[ai]` | AI proposals awaiting `textus accept` |
| `derived` | `[build]` | Computed outputs from `textus build` |

The effective role for any CLI call is resolved in order: `--as` flag, then `TEXTUS_ROLE` env, then `.textus/role`, then default `human`. Mismatches return `write_forbidden`. Every write records the resolved role in `.textus/audit.log`.

## Compute layer

Derived entries are not authored by hand. Each declares a `projection:` block (select prefixes, pluck fields, optional sort/limit/transform) and optionally a Mustache template under `.textus/templates/`. textus implements a deliberately restricted Mustache subset (variables, sections, inverted sections, comments — no partials, no lambdas, no HTML escaping). Results are bounded at 1000 rows; template recursion at depth 8.

A derived entry MAY declare `publish_to:` listing repo-relative destinations. On rebuild, textus performs an atomic symlink swap (with copy-mode fallback on filesystems without symlinks). See SPEC §5.2 and §5.3.

## Extension points

Three named hooks where user code may run. Each is registry-shaped and bounded by a 2-second timeout where applicable.

- **Parsers** (`.textus/parsers/*.rb`) — translate raw bytes to entries during intake refresh. Built-ins: `json`, `csv`, `markdown-links`, `ical-events`, `rss`. Project-local parsers auto-load at `Store#initialize`. SPEC §5.4.
- **Calculators** (`.textus/calculators/*.rb`) — pure row-to-row transforms used by projections via `transform: NAME`. Run between pluck and sort. Must not perform I/O. SPEC §5.9.
- **Hooks** — declarative entries under a manifest entry's `hooks:` block, keyed by event (`on_put`, `on_delete`, `on_refresh`, `on_stale`, `on_accept`, `on_build`). textus enumerates; external runners (lefthook, cron, CI) invoke. SPEC §5.10.

Schema fields may also declare `maintained_by:` and a top-level `evolution:` block (`added_in`, `deprecated_at`, `migrate_from`). SPEC §5.8.

## Examples

- [`examples/claude-plugin/`](examples/claude-plugin/) — full tour: parser, calculator, lifecycle hooks, schema ownership, and a `derived.claude.root` entry published to `CLAUDE.md`.
- [`examples/mcp-server/`](examples/mcp-server/) — 50-line MCP server wrapping `textus get/put` as tools.

## Tests

```sh
bundle exec rspec
```

Runs the full suite, including conformance fixtures A–I from SPEC §12.

## License

MIT.
