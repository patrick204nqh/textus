# textus

Reference Ruby implementation of the **textus/1** protocol — a storage convention and JSON wire protocol that lets AI agents and humans read and write structured project memory deterministically.

See [`SPEC.md`](SPEC.md) for the full specification. Implementation notes and conventions live in [`docs/`](docs/).

## Install

```sh
gem install textus     # (when published)
# or, from this repo:
bundle install
bundle exec exe/textus --help
```

## Quick start

Create a `.textus/` directory in your project:

```
.textus/
  manifest.yaml
  schemas/person.yaml
  state/network/org/jane.md
```

`manifest.yaml`:

```yaml
version: textus/1
entries:
  - key: state.network.org
    path: state/network/org
    zone: state
    schema: person
    owner: textus:network
    nested: true
```

`schemas/person.yaml`:

```yaml
name: person
required: [name, relationship, org]
fields:
  name:         { type: string, max: 80 }
  relationship: { type: enum, values: [peer, manager, report, external] }
  org:          { type: string }
```

`state/network/org/jane.md`:

```markdown
---
name: jane
relationship: peer
org: envato
---
Notes about Jane.
```

Then:

```sh
textus get state.network.org.jane --format=json
textus list --prefix=state --format=json
echo '{"frontmatter":{"name":"bob","relationship":"peer","org":"envato"},"body":"hi\n"}' \
  | textus put state.network.org.bob --stdin --format=json
textus stale --format=json
```

## CLI verbs

| Verb | Purpose |
|---|---|
| `textus list [--prefix=<key>] --format=json` | Enumerate keys |
| `textus where <key> --format=json` | Resolve a key to its file path |
| `textus get <key> --format=json` | Return the full envelope |
| `textus put <key> --stdin --format=json` | Write/update (stdin: `{frontmatter, body, if_etag?}`) |
| `textus schema <key> --format=json` | Return the schema definition |
| `textus stale [--prefix=<key>] --format=json` | List stale derived entries |

## Zones

- **`fixed`** — human-only writes (identity, voice, canon). Agents get `write_forbidden`.
- **`state`** — agent-writable.
- **`derived`** — build-tool writes only. `textus stale` flags entries whose declared sources have changed; build runners execute the `generator.command` themselves. textus is a **dataflow oracle, not an executor**.

## Tests

```sh
bundle exec rspec
```

Covers the four conformance fixtures from §12 of the spec (resolve+read, zone gate, schema violation, staleness detection) plus CLI smoke tests for `get` and etag-mismatched `put`.

## License

MIT.
