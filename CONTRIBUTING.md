# Contributing

textus is a young project. Bugs, missing fixtures, and rough edges are expected. Open an issue with a failing fixture name, or send a PR.

## Before you open a PR

1. Read [`SPEC.md`](SPEC.md) — it is the source of truth for the wire format. Implementation can change; the protocol stays put unless we bump the version.
2. Run the suite:
   ```sh
   bundle install
   bundle exec rspec        # full suite, including conformance fixtures
   bundle exec rubocop      # zero offenses expected
   ```
3. If you're adding a feature, add a spec. If you're fixing a bug, add the regression test first.

## Local hooks

```sh
brew bundle install      # installs lefthook
lefthook install         # writes .git/hooks/{pre-commit,pre-push}
```

`pre-commit` runs rubocop on staged Ruby. `pre-push` runs the full rspec + rubocop. Bypass with `LEFTHOOK=0 git commit ...` when needed.

## Scope and tradeoffs

textus is deliberately small. Before adding a new verb, action, or extension hook:

- Can existing primitives compose it? Prefer composition over new surface.
- Does it belong in the gem or in `.textus/extensions/`? Project-local extensions are encouraged — that's what the DSL exists for.
- Is the wire format affected? Then it needs a SPEC update too.

Name the cost in the PR description. "Adds X; costs Y" beats "adds X."

## Commit and PR style

- Conventional prefixes preferred, not enforced.
- One logical change per PR. Keep diffs reviewable.
- Update `CHANGELOG.md` under `## [Unreleased]` for anything user-visible.

## Releases

Maintainers tag `vX.Y.Z` on `main`. The release workflow publishes to RubyGems and creates a GitHub release with the extracted changelog section.

## Reporting security issues

See [`SECURITY.md`](SECURITY.md).

## Sources of truth

`docs/architecture/README.md` — read this first for orientation. `SPEC.md` is the wire contract you reach for once you know the layout. Treat `SPEC.md`, `ARCHITECTURE.md`, and `docs/` as current. `CHANGELOG.md` is the canonical record of what shipped per version. Per-release implementation plans live under `docs/plans/` as scratch artifacts — not gating documents. Contributors are not expected to write or follow them.
