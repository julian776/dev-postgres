# Query Examples

Common query patterns using the dev-postgres wrapper scripts.

## Basic Queries

```bash
# Select all rows (auto-limited to max_rows)
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT * FROM users"

# Filtered query
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name, email FROM users WHERE active = true ORDER BY created_at DESC"

# Aggregate query
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT department, COUNT(*) as count, AVG(salary) as avg_salary FROM employees GROUP BY department ORDER BY count DESC"

# Join query
bash skills/dev-postgres/scripts/pg-query.sh --query "
  SELECT o.id, o.created_at, u.name, o.total
  FROM orders o
  JOIN users u ON u.id = o.user_id
  WHERE o.status = 'completed'
  ORDER BY o.created_at DESC
  LIMIT 50
"
```

## Write Operations (read-write connections only)

```bash
# Insert
bash skills/dev-postgres/scripts/pg-query.sh --query "
  INSERT INTO users (name, email, active)
  VALUES ('Alice Smith', 'alice@example.com', true)
  RETURNING id, name
" --connection dev

# Update
bash skills/dev-postgres/scripts/pg-query.sh --query "
  UPDATE users SET active = false WHERE last_login < NOW() - INTERVAL '1 year'
  RETURNING id, name, last_login
" --connection dev

# Delete (with WHERE clause)
bash skills/dev-postgres/scripts/pg-query.sh --query "
  DELETE FROM sessions WHERE expires_at < NOW()
  RETURNING id
" --connection dev

# Upsert
bash skills/dev-postgres/scripts/pg-query.sh --query "
  INSERT INTO settings (key, value) VALUES ('theme', 'dark')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
  RETURNING key, value
" --connection dev
```

## Destructive Operations (require --confirm)

```bash
# Drop table
bash skills/dev-postgres/scripts/pg-query.sh --query "DROP TABLE temp_results" --connection dev --confirm

# Truncate
bash skills/dev-postgres/scripts/pg-query.sh --query "TRUNCATE TABLE logs" --connection dev --confirm

# Delete without WHERE (deletes all rows)
bash skills/dev-postgres/scripts/pg-query.sh --query "DELETE FROM temp_data" --connection dev --confirm
```

## Schema Operations

```bash
# Create table
bash skills/dev-postgres/scripts/pg-query.sh --query "
  CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    action VARCHAR(50) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    record_id BIGINT,
    changed_by VARCHAR(100),
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    old_values JSONB,
    new_values JSONB
  )
" --connection dev

# Add column
bash skills/dev-postgres/scripts/pg-query.sh --query "
  ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20)
" --connection dev

# Create index
bash skills/dev-postgres/scripts/pg-query.sh --query "
  CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email ON users (email)
" --connection dev
```

## Output Formats

```bash
# Default aligned (tabular)
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name FROM users LIMIT 5"
# Output:
#  id |  name
# ----+--------
#   1 | Alice
#   2 | Bob

# CSV
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name FROM users LIMIT 5" --format csv
# Output:
# id,name
# 1,Alice
# 2,Bob

# JSON
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT id, name FROM users LIMIT 5" --format json
# Output:
# [
#   {"id": "1", "name": "Alice"},
#   {"id": "2", "name": "Bob"}
# ]
```

## Schema Inspection

```bash
# Explore database structure
bash skills/dev-postgres/scripts/pg-schema.sh --action list-schemas
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables --schema analytics
bash skills/dev-postgres/scripts/pg-schema.sh --action list-views

# Examine specific tables
bash skills/dev-postgres/scripts/pg-schema.sh --action describe --table users
bash skills/dev-postgres/scripts/pg-schema.sh --action indexes --table users
bash skills/dev-postgres/scripts/pg-schema.sh --action foreign-keys --table orders

# Check sizes
bash skills/dev-postgres/scripts/pg-schema.sh --action table-sizes

# Verify connection
bash skills/dev-postgres/scripts/pg-schema.sh --action connection-info --connection prod
```

## Multi-Connection Workflow

```bash
# Check prod schema
bash skills/dev-postgres/scripts/pg-schema.sh --action describe --table users --connection prod

# Replicate structure in dev
bash skills/dev-postgres/scripts/pg-query.sh --query "
  CREATE TABLE IF NOT EXISTS users_v2 (LIKE users INCLUDING ALL)
" --connection dev

# Compare row counts
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT count(*) FROM users" --connection prod
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT count(*) FROM users" --connection dev
```
