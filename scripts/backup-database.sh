#!/bin/bash
# Backup one PostgreSQL database from the in-cluster database server.
# Usage: ./scripts/backup-database.sh <project_name> [db_name]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

PROJECT_NAME="${1:-}"
DB_NAME="${2:-$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: ./scripts/backup-database.sh <project_name> [db_name]"
    exit 1
fi

K8S_NAMESPACE="${K8S_NAMESPACE:-statex-apps}"
POSTGRES_DEPLOYMENT="${POSTGRES_DEPLOYMENT:-db-server-postgres}"
BACKUP_DIR="${DB_BACKUP_DIR:-$PROJECT_ROOT/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$BACKUP_DIR/$TIMESTAMP"
BACKUP_FILE="$RUN_DIR/${DB_NAME}_${TIMESTAMP}.sql.gz"

mkdir -p "$RUN_DIR"
chmod 700 "$RUN_DIR"

if ! kubectl -n "$K8S_NAMESPACE" get "deploy/$POSTGRES_DEPLOYMENT" >/dev/null 2>&1; then
    echo "ERROR: PostgreSQL deployment $K8S_NAMESPACE/$POSTGRES_DEPLOYMENT not found"
    exit 1
fi

if ! kubectl -n "$K8S_NAMESPACE" exec "deploy/$POSTGRES_DEPLOYMENT" -- sh -lc \
    'psql -U "$POSTGRES_USER" -d postgres -At -c "select datname from pg_database where datistemplate = false;"' \
    | grep -Fxq "$DB_NAME"; then
    echo "ERROR: database not found: $DB_NAME"
    exit 1
fi

echo "Backing up PostgreSQL database $DB_NAME"

kubectl -n "$K8S_NAMESPACE" exec "deploy/$POSTGRES_DEPLOYMENT" -- sh -lc \
    "pg_dump -U \"\$POSTGRES_USER\" -F p \"$DB_NAME\"" \
    | gzip -9 > "$BACKUP_FILE"

gzip -t "$BACKUP_FILE"

echo "Backup created: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | awk '{print $1}'))"
