#!/bin/bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name')
SID=$(echo "$input" | jq -r '.session_id' | cut -c1-8)
LOOP=$(bundle exec exe/textus loop 2>/dev/null | jq -r '.current_node.name // "—"')

printf '\e]0;textus — %s — %s\a' "$LOOP" "$SID"
printf '■ %s  ◆ %s  ● %s' "$LOOP" "$SID" "$MODEL"
