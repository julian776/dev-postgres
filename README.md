# dev-postgres: Secure PostgreSQL Access for Claude Code

## ⚠️ BETA - TESTING IN PROGRESS
Do not use in production environments. Currently under active testing.

**dev-postgres** is a Claude Code skill that provides secure, auditable PostgreSQL database access with defense-in-depth security.

## Installation

### Step 1: Install Prerequisites

```bash
# Check if already installed
psql --version    # Need 14+
jq --version      # Need 1.6+
```

If missing:

```bash
# macOS
brew install libpq jq && brew link --force libpq

# Ubuntu/Debian
sudo apt-get install -y postgresql-client jq

# RHEL/Fedora
sudo dnf install -y postgresql jq
```

### Step 2: Install the Plugin

Run these commands inside Claude Code:

```
/plugin marketplace add julian776/dev-postgres
/plugin install dev-postgres@julian776/dev-postgres
```

**Restart Claude Code after installation.**

---

### Step 3: Configure Your Database Connection

Edit the config file created by the installer:

```bash
# Open the config file
nano .dev-postgres.json
```

Replace the example values with your actual database credentials:

```json
{
  "connections": {
    "dev": {
      "host": "localhost",
      "port": 5432,
      "database": "your_database_name",
      "user": "your_username",
      "password": "${DEV_POSTGRES_PASSWORD}",
      "mode": "read-write",
      "description": "Local development database"
    }
  },
  "default_connection": "dev",
  "security": {
    "max_rows": 1000,
    "query_timeout_seconds": 30
  }
}
```

**Configuration Fields:**

| Field | Description | Example |
|-------|-------------|---------|
| `host` | Database hostname | `localhost`, `db.example.com` |
| `port` | Database port | `5432` |
| `database` | Database name | `myapp_dev` |
| `user` | PostgreSQL username | `dev_user` |
| `password` | Use `${ENV_VAR}` syntax | `${DEV_POSTGRES_PASSWORD}` |
| `mode` | `read-only` or `read-write` | `read-write` |

---

### Step 4: Set Your Password

Set the password as an environment variable (never hardcode it in the config):

```bash
# Set for current session
export DEV_POSTGRES_PASSWORD="your_actual_password"

# Or add to your shell profile for persistence
echo 'export DEV_POSTGRES_PASSWORD="your_actual_password"' >> ~/.zshrc
source ~/.zshrc
```

---

### Step 5: Test the Connection

```bash
# Verify connection works
bash skills/dev-postgres/scripts/pg-schema.sh --action connection-info
```

**Expected output:**

```
Connection: dev
Host: localhost:5432
Database: your_database_name
User: your_username
Mode: read-write
Status: connected
```

---

## Usage

Once installed, ask Claude to interact with your database naturally:

- *"Show me all tables in the database"*
- *"What columns does the users table have?"*
- *"How many orders were placed today?"*
- *"List all active users with their email addresses"*

### Manual Commands

```bash
# List all tables
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables

# Describe a table structure
bash skills/dev-postgres/scripts/pg-schema.sh --action describe --table users

# Run a query
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT * FROM users LIMIT 10"

# Export as CSV
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT * FROM users" --format csv

# Use a specific connection
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT count(*) FROM orders" --connection prod
```

---

## Multiple Connections (Dev, Staging, Prod)

You can configure multiple database connections. Use the `description` field to explain to the agent what each connection is for — the agent reads these descriptions when listing connections and uses them to pick the right database for your request:

```json
{
  "connections": {
    "dev": {
      "host": "localhost",
      "port": 5432,
      "database": "myapp_dev",
      "user": "dev_user",
      "password": "${DEV_POSTGRES_PASSWORD}",
      "mode": "read-write",
      "description": "Local development database — safe to write"
    },
    "staging": {
      "host": "staging-db.example.com",
      "port": 5432,
      "database": "myapp_staging",
      "user": "readonly_user",
      "password": "${STAGING_POSTGRES_PASSWORD}",
      "mode": "read-only",
      "description": "Staging replica for QA and testing"
    },
    "prod": {
      "host": "prod-replica.example.com",
      "port": 5432,
      "database": "myapp_prod",
      "user": "readonly_user",
      "password": "${PROD_POSTGRES_PASSWORD}",
      "mode": "read-only",
      "description": "Production read replica — live customer data"
    }
  },
  "default_connection": "dev"
}
```

Then set all password environment variables:

```bash
export DEV_POSTGRES_PASSWORD="dev_password"
export STAGING_POSTGRES_PASSWORD="staging_password"
export PROD_POSTGRES_PASSWORD="prod_password"
```

---

## Securing Your Connections

The skill enforces read-only mode at the session level, but the strongest protection comes from the database itself. If the PostgreSQL user only has `SELECT` privileges, no client — including this skill — can perform writes, regardless of configuration mistakes or software bugs.

### Step 1: Create a Read-Only Role in PostgreSQL

Connect to your database as a superuser and create a role with only read permissions:

```sql
-- Create the role
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'CHANGE_ME';

-- Allow connecting to the database
GRANT CONNECT ON DATABASE myapp TO readonly_user;

-- Grant read access to the schemas you need
GRANT USAGE ON SCHEMA public TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;

-- Auto-grant SELECT on any tables created in the future
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO readonly_user;

-- Optional: enforce a query timeout at the role level
ALTER ROLE readonly_user SET statement_timeout = '30s';
```

> A complete example with multiple schemas is available in [templates/setup-roles.sql](templates/setup-roles.sql).

### Step 2: Use the Read-Only Role in Your Connection Config

