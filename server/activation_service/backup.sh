#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${LICENSE_DB_PATH:-/var/lib/adventure-license/license.db}"
BACKUP_DIR="${LICENSE_BACKUP_DIR:-/var/backups/adventure-license}"
RETENTION_DAYS="${LICENSE_BACKUP_RETENTION_DAYS:-14}"

if [[ ! -f "$DB_PATH" ]]; then
  echo "Database not found: $DB_PATH" >&2
  exit 1
fi

install -d -o adventure-license -g adventure-license -m 0750 "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$BACKUP_DIR/.license-$timestamp.sqlite.tmp"
dest="$BACKUP_DIR/license-$timestamp.sqlite"

sqlite3 "$DB_PATH" ".timeout 15000" ".backup '$tmp'"
chown adventure-license:adventure-license "$tmp"
chmod 0640 "$tmp"
mv "$tmp" "$dest"

find "$BACKUP_DIR" -type f -name 'license-*.sqlite' -mtime "+$RETENTION_DAYS" -delete

echo "Backup created: $dest"
