#!/usr/bin/env bash
# test-validate.sh — Tests for pg-validate.sh
# Run: bash skills/dev-postgres/tests/test-validate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../scripts/pg-validate.sh"

PASS=0
FAIL=0

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

echo "=== pg-validate.sh tests ==="
echo ""

# --- Read queries on read-only connections (should pass) ---
echo "Read queries on read-only connections:"
assert_exit "Simple SELECT" 0 \
  --query "SELECT * FROM users" --mode read-only
assert_exit "SELECT with WHERE" 0 \
  --query "SELECT id, name FROM users WHERE active = true" --mode read-only
assert_exit "SELECT with JOIN" 0 \
  --query "SELECT u.name, o.total FROM users u JOIN orders o ON o.user_id = u.id" --mode read-only
assert_exit "SELECT count" 0 \
  --query "SELECT count(*) FROM users" --mode read-only
assert_exit "SHOW command" 0 \
  --query "SHOW server_version" --mode read-only
assert_exit "EXPLAIN" 0 \
  --query "EXPLAIN SELECT * FROM users" --mode read-only
echo ""

# --- Write queries on read-only connections (should block) ---
echo "Write queries on read-only connections:"
assert_exit "INSERT blocked" 1 \
  --query "INSERT INTO users (name) VALUES ('test')" --mode read-only
assert_exit "UPDATE blocked" 1 \
  --query "UPDATE users SET name = 'test' WHERE id = 1" --mode read-only
assert_exit "DELETE blocked" 1 \
  --query "DELETE FROM users WHERE id = 1" --mode read-only
assert_exit "CREATE TABLE blocked" 1 \
  --query "CREATE TABLE test (id int)" --mode read-only
assert_exit "ALTER TABLE blocked" 1 \
  --query "ALTER TABLE users ADD COLUMN foo text" --mode read-only
assert_exit "DROP TABLE blocked" 1 \
  --query "DROP TABLE users" --mode read-only
assert_exit "TRUNCATE blocked" 1 \
  --query "TRUNCATE users" --mode read-only
echo ""

# --- Write queries on read-write connections (should pass) ---
echo "Write queries on read-write connections:"
assert_exit "INSERT allowed" 0 \
  --query "INSERT INTO users (name) VALUES ('test')" --mode read-write
assert_exit "UPDATE allowed" 0 \
  --query "UPDATE users SET name = 'test' WHERE id = 1" --mode read-write
assert_exit "DELETE with WHERE allowed" 0 \
  --query "DELETE FROM users WHERE id = 1" --mode read-write
assert_exit "CREATE TABLE allowed" 0 \
  --query "CREATE TABLE test (id int)" --mode read-write
echo ""

# --- Destructive operations requiring confirmation ---
echo "Destructive operations (with --require-confirmation):"
assert_exit "DROP TABLE needs confirm" 2 \
  --query "DROP TABLE users" --mode read-write --require-confirmation
assert_exit "TRUNCATE needs confirm" 2 \
  --query "TRUNCATE users" --mode read-write --require-confirmation
assert_exit "DELETE without WHERE needs confirm" 2 \
  --query "DELETE FROM users" --mode read-write --require-confirmation
assert_exit "DELETE with WHERE is fine" 0 \
  --query "DELETE FROM users WHERE id = 1" --mode read-write --require-confirmation
echo ""

# --- Case insensitivity ---
echo "Case insensitivity:"
assert_exit "Lowercase insert blocked on read-only" 1 \
  --query "insert into users (name) values ('test')" --mode read-only
assert_exit "Mixed case SELECT allowed" 0 \
  --query "Select * From users" --mode read-only
echo ""

# --- Summary ---
echo "=== Results: $PASS passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
