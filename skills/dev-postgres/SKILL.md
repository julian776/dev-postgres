---
name: dev-postgres
description: >
  Secure PostgreSQL database access for developers and AI agents.
  Use when users ask to query databases, inspect schemas, list tables,
  run SQL, check database structure, or explore data.
  Trigger phrases include "query the database", "show me the schema",
  "list tables", "run SQL", "check the data", "how many rows",
  "describe the table", or any database interaction request.
hooks:
  - type: PreToolUse
    matcher: Bash
    script: skills/dev-postgres/scripts/pg-hook.sh
allowed-tools:
  - Bash
  - Read
  - Glob
---

# PostgreSQL Database Access

You have access to PostgreSQL databases through secure wrapper scripts. **Never use `psql` or other PostgreSQL CLI tools directly** — always use the wrapper scripts below. Direct access is blocked by a security hook.

## Recommended Workflow

Follow this pattern when exploring a database:

1. **Discover** — Start with schema inspection to understand the structure
2. **Query** — Write focused queries based on what you learned
3. **Observe** — Check the results and refine
4. **Repeat** — Narrow down or expand based on findings

```bash
# 1. Discover: What tables exist?
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables

# 2. Discover: What does a table look like?
bash skills/dev-postgres/scripts/pg-schema.sh --action describe --table users

# 3. Query: Get the data you need
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name, email FROM users WHERE active = true LIMIT 10"
```

## Configuration

Database connections are defined in `.dev-postgres.json` in the project root. Each connection has a name, credentials, and a mode (`read-only` or `read-write`).

## Running Queries

Use `pg-query.sh` for all SQL operations:

```bash
# Query the default connection
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT * FROM users WHERE active = true"

# Query a specific connection
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT count(*) FROM orders" --connection prod

# CSV output
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name FROM products" --format csv

# JSON output
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name FROM products" --format json

# Write operations (only on read-write connections)
bash skills/dev-postgres/scripts/pg-query.sh --query "INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')" --connection dev

# Destructive operations require --confirm flag
bash skills/dev-postgres/scripts/pg-query.sh --query "DROP TABLE temp_data" --connection dev --confirm
```

### Output Formats

- `aligned` (default) — Tabular output, best for reading
- `csv` — CSV output, good for data processing
- `json` — JSON array of objects, good for programmatic use (requires python3)

## Schema Inspection

Use `pg-schema.sh` for database structure exploration:

```bash
# List all tables
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables

# List tables in a specific schema
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables --schema analytics

# Describe a table's columns
bash skills/dev-postgres/scripts/pg-schema.sh --action describe --table users

# Show indexes
bash skills/dev-postgres/scripts/pg-schema.sh --action indexes --table users

# Show foreign keys
bash skills/dev-postgres/scripts/pg-schema.sh --action foreign-keys --table orders

# Show table sizes
bash skills/dev-postgres/scripts/pg-schema.sh --action table-sizes

# List schemas
bash skills/dev-postgres/scripts/pg-schema.sh --action list-schemas

# List views
bash skills/dev-postgres/scripts/pg-schema.sh --action list-views

# Connection info
bash skills/dev-postgres/scripts/pg-schema.sh --action connection-info
```

All schema commands accept `--connection`, `--format`, and `--schema` options.

## Security Rules

1. **Never run `psql`, `pg_dump`, `pgcli`, or any PostgreSQL CLI tool directly.** The security hook will block it.
2. **Respect connection modes.** Read-only connections reject all write operations.
3. **Destructive operations** (DROP, TRUNCATE, DELETE without WHERE) require the `--confirm` flag unless the connection has `"require_confirmation": false` or the global `require_confirmation_for_destructive` is `false`.
4. **SELECT queries** automatically get a LIMIT applied based on `max_rows` config (default 1000). Add an explicit LIMIT if you need different behavior.
5. **Passwords** are resolved from environment variables at runtime — never hardcode them.

## Connection Switching

When working with multiple databases, specify the connection explicitly:

```bash
# Dev database (read-write)
bash skills/dev-postgres/scripts/pg-query.sh --query "INSERT INTO logs (msg) VALUES ('test')" --connection dev

# Prod database (read-only)
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT count(*) FROM logs" --connection prod
```

## Error Handling

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | Blocked by validation (write on read-only) |
| 2 | Requires confirmation (destructive operation) |
| 3 | Usage or configuration error |
| 4 | Query execution error |

When a query is blocked (exit 1), explain to the user why and suggest alternatives. When confirmation is required (exit 2), ask the user before re-running with `--confirm`.

## Workflow Tips

- Start by inspecting the schema: `pg-schema.sh --action list-tables` then `--action describe --table <name>`
- Use `--format csv` or `--format json` when you need to process results programmatically
- For large result sets, add explicit `LIMIT` and `OFFSET` clauses
- Check `pg-schema.sh --action connection-info` to verify you're connected to the right database
