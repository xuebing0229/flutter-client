#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8765}"

echo "[1/3] Health"
curl -fsS "$BASE_URL/health"
echo

echo "[2/3] Service"
systemctl is-active --quiet adventure-license
echo "adventure-license: active"

echo "[3/3] Database integrity"
DB_PATH="${LICENSE_DB_PATH:-/var/lib/adventure-license/license.db}"
sqlite3 "$DB_PATH" 'PRAGMA integrity_check;' | grep -qx 'ok'
echo "sqlite integrity: ok"
