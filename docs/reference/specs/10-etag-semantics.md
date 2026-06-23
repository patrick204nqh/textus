## 10. ETag semantics

The etag is `sha256:<lowercase-hex-digest-of-raw-file-bytes>`. Computed after any normalization (trailing newline on write, UTF-8 encoding). Both reads and successful writes return the current etag; passing it back in `if_etag` enforces optimistic concurrency.
## 10.1 Errors carry hints

Every `Textus::Error` exposes `code`, `message`, and an optional `hint:`. The hint is a single short string suggesting the next action — the file to edit, the role to pass, the command to run. Errors in the wire envelope include the hint as a top-level `hint:` field when present. The CLI prints failures to stderr as `code: message` followed by `  → hint` (when a hint exists), in addition to the JSON envelope on stdout. Hints are advisory: implementations MAY omit or rephrase them without breaking conformance.

## 10.2 `textus doctor`

`textus doctor` returns a health-check envelope: `{ "protocol": "textus/4", "ok": bool, "issues": [...], "summary": {error, warning, info} }`. Each issue carries `code`, `level` (`error|warning|info`), `subject`, `message`, and optionally `fix`. `ok` is true iff no error-level issues are present; warnings and info do not flip the bit. Builtin checks: `protocol_version`, `manifest_files`, `schemas`, `schema_parse_error`, `templates`, `intake_registration`, `illegal_keys`, `sentinels`, `audit_log`, `unowned_schema_fields`, `schema_violations`, `rule_ambiguity`, `handler_permit`, `fetch_locks`, `proposal_targets`, `publish.tree_index_overlap`, `generator_drift`. Additional registered `:validate` hooks (§5.10) run after the builtin set. Exit code is 0 on `ok`, 1 otherwise.

