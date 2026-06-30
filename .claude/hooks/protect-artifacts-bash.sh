#!/usr/bin/env bash
# PreToolUse hook (Bash) — warn when shell commands write to textus-managed artifacts.
#
# Catches patterns like: echo "..." > README.md, tee docs/foo.md, cp x docs/y
# Cannot catch every case, but surfaces the most common agent patterns.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('command', ''))
" <<< "$INPUT" 2>/dev/null) || true

[ -z "$COMMAND" ] && exit 0

# Patterns that suggest writing to a protected artifact.
# Match: redirect (> or >>) into a protected path, or tee/cp targeting one.
PROTECTED_PATTERN='(>|>>|tee|cat >)\s*(docs/|CHANGELOG\.md|README\.md|AGENTS\.md|CLAUDE\.md|CONTRIBUTING\.md|SECURITY\.md|CODE_OF_CONDUCT\.md|\.mcp\.json|opencode\.json|\.claude-plugin/)'

if echo "$COMMAND" | grep -qP "$PROTECTED_PATTERN" 2>/dev/null || \
   echo "$COMMAND" | grep -qE "(>|>>)\s*(docs/|CHANGELOG\.md|README\.md|CONTRIBUTING\.md|SECURITY\.md|CODE_OF_CONDUCT\.md|AGENTS\.md|CLAUDE\.md|\.mcp\.json|opencode\.json)" 2>/dev/null; then
  cat >&2 <<'EOF'

  ✗  Shell write to textus-managed artifact detected.

  docs/, CHANGELOG.md, README.md, and other root files are published
  by `textus drain` — do not write to them via shell redirects.

  Use the textus protocol:
    bundle exec exe/textus put KEY --stdin --as=automation
    bundle exec exe/textus drain --as=automation

  To find the key for a path:
    bundle exec exe/textus where FRAGMENT

EOF
  exit 2
fi

exit 0
