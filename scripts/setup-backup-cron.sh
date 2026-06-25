#!/bin/bash
# Setup automated daily in-cluster database backups.
# Usage:
#   DB_BACKUP_DIR=/path/on/backup/disk ./scripts/setup-backup-cron.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

BACKUP_DIR="${DB_BACKUP_DIR:-$PROJECT_ROOT/backups}"
RETENTION_DAYS="${DB_BACKUP_RETENTION_DAYS:-14}"
LOG_DIR="$PROJECT_ROOT/logs"
CRON_JOB="0 2 * * * DB_BACKUP_DIR=$BACKUP_DIR DB_BACKUP_RETENTION_DAYS=$RETENTION_DAYS cd $PROJECT_ROOT && $PROJECT_ROOT/scripts/backup-all-databases.sh >> $LOG_DIR/backup.log 2>&1"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

TMP_CRON="$(mktemp)"
trap 'rm -f "$TMP_CRON"' EXIT

crontab -l 2>/dev/null > "$TMP_CRON" || true
if grep -q "$PROJECT_ROOT/scripts/backup-all-databases.sh" "$TMP_CRON"; then
    grep -v "$PROJECT_ROOT/scripts/backup-all-databases.sh" "$TMP_CRON" > "$TMP_CRON.next" || true
    mv "$TMP_CRON.next" "$TMP_CRON"
fi

printf '%s\n' "$CRON_JOB" >> "$TMP_CRON"
crontab "$TMP_CRON"

echo "Backup cron job installed:"
crontab -l | grep "$PROJECT_ROOT/scripts/backup-all-databases.sh"
