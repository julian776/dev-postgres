# Known Limitations

## 1. Skill-scoped hooks may not trigger

Skill-scoped hooks defined in plugins may not trigger due to a known issue (GitHub issue #17688). If the PreToolUse hook is not blocking direct `psql` access, add it manually to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash skills/dev-postgres/scripts/pg-hook.sh"
          }
        ]
      }
    ]
  }
}
```

## 2. Regex-based query parsing

The query validator (`pg-validate.sh`) uses regex pattern matching, which cannot catch all cases:

- Function calls that perform writes (`SELECT my_write_function()`)
- Queries constructed with string concatenation inside `DO` blocks

The following cases **are** detected:
- Writes inside CTEs (`WITH ... AS (INSERT INTO ...)`) — detected by embedded write patterns
- `DO` blocks — always classified as writes and flagged as destructive (since their `EXECUTE` content cannot be statically inspected)
- `EXPLAIN ANALYZE` — treated as a write since it actually executes the wrapped statement
- `SET` / `RESET` — blocked on read-only connections to prevent disabling security settings

**Mitigation:** Layer 3 (`SET default_transaction_read_only = ON`) is enforced by PostgreSQL itself and cannot be bypassed by query construction. This is the true security guarantee for read-only connections.

## 3. No prepared statement support

Queries are passed as raw strings to `psql -c`. Parameterized queries are not supported; callers must construct the full SQL string. SQL injection risk is mitigated because the agent constructs queries, not untrusted user input.

## 4. Single-statement LIMIT injection

The auto-LIMIT feature (appending `LIMIT N` to unbounded SELECTs) uses regex detection with comment stripping. SQL comments containing `LIMIT` (e.g., `-- LIMIT 100` or `/* LIMIT 100 */`) are stripped before checking, so they cannot bypass auto-LIMIT injection. Multi-statement queries or complex subqueries may not be correctly handled. Add explicit LIMIT clauses for predictable behavior.

## 5. No connection pooling

Each query opens a new `psql` connection. For high-frequency usage, this adds latency. Not a concern for typical AI-assisted development workflows.

## 6. Password exposure in process list

`PGPASSWORD` is scoped to psql invocations only (via inline env prefix, not `export`), so child processes like python3 do not inherit it. However, the password may still briefly appear in `/proc` or `ps` output during psql execution. For high-security environments, use a `.pgpass` file or `PGPASSFILE` environment variable instead. See security.md for details.

## 7. No SSL client certificate support

The skill supports `sslmode` but does not currently handle `sslcert`, `sslkey`, or `sslrootcert` parameters. Can be added in a future version.

## 8. JSON output depends on python3

The `--format json` option uses python3 to convert CSV to JSON. If python3 is not available, JSON output will fall back to CSV with a warning.

## 9. Hook bypass via non-Bash tools

The PreToolUse hook only intercepts `Bash` tool calls. If another tool (e.g., a different MCP server) provides database access, the hook will not block it. Ensure no other database tools are configured alongside this skill.

## 10. No audit log rotation

Query logs (`.dev-postgres-query.log`) grow indefinitely. Users must manage log rotation themselves. Consider adding a cron job or logrotate configuration:

```bash
# Example logrotate config (/etc/logrotate.d/dev-postgres)
/path/to/project/.dev-postgres-query.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```
