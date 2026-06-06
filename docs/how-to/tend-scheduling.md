# Scheduling `reconcile` — unattended upkeep

`reconcile` is the full two-phase maintenance pass (ADR 0087):

1. **Phase 1 — materialize** — re-render every derived entry in scope from its
   sources (idempotent; unchanged sources write nothing).
2. **Phase 2 — stale sweep** — apply each entry's destructive `upkeep: { "on": stale }`
   action (`action: drop` deletes; `action: archive` moves the leaf to
   `.textus/archive/` then deletes the original) to entries past their TTL.

(Intake refresh **is** part of the `reconcile` sweep — a stale `action: refresh`
intake entry is re-pulled there, or by a `hook run` event. A `get` never
refreshes; it is a pure read (ADR 0089).)

textus schedules **nothing** itself — it has no in-process runner by design
(ADR 0078). The host owns the timer; `reconcile` is the verb it calls.

In day-to-day use, derived entries stay fresh **reactively** — a canon write
re-materializes dependent derived entries automatically per the
`upkeep: { "on": source_change }` rule. `reconcile` is the on-demand catch-all for full recomputation or
lifecycle enforcement.

## Preview first

```bash
textus reconcile --dry-run --as=automation
```

Reports `would_materialize`, `would_drop` / `would_archive`, and the health
report without writing anything.

## Apply

```bash
textus reconcile --as=automation
```

Scope a single zone on its own cadence with `--zone` or `--prefix`:

```bash
textus reconcile --zone feeds --as=automation
```

## Authority

`reconcile` self-elevates for Phase 1 (materializing derived entries is a pure,
idempotent function of already-accepted canon — ADR 0087). Phase 2 runs as the
**caller's** role; rows whose zone the scheduled role cannot write surface in the
result's `failed` lists rather than aborting the pass. Schedule it as
`automation` and it can do exactly what `automation` could already do by hand.

## Wiring examples

**cron** (hourly, log to the store's run dir):

```cron
0 * * * * cd /path/to/repo && textus reconcile --as=automation >> .textus/.run/reconcile.log 2>&1
```

**Claude Code routine** (`/schedule`): a daily agent run that calls the
`reconcile` MCP tool over the same connection it uses for the edit→accept loop,
then reads back the `health` block.
