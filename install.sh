#!/bin/bash

# install.sh — One-command setup for dev-postgres skill
# Usage: bash install.sh
#        curl -fsSL https://raw.githubusercontent.com/julian776/dev-postgres/main/install.sh | bash

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If running via curl pipe, clone the repo first
if [[ ! -d "$SCRIPT_DIR/skills/dev-postgres" ]]; then
  echo "=== Cloning dev-postgres ==="
  INSTALL_DIR="${DEV_POSTGRES_INSTALL_DIR:-$HOME/.dev-postgres}"

  if [[ -d "$INSTALL_DIR" ]]; then
    echo "Updating existing installation at $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git pull --quiet
  else
    echo "Installing to $INSTALL_DIR..."
    git clone --quiet https://github.com/julian776/dev-postgres.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi

  SCRIPT_DIR="$INSTALL_DIR"
fi

cd "$SCRIPT_DIR"
SKILL_DIR="$SCRIPT_DIR/skills/dev-postgres"

echo ""
echo "=== dev-postgres Setup ==="
echo ""

# --- Check dependencies ---
MISSING=()

if ! command -v psql &>/dev/null; then
  MISSING+=("psql")
fi

if ! command -v jq &>/dev/null; then
  MISSING+=("jq")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing required dependencies: ${MISSING[*]}"
  echo ""

  # Auto-install on macOS with Homebrew
  if [[ "$(uname)" == "Darwin" ]] && command -v brew &>/dev/null; then
    echo "Detected macOS with Homebrew. Installing dependencies..."
    for dep in "${MISSING[@]}"; do
      if [[ "$dep" == "psql" ]]; then
        brew install libpq
        brew link --force libpq
      else
        brew install "$dep"
      fi
    done
    echo ""
  else
    echo "Please install the missing dependencies:"
    echo ""
    echo "  macOS:        brew install libpq jq && brew link --force libpq"
    echo "  Ubuntu/Debian: sudo apt-get install -y postgresql-client jq"
    echo "  RHEL/Fedora:   sudo dnf install -y postgresql jq"
    echo ""
    exit 1
  fi
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

# --- Copy config template to current working directory ---
ORIGINAL_DIR="${OLDPWD:-$(pwd)}"
CONFIG_FILE="$SCRIPT_DIR/.dev-postgres.json"

if [[ -f "$CONFIG_FILE" ]]; then
  echo "[ok] Config file already exists: .dev-postgres.json"
else
  cp "$SKILL_DIR/templates/config-example.json" "$CONFIG_FILE"
  echo "[ok] Created .dev-postgres.json from template"
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
echo "=== Installation Complete ==="
echo ""
echo "Installed to: $SCRIPT_DIR"
echo ""
echo "Next steps:"
echo ""
echo "  1. Register the plugin in Claude Code:"
echo "     /plugin marketplace add julian776/dev-postgres"
echo "     /plugin install dev-postgres@julian776/dev-postgres"
echo ""
echo "  2. Edit .dev-postgres.json with your connection details:"
echo "     nano $CONFIG_FILE"
echo ""
echo "  3. Set your database password:"
echo "     export DEV_POSTGRES_PASSWORD=\"your_password\""
echo ""
echo "  4. Restart Claude Code and test:"
echo "     bash $SKILL_DIR/scripts/pg-schema.sh --action connection-info"
echo ""
