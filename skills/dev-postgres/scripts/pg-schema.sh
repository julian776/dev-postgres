#!/usr/bin/env bash
# pg-schema.sh — Schema inspection helpers for dev-postgres skill
# Delegates all queries to pg-query.sh for consistent security enforcement.
#
# Exit codes:
#   0 — Success
#   3 — Usage error
#   * — Passes through pg-query.sh exit codes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<EOF
Usage: pg-schema.sh --action <action> [--connection <name>] [--table <name>] [--schema <name>] [--format <aligned|csv|json>] [--config <path>]

Actions:
  list-connections  List configured database connections (no database access needed)
  list-tables       List all tables (optionally in a schema)
  list-views        List all views (optionally in a schema)
  list-schemas      List all schemas
  describe          Describe a table's columns (requires --table)
  indexes           Show indexes for a table (requires --table)
  foreign-keys      Show foreign keys for a table (requires --table)
  table-sizes       Show table sizes
  connection-info   Show current connection info

Options:
  --action      Action to perform (required)
  --connection  Named connection from config
  --table       Table name (for describe, indexes, foreign-keys)
  --schema      Schema name (for list-tables, list-views; default: public)
  --format      Output format: aligned, csv, json (default: aligned)
  --config      Path to config file
EOF
  exit 3
}

ACTION=""
CONNECTION_ARGS=()
TABLE=""
SCHEMA="public"
FORMAT="aligned"
CONFIG_PATH=""
CONFIG_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)
      ACTION="$2"
      shift 2
      ;;
    --connection)
      CONNECTION_ARGS=(--connection "$2")
      shift 2
      ;;
    --table)
      TABLE="$2"
      shift 2
      ;;
    --schema)
      SCHEMA="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --config)
      CONFIG_PATH="$2"
      CONFIG_ARGS=(--config "$2")
      shift 2
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Error: --action is required" >&2
  usage
fi

# Sanitize SQL identifiers to prevent injection.
# Only allows alphanumeric, underscore, and dollar sign (valid PostgreSQL identifier chars).
# Rejects anything else (quotes, semicolons, spaces, etc.).
sanitize_identifier() {
  local value="$1"
  local label="$2"
  if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_\$]*$ ]]; then
    echo "Error: Invalid $label: '$value' (must be a valid SQL identifier — alphanumeric and underscores only)" >&2
    exit 3
  fi
  echo "$value"
}

SCHEMA=$(sanitize_identifier "$SCHEMA" "schema name")
if [[ -n "$TABLE" ]]; then
  TABLE=$(sanitize_identifier "$TABLE" "table name")
fi

# Find config file (walks up directories, same logic as pg-query.sh)
find_config() {
  if [[ -n "$CONFIG_PATH" ]]; then
    if [[ ! -f "$CONFIG_PATH" ]]; then
      echo "Error: Config file not found: $CONFIG_PATH" >&2
      exit 3
    fi
    echo "$CONFIG_PATH"
    return
  fi
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

# Run a query through pg-query.sh
run_query() {
  local sql="$1"
  "$SCRIPT_DIR/pg-query.sh" \
    --query "$sql" \
    --format "$FORMAT" \
    "${CONNECTION_ARGS[@]+"${CONNECTION_ARGS[@]}"}" \
    "${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"}"
}

