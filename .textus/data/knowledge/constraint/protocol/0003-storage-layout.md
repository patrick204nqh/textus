## 3. Storage layout

The root is `.textus/` at the project working directory. A typical tree:

```
.textus/
  manifest.yaml          # internal: key → subtree mapping + role/lane declarations
  schemas/               # internal: YAML schema files
  templates/             # internal: ERB templates referenced by produced entries
  workflows/             # user: Textus.workflow DSL files for produced entry acquisition
  .state/                  # runtime (git-ignored): audit log, sentinels, locks, queue, pulse cursors
    audit.log            # append-only NDJSON log of every successful write
    sentinels/           # byte-copied publish bookkeeping (see §5.3)
  data/                  # ALL user content lives here
    knowledge/           # lane: knowledge (kind: canon — author-holders write)
    scratchpad/            # lane: scratchpad (kind: workspace — keep-holders write; agent's own durable lane)
    proposals/           # lane: proposals (kind: queue — propose-holders write)
    artifacts/           # lane: artifacts (kind: machine — converge-holders write)
    raw/                 # lane: raw (kind: raw — ingest-holders write; write-once)
```

Textus internals (`manifest.yaml`, `schemas/`, `templates/`, `workflows/`) live directly under `.textus/`; disposable runtime state (audit log, publish `sentinels/`, fetch/build locks, pulse cursors, job queue) lives under `.textus/.state/` (git-ignored, ADR 0038/0070). **All user content lives under `.textus/data/`.** Manifest `path:` fields are relative to `.textus/` — they include the `data/` prefix explicitly (e.g. `path: data/knowledge/foo.md`).

Lane directories under `data/` are conventional; their write semantics are derived from the lane's declared `kind:` (and the capabilities roles hold), not the directory name.

`.textus/audit.log` is an append-only NDJSON file written under a file lock by every successful `put`, `key_delete`, `key_mv`, and `accept`. Convergence (`drain`/`serve`) writes through these same verbs — a produced entry logs as `put`, a swept entry as `key_delete` — so there is no distinct `drain` audit verb. `.textus/role` (one line containing a role name) is optional and participates in the role-resolution order (§5).

### 3.1 Store location precedence

Implementations MUST resolve the store root in this order; the first match wins:

1. `--root <path>` flag passed to the CLI (or `root:` kwarg to `Store.discover`).
2. `TEXTUS_ROOT` environment variable.
3. Walk up from cwd looking for a `.textus/` directory containing `manifest.yaml`.

When (1) or (2) names a path that has no `manifest.yaml`, the CLI exits with `io_error` and a message naming the resolved absolute path. When (3) reaches the filesystem root without finding a store, the CLI exits with `io_error` naming the search start point.
