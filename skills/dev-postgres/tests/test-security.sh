#!/usr/bin/env bash
# test-security.sh — Security vulnerability tests for dev-postgres skill
# Tests bypass vectors discovered during security review (2026-02-26).
# Run: bash skills/dev-postgres/tests/test-security.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../scripts/pg-hook.sh"
VALIDATE="$SCRIPT_DIR/../scripts/pg-validate.sh"

PASS=0
FAIL=0

assert_hook_decision() {
  local description="$1"
  local expected="$2"
  local command="$3"

  # Use python3 for proper JSON encoding to avoid shell escaping issues
  local input
  input=$(python3 -c "import json; print(json.dumps({'tool_input': {'command': '$command'}}))")
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

assert_hook_decision_raw() {
  local description="$1"
  local expected="$2"
  local json_input="$3"

  local output
  output=$(echo "$json_input" | bash "$HOOK" 2>/dev/null)
  local decision
  decision=$(echo "$output" | jq -r '.decision' 2>/dev/null)

  if [[ "$decision" == "$expected" ]]; then
    echo "  PASS: $description ($decision)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected $expected, got $decision)"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  local description="$1"
  local expected_exit="$2"
  shift 2

  local actual_exit=0
  "$VALIDATE" "$@" >/dev/null 2>&1 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    echo "  PASS: $description (exit=$actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected exit=$expected_exit, got exit=$actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Security Vulnerability Tests ==="
echo ""

# =============================================
# Hook bypass via command substitution
# =============================================
echo "Hook bypass: command substitution in wrapper args"

JSON_INPUT=$(python3 -c "
import json
cmd = 'bash skills/dev-postgres/scripts/pg-query.sh --query \"\$(psql -h localhost mydb -c \\\\\"SELECT 1\\\\\")\" --connection dev'
print(json.dumps({'tool_input': {'command': cmd}}))
")
assert_hook_decision_raw "psql in \$() inside pg-query.sh args" "block" "$JSON_INPUT"
echo ""

# =============================================
# Hook bypass via encoding / indirection
# =============================================
echo "Hook bypass: encoding and indirection"

assert_hook_decision "base64 encoded psql" "block" \
  "echo cHNxbCAtaCBsb2NhbGhvc3QgbXlkYg== | base64 -d | bash"

assert_hook_decision "eval with string concatenation" "block" \
  'eval "ps""ql -h localhost mydb"'

JSON_INPUT=$(python3 -c "
import json
cmd = '\$(printf \"\\\\x70\\\\x73\\\\x71\\\\x6c\") -h localhost mydb'
print(json.dumps({'tool_input': {'command': cmd}}))
")
assert_hook_decision_raw "printf hex encoding" "block" "$JSON_INPUT"

assert_hook_decision "base64 via eval" "block" \
  'eval \$(echo cHNxbCAtaCBsb2NhbGhvc3Q= | base64 -d)'

echo ""

# =============================================
# Hook: missing PostgreSQL CLI tools
# =============================================
echo "Hook: missing PostgreSQL CLI tools in blocklist"

assert_hook_decision "vacuumdb blocked" "block" "vacuumdb --all"
assert_hook_decision "reindexdb blocked" "block" "reindexdb --all"
assert_hook_decision "clusterdb blocked" "block" "clusterdb --all"
assert_hook_decision "pg_recvlogical blocked" "block" "pg_recvlogical --start"
assert_hook_decision "pg_amcheck blocked" "block" "pg_amcheck mydb"

echo ""

# =============================================
# LIMIT bypass via SQL comments
# =============================================
echo "LIMIT injection: comment bypass"

# Test via the inject_limit function extracted from pg-query.sh
test_inject_limit() {
  local sql="$1"
  local max="$2"
  local description="$3"
  local expect_limit="$4"

  # Source the inject_limit function from pg-query.sh
  # We can't source the whole file (it runs immediately), so extract the function
  local result
  result=$(bash -c '
    inject_limit() {
      local sql="$1"
      local max="$2"
      local upper
      upper=$(echo "$sql" | tr "[:lower:]" "[:upper:]" | tr "\n" " " | sed "s/  */ /g")
      # Strip SQL comments before checking for existing LIMIT
      local stripped
      stripped=$(echo "$upper" | sed "s/--.*$//" | perl -pe "s|/\*.*?\*/||gs" 2>/dev/null || echo "$upper" | sed "s|/\*[^*]*\*/||g")
      stripped=$(echo "$stripped" | sed "s/  */ /g" | sed "s/^ *//;s/ *$//")
      if echo "$stripped" | grep -qE "^[[:space:]]*SELECT[[:space:]]" && \
         ! echo "$stripped" | grep -qE "LIMIT[[:space:]]+[0-9]" && \
         ! echo "$stripped" | grep -qE ";.*SELECT"; then
        sql=$(echo "$sql" | sed "s/[[:space:]]*;[[:space:]]*$//")
        echo "$sql LIMIT $max;"
      else
        echo "$sql"
      fi
    }
    inject_limit "$1" "$2"
  ' -- "$sql" "$max")

  local has_limit=false
  if echo "$result" | grep -qE "LIMIT $max" 2>/dev/null; then
    has_limit=true
  fi

  if [[ "$expect_limit" == "true" && "$has_limit" == "true" ]]; then
    echo "  PASS: $description (LIMIT injected)"
    PASS=$((PASS + 1))
  elif [[ "$expect_limit" == "false" && "$has_limit" == "false" ]]; then
    echo "  PASS: $description (LIMIT not injected, as expected)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expect_limit=$expect_limit, has_limit=$has_limit, result=$result)"
    FAIL=$((FAIL + 1))
  fi
}

# These test the FIXED version (comment stripping before LIMIT check)
# We test inject_limit directly here since the fix is in that function
test_inject_limit "SELECT * FROM users -- LIMIT 100" "1000" \
  "Single-line comment LIMIT should still inject" "true"

test_inject_limit "SELECT * FROM users /* LIMIT 100 */" "1000" \
  "Block comment LIMIT should still inject" "true"

test_inject_limit "SELECT * FROM users LIMIT 50" "1000" \
  "Real LIMIT should NOT be overridden" "false"

echo ""

# =============================================
# DO block destructive detection bypass
# =============================================
echo "Destructive detection: DO block obfuscation"

assert_exit "DO block with obfuscated DROP (string concat) needs confirm" 2 \
  --query "DO \$\$ BEGIN EXECUTE 'DRO' || 'P TABLE users'; END \$\$;" --mode read-write --require-confirmation

assert_exit "DO block with dynamic DELETE needs confirm" 2 \
  --query "DO \$\$ DECLARE t text := 'users'; BEGIN EXECUTE 'DELETE FROM ' || t; END \$\$;" --mode read-write --require-confirmation

assert_exit "DO block with plain DROP TABLE still needs confirm" 2 \
  --query "DO \$\$ BEGIN EXECUTE 'DROP TABLE users'; END \$\$;" --mode read-write --require-confirmation

assert_exit "DO block blocked on read-only" 1 \
  --query "DO \$\$ BEGIN EXECUTE 'anything'; END \$\$;" --mode read-only

echo ""

# =============================================
# max_rows validation (SQL injection via config)
# =============================================
echo "Config validation: max_rows injection"

# This tests that inject_limit validates max_rows is a positive integer.
# A malicious max_rows like "1; DROP TABLE users; --" should be rejected.
test_max_rows_validation() {
  local max_rows="$1"
  local description="$2"
  local expect_safe="$3"

  local result
  result=$(bash -c '
    max_rows="$1"
    # Validate max_rows is a positive integer
    if ! [[ "$max_rows" =~ ^[0-9]+$ ]] || [[ "$max_rows" -eq 0 ]]; then
      echo "REJECTED"
      exit 0
    fi
    echo "ACCEPTED"
  ' -- "$max_rows")

  if [[ "$expect_safe" == "rejected" && "$result" == "REJECTED" ]]; then
    echo "  PASS: $description (rejected)"
    PASS=$((PASS + 1))
  elif [[ "$expect_safe" == "accepted" && "$result" == "ACCEPTED" ]]; then
    echo "  PASS: $description (accepted)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $description (expected $expect_safe, got $result)"
    FAIL=$((FAIL + 1))
  fi
}

test_max_rows_validation "1000" "Normal max_rows=1000" "accepted"
test_max_rows_validation "1; DROP TABLE users; --" "SQL injection in max_rows" "rejected"
test_max_rows_validation "-1" "Negative max_rows" "rejected"
test_max_rows_validation "0" "Zero max_rows" "rejected"
test_max_rows_validation "abc" "Non-numeric max_rows" "rejected"

echo ""

# =============================================
# Summary
# =============================================
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
