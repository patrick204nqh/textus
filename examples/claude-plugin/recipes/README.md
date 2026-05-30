# Recipes

Opt-in hook patterns that you copy into your store's `.textus/hooks/`
directory to enable. They live under `recipes/` rather than `.textus/hooks/`
in this example so they don't auto-load — pick the ones you want and
copy them in.

## `skill_fanout.rb`

Listens for `:entry_fetched` events on `intake.skills.*` and fans the
bundle out into per-file `vendor.skills.<slug>.<rel>` derived entries.
Reconciles: orphaned children whose source path disappeared upstream are
deleted. Inner writes use `suppress_events: true` to prevent recursion.

See [docs/recipes/github-skill-bundle.md](../../../docs/recipes/github-skill-bundle.md)
for the end-to-end recipe (manifest snippet, copy command, caveats).
