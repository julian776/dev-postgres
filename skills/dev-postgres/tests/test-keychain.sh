#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"
cat > "$TMP/bin/uname" <<'MOCK'
#!/bin/bash
echo "${MOCK_OS:-Darwin}"
MOCK
cat > "$TMP/bin/security" <<'MOCK'
#!/bin/bash
[[ -z "${SECURITY_CALLED_FILE:-}" ]] || touch "$SECURITY_CALLED_FILE"
[[ "$*" == "find-generic-password -s service-name -a user-name -w" ]] || exit 1
[[ "${MOCK_FAIL:-0}" != 1 ]] || exit 1
printf '%s\n' 'special $ credential'
MOCK
cat > "$TMP/bin/psql" <<'MOCK'
#!/bin/bash
[[ "$PGPASSWORD" == "$EXPECTED_PASSWORD" ]] || exit 1
printf 'ok\n'
MOCK
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
export EXPECTED_PASSWORD='special $ credential'
cat > "$TMP/config.json" <<'JSON'
{"default_connection":"key", "connections":{
  "key":{"database":"test", "user":"user-name", "password_keychain":"service-name"},
  "literal":{"database":"test", "password":"legacy-secret"},
  "environment":{"database":"test", "password":"${TEST_DB_PASSWORD}"},
  "none":{"database":"test"}
}}
JSON
query() { bash "$ROOT/scripts/pg-query.sh" --config "$TMP/config.json" --query "SELECT 1" "$@"; }
query >"$TMP/out" 2>"$TMP/err"
grep -q ok "$TMP/out"
! grep -q 'special \$ credential' "$TMP/out" "$TMP/err"
export SECURITY_CALLED_FILE="$TMP/security-called"
if bash "$ROOT/scripts/pg-query.sh" --config "$TMP/config.json" --query 'DROP TABLE users' >"$TMP/out" 2>"$TMP/err"; then exit 1; fi
[[ ! -e "$SECURITY_CALLED_FILE" ]]
unset SECURITY_CALLED_FILE
export MOCK_FAIL=1
if query >"$TMP/out" 2>"$TMP/err"; then exit 1; fi
grep -q 'Could not retrieve' "$TMP/err"
unset MOCK_FAIL
export MOCK_OS=Linux
if query >"$TMP/out" 2>"$TMP/err"; then exit 1; fi
grep -q 'requires macOS' "$TMP/err"
unset MOCK_OS
export EXPECTED_PASSWORD=legacy-secret
query --connection literal >"$TMP/out" 2>"$TMP/err"
grep -q 'legacy password' "$TMP/err"
! grep -q legacy-secret "$TMP/err"
export TEST_DB_PASSWORD=env-secret EXPECTED_PASSWORD=env-secret
query --connection environment >"$TMP/out" 2>"$TMP/err"
grep -q 'legacy password' "$TMP/err"
export EXPECTED_PASSWORD=""
query --connection none >"$TMP/out" 2>"$TMP/err"
! grep -q 'legacy password' "$TMP/err"
jq '.connections.key.password = "ambiguous"' "$TMP/config.json" > "$TMP/new" && mv "$TMP/new" "$TMP/config.json"
if query >"$TMP/out" 2>"$TMP/err"; then exit 1; fi
grep -q 'specifies both' "$TMP/err"
for format in json csv; do
  bash "$ROOT/scripts/pg-schema.sh" --action list-connections --format "$format" --config "$TMP/config.json" >"$TMP/out" 2>"$TMP/err"
  grep -q literal "$TMP/err"
  grep -q environment "$TMP/err"
  ! grep -q legacy-secret "$TMP/out" "$TMP/err"
  if [[ "$format" == json ]]; then jq -e 'length == 4' "$TMP/out" >/dev/null; else python3 -c 'import csv,sys; assert len(list(csv.reader(sys.stdin))) == 5' < "$TMP/out"; fi
done
echo "Keychain credential tests passed"
