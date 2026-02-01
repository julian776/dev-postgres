#!/bin/bash

# install.sh — Setup script for dev-postgres skill
# Checks dependencies, copies config template, sets script permissions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$SCRIPT_DIR/skills/dev-postgres"

echo "=== dev-postgres Setup ==="
echo ""

# --- Check dependencies ---
MISSING=()

if ! command -v psql &>/dev/null; then
  MISSING+=("psql  — brew install libpq && brew link --force libpq")
fi

if ! command -v jq &>/dev/null; then
  MISSING+=("jq    — brew install jq")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing required dependencies:"
  for dep in "${MISSING[@]}"; do
    echo "  - $dep"
  done
  echo ""
  echo "Install them and re-run this script."
  exit 1
fi

echo "[ok] psql $(psql --version | head -1)"
echo "[ok] jq $(jq --version)"

if command -v python3 &>/dev/null; then
  echo "[ok] python3 $(python3 --version 2>&1 | awk '{print $2}') (enables --format json)"
else
  echo "[--] python3 not found (optional, needed for --format json)"
fi

echo ""

# --- Set script permissions ---
chmod +x "$SKILL_DIR/scripts/"*.sh
echo "[ok] Script permissions set"

# --- Copy config template ---
CONFIG_FILE="$SCRIPT_DIR/.dev-postgres.json"
if [[ -f "$CONFIG_FILE" ]]; then
  echo "[ok] Config file already exists: .dev-postgres.json"
else
  cp "$SKILL_DIR/templates/config-example.json" "$CONFIG_FILE"
  echo "[ok] Created .dev-postgres.json from template"
  echo "     Edit it with your connection details."
fi

# --- Check .gitignore ---
GITIGNORE="$SCRIPT_DIR/.gitignore"
NEEDS_GITIGNORE=()

if [[ -f "$GITIGNORE" ]]; then
  grep -q '.dev-postgres.json' "$GITIGNORE" 2>/dev/null || NEEDS_GITIGNORE+=(".dev-postgres.json")
  grep -q '.dev-postgres-query.log' "$GITIGNORE" 2>/dev/null || NEEDS_GITIGNORE+=(".dev-postgres-query.log")
else
  NEEDS_GITIGNORE+=(".dev-postgres.json" ".dev-postgres-query.log")
fi

if [[ ${#NEEDS_GITIGNORE[@]} -gt 0 ]]; then
  for entry in "${NEEDS_GITIGNORE[@]}"; do
    echo "$entry" >> "$GITIGNORE"
  done
  echo "[ok] Added entries to .gitignore: ${NEEDS_GITIGNORE[*]}"
else
  echo "[ok] .gitignore already configured"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .dev-postgres.json with your connection details"
echo "  2. Set password environment variables (e.g. export DEV_POSTGRES_PASSWORD=...)"
echo "  3. Test: bash skills/dev-postgres/scripts/pg-schema.sh --action connection-info"
