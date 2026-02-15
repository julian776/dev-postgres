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

# Check blocked patterns FIRST — always, even if the command also references
# our wrapper scripts. This prevents chaining bypasses like:
#   bash pg-query.sh --query 'SELECT 1' && psql -h prod mydb
IS_BLOCKED=false
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    IS_BLOCKED=true
    break
  fi
done

# If the command references a blocked tool, check whether it's ONLY being used
# through our wrapper scripts. We strip the wrapper script invocations and
# re-check for blocked patterns in the remainder.
if [[ "$IS_BLOCKED" == true ]]; then
  STRIPPED_COMMAND="$COMMAND"
  for pattern in "${ALLOWED_PATTERNS[@]}"; do
    # Remove wrapper script invocations (and their arguments up to a command separator)
    STRIPPED_COMMAND=$(echo "$STRIPPED_COMMAND" | sed -E "s|[^;&|]*${pattern}[^;&|]*||g")
  done
  # Re-check: if blocked patterns still appear after stripping allowed invocations, block
  STILL_BLOCKED=false
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$STRIPPED_COMMAND" | grep -qE "$pattern"; then
      STILL_BLOCKED=true
      break
    fi
  done
  if [[ "$STILL_BLOCKED" == true ]]; then
    REASON="Direct PostgreSQL CLI access is blocked by dev-postgres security policy. Use the wrapper scripts instead:\\n"
    REASON+="  - pg-query.sh --query 'SELECT ...' [--connection name]\\n"
    REASON+="  - pg-schema.sh --action list-tables [--connection name]\\n"
    REASON+="See SKILL.md for full usage."
    echo "{\"decision\": \"block\", \"reason\": \"$REASON\"}"
    exit 0
  fi
fi

# Not a PostgreSQL command — allow
echo '{"decision": "allow"}'
exit 0
