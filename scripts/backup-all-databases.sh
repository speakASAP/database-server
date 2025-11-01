#!/bin/bash
# Backup All Databases
# Usage: ./scripts/backup-all-databases.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load .env
if [ -f .env ]; then
    source .env
fi

ADMIN_USER="${DB_SERVER_ADMIN_USER:-dbadmin}"
BACKUP_DIR="$PROJECT_ROOT/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Check if database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "❌ Database server is not running"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "📦 Creating backups of all databases..."
echo ""

# Get list of databases (excluding system databases)
DATABASES=$(docker exec db-server-postgres psql -U "$ADMIN_USER" -d postgres -t -c \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")

BACKUP_COUNT=0
FAILED_COUNT=0

for DB_NAME in $DATABASES; do
    DB_NAME=$(echo "$DB_NAME" | tr -d ' ')
    if [ -z "$DB_NAME" ]; then
        continue
    fi
    
    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql"
    
    echo "📦 Backing up: $DB_NAME"
    
    if docker exec db-server-postgres pg_dump -U "$ADMIN_USER" -F p "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null; then
        # Compress backup
        gzip "$BACKUP_FILE"
        BACKUP_FILE="${BACKUP_FILE}.gz"
        
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "   ✅ $DB_NAME backed up ($BACKUP_SIZE)"
        BACKUP_COUNT=$((BACKUP_COUNT + 1))
    else
        echo "   ❌ Failed to backup $DB_NAME"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
if [ $BACKUP_COUNT -gt 0 ]; then
    echo "✅ Successfully backed up $BACKUP_COUNT database(s)"
fi

if [ $FAILED_COUNT -gt 0 ]; then
    echo "⚠️  Failed to backup $FAILED_COUNT database(s)"
    exit 1
fi

echo ""
echo "💾 Backup location: $BACKUP_DIR"
echo "📅 Timestamp: $TIMESTAMP"
echo ""
echo "💡 Use './scripts/restore-database.sh <project_name> <backup_file>' to restore"

