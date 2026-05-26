---
name: deploy
description: How to ship a release of this project.
oncall_only: false
---

1. Bump the version constant.
2. `bundle install` to refresh the lockfile.
3. `git tag vX.Y.Z` and push.
4. CI publishes the artifact.
