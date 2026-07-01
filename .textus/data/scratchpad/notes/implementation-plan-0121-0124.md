---
uid: 3e9dc36460ab164c
---
# Implementation Plan: ADRs 0121–0124

## Ordering

The 4 ADRs have one dependency edge: **C3 (MCP session resilience) is prerequisite to C1 (graph verb surfacing)** — the graph verb needs a stable connection to surface on MCP. Otherwise they are independent.

**Recommended order:** C3 → C1 → C2 → C4
- C3: MCP session resilience (smallest change, enables stable foundation)
- C1: Knowledge links (largest change, builds on stable MCP)
- C2: Proposal diff (medium change, independent)
- C4: Workflow parallel (medium change, independent)

---

## C3 — MCP Session Resilience (ADR 0123)

**Files touched:** `lib/textus/surface/mcp/server.rb`, `lib/textus/store/cursor.rb`

### Steps

1. **Add checkpoint interval config** to manifest's `worker_config` (default 30s).
2. **Background thread in MCP::Server#initialize** that loops: sleep(interval) → `Cursor.write(@store.cursor)`.
3. **Modify Store#build_session!** to check cursor file before defaulting to `latest_seq`.
4. **Add `contract_drifted` field to pulse response** — check etag before returning, attach boolean + current etag.
5. **Remove hard ContractDrift error for writes** — replace with soft warning in response.
6. **Update default audit `keep:` to never-expire** — change default from 5 to a high value.
7. **Add doctor check** for nearing retention limit with active cursors.

**Tests:** Existing cursor_spec, MCP server_spec, pulse_entries_spec.

---

## C1 — Knowledge Links (ADR 0121)

**Files touched:** `lib/textus/links/link_edge_store.rb`, `lib/textus/store.rb`, `lib/textus/port/store.rb` (SQLite), `lib/textus/verb_registry.rb`, `lib/textus/handlers/read/`, `lib/textus/surface/`

### Steps

1. **Add `link_edges(from_key TEXT, to_key TEXT)` table** to `Port::Store.setup!` (existing store.db).
2. **Replace LinkEdgeStore** in-memory Hash with SQLite-backed adapter implementing `record + dependents_of`.
3. **Wire into Store#build_ctx** — replace `Links::LinkEdgeStore.new` with SQLite-backed version.
4. **Add background sweep job** for catching missed edges (enumerate published entries, scan for textus:KEY URIs, insert missing edges).
5. **Register `graph` verb** in VerbRegistry — `neighbors(key)` and `reachable(key, depth=N)`.
6. **Write Graph handler** — SQLite queries for neighbors (direct links) and reachable (recursive CTE or BFS in Ruby).
7. **Backfill `rdeps`** to query both manifest-produced deps AND `link_edges` table — unified response.
8. **Register new CLI/MCP surfaces** — auto-generated from verb spec.

**Tests:** New link_edge_store_spec (SQLite), graph_handler_spec, rdeps_spec.

---

## C2 — Proposal Diff (ADR 0122)

**Files touched:** `lib/textus/verb_registry.rb`, `lib/textus/handlers/read/diff_proposal.rb`, `lib/textus/handlers/write/accept_proposal.rb`, `lib/textus/handlers/write/reject_proposal.rb`

### Steps

1. **Write diff engine** — pure Ruby Myers diff for body lines (markdown/text), structural diff for meta/schema.
2. **Register `diff` verb** in VerbRegistry — takes `pending_key`, returns diff envelope.
3. **Write DiffProposal handler** — reads proposal, reads target, computes diff, returns result.
4. **Add `--dry-run` to `accept` contract** — optional boolean arg.
5. **Modify AcceptProposal handler** — when `dry_run: true`, compute diff and return without promoting.
6. **Add `--reason` to `reject` contract** — optional string arg.
7. **Modify RejectProposal handler** — emit `:proposal_rejected` with reason, write audit log with reason, optionally write scratchpad note.
8. **Surfaced to CLI and MCP** — auto-generated.

**Tests:** Diff engine spec (pure function), diff_handler_spec, accept_dry_run_spec, reject_reason_spec.

---

## C4 — Workflow Parallel Steps (ADR 0124)

**Files touched:** `lib/textus/workflow/dsl.rb`, `lib/textus/workflow/runner.rb`, `textus.gemspec`

### Steps

1. **Add concurrent-ruby dependency** to gemspec (`s.add_dependency "concurrent-ruby", "~> 1.3"`).
2. **Add `Parallel` Data class** to Workflow::DSL.
3. **Add `parallel` method** to Definition — captures block, collects steps into Parallel.
4. **Modify Workflow::Runner** to pattern-match on `Parallel` vs `Step`:
   - `Parallel` → execute steps concurrently via `Concurrent::Promises.future` + `zip(*futures).value!`
   - Collect errors, raise `ParallelStepFailed` if any fail.
5. **Add worker_config.pool_size** to manifest for thread pool size.
6. **Add timeout support** for parallel steps (inherit per-step timeout from existing DSL).

**Tests:** Workflow DSL spec (parallel block parsing), Runner spec (concurrent execution, error collection), conformance spec for existing workflows (unchanged).

---

## Summary

| ADR | Files changed | Est. LOC | Dependencies |
|---|---|---|---|
| C3 | 3 source + 1 config | ~100 | None |
| C1 | 6 source + 1 migration | ~250 | C3 (for MCP surface) |
| C2 | 4 source | ~200 | None |
| C4 | 3 source + gemspec | ~140 | concurrent-ruby gem |

Total: ~690 LOC across 4 ADRs. C1 is the largest change; C3 is the smallest.
