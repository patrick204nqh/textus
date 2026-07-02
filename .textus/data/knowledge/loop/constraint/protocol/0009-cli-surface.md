## 9. CLI surface

The reference binary is `textus`. Conforming implementations MAY use any binary name; the protocol is in the JSON.

All verbs accept `--output=json` and emit a canonical envelope (success or error). Write verbs require `--as=<role>`; the role must satisfy the target lane's write gate (§5). The per-entry `format:` field in the manifest is unchanged — `--output` controls only the CLI envelope rendering.

| Verb | Reads / writes | Role required |
|---|---|---|
| `list [--prefix=K] [--lane=Z]` | read | any |
| `where K` | read | any |
| `get K` | read (a pure on-disk read annotated with a freshness verdict; never refreshes — ADR 0089) | any |
| `schema show K` | read | any |
| `audit [--key=K] [--lane=Z] [--role=R] [--verb=V] [--since=X] [--correlation-id=ID] [--limit=N]` | read | any |
| `blame KEY` | read | any |
| `rule list` / `rule explain KEY` | read | any |
| `deps K` / `rdeps K` | read | any |
| `published` | read | any |
| `hook list` | read | any |
| `hook run NAME` | write | any |
| `doctor [--check=NAME[,NAME]] [--output=json]` | read | any |
| `boot [--output=json]` | read | any |
| `pulse [--since=N]` | read | any |
| `put K --stdin --as=R` | write (stores the stdin JSON; runs no handler — ADR 0089) | per lane |
| `propose K --stdin --as=R` | write | `propose`-holder (auto-prefixes propose_zone) |
| `key delete K --if-etag=E --as=R` | write | per lane |
| `drain [--prefix=K] [--lane=Z]` | write | `converge`-holder (typically `automation`) |
| `serve [--poll=SECS]` | write (long-lived daemon) | `converge`-holder (typically `automation`) |
| `jobs [--state=ready\|leased\|done\|failed] [--action=retry\|purge] [--job-id=ID]` | read | any |
| `accept K --as=human` | write | `author`-holder (typically `human`) |
| `reject K --as=human` | write | `author`-holder (typically `human`) |
| `init` | write | `human` |
| `schema {show,init,diff,migrate}` | read/write | `human` for writes |
| `key mv OLD NEW [--as=R] [--dry-run]` | write | per lane (same-lane only) |
| `key uid K` | read | any |

**`textus boot` envelope extras.** In addition to lanes, entries, hooks, write flows, and the `cli_verbs` catalog, the boot envelope includes an `agent_quickstart` block synthesized from the manifest's role capabilities:

```json
{
  "agent_quickstart": {
    "read_verbs":     ["get", "list", "pulse", "schema_show", "boot", "rule_explain", "where", "deps", "rdeps"],
    "write_verbs":    ["accept", "key_delete", "key_mv", "propose", "put", "reject"],
    "writable_lanes": ["proposals"],
    "propose_lane":   "proposals",
    "latest_seq":     1842
  }
}
```

