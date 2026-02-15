#!/usr/bin/env bash
# test-hook.sh — Tests for pg-hook.sh
# Run: bash skills/dev-postgres/tests/test-hook.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../scripts/pg-hook.sh"

PASS=0
FAIL=0

assert_decision() {
  local description="$1"
  local expected="$2"
  local command="$3"

  local input="{\"tool_input\": {\"command\": \"$command\"}}"
  local output
  output=$(echo "$input" | bash "$HOOK" 2>/dev/null)
  local decision
  decision=$(echo "$output" | jq -r '.decision' 2>/dev/null)

  if [[ "$decision" == "$expected" ]]; then
    echo "  PASS: $description ($decision)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected $expected, got $decision)"
    echo "        command: $command"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== pg-hook.sh tests ==="
echo ""

# --- Blocked commands ---
echo "Commands that should be blocked:"
assert_decision "Direct psql" "block" "psql -h localhost mydb"
assert_decision "pg_dump" "block" "pg_dump mydb > backup.sql"
assert_decision "pg_restore" "block" "pg_restore backup.sql"
assert_decision "pgcli" "block" "pgcli mydb"
assert_decision "createdb" "block" "createdb testdb"
assert_decision "dropdb" "block" "dropdb testdb"
assert_decision "postgresql:// URI" "block" "curl postgresql://localhost/mydb"
assert_decision "postgres:// URI" "block" "curl postgres://localhost/mydb"
echo ""

# --- Allowed commands ---
echo "Commands that should be allowed:"
assert_decision "pg-query.sh" "allow" "bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1'"
assert_decision "pg-schema.sh" "allow" "bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables"
assert_decision "Non-postgres command" "allow" "ls -la"
assert_decision "Git command" "allow" "git status"
assert_decision "npm install" "allow" "npm install"
echo ""

# --- Command chaining bypass prevention ---
echo "Command chaining bypass prevention:"
assert_decision "pg-query.sh && psql blocked" "block" "bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1' && psql -h localhost mydb"
assert_decision "pg-query.sh ; psql blocked" "block" "bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1'; psql -h localhost mydb"
assert_decision "pg-query.sh | psql blocked" "block" "bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1' | psql -h localhost mydb"
assert_decision "pg-query.sh || psql blocked" "block" "bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1' || psql -h localhost mydb"
assert_decision "psql && pg-query.sh blocked" "block" "psql -h localhost mydb && bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1'"
assert_decision "pg-query.sh alone still allowed" "allow" "bash skills/dev-postgres/scripts/pg-query.sh --query 'SELECT 1'"
assert_decision "pg-schema.sh alone still allowed" "allow" "bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables"
echo ""

# --- Edge cases ---
echo "Edge cases:"
assert_decision "Empty input allows" "allow" ""

# Test with no tool_input
NO_INPUT_RESULT=$(echo '{}' | bash "$HOOK" 2>/dev/null)
NO_INPUT_DECISION=$(echo "$NO_INPUT_RESULT" | jq -r '.decision' 2>/dev/null)
if [[ "$NO_INPUT_DECISION" == "allow" ]]; then
  echo "  PASS: No tool_input allows ($NO_INPUT_DECISION)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: No tool_input (expected allow, got $NO_INPUT_DECISION)"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- Summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