Point your read-only connections at this new role and set `mode` to `read-only`:

```json
{
  "connections": {
    "dev": {
      "host": "localhost",
      "port": 5432,
      "database": "myapp_dev",
      "user": "dev_user",
      "password": "${DEV_POSTGRES_PASSWORD}",
      "mode": "read-write",
      "description": "Local development database — safe to write"
    },
    "prod": {
      "host": "prod-db.example.com",
      "port": 5432,
      "database": "myapp_prod",
      "user": "readonly_user",
      "password": "${PROD_READONLY_PASSWORD}",
      "mode": "read-only",
      "sslmode": "require",
      "description": "Production — read-only role, cannot write"
    }
  },
  "default_connection": "dev"
}
```

This gives you two independent layers of write protection on the `prod` connection:

1. **Database-level** — the `readonly_user` role only has `SELECT` privileges, so PostgreSQL itself rejects any write attempt.
2. **Skill-level** — `"mode": "read-only"` enables session-level `SET default_transaction_read_only = ON` and regex-based write blocking.

Even if one layer fails, the other still prevents writes.

### Why This Matters

| Protection layer | Blocks writes? | Can be bypassed by config mistake? |
|---|---|---|
| `mode: "read-only"` in config | Yes (session + regex) | Yes — if someone changes it to `read-write` |
| Read-only PostgreSQL role | Yes (server-enforced) | No — only a superuser can grant write privileges |
| Read replica | Yes (physically impossible) | No — replicas cannot accept writes |

**Recommended approach:** use a read-only PostgreSQL role for staging and production connections. If available, connect to a read replica for the strongest guarantee.

---

## Security

Every query passes through 5 independent security layers:

1. **Hook** — Blocks direct CLI access to `psql`, `pg_dump`, `vacuumdb`, and 14 other PostgreSQL tools. Also detects evasion techniques (base64 encoding, eval, printf hex).
2. **Validation** — Regex-based read/write classification. Detects writes in multi-statement queries, CTEs, EXPLAIN ANALYZE, SET/RESET, and DO blocks.
3. **PostgreSQL Session** — `SET default_transaction_read_only = ON` for read-only connections (server-enforced, cannot be bypassed by query construction).
4. **Timeout** — `SET statement_timeout` prevents runaway queries.
5. **Confirmation** — Destructive operations (DROP, TRUNCATE, DELETE without WHERE, all DO blocks) require explicit `--confirm`.

Additional protections:

- **Config validation** — `max_rows` and `query_timeout_seconds` are validated as positive integers to prevent SQL injection via config.
- **Password scoping** — `PGPASSWORD` is scoped to psql invocations only, not exported to child processes.
- **Schema name validation** — Schema and table names in pg-schema.sh are validated against a strict identifier allowlist.

> **Important:** For production databases, use a **read replica** (physically cannot write) or a **read-only PostgreSQL user**. See [templates/setup-roles.sql](templates/setup-roles.sql) for role setup.

---

## Troubleshooting

### "Connection refused" or "could not connect"

1. Verify the database is running
2. Check host/port in `.dev-postgres.json`
3. Ensure your IP is allowed in the database firewall/`pg_hba.conf`

### "Password authentication failed"

1. Verify the environment variable is set: `echo $DEV_POSTGRES_PASSWORD`
2. Ensure the password matches the database user
3. Check that `${ENV_VAR}` syntax in config matches your export

---

## Features

- **Named Connections** — Configure multiple databases (dev, staging, prod)
- **Read/Write Enforcement** — Read-only connections enforced at validation + session level
- **Defense-in-Depth** — 5 independent security layers
- **Schema Inspection** — Explore tables, views, indexes, foreign keys
- **Output Formats** — Aligned (tabular), CSV, and JSON
- **Query Logging** — Full audit trail of all executed queries
- **Auto-LIMIT** — Unbounded SELECTs get configurable row limit

---

## Changelog

### 2026-02-26 — Security Hardening

Security review identified and fixed 9 vulnerabilities across the hook, query executor, and validator scripts. All fixes are covered by 22 new regression tests in `test-security.sh`.

**Hook (pg-hook.sh):**
- Fixed bypass via command substitution (`$(psql ...)` embedded in wrapper script arguments)
- Fixed bypass via encoding/obfuscation (base64, eval string concatenation, printf hex)
- Added 5 missing PostgreSQL CLI tools to blocklist: `vacuumdb`, `reindexdb`, `clusterdb`, `pg_recvlogical`, `pg_amcheck`
- Removed dead `block_direct_access` config option (was read but never enforced)

**Query executor (pg-query.sh):**
- Fixed auto-LIMIT bypass via SQL comments (`-- LIMIT 100` and `/* LIMIT 100 */` no longer fool the LIMIT detection)
- Fixed SQL injection via `max_rows` config value (now validated as positive integer)
- Added validation for `query_timeout_seconds` (must be positive integer)
- Scoped `PGPASSWORD` to psql invocations only (no longer exported to child processes like python3)

**Validator (pg-validate.sh):**
- All `DO` blocks now flagged as destructive and require `--confirm`, since dynamic SQL inside `EXECUTE` cannot be statically inspected for destructive operations

---

## Documentation

- [Security Architecture](skills/dev-postgres/references/security.md)
- [Query Examples](skills/dev-postgres/references/query-examples.md)
- [Known Limitations](skills/dev-postgres/references/limitations.md)
- [PostgreSQL Role Setup](templates/setup-roles.sql) — SQL templates for creating read-only and read-write roles

## License

MIT