`read_verbs` is derived from the MCP verb catalog — the verbs the agent can actually call over its transport — so it lists the read/discovery verbs (`schema_show` for an entry's field shape, `rule_explain` for its retention/guard policy, and the graph reads `where`/`deps`/`rdeps`, ADR 0060) and never the CLI-only `audit`/`doctor`, nor `freshness` (the Ruby-only internal lifecycle scan, ADR 0085) (ADR 0056). An agent learns an entry's `_meta` shape by calling the `schema_show` verb before a `put`/`propose`, not by shelling out to a CLI. The graph reads `deps`/`rdeps` return a structured `{key, deps}`/`{key, rdeps}` envelope on every surface (CLI, Ruby, MCP) — a hash, not a bare array, consistent with the other structured read responses such as `where` (ADR 0060 amendment).

The agent's MCP write surface includes the single-key `key_delete` and `key_mv` tools alongside their bulk `key_delete_prefix`/`key_mv_prefix` cousins (ADR 0060 amendment; the single-key tools were renamed from `delete`/`mv` to share the `key_` family stem in ADR 0082, which also removed the `migrate` YAML-plan orchestrator — its `data_mv`/`key_mv_prefix`/`key_delete_prefix` ops remain individually callable). The structural mutation verbs (`key_mv`, `key_mv_prefix`, `key_delete_prefix`, `data_mv`) accept `dry_run: true` as an opt-in preview that returns a Plan without mutating (ADR 0071). `drain` does not support `dry_run` (it is async-only, ADR 0110). Single-key `key_delete` additionally accepts an optional `if_etag` optimistic-concurrency check. The blast-radius reads (`where`/`deps`/`rdeps`) remain on MCP so an agent can look before it leaps. The promotion verbs `accept` and `reject` are also on MCP (ADR 0072): they are gated by the `author_held` capability floor, not by transport absence — a default-`agent` connection is refused, while a connection launched as a role holding `author` (`--as`/`TEXTUS_ROLE`/`.textus/role`, resolved once at launch per ADR 0040) can promote, closing the propose→accept loop over one transport. `drain` is also on MCP (ADR 0076, ADR 0087, ADR 0110): it is caller-agnostic and its produce jobs self-elevate — materialization always runs as the manifest's `converge`-capable actor regardless of the calling role, granting no authority over content (materialization is a pure, idempotent function of already-accepted canon, ADR 0070); the destructive retention sweep runs as the caller. Each produce job self-acquires the single-writer build lock, so a concurrent CLI, reactive, or background pass cannot collide with an MCP-triggered one — a held lock is a graceful soft-miss (ADR 0110).

`latest_seq` is the current high-water mark of the audit log; agents should use it as the starting cursor for `pulse`.

**`textus pulse` output shape:**

```json
{
  "cursor":         1845,
  "changed":        [ { "seq": 1843, "key": "knowledge.notes.x", "verb": "put", "role": "human", "ts": "..." } ],
  "pending_review": [ "proposals.proposal.123" ],
  "contract_etag":  "sha256:1f3a…",
  "index_etag":     "sha256:8f3c…"
}
```

`cursor` is the new high-water mark; pass it as `--since` on the next call. `changed` is sourced from `audit --seq-since`. `pending_review` lists all keys in the `proposals` queue lane. `contract_etag` is the `sha256:`-prefixed composite content hash of the contract — the manifest plus hooks and schemas (ADR 0074, via ADR 0025) — for cheap change-detection. `index_etag` is the etag of the `artifacts.index` catalog file, or `null` when it does not exist — agents use this to detect when the catalog has been rebuilt. When `--since` is below the oldest available seq (due to audit log rotation), pulse returns `CursorExpired`.

**`put` input** (read from stdin when `--stdin` is given):

```json
{ "_meta": { "name": "jane", "relationship": "peer", "org": "acme" },
  "body": "Short body.\n",
  "if_etag": "sha256:8f3c…" }
```

`if_etag` is optional on both `put` and `key_delete`. When provided, the write fails with `etag_mismatch` if the on-disk file's etag differs. When omitted, the write is unconditional (last-writer-wins).

The lifecycle scan runs per-entry at `get` time — each `get` response carries `stale`/`stale_reason` when the entry has a TTL rule. ADR 0085 removed the standalone `freshness` verb; human drill-down into a single entry's verdict is `textus get KEY` (carries `stale`/`stale_reason`) plus `textus rule_explain KEY` (the `source.ttl` and retention policy). `pulse` does not include a `stale` list. `textus drain` enqueues the convergence jobs — produce every in-scope derived entry, re-pull every stale intake entry, and a retention sweep — then drains the queue to empty (§5.11). Convergence is async-only (ADR 0110): there is no `--dry-run`.

`textus accept K --as=human` promotes a pending entry into its target lane: it copies the patch body into the target key, deletes the pending entry, and writes one audit line per side (§audit). Only a role holding the `author` capability (the trust anchor — `human` by default) may invoke `accept`.

`textus drain [--prefix=K] [--lane=Z]` is the manual converge-and-exit pass (ADR 0093, ADR 0110). It seeds a closed allow-list of jobs into the durable file-backed queue (`Ports::Queue` under `.textus/.state/queue/`) and runs a worker until the queue is empty: a **`materialize`** job per in-scope derived / publish entry (always rebuild — pure/idempotent, unchanged sources write nothing; nested `{ tree: }` targets included), a **`re-pull`** job per intake entry past its `source.ttl`, and a single **`sweep`** job for the destructive `retention:` GC (§5.11). Authority is frozen at enqueue: `materialize`/`re-pull` self-elevate inside `Produce::Engine` to the manifest's `converge`-capable actor (`automation` by default) — materialization is a pure function of already-accepted canon and grants no authority over content — while `sweep` runs as the **caller** (gated as the caller's own `key_delete` authority), never self-elevating. Drain is single-pass and **serial**: each produce job self-acquires the non-reentrant build lock, so a held lock is a graceful soft-miss. `drain` returns `{ ok, completed, failed, health }` and exits non-zero if any job dead-lettered; per-key produce failures surface as `:produce_failed` events. There is no `--dry-run` (materialization is async-only). `textus serve` is the same worker as a long-lived daemon, whose `Scheduler` seeds TTL re-pull + sweep each tick; `textus jobs` inspects/retries/purges the queue. In day-to-day use derived entries stay fresh **reactively** — a canon write enqueues a `materialize` job for each dependent derived entry (the reactive scope is "converge narrowed to rdeps ∩ derived"), processed by a running `serve` or the next `drain` — so `drain` is the on-demand / CI catch-all, not a step in the normal write loop.

`textus init` scaffolds a fresh `.textus/` tree (manifest, lanes, schemas, audit log) under the current directory with a default manifest. Customize by editing `.textus/manifest.yaml` after init.

`textus schema show K` prints the schema for entry `K`. `textus schema init NAME` writes a stub schema. `textus schema diff NAME` compares the on-disk schema against entries that claim it and prints the deltas. `textus schema migrate NAME --rename=OLD:NEW` rewrites the `_meta` key `OLD` to `NEW` across every entry that uses the named schema, in a single transactional sweep that logs each touched file.
