# Recipes

Optional hook files demonstrating patterns built on textus primitives. **These files do not auto-load** — they live outside `.textus/hooks/` on purpose, so the example plugin's `textus doctor` stays clean.

To use a recipe, copy the file into your own `.textus/hooks/` and add the corresponding manifest entries documented in `docs/recipe-*.md`.

## Available recipes

| File | Pattern | Docs |
|------|---------|------|
| `github_folder.rb` | Fetch a folder from a public GitHub repo as a single intake entry | `docs/recipe-github-skill-bundle.md` |
| `skill_fanout.rb`  | Fan out one intake entry into N derived entries, with reconciliation | `docs/recipe-github-skill-bundle.md` |