case "$ACTION" in
  list-connections)
    CONFIG_RESOLVED=$(find_config)
    DEFAULT_CONN=$(jq -r '.default_connection // ""' "$CONFIG_RESOLVED")
    case "$FORMAT" in
      json)
        jq --arg dc "$DEFAULT_CONN" \
          '[.connections | to_entries | sort_by(.key)[] | {
            name: .key,
            description: (.value.description // ""),
            mode: (.value.mode // "read-only"),
            database: .value.database,
            host: (.value.host // "localhost"),
            default: (.key == $dc)
          }]' "$CONFIG_RESOLVED"
        ;;
      csv)
        echo "name,description,mode,database,host,default"
        jq -r --arg dc "$DEFAULT_CONN" \
          '.connections | to_entries | sort_by(.key)[] | [
            .key,
            (.value.description // ""),
            (.value.mode // "read-only"),
            .value.database,
            (.value.host // "localhost"),
            (if .key == $dc then "true" else "false" end)
          ] | @csv' "$CONFIG_RESOLVED"
        ;;
      aligned)
        {
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "name" "description" "mode" "database" "host" "default"
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "----" "-----------" "----" "--------" "----" "-------"
          jq -r --arg dc "$DEFAULT_CONN" \
            '.connections | to_entries | sort_by(.key)[] | [
              .key,
              (.value.description // ""),
              (.value.mode // "read-only"),
              .value.database,
              (.value.host // "localhost"),
              (if .key == $dc then "*" else "" end)
            ] | @tsv' "$CONFIG_RESOLVED"
        } | column -s $'\t' -t
        ;;
      *)
        echo "Error: Unknown format: $FORMAT (use aligned, csv, json)" >&2
        exit 3
        ;;
    esac
    ;;

  list-tables)
    run_query "
      SELECT table_schema, table_name, table_type
      FROM information_schema.tables
      WHERE table_schema = '$SCHEMA'
        AND table_type = 'BASE TABLE'
      ORDER BY table_name;
    "
    ;;

  list-views)
    run_query "
      SELECT table_schema, table_name
      FROM information_schema.views
      WHERE table_schema = '$SCHEMA'
      ORDER BY table_name;
    "
    ;;

  list-schemas)
    run_query "
      SELECT schema_name, schema_owner
      FROM information_schema.schemata
      WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
      ORDER BY schema_name;
    "
    ;;

  describe)
    if [[ -z "$TABLE" ]]; then
      echo "Error: --table is required for 'describe' action" >&2
      exit 3
    fi
    run_query "
      SELECT
        column_name,
        data_type,
        character_maximum_length,
        is_nullable,
        column_default
      FROM information_schema.columns
      WHERE table_schema = '$SCHEMA'
        AND table_name = '$TABLE'
      ORDER BY ordinal_position;
    "
    ;;

  indexes)
    if [[ -z "$TABLE" ]]; then
      echo "Error: --table is required for 'indexes' action" >&2
      exit 3
    fi
    run_query "
      SELECT
        i.relname AS index_name,
        am.amname AS index_type,
        ix.indisunique AS is_unique,
        ix.indisprimary AS is_primary,
        pg_get_indexdef(ix.indexrelid) AS index_definition
      FROM pg_index ix
      JOIN pg_class t ON t.oid = ix.indrelid
      JOIN pg_class i ON i.oid = ix.indexrelid
      JOIN pg_am am ON am.oid = i.relam
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE t.relname = '$TABLE'
        AND n.nspname = '$SCHEMA'
      ORDER BY i.relname;
    "
    ;;

  foreign-keys)
    if [[ -z "$TABLE" ]]; then
      echo "Error: --table is required for 'foreign-keys' action" >&2
      exit 3
    fi
    run_query "
      SELECT
        tc.constraint_name,
        kcu.column_name,
        ccu.table_schema AS foreign_table_schema,
        ccu.table_name AS foreign_table_name,
        ccu.column_name AS foreign_column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_name = '$TABLE'
        AND tc.table_schema = '$SCHEMA';
    "
    ;;

  table-sizes)
    run_query "
      SELECT
        schemaname AS schema,
        tablename AS table,
        pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
        pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS data_size,
        pg_size_pretty(pg_indexes_size(schemaname || '.' || quote_ident(tablename))) AS index_size
      FROM pg_tables
      WHERE schemaname = '$SCHEMA'
      ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;
    "
    ;;

  connection-info)
    run_query "
      SELECT
        current_database() AS database,
        current_user AS user,
        inet_server_addr() AS server_addr,
        inet_server_port() AS server_port,
        version() AS pg_version;
    "
    ;;

  *)
    echo "Error: Unknown action: $ACTION" >&2
    echo "Valid actions: list-connections, list-tables, list-views, list-schemas, describe, indexes, foreign-keys, table-sizes, connection-info" >&2
    exit 3
    ;;
esac
