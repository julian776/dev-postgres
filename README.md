# dev-postgres: Secure PostgreSQL Access for Claude Code

## ⚠️ BETA - TESTING IN PROGRESS
Do not use in production environments. Currently under active testing.

**dev-postgres** is a Claude Code skill that provides secure, auditable PostgreSQL database access through wrapper scripts with defense-in-depth security.

## Features

- **Named Connections**: Configure multiple databases (dev, staging, prod) with per-connection security modes
- **Read/Write Enforcement**: Read-only connections enforced at both validation and PostgreSQL session level
- **Defense-in-Depth**: 5 independent security layers — hook blocking, query validation, PostgreSQL session enforcement, statement timeouts, and destructive operation confirmation
- **Schema Inspection**: Explore tables, views, indexes, foreign keys, and sizes without writing raw SQL
- **Output Formats**: Aligned (tabular), CSV, and JSON
- **Query Logging**: Full audit trail of all executed queries
- **Auto-LIMIT**: Unbounded SELECTs automatically get a configurable row limit

## Installation

### Prerequisites

- `psql` 14+ (PostgreSQL client)
- `jq` 1.6+ (JSON processing)
- `bash` 4.0+
- `python3` 3.8+ (optional, for JSON output)

### Quick Start

```bash
# Run the install script
bash skills/dev-postgres/install.sh

# Edit the generated config with your connection details
$EDITOR .dev-postgres.json

# Set password environment variables
export DEV_POSTGRES_PASSWORD="your_password"

# Test the connection
bash skills/dev-postgres/scripts/pg-schema.sh --action connection-info
```

## Usage

Ask Claude to interact with your database — for example: *"Show me the schema for the users table"*, *"How many orders were placed today?"*, or *"List all tables in the analytics schema"*.

All access goes through wrapper scripts. Direct `psql` access is blocked by a security hook.

```bash
# Run a query
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT * FROM users WHERE active = true"

# Inspect schema
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables

# Query a specific connection
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT count(*) FROM orders" --connection prod
```

## Security

Every query passes through 5 independent security layers:

1. **Hook** — Blocks direct CLI access to `psql`, `pg_dump`, etc.
2. **Validation** — Regex-based read/write classification
3. **PostgreSQL Session** — `SET default_transaction_read_only = ON` for read-only connections
4. **Timeout** — `SET statement_timeout` prevents runaway queries
5. **Confirmation** — Destructive operations (DROP, TRUNCATE) require explicit `--confirm`

> **Important:** These layers are defense-in-depth. For production databases, enforce read-only at the database level by connecting to a **read replica** (strongest — physically cannot accept writes) or using a **read-only PostgreSQL user** with only SELECT privileges. See [templates/setup-roles.sql](skills/dev-postgres/templates/setup-roles.sql) for a ready-to-use role template.

See [references/security.md](skills/dev-postgres/references/security.md) for details.

## License

MIT
