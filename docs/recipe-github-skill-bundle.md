# Recipe: fan an intake bundle out into per-file derived entries

This recipe shows how to take a single intake entry whose payload is a
bundle of files (`content.files == { relative_path => bytes }`) and fan
it out into per-file derived entries using existing textus primitives —
no patches to textus core required.

It uses one example hook file from `examples/claude-plugin/recipes/`:

- `skill_fanout.rb` — a `:entry_refreshed` listener that fans the bundle
  out into `vendor.skills.<slug>.*` entries, with reconciliation
  (orphaned children are deleted).

The intake side (how the bundle entry gets its `content.files` payload)
is left to your application. A common shape is a `Textus.intake` handler
that fetches a folder from a public GitHub repo via the REST API and
returns `{ "content" => { "files" => { ... } } }` — the listener doesn't
care how the entry was produced, only that the envelope matches.

## Setup

Copy the fan-out hook into your store's `hooks/` directory:

```bash
cp examples/claude-plugin/recipes/skill_fanout.rb .textus/hooks/
```

Declare an intake entry in your manifest (`.textus/manifest.yaml`),
pointing at whatever intake handler you've supplied:

```yaml
- key: intake.skills.agent-eval
  path: intake/skills/agent-eval.json
  zone: intake
  format: json
  intake:
    handler: your_bundle_handler
    config:
      repo: affaan-m/ECC
      ref: main
      path: skills/agent-eval
```

Trigger the refresh:

```bash
textus refresh intake.skills.agent-eval
```

The intake entry lands at `intake.skills.agent-eval`. The
`:entry_refreshed` listener then writes
`vendor.skills.agent-eval.skill.md`,
`vendor.skills.agent-eval.scripts.run.rb`, etc.

## Required manifest plumbing

- The destination zone (`vendor` in the example) must exist and be
  writable by the role triggering the refresh. If you don't already have
  a `vendor` zone, add one to the top of your manifest:

  ```yaml
  zones:
    - { name: vendor, write_policy: [runner, system] }
  ```

- Declare a nested entry for the derived tree so reads can resolve the
  fan-out keys:

  ```yaml
  - { key: vendor.skills, path: vendor/skills, zone: vendor, schema: null, owner: runner, nested: true }
  ```

- Bundle file names must be lowercase and match textus's key grammar
  (`[a-z0-9][a-z0-9-]*` per segment). `SKILL.md` will be rejected — use
  `skill.md` or normalize upstream.

## Caveats and known limitations

1. **30-second intake timeout.** `lib/textus/application/refresh/worker.rb:7`
   caps intake at 30s. Large folders with many files may exceed this.
   Workarounds: narrow the bundle source, or stream via a CDN-backed
   mirror.

2. **No re-entry guard beyond `suppress_events: true`.** The listener
   uses the Operations facade for inner writes
   (`Operations.writes.put.call(...)`, `Operations.writes.delete.call(...)`)
   with `suppress_events: true` to prevent its own refresh from
   triggering itself. If you fork the recipe and forget this, you get
   an event loop.

3. **Reconciliation is per-source.** Only derived keys under
   `vendor.skills.<slug>.` for the refreshed source are reconciled.
   Deleting the intake source entry does **not** garbage-collect its
   children — you would need a separate `:entry_deleted` listener for
   that.

4. **Hook is not bundled with the skill.** Pulling a skill folder
   fetches its *content*, not the hook that processes it. If you want a
   true self-contained skill bundle (entries + their own intake
   handler), that's a different architecture — see
   `docs/architecture/decisions/0001-skill-bundle-deferral.md`.

## When to graduate to first-class support

If you find yourself copy-pasting the fan-out listener for a third or
fourth use case, that's the signal to revisit the deferral and promote
intake-returns-N-entries into the worker. The ADR
(`docs/architecture/decisions/0001-skill-bundle-deferral.md`) captures
the criteria.
