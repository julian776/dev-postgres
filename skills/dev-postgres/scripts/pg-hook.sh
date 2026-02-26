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

# --- Patterns for PostgreSQL CLI tools that should be blocked ---
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
  '\bvacuumdb\b'
  '\breindexdb\b'
  '\bclusterdb\b'
  '\bpg_recvlogical\b'
  '\bpg_amcheck\b'
  'postgresql://'
  'postgres://'
)

# --- Patterns that indicate encoding/obfuscation attempts ---
# These are suspicious in combination with any database-related context
EVASION_PATTERNS=(
  '\bbase64\b'
  '\beval\b'
  '\\x[0-9a-fA-F]{2}'
  '\bprintf\b.*\\\\x'
)

# --- Patterns for our wrapper scripts (sole permitted entry point) ---
WRAPPER_PATTERN='(pg-query\.sh|pg-schema\.sh|pg-validate\.sh|pg-hook\.sh)'

block() {
  local reason="Direct PostgreSQL CLI access is blocked by dev-postgres security policy. Use the wrapper scripts instead:\\n"
  reason+="  - pg-query.sh --query 'SELECT ...' [--connection name]\\n"
  reason+="  - pg-schema.sh --action list-tables [--connection name]\\n"
  reason+="See SKILL.md for full usage."
  echo "{\"decision\": \"block\", \"reason\": \"$reason\"}"
  exit 0
}

# Strategy: A command is allowed ONLY if it matches one of these cases:
#   1. It does not contain any blocked pattern AND no evasion patterns
#   2. It is EXACTLY a wrapper script invocation (no command chaining with blocked tools)
#
# For case 2, we require that after removing the wrapper invocations,
# no blocked patterns remain. The key fix: we split on command separators
# FIRST, then check each segment independently.

# --- Check for evasion patterns ---
# Block commands that use encoding/obfuscation techniques (base64, eval, printf hex)
# These have no legitimate use in database wrapper invocations.
for pattern in "${EVASION_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    # Allow if the command is purely a wrapper script invocation with no blocked tools
    if echo "$COMMAND" | grep -qE "$WRAPPER_PATTERN"; then
      # Even with a wrapper present, block if evasion is detected alongside it
      # Legitimate wrapper usage never needs base64/eval/printf-hex
      :
    fi
    block
  fi
done

# --- Check for blocked patterns ---
IS_BLOCKED=false
for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if echo "$COMMAND" | grep -qE "$pattern"; then
    IS_BLOCKED=true
    break
  fi
done

if [[ "$IS_BLOCKED" == false ]]; then
  # No blocked patterns found — allow
  echo '{"decision": "allow"}'
  exit 0
fi

# --- Blocked pattern detected: check if ONLY via wrapper scripts ---
# Split command into segments by shell operators (&&, ||, ;, |) and check each.
# A segment is allowed if it contains a wrapper script pattern.
# A segment is blocked if it contains a blocked pattern without a wrapper.
#
# This prevents bypasses like:
#   bash pg-query.sh --query "$(psql ...)"  — psql is INSIDE the wrapper segment
#
# The fix: a wrapper segment that also contains blocked patterns is BLOCKED.
# Wrapper scripts invoke psql internally (not via the Bash tool), so a legitimate
# wrapper invocation never has psql in the command string itself.

# Split on ;, &&, ||, | (but not inside quotes — approximated by splitting on operators)
# Use a simple approach: any segment containing both a wrapper AND a blocked pattern is blocked.
SEGMENTS=$(echo "$COMMAND" | sed -E 's/[;&|]+/\n/g')

ALL_COVERED=true
while IFS= read -r segment; do
  # Skip empty segments
  [[ -z "$(echo "$segment" | tr -d '[:space:]')" ]] && continue

  HAS_BLOCKED=false
  for pattern in "${BLOCKED_PATTERNS[@]}"; do
    if echo "$segment" | grep -qE "$pattern"; then
      HAS_BLOCKED=true
      break
    fi
  done

  if [[ "$HAS_BLOCKED" == true ]]; then
    HAS_WRAPPER=false
    if echo "$segment" | grep -qE "$WRAPPER_PATTERN"; then
      HAS_WRAPPER=true
    fi

    if [[ "$HAS_WRAPPER" == true ]]; then
      # Segment has BOTH a wrapper and a blocked pattern.
      # This means the blocked tool is embedded in the wrapper's args (e.g., $(psql ...)).
      # Block it — legitimate wrapper usage never embeds psql in the command text.
      block
    else
      # Segment has a blocked pattern with no wrapper — clearly blocked
      block
    fi
  fi
  # Segment has no blocked pattern — it's fine
done <<< "$SEGMENTS"

# All segments checked, none had unaccounted blocked patterns
echo '{"decision": "allow"}'
exit 0
