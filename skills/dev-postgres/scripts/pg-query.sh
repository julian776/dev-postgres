#!/usr/bin/env bash
# pg-query.sh — Main query executor for dev-postgres skill
# Loads config, resolves connections, enforces security, executes via psql.
#
# Exit codes:
#   0 — Success
#   1 — Blocked by validation
#   2 — Requires confirmation (destructive)
#   3 — Usage / config error
#   4 — Execution error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
QUERY=""
CONNECTION=""
FORMAT="aligned"
CONFIRM_DESTRUCTIVE=false

usage() {
  cat >&2 <<EOF
Usage: pg-query.sh --query <sql> [--connection <name>] [--format <aligned|csv|json>] [--config <path>]

Options:
  --query       SQL query to execute (required)
  --connection  Named connection from config (default: uses default_connection)
  --format      Output format: aligned, csv, json (default: aligned)
  --config      Path to config file (default: .dev-postgres.json in project root)
  --confirm     Acknowledge destructive operation (skip confirmation check)
EOF
  exit 3
}

# --- Dependency checks ---
check_dependencies() {
  local missing=()
  if ! command -v psql &>/dev/null; then
    missing+=("psql (install: brew install libpq && brew link --force libpq)")
  fi
  if ! command -v jq &>/dev/null; then
    missing+=("jq (install: brew install jq)")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing required dependencies:" >&2
    for dep in "${missing[@]}"; do
      echo "  - $dep" >&2
    done
    exit 3
  fi
}

check_dependencies

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)
      QUERY="$2"
      shift 2
      ;;
    --connection)
      CONNECTION="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --confirm)
      CONFIRM_DESTRUCTIVE=true
      shift
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$QUERY" ]]; then
  echo "Error: --query is required" >&2
  usage
fi

# --- Locate config ---
find_config() {
  if [[ -n "$CONFIG_FILE" ]]; then
    if [[ ! -f "$CONFIG_FILE" ]]; then
      echo "Error: Config file not found: $CONFIG_FILE" >&2
      exit 3
    fi
    echo "$CONFIG_FILE"
    return
  fi
  # Walk up from current directory to find .dev-postgres.json
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.dev-postgres.json" ]]; then
      echo "$dir/.dev-postgres.json"
      return
    fi
    dir="$(dirname "$dir")"
  done
  echo "Error: No .dev-postgres.json found. Create one in your project root." >&2
  exit 3
}

CONFIG_FILE=$(find_config)

# --- Load config ---
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "Error: Invalid JSON in config file: $CONFIG_FILE" >&2
  exit 3
fi

# Resolve connection name
if [[ -z "$CONNECTION" ]]; then
  CONNECTION=$(jq -r '.default_connection // empty' "$CONFIG_FILE")
  if [[ -z "$CONNECTION" ]]; then
    echo "Error: No --connection specified and no default_connection in config" >&2
    exit 3
  fi
fi

# Extract connection config
CONN_JSON=$(jq -r ".connections.\"$CONNECTION\" // empty" "$CONFIG_FILE")
if [[ -z "$CONN_JSON" ]]; then
  echo "Error: Connection '$CONNECTION' not found in config" >&2
  echo "Available connections: $(jq -r '.connections | keys | join(", ")' "$CONFIG_FILE")" >&2
  exit 3
fi

# --- Extract connection parameters ---
DB_HOST=$(echo "$CONN_JSON" | jq -r '.host // "localhost"')
DB_PORT=$(echo "$CONN_JSON" | jq -r '.port // 5432')
DB_NAME=$(echo "$CONN_JSON" | jq -r '.database // empty')
DB_USER=$(echo "$CONN_JSON" | jq -r '.user // empty')
DB_PASSWORD_RAW=$(echo "$CONN_JSON" | jq -r '.password // empty')
DB_MODE=$(echo "$CONN_JSON" | jq -r '.mode // "read-only"')
DB_SSLMODE=$(echo "$CONN_JSON" | jq -r '.sslmode // "prefer"')
DB_SCHEMAS=$(echo "$CONN_JSON" | jq -r '.schemas // empty')

if [[ -z "$DB_NAME" ]]; then
  echo "Error: Connection '$CONNECTION' missing required field: database" >&2
  exit 3
fi

# --- Resolve password (env var interpolation) ---
resolve_env_var() {
  local value="$1"
  if [[ "$value" =~ ^\$\{([^}]+)\}$ ]]; then
    local var_name="${BASH_REMATCH[1]}"
    local resolved="${!var_name:-}"
    if [[ -z "$resolved" ]]; then
      echo "Error: Environment variable '$var_name' is not set (needed for connection '$CONNECTION' password)" >&2
      exit 3
    fi
    echo "$resolved"
  else
    echo "$value"
  fi
}

DB_PASSWORD=""
if [[ -n "$DB_PASSWORD_RAW" ]]; then
  DB_PASSWORD=$(resolve_env_var "$DB_PASSWORD_RAW")
fi

# --- Security settings ---
SECURITY_JSON=$(jq -r '.security // {}' "$CONFIG_FILE")
BLOCK_DIRECT=$(echo "$SECURITY_JSON" | jq -r '.block_direct_access // true')
REQUIRE_CONFIRM=$(echo "$SECURITY_JSON" | jq -r '.require_confirmation_for_destructive // true')
LOG_QUERIES=$(echo "$SECURITY_JSON" | jq -r '.log_all_queries // true')
MAX_ROWS=$(echo "$SECURITY_JSON" | jq -r '.max_rows // 1000')
QUERY_TIMEOUT=$(echo "$SECURITY_JSON" | jq -r '.query_timeout_seconds // 30')

