#!/usr/bin/env bash
# Run from a directory containing .textus/. Requires: textus.
#
# In 0.2 textus owns the fetch step directly: `textus refresh` walks every
# intake entry whose TTL has expired, calls its registered fetcher (built-in
# or `.textus/extensions/*.rb`), and writes the result back through put.
set -euo pipefail

textus refresh --format=json | jq -c '.refreshed[]?' || true
echo "intake refresh complete"
