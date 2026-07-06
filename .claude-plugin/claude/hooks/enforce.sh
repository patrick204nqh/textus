#!/bin/bash
FILE=$(jq -r '.tool_input.file_path // ""' < /dev/stdin)
[ -z "$FILE" ] && exit 0

BOOT=$(bundle exec exe/textus boot 2>/dev/null)
[ -z "$BOOT" ] && exit 0

PROTECTED=$(echo "$BOOT" | jq -r '.plugin.protected_paths[]' 2>/dev/null)

for pattern in $PROTECTED; do
  if [[ "$FILE" == "$pattern"* ]]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "File is protected by textus — write via textus propose."
      }
    }'
    exit 0
  fi
done

exit 0
