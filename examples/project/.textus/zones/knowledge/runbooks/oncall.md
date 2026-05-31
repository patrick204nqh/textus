---
name: oncall
description: First response when ledger pages out of hours.
oncall_only: true
---

1. Acknowledge the page in PagerDuty within 5 minutes.
2. Open the `ledger / overview` Datadog dashboard. Check
   `transactions.write.error_rate` and Postgres CPU first.
3. If `error_rate > 1%` for 5+ minutes, declare SEV-2 in `#incident`
   and page the payments secondary.
4. If Postgres is the bottleneck, fail over to the standby via
   `bk trigger ledger-db-failover` (requires `oncall` Buildkite role).
5. Once stable, write a brief incident note under
   `review/decisions/` so the team can ADR the follow-up.
