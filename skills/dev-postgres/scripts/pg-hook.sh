#!/usr/bin/env bash
# pg-hook.sh — PreToolUse hook for dev-postgres skill
# Blocks direct access to PostgreSQL CLI tools. All database access must go
# through the wrapper scripts (pg-query.sh, pg-schema.sh).
#
# This script reads a JSON payload from stdin (Claude Code hook protocol),
# inspects the command field, and returns a permission decision.
#
# Returns JSON:
#   {"decision": "allow"}  — command is permitted
#   {"decision": "block", "reason": "..."}  — command is denied

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract the command from tool_input.command
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [[ -z "$COMMAND" ]]; then
  # Not a Bash tool call or no command — allow
  echo '{"decision": "allow"}'
  exit 0
fi

# Patterns for PostgreSQL CLI tools that should be blocked
BLOCKED_PATTERNS=(
  '\bpsql\b'
  '\bpg_dump\b'
  '\bpg_restore\b'
  '\bpgcli\b'
  '\bcreatedb\b'
  '\bdropdb\b'
  '\bcreateuser\b'
  '\bdropuser\b'
  '\bpg_basebackup\b'
  'postgresql://'
  'postgres://'
)

# Patterns for our wrapper scripts — these are always allowed
ALLOWED_PATTERNS=(
  'pg-query\.sh'
  'pg-schema\.sh'
  'pg-validate\.sh'
  'pg-hook\.sh'
)

# Check if command invokes one of our wrapper scripts
for pattern in "${ALLOWED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    echo '{"decision": "allow"}'
    exit 0
  fi
done

# Check if command matches any blocked pattern
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    REASON="Direct PostgreSQL CLI access is blocked by dev-postgres security policy. Use the wrapper scripts instead:\\n"
    REASON+="  - pg-query.sh --query 'SELECT ...' [--connection name]\\n"
    REASON+="  - pg-schema.sh --action list-tables [--connection name]\\n"
    REASON+="See SKILL.md for full usage."
    echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    exit 0
  fi
done

# Not a PostgreSQL command — allow
echo '{"decision": "allow"}'
exit 0
