#!/bin/bash
BOOT=$(bundle exec exe/textus boot 2>/dev/null)
LOOP=$(echo "$BOOT" | jq -r '.state.loop.current_node // "—"' 2>/dev/null)
printf '\e]0;textus — %s\a' "$LOOP"
