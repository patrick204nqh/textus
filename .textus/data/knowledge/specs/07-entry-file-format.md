## 7. Entry file format

Every entry is a UTF-8 Markdown file with a YAML frontmatter block:

```markdown
---
name: jane
relationship: peer
org: acme
---
Short body in Markdown.
```

The frontmatter `name:` field, when present, must match the file's basename (without `.md`). Implementations may relax this for backward compat but the reference impl enforces it.

**`uid:` (Textus UID).** Entries MAY carry a stable identity field that survives renames and moves. Optional. When present:

- Lives at top-level `uid:` in markdown frontmatter, or `_meta.uid` in `json`/`yaml` entries.
- Format: lowercase hex string, 12 or more characters. The reference impl mints 16 hex chars (`SecureRandom.hex(8)`). This is a **Textus UID**, not a UUID — short on purpose.
- Auto-assigned on the first successful `Store#put` if the payload has no uid. Preserved on subsequent puts.
- Existing files without a uid continue to work. The envelope shows `"uid": null` until a put mints one.
- `text` entries have no metadata channel and therefore no uid; their envelope always shows `"uid": null`.

**`sources:` (Source references).** Entries MAY carry a `sources` array in
their frontmatter to declare external provenance. Each element is an object
with a required `raw` field (a raw-lane key, starting with `raw.`) and
optional `url` and `label` fields. The array is preserved on write —
existing sources carry forward if no new `sources` are provided. The
envelope returns `sources` as a top-level array when non-empty; omitted
when absent.

Entries in a `produced` lane SHOULD additionally carry the `generated:` block defined in §5.2. Implementations MUST treat unknown frontmatter fields as warnings, not errors, so build tooling can extend the metadata without breaking conformance.
