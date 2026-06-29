## 8. Envelope (the wire format)

Every successful CLI response (`--output=json`) is a single JSON envelope:

```json
{
  "protocol": "textus/4",
  "key": "knowledge.network.org.jane",
  "lane": "knowledge",
  "owner": "human:network",
  "path": "/absolute/path/to/.textus/data/knowledge/network/org/jane.md",
  "format": "markdown",
  "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body in Markdown.\n",
  "etag": "sha256:8f3c…",
  "schema_ref": "person",
  "uid": "a1b2c3d4e5f60718",
  "sources": [
    { "key": "raw.2026.06.20.url-mcp-spec", "etag": "sha256:1a2b…", "suspended": false }
  ],
  "stale": false,
  "stale_reason": null,
  "fetching": false
}
```

**Field rules:**
- `protocol` MUST be the exact string `textus/4`.
- `key` MUST be the canonical resolved key.
- `lane` MUST be one of the lanes declared in the manifest (`knowledge`, `scratchpad`, `proposals`, `artifacts`, `raw` in the default Setup-1 scaffold).
- `path` MUST be an absolute filesystem path.
- `format` MUST be one of `markdown`, `json`, `yaml`, `text` (§5.12). Absent envelopes are treated as `markdown` for back-compat.
- `body` is the raw on-disk bytes as a UTF-8 string for every format.
- `content` is present only when `format` is `json` or `yaml`; equals the parsed object. For `json|yaml`, `_meta` mirrors the top-level `_meta` block (or `{}` if absent). For `markdown`, `_meta` holds the parsed YAML frontmatter. For `text`, `_meta` is `{}`.
- `etag` MUST be `sha256:<hex>` of the raw file bytes, computed identically for every format.
- `schema_ref` MAY be `null` for entries in subtrees with `schema: null`.
- `uid` is the stable Textus UID (§7) if the entry carries one, else `null`. Always present in the envelope.
- `sources` is an array of source objects. Each object has `key` (the referenced entry's key), `etag` (sha256 snapshot taken at write time, or absent when no snapshot exists), and `suspended` (`true` when the referenced entry's current on-disk etag differs from the stored snapshot — the source changed after this entry was last written). Present only when non-empty.
- `stale` is `true` when the entry's `source.ttl` has elapsed and the entry has not yet been re-materialised; `false` otherwise. Only populated for produced entries with a declared `ttl`; always `false` for other entries.
- `stale_reason` is a short human-readable string describing why the entry is stale (e.g. `"ttl_exceeded"`, `"never_fetched"`), or `null` when `stale` is `false`.
- `fetching` is `true` when a background re-pull is in flight for this entry; `false` otherwise. Callers observing `stale: true, fetching: true` SHOULD retry after a short delay.

> **Note:** `list`/`where` envelopes do **not** include `stale`, `stale_reason`, or `fetching` — freshness annotation is only provided by `get`.

Errors use a distinct envelope:

```json
{
  "protocol": "textus/4",
  "ok": false,
  "code": "write_forbidden",
  "message": "writing 'knowledge.identity.self' (lane 'knowledge') needs capability 'author'",
  "hint": "held by: human; pass --as=<role>",
  "details": { "key": "knowledge.identity.self", "lane": "knowledge", "verb": "author", "holders": ["human"] }
}
```

**Error codes:**

| Code | Meaning | Default exit |
|---|---|---|
| `unknown_key` | Key does not resolve | 1 |
| `bad_frontmatter` | YAML parse failed or `name:` mismatch | 1 |
| `schema_violation` | Required field missing or wrong type | 1 |
| `write_forbidden` | Resolved role lacks the capability the lane-kind requires | 1 |
| `etag_mismatch` | Concurrent write detected | 1 |
| `io_error` | Filesystem failure | 64 |
| `usage` | CLI argument error | 2 |
