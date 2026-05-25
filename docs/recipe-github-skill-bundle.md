# Recipe: pull a GitHub folder as a skill bundle

This recipe shows how to install a folder from a public GitHub repo into your textus store as a single intake entry, then fan it out into per-file derived entries using existing primitives — no patches to textus core required.

It uses two example hook files from `examples/claude-plugin/recipes/`:

- `github_folder.rb` — a `Textus.intake` handler that fetches a folder via the GitHub REST API and returns one entry whose `content.files` is a `{ relative_path => bytes }` hash.
- `skill_fanout.rb` — a `Textus.refreshed` listener that fans the bundle out into `vendor.skills.<slug>.*` entries, with reconciliation (orphaned children are deleted).

## Setup

Copy both files into your store's `hooks/` directory:

```bash
cp examples/claude-plugin/recipes/github_folder.rb .textus/hooks/
cp examples/claude-plugin/recipes/skill_fanout.rb .textus/hooks/
```

Declare an intake entry in your manifest (`.textus/manifest.yaml`):

```yaml
- key: intake.skills.agent-eval
  path: intake/skills/agent-eval.json
  zone: intake
  format: json
  intake:
    handler: github_folder
    config:
      repo: affaan-m/ECC
      ref: main
      path: skills/agent-eval
```

Trigger the refresh:

```bash
textus refresh intake.skills.agent-eval
```

The intake entry lands at `intake.skills.agent-eval`. The `:refreshed` listener then writes `vendor.skills.agent-eval.SKILL.md`, `vendor.skills.agent-eval.scripts.run.rb`, etc.

## Required manifest plumbing

- The destination zone (`vendor` in the example) must exist and be writable by the role triggering the refresh. If you don't already have a `vendor` zone, add one to the top of your manifest:

  ```yaml
  zones:
    - { name: vendor, writable_by: [script, system] }
  ```

- Derived keys are written without manifest entries. `textus doctor` will not complain about them today because doctor checks manifest references, not raw store entries. (When manifest-coverage-of-all-keys becomes a doctor check, this recipe will need to declare derived keys via a pattern entry — see the ADR.)

## Caveats and known limitations

1. **30-second fetch timeout.** `lib/textus/application/refresh/worker.rb:7` caps intake at 30s. Large folders with many files may exceed this. Workarounds: narrow the `path` config, or fetch via a CDN-backed mirror.

2. **No re-entry guard.** The listener calls `store.put`/`store.delete` with `suppress_events: true` to prevent its own refresh from triggering itself. If you fork the recipe and forget this, you get an event loop.

3. **Reconciliation is per-source.** Only derived keys under `vendor.skills.<slug>.` for the refreshed source are reconciled. Deleting the intake source entry does **not** garbage-collect its children — you would need a separate `:deleted` listener for that.

4. **Public repos only as written.** The hook does not send an `Authorization` header. For private repos or to dodge unauthenticated rate limits, extend `TextusRecipes::GithubFolder::DEFAULT_FETCHER` to inject a `Bearer` token from `ENV`.

5. **Hook is not bundled with the skill.** Pulling a skill folder fetches its *content*, not the hook that processes it. If you want a true self-contained skill bundle (entries + their own intake handler), that's a different architecture — see `docs/architecture/decisions/0001-skill-bundle-deferral.md`.

## When to graduate to first-class support

If you find yourself copy-pasting the fanout listener for a third or fourth use case, that's the signal to revisit the deferral and promote intake-returns-N-entries into the worker. The ADR (`docs/architecture/decisions/0001-skill-bundle-deferral.md`) captures the criteria.
