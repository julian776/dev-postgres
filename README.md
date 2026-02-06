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
      "mode": "read-write"
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

You can configure multiple database connections:

```json
{
  "connections": {
    "dev": {
      "host": "localhost",
      "port": 5432,
      "database": "myapp_dev",
      "user": "dev_user",
      "password": "${DEV_POSTGRES_PASSWORD}",
      "mode": "read-write"
    },
    "staging": {
      "host": "staging-db.example.com",
      "port": 5432,
      "database": "myapp_staging",
      "user": "readonly_user",
      "password": "${STAGING_POSTGRES_PASSWORD}",
      "mode": "read-only"
    },
    "prod": {
      "host": "prod-replica.example.com",
      "port": 5432,
      "database": "myapp_prod",
      "user": "readonly_user",
      "password": "${PROD_POSTGRES_PASSWORD}",
      "mode": "read-only"
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

## Security

Every query passes through 5 independent security layers:

1. **Hook** — Blocks direct CLI access to `psql`, `pg_dump`, etc.
2. **Validation** — Regex-based read/write classification
3. **PostgreSQL Session** — `SET default_transaction_read_only = ON` for read-only connections
4. **Timeout** — `SET statement_timeout` prevents runaway queries
5. **Confirmation** — Destructive operations (DROP, TRUNCATE) require explicit `--confirm`

> **Important:** For production databases, use a **read replica** (physically cannot write) or a **read-only PostgreSQL user**. See [templates/setup-roles.sql](skills/dev-postgres/templates/setup-roles.sql) for role setup.

---

## Troubleshooting

### "psql: command not found"

Install the PostgreSQL client:

```bash
# macOS
brew install libpq && brew link --force libpq

# Ubuntu/Debian
sudo apt-get install postgresql-client
```

### "jq: command not found"

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

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

## Documentation

- [Security Architecture](skills/dev-postgres/references/security.md)
- [Query Examples](skills/dev-postgres/references/query-examples.md)
- [Known Limitations](skills/dev-postgres/references/limitations.md)
- [PostgreSQL Role Setup](skills/dev-postgres/templates/setup-roles.sql)

## License

MIT
