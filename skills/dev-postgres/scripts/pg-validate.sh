#!/usr/bin/env bash
# pg-validate.sh — Query validation for dev-postgres skill
# Classifies SQL as read/write, enforces read-only mode, flags destructive ops.
#
# Exit codes:
#   0 — Query is allowed
#   1 — Query is blocked (write on read-only connection)
#   2 — Query requires confirmation (destructive operation)
#   3 — Usage error

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: pg-validate.sh --query <sql> --mode <read-only|read-write> [--require-confirmation]

Options:
  --query                 SQL query to validate
  --mode                  Connection mode: read-only or read-write
  --require-confirmation  Flag destructive operations for confirmation (exit 2)
EOF
  exit 3
}

QUERY=""
MODE=""
REQUIRE_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      QUERY="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --require-confirmation)
      REQUIRE_CONFIRMATION=true
      shift
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$QUERY" || -z "$MODE" ]]; then
  echo "Error: --query and --mode are required" >&2
  usage
fi

# Normalize: strip comments, collapse whitespace, uppercase for matching
normalize_sql() {
  local sql="$1"
  # Remove single-line comments
  sql=$(echo "$sql" | sed 's/--.*$//')
  # Remove multi-line comments (simple, non-nested) — compatible with BSD sed
  sql=$(echo "$sql" | perl -pe 's|/\*.*?\*/||gs' 2>/dev/null || echo "$sql" | sed 's|/\*[^*]*\*/||g')
  # Collapse whitespace
  sql=$(echo "$sql" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')
  # Uppercase
  echo "$sql" | tr '[:lower:]' '[:upper:]'
}

NORMALIZED=$(normalize_sql "$QUERY")

# --- Write operation detection ---
# Matches DML writes and DDL statements
WRITE_PATTERNS=(
  '^[[:space:]]*INSERT[[:space:]]'
  '^[[:space:]]*UPDATE[[:space:]]'
  '^[[:space:]]*DELETE[[:space:]]'
  '^[[:space:]]*CREATE[[:space:]]'
  '^[[:space:]]*ALTER[[:space:]]'
  '^[[:space:]]*DROP[[:space:]]'
  '^[[:space:]]*TRUNCATE[[:space:]]'
  '^[[:space:]]*GRANT[[:space:]]'
  '^[[:space:]]*REVOKE[[:space:]]'
  '^[[:space:]]*COPY[[:space:]]'
  '^[[:space:]]*VACUUM[[:space:]]'
  '^[[:space:]]*REINDEX[[:space:]]'
  '^[[:space:]]*CLUSTER[[:space:]]'
  '^[[:space:]]*COMMENT[[:space:]]'
  '^[[:space:]]*SECURITY[[:space:]]'
  '^[[:space:]]*DO[[:space:]]'
)

# Also check for writes inside multi-statement strings (split on ;)
is_write_query() {
  local sql="$1"
  # Check each statement separated by semicolons
  local IFS=';'
  for stmt in $sql; do
    # Trim leading whitespace
    stmt=$(echo "$stmt" | sed 's/^[[:space:]]*//')
    [[ -z "$stmt" ]] && continue
    for pattern in "${WRITE_PATTERNS[@]}"; do
      if echo "$stmt" | grep -qE "$pattern"; then
        return 0
      fi
    done
  done
  return 1
}

# --- Destructive operation detection ---
DESTRUCTIVE_PATTERNS=(
  'DROP[[:space:]]+(TABLE|DATABASE|SCHEMA|INDEX|VIEW|FUNCTION|TRIGGER|SEQUENCE|TYPE|EXTENSION|ROLE)'
  'TRUNCATE[[:space:]]'
  'DELETE[[:space:]]+FROM[[:space:]]+[^[:space:]]+[[:space:]]*;'
  'DELETE[[:space:]]+FROM[[:space:]]+[^[:space:]]+[[:space:]]*$'
)

is_destructive() {
  local sql="$1"
  for pattern in "${DESTRUCTIVE_PATTERNS[@]}"; do
    if echo "$sql" | grep -qE "$pattern"; then
      # For DELETE, check if there's a WHERE clause
      if echo "$sql" | grep -qE 'DELETE[[:space:]]+FROM'; then
        if ! echo "$sql" | grep -qE 'DELETE[[:space:]]+FROM[[:space:]]+[^[:space:]]+[[:space:]]+WHERE[[:space:]]'; then
          return 0
        fi
      else
        return 0
      fi
    fi
  done
  return 1
}

# --- Enforcement ---

IS_WRITE=false
if is_write_query "$NORMALIZED"; then
  IS_WRITE=true
fi

# Block writes on read-only connections
if [[ "$IS_WRITE" == true && "$MODE" == "read-only" ]]; then
  echo "BLOCKED: Write operation not allowed on read-only connection." >&2
  echo "Query: $QUERY" >&2
  exit 1
fi

# Flag destructive operations for confirmation
if [[ "$IS_WRITE" == true && "$REQUIRE_CONFIRMATION" == true ]]; then
  if is_destructive "$NORMALIZED"; then
    echo "DESTRUCTIVE: This query requires confirmation before execution." >&2
    echo "Query: $QUERY" >&2
    exit 2
  fi
fi

# Query is allowed
exit 0
