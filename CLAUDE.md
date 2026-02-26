# dev-postgres Development Guide

## Project Structure

```
skills/dev-postgres/
├── SKILL.md              # Skill definition (loaded by Claude Code)
├── install.sh            # Setup script for new users
├── scripts/
│   ├── pg-hook.sh        # PreToolUse hook — blocks direct psql access
│   ├── pg-query.sh       # Main query executor
│   ├── pg-schema.sh      # Schema inspection helpers
│   └── pg-validate.sh    # SQL classification and enforcement
├── references/
│   ├── security.md       # Defense-in-depth architecture docs
│   ├── limitations.md    # Known limitations
│   ├── query-examples.md # Common query patterns
│   └── installation.md   # Setup instructions
├── templates/
│   ├── config-example.json  # Example .dev-postgres.json
│   └── setup-roles.sql     # PostgreSQL role setup SQL
└── tests/
    ├── test-validate.sh  # Validation script tests
    ├── test-hook.sh      # Hook script tests
    └── test-security.sh  # Security vulnerability regression tests
```

## Architecture

All database access flows through a single pipeline:

```
User request → SKILL.md instructions → pg-query.sh → pg-validate.sh → psql
                                        ↑
                              pg-schema.sh (convenience wrapper)
```

**pg-hook.sh** runs as a PreToolUse hook and intercepts Bash tool calls before they execute, blocking direct `psql`/`pg_dump`/etc. access.

**pg-validate.sh** classifies SQL as read or write using regex patterns. Returns exit code 0 (allow), 1 (blocked), or 2 (needs confirmation).

**pg-query.sh** is the main executor: loads config, resolves connection, calls validation, injects LIMIT, sets session preamble (timeout, read-only mode, search_path), executes via psql.

**pg-schema.sh** translates schema actions into SQL and delegates to pg-query.sh.

## Key Design Decisions

- **Bash-only, no runtime dependencies** beyond psql and jq. No Node.js, Python (except optional JSON output), or other runtimes needed.
- **Config walks up directories** to find `.dev-postgres.json`, similar to how tools find `.gitignore`.
- **Exit codes are semantic**: 0=success, 1=blocked, 2=needs-confirm, 3=usage-error, 4=execution-error.
- **Preamble-based security**: Read-only enforcement happens at the PostgreSQL session level, not just regex validation.

## Testing

```bash
# Run all unit tests
bash skills/dev-postgres/tests/test-validate.sh
bash skills/dev-postgres/tests/test-hook.sh
bash skills/dev-postgres/tests/test-security.sh
```

## Pre-Completion Checklist

Before finishing any task:

1. Run `bash -n skills/dev-postgres/scripts/*.sh` to syntax-check all scripts
2. Run `bash skills/dev-postgres/tests/test-validate.sh` to verify validation logic
3. Run `bash skills/dev-postgres/tests/test-hook.sh` to verify hook logic
4. Run `bash skills/dev-postgres/tests/test-security.sh` to verify security regression tests
5. Ensure all scripts have `set -euo pipefail` at the top
6. Ensure all scripts use `#!/usr/bin/env bash` shebang
7. Verify BSD compatibility (macOS) — avoid GNU-only sed/grep flags
