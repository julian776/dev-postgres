# Security Architecture

dev-postgres implements defense-in-depth security with 5 independent layers. Each layer provides protection even if other layers are bypassed.

## Layer 1: PreToolUse Hook (pg-hook.sh)

The hook intercepts all Bash tool calls before execution and blocks direct access to PostgreSQL CLI tools.

**Blocked commands:**
- `psql` — Interactive PostgreSQL client
- `pg_dump` / `pg_restore` — Backup/restore tools
- `pgcli` — Alternative PostgreSQL client
- `createdb` / `dropdb` — Database management
- `createuser` / `dropuser` — Role management
- `pg_basebackup` — Physical backup tool
- `postgresql://` / `postgres://` — Connection URI patterns

**Allowed through:** Commands that invoke the wrapper scripts (`pg-query.sh`, `pg-schema.sh`, `pg-validate.sh`).

**Limitation:** The hook only intercepts `Bash` tool calls. Other tools (MCP servers, etc.) are not covered. See limitations.md.

## Layer 2: Query Validation (pg-validate.sh)

Before any query reaches the database, `pg-validate.sh` classifies it as read or write using regex pattern matching.

**Write patterns detected:**
INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, TRUNCATE, GRANT, REVOKE, COPY, VACUUM, REINDEX, CLUSTER, COMMENT, SECURITY, DO

**Enforcement:**
- Read-only connections: all write operations are blocked (exit code 1)
- Destructive operations (DROP, TRUNCATE, DELETE without WHERE): flagged for confirmation (exit code 2)

**Limitation:** Regex-based parsing cannot catch all cases. Complex SQL with writes hidden in CTEs, dynamic SQL in `DO $$ ... $$` blocks, or function calls that perform writes may not be detected. This is why Layer 3 exists.

## Layer 3: PostgreSQL Session Enforcement

For read-only connections, the wrapper prepends:

```sql
SET default_transaction_read_only = ON;
```

This is enforced by PostgreSQL itself at the server level. Even if Layers 1 and 2 are bypassed, PostgreSQL will reject any write operation in the session. This is the true security guarantee for read-only connections.

## Layer 4: Statement Timeout

Every query session includes:

```sql
SET statement_timeout = '<configured_ms>ms';
```

This prevents runaway queries from consuming database resources. Default: 30 seconds, configurable per-project in `.dev-postgres.json`.

## Layer 5: Destructive Operation Confirmation

When `require_confirmation_for_destructive` is enabled (default), operations like DROP TABLE, TRUNCATE, and DELETE without WHERE require an explicit `--confirm` flag. This provides a human-in-the-loop checkpoint for irreversible operations.

## Password Security

- Passwords in `.dev-postgres.json` use `${ENV_VAR}` syntax and are resolved at runtime
- Never store plaintext passwords in the config file
- The `PGPASSWORD` environment variable is used to pass credentials to `psql` and is unset immediately after execution
- For higher security, use a `.pgpass` file or `PGPASSFILE` environment variable instead

**Important:** `PGPASSWORD` may briefly appear in `/proc` or `ps` output. In high-security environments, prefer `.pgpass`.

## Query Logging

When `log_all_queries` is enabled (default), all queries are logged to `.dev-postgres-query.log` in the project root with timestamps, connection names, and modes. This provides an audit trail but logs are not rotated automatically.

## Recommendations

1. **Always use read-only connections for production databases.** The PostgreSQL-level enforcement (Layer 3) provides a hard guarantee.
2. **Set up dedicated database roles** with minimal privileges. See `templates/setup-roles.sql`.
3. **Add `.dev-postgres.json` to `.gitignore`** if it contains any sensitive information (even with env var syntax, connection details may be sensitive).
4. **Add `.dev-postgres-query.log` to `.gitignore`** to avoid committing query logs.
5. **Review the hook configuration** to ensure it's active. See limitations.md for known issues with skill-scoped hooks.
