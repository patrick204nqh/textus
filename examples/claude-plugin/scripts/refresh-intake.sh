#!/usr/bin/env bash
# Run from a directory containing .textus/. Requires: curl, jq, textus.
set -euo pipefail

stale_json=$(textus stale --zone=intake --format=json)
echo "$stale_json" | jq -c '.[]?' | while read -r row; do
  key=$(echo "$row"    | jq -r '.key')
  url=$(echo "$row"    | jq -r '.source.from')
  parser=$(echo "$row" | jq -r '.source.parse')
  echo "refreshing $key  ←  $url  (parser=$parser)"
  curl -sSL "$url" \
    | textus put "$key" --parse="$parser" --stdin --as=script --format=json \
    | jq -c '{key, etag}'
done
echo "intake refresh complete"
