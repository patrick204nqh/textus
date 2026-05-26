---
name: deploy
description: Ship a ledger release to production.
oncall_only: false
---

1. Open a release PR against `main`; CI must be green.
2. Squash-merge; Buildkite kicks off the `ledger-deploy` pipeline.
3. Watch the migration step — it runs `rails db:migrate` against a
   replica before promoting. Abort if it exceeds 60s.
4. Once the green deploy lands, post `#payments` with the release URL.
5. Monitor the `ledger.transactions.write` SLO for 15 minutes.
