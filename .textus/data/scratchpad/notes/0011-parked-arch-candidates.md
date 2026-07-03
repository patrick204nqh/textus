---
name: parked-arch-candidates
uid: b122a9288522f848
---
# Parked — architecture review 2026-06-30

Candidates 5, 6, 7 — set aside while 1-4 are explored.

## 5 — Read Path Caching
`lib/textus/store/entry/reader.rb` — every `get` = FS read + YAML parse. No cache.
Optional SQLite read-through cache keyed by (key, etag). Trivial invalidation (etag changes on write).
⚠ Contradicts Rule 08 (no hidden side-effects on read) but cache is read-through, not mutation.

## 6 — CLI UX: Human-readable output
`lib/textus/surface/cli.rb` — JSON-only. No `--format=text`. No progress for `drain`. No tab completion.
Add `--format=text|json`. Text mode: `get` prints body, `list` prints table.

## 7 — Audit Log Index
`lib/textus/port/audit_log.rb` — NDJSON scan-only filtering. No index.
Mirror to SQLite with indexed columns. Speculative — revisit if query perf becomes pain.