# --- Query validation ---
VALIDATE_ARGS=(--query "$QUERY" --mode "$DB_MODE")
if [[ "$REQUIRE_CONFIRM" == "true" && "$CONFIRM_DESTRUCTIVE" != "true" ]]; then
  VALIDATE_ARGS+=(--require-confirmation)
fi

VALIDATE_EXIT=0
"$SCRIPT_DIR/pg-validate.sh" "${VALIDATE_ARGS[@]}" || VALIDATE_EXIT=$?

case $VALIDATE_EXIT in
  0) ;; # allowed
  1)
    echo "BLOCKED: Query rejected by validation policy." >&2
    exit 1
    ;;
  2)
    echo "CONFIRMATION REQUIRED: This is a destructive operation." >&2
    echo "Re-run with --confirm to proceed." >&2
    exit 2
    ;;
  *)
    echo "Error: Validation failed with unexpected exit code: $VALIDATE_EXIT" >&2
    exit 3
    ;;
esac

# --- Auto-LIMIT for unbounded SELECTs ---
inject_limit() {
  local sql="$1"
  local max="$2"
  # Normalize for detection (uppercase, collapse whitespace)
  local upper
  upper=$(echo "$sql" | tr '[:lower:]' '[:upper:]' | tr '\n' ' ' | sed 's/  */ /g')
  # Only apply to simple SELECT statements without existing LIMIT
  if echo "$upper" | grep -qE '^[[:space:]]*SELECT[[:space:]]' && \
     ! echo "$upper" | grep -qE 'LIMIT[[:space:]]+[0-9]' && \
     ! echo "$upper" | grep -qE ';.*SELECT'; then
    # Strip trailing semicolons and whitespace, add LIMIT
    sql=$(echo "$sql" | sed 's/[[:space:]]*;[[:space:]]*$//')
    echo "$sql LIMIT $max;"
  else
    echo "$sql"
  fi
}

FINAL_QUERY=$(inject_limit "$QUERY" "$MAX_ROWS")

# --- Build session preamble ---
PREAMBLE=""
# Timeout
TIMEOUT_MS=$((QUERY_TIMEOUT * 1000))
PREAMBLE+="SET statement_timeout = '${TIMEOUT_MS}ms';"
# Read-only enforcement at PostgreSQL level
if [[ "$DB_MODE" == "read-only" ]]; then
  PREAMBLE+=" SET default_transaction_read_only = ON;"
fi
# Schema search path
if [[ -n "$DB_SCHEMAS" && "$DB_SCHEMAS" != "null" ]]; then
  SCHEMA_PATH=$(echo "$CONN_JSON" | jq -r '.schemas | join(", ")')
  PREAMBLE+=" SET search_path TO $SCHEMA_PATH;"
fi

FULL_QUERY="$PREAMBLE $FINAL_QUERY"

# --- Logging ---
if [[ "$LOG_QUERIES" == "true" ]]; then
  LOG_DIR="$(dirname "$CONFIG_FILE")"
  LOG_FILE="$LOG_DIR/.dev-postgres-query.log"
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] connection=$CONNECTION mode=$DB_MODE query=$(echo "$QUERY" | tr '\n' ' ')" >> "$LOG_FILE"
fi

# --- Build psql command ---
PSQL_ARGS=(-h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -v ON_ERROR_STOP=1 --no-psqlrc)
if [[ -n "$DB_USER" ]]; then
  PSQL_ARGS+=(-U "$DB_USER")
fi

# Output format
case "$FORMAT" in
  aligned)
    PSQL_ARGS+=(-c "$FULL_QUERY")
    ;;
  csv)
    PSQL_ARGS+=(--csv -c "$FULL_QUERY")
    ;;
  json)
    # Use CSV output then convert to JSON via python3
    PSQL_ARGS+=(--csv -c "$FULL_QUERY")
    ;;
  *)
    echo "Error: Unknown format: $FORMAT (use aligned, csv, json)" >&2
    exit 3
    ;;
esac

# --- Execute ---
export PGPASSWORD="$DB_PASSWORD"
export PGSSLMODE="$DB_SSLMODE"

cleanup() {
  unset PGPASSWORD
  unset PGSSLMODE
}
trap cleanup EXIT

if [[ "$FORMAT" == "json" ]]; then
  CSV_OUTPUT=$(psql "${PSQL_ARGS[@]}" 2>&1) || {
    EXIT_CODE=$?
    echo "Error executing query:" >&2
    echo "$CSV_OUTPUT" >&2
    exit 4
  }
  # Convert CSV to JSON
  if command -v python3 &>/dev/null; then
    echo "$CSV_OUTPUT" | python3 -c "
import csv, json, sys
reader = csv.DictReader(sys.stdin)
rows = list(reader)
json.dump(rows, sys.stdout, indent=2, default=str)
print()
"
  else
    echo "Warning: python3 not available, falling back to CSV output" >&2
    echo "$CSV_OUTPUT"
  fi
else
  psql "${PSQL_ARGS[@]}" 2>&1 || {
    EXIT_CODE=$?
    echo "Error executing query (exit code: $EXIT_CODE)" >&2
    exit 4
  }
fi
