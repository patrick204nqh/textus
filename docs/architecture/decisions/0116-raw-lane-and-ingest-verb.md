# ADR 0116: Raw Lane and Ingest Verb — Write-Once External Source Material

**Status:** Accepted
**Date:** 2026-06-16

## Context

textus has four zone-kinds (canon, workspace, queue, machine), each with a
capability gating writes. External source material — URLs to capture, files to
import, screenshots to archive — had no dedicated home. The `quarantine` concept
from ADR 0088/0089 was removed in the foundation refactor (ADR 0114), leaving a
gap: agents and humans could store ingested material only by hand-crafting
entries in existing lanes, missing write-once semantics and a dedicated verb.

The requirements:

1. **Write-once ingestion** — the same slug on the same day must be
   non-replaceable (idempotent collision, not silent overwrite).
2. **Three source kinds** — URL (structured metadata), file (body text from a
   local path), asset (binary file copied to a managed directory).
3. **Asset management** — binary files (screenshots, PDFs) should be copied into
   a project-scoped `assets/raw/` tree, not stored inline.
4. **Notebook stubs** — each ingest creates a lightweight scratchpad.notes stub
   linking back to the raw key, so the agent or human can annotate the ingested
   material without touching the write-once record.
5. **Raw lane** — entries live under a `raw.*` key prefix on a `kind: raw`
   lane, formatted as YAML for structured content.
6. **No `Jobs::Refresh`** — the old `refresh` job is vestigial and is removed
   (no `on_expire: refresh` on raw entries).

## Decision

### 1. Add `raw => ingest` to the lane/capability bijection

`Schema::Vocabulary::LANES` gains `"raw" => "ingest"`, so a role holding the
`ingest` capability may write the raw lane. All three default roles (human,
agent, automation) receive `ingest` in their `can:` sets.

### 2. FLOOR predicates for the raw lane

Three new base-level guards in `gate/auth.rb`:

- **`raw_lane_ingest_only`** — the raw lane's authoritative verb is `ingest`,
  rejecting `put`/`propose`/`accept`/etc. Only `ingest` may originate bytes
  into this lane.
- **`raw_write_once`** — a raw entry key that already exists is refused on
  write; there is no update path. The operator deletes and re-ingests.
- **`lane_deletable_by`** — raw-kind entries may only be deleted by a role
  holding the `author` capability (not by the lane's own verb), so an ingest
  holder cannot accidentally destroy ingested records.

### 3. `Action::Ingest`

A new use-case `Textus::Action::Ingest` accepts a `Command::Ingest` with
fields: `kind` (url|file|asset), `slug`, `url` (for URL kind), `path` (for
file/asset), `zone` (for asset subdirectory), `label`, and `role`.

The `call` method:
- Validates kind and required fields per kind (URL requires `url`).
- Derives the daily key `raw.YYYY.MM.DD.<kind>-<slug>`.
- Detects write-once collision and raises.
- Writes a YAML-format raw entry with structured content (ingested_at,
  source, and kind-specific fields).
- For asset kind, copies the source file into `assets/raw/YYYY/MM/DD/<zone>/`.
- Creates a scratchpad.notes stub with a backlink in the body.
- Returns the raw entry's uid.

### 4. Guarded surfaces

The `ingest` verb is registered in `Action::VERBS`, `Gate::ROUTES`, and
`CURATED_CLI_VERBS`. It appears in the CLI verb table and MCP tool catalog. The
MCP tool is auto-generated (`GenIngest`) from the contract.

### 5. Asset directory sentinel

`textus init` creates `assets/raw/` with a `.gitkeep` so the directory is
tracked by git before any ingest occurs.

### 6. Doctor checks

Two new doctor checks:
- **`raw_asset_paths`** — scans all raw entries for `asset` references and
  reports missing files on disk.
- **`scratchpad_sources`** — scans scratchpad entries for `Ingested from raw.`
  backlinks and reports dangling references to deleted raw entries.

## Consequences

- The ingestion path is a single-purpose write-once lane, clearly separated
  from authored content (canon), working notes (workspace), and computed
  outputs (machine).
- Removes the vestigial `Jobs::Refresh` job and all its wiring.
- Breaking: manifests using `kind: nested` entries with `format: yaml` for raw
  data must declare the `raw` lane and entry if they want to use `ingest`.

## Alternatives considered

- **Reuse `put` with flags.** Rejected: write-once is a fundamentally different
  contract from `put`'s create-or-update. A separate verb makes the semantic
  difference visible in the verb catalog, MCP tool list, and audit log.
- **Inline binary assets in YAML.** Rejected: large binaries should not live in
  tracked data files. Copying to `assets/raw/` keeps the data directory lean
  and lets git manage the binaries independently.
- **No scratchpad stub.** Rejected: without a stub the agent has no way to
  discover or annotate ingested material through the scratchpad interface. The
  backlink pattern (`Ingested from raw.…`) is text-searchable and machine-
  parseable.
