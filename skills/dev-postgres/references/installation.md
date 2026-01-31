# Installation & Prerequisites

## Required System Dependencies

| Dependency | Minimum Version | Purpose | Required |
|-----------|----------------|---------|----------|
| `psql` | 14+ | PostgreSQL client for query execution | Yes |
| `jq` | 1.6+ | JSON parsing in hook and config scripts | Yes |
| `bash` | 4.0+ | Script execution | Yes (pre-installed) |
| `python3` | 3.8+ | JSON output format conversion | Optional |

## Install Dependencies

### macOS (Homebrew)

```bash
# PostgreSQL client (includes psql)
brew install libpq
brew link --force libpq

# jq for JSON processing
brew install jq

# python3 (usually pre-installed on macOS)
brew install python3
```

### Ubuntu / Debian

```bash
sudo apt-get update
sudo apt-get install -y postgresql-client jq python3
```

### RHEL / CentOS / Fedora

```bash
sudo dnf install -y postgresql jq python3
```

### Alpine Linux

```bash
apk add postgresql-client jq python3
```

### Windows (WSL)

Use the Ubuntu/Debian instructions inside WSL. Native Windows is not supported.

## Verify Dependencies

```bash
psql --version    # Should show 14+
jq --version      # Should show 1.6+
python3 --version # Should show 3.8+ (optional)
```

The skill scripts check for required dependencies at runtime and provide specific error messages if any are missing.

## Setup

1. **Copy the config template** to your project root:

   ```bash
   cp skills/dev-postgres/templates/config-example.json .dev-postgres.json
   ```

2. **Edit `.dev-postgres.json`** with your connection details. Use `${ENV_VAR}` syntax for passwords.

3. **Set environment variables** for passwords:

   ```bash
   export DEV_POSTGRES_PASSWORD="your_dev_password"
   export PROD_POSTGRES_PASSWORD="your_prod_password"
   ```

   Consider adding these to your shell profile or using a tool like `direnv`.

4. **Add to `.gitignore`**:

   ```
   .dev-postgres.json
   .dev-postgres-query.log
   ```

5. **Set up database roles** (recommended):

   Review and run `skills/dev-postgres/templates/setup-roles.sql` against your databases to create appropriately scoped roles.

6. **Make scripts executable**:

   ```bash
   chmod +x skills/dev-postgres/scripts/*.sh
   ```

7. **Verify the hook** is working by checking that direct `psql` commands are blocked. If not, see limitations.md for manual hook configuration.

## Test the Setup

```bash
# Test connection
bash skills/dev-postgres/scripts/pg-schema.sh --action connection-info

# List tables
bash skills/dev-postgres/scripts/pg-schema.sh --action list-tables

# Run a query
bash skills/dev-postgres/scripts/pg-query.sh --query "SELECT 1 AS test"
```
