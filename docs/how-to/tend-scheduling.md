# Scheduling `tend` — unattended upkeep

`tend` runs the recurring upkeep passes in one shot:

1. `fetch_all` — refresh stale `quarantine` intake entries past their TTL.
2. `retain`    — apply each entry's retention policy (expire / archive).
3. `doctor`    — report residual health (missing schemas, sentinel drift, …).

textus schedules **nothing** itself — it has no in-process runner by design
(ADR 0078). The host owns the timer; `tend` is the verb it calls.

## Preview first

```bash
textus tend --dry-run --as=automation
```

Reports `would_fetch` / `would_expire` / `would_archive` and the health report
without writing anything.

## Apply

```bash
textus tend --as=automation
```

Scope a single zone on its own cadence with `--zone` or `--prefix`:

```bash
textus tend --zone feeds --as=automation
```

## Authority

`tend` runs as the **caller's** role — it does *not* self-elevate (the
deliberate contrast with `build`, ADR 0076). Each sub-op stays gated: rows whose
zone the scheduled role cannot write surface in the result's `failed` lists
rather than aborting the pass. Schedule it as `automation` and it can do exactly
what `automation` could already do by hand (fetch + retain in `quarantine`).

## Wiring examples

**cron** (hourly, log to the store's run dir):

```cron
0 * * * * cd /path/to/repo && textus tend --as=automation >> .textus/.run/tend.log 2>&1
```

**Claude Code routine** (`/schedule`): a daily agent run that calls the `tend`
MCP tool over the same connection it uses for the edit→accept→build loop, then
reads back the `health` block.
