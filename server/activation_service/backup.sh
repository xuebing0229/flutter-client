#!/usr/bin/env bash
set -euo pipefail

DB_PATH="${LICENSE_DB_PATH:-/var/lib/adventure-license/license.db}"
BACKUP_DIR="${LICENSE_BACKUP_DIR:-/var/backups/adventure-license}"
RETENTION_DAYS="${LICENSE_BACKUP_RETENTION_DAYS:-14}"

if [[ ! -f "$DB_PATH" ]]; then
  echo "Database not found: $DB_PATH" >&2
  exit 1
fi

# Backups are recovery material, not runtime data. Keep them outside the
# service account's write access so a compromised API process cannot erase or
# replace the copies that would be needed to recover the ledger.
install -d -o root -g root -m 0700 "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$BACKUP_DIR/.license-$timestamp.sqlite.tmp"
dest="$BACKUP_DIR/license-$timestamp.sqlite"

sqlite3 "$DB_PATH" ".timeout 15000" ".backup '$tmp'"
chown root:root "$tmp"
chmod 0600 "$tmp"
mv "$tmp" "$dest"

find "$BACKUP_DIR" -type f -name 'license-*.sqlite' -mtime "+$RETENTION_DAYS" -delete

echo "Backup created: $dest"
