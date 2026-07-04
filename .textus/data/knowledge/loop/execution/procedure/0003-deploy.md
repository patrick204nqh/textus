---
name: deploy
description: Cut a textus release — bump version, update lockfile, tag, publish.
---
## deploy

**Prerequisites:** All tests passing (`bundle exec rspec`), clean lint (`bundle exec rubocop`).

**Steps:**

1. Update version in `lib/textus/version.rb` (semver)
2. Run `bundle install` to update `Gemfile.lock`
3. Commit with message format: `release: v<version>`
4. Tag: `git tag v<version>`
5. Push: `git push && git push --tags`
6. Build gem: `gem build textus.gemspec`
7. Publish: `gem push textus-<version>.gem`

**Verify:** `textus --version` should report the new version.
