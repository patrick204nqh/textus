---
name: release
description: Cut a textus release — bump the version, regenerate Gemfile.lock, then tag via PR.
---

Pattern: `knowledge.patterns.trigger-catalog` — release triggers a full converge sweep.

1. Bump `Textus::VERSION` in `lib/textus/version.rb`.
2. Run `bundle install` so `Gemfile.lock` records the new version — **commit
   the lockfile in the same change**. CI runs `bundle install --frozen`; a lock
   mismatch fails every job.
3. Update `CHANGELOG.md` with the version's notable changes (link the ADRs).
4. Open a PR titled `textus X.Y.Z — <headline>`; merge once CI is green.
