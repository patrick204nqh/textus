---
name: ledger
description: Internal double-entry accounting service. Postgres-backed Rails API serving the billing team.
repo: https://github.com/example/ledger
---

ledger is the system of record for every customer charge, refund, and
internal transfer. Owned by the **payments** team; on-call rotates
weekly. The hot path is `POST /v1/transactions`; everything downstream
(invoicing, dunning, finance exports) reads from `transactions` and
`balances`.

Stack: Ruby 3.3 / Rails 7.2 / Postgres 15 / Sidekiq. Deployed to AWS
ECS via Buildkite. Logs in Datadog, traces in Honeycomb.

This file is the slow-changing root identity entry. Only humans can
write to the `identity` zone; agents and automation cannot. Edit this
file then run `textus build` to rebuild the projected `CLAUDE.md` and
`AGENTS.md` at the repo root.
