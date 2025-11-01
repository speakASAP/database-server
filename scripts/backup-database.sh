#!/bin/bash
# Backup Database
# Usage: ./scripts/backup-database.sh <project_name> [db_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load .env
if [ -f .env ]; then
    source .env
fi

PROJECT_NAME="$1"
DB_NAME="${2:-$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ]; then
    echo "❌ Usage: ./scripts/backup-database.sh <project_name> [db_name]"
    exit 1
fi

ADMIN_USER="${DB_SERVER_ADMIN_USER:-dbadmin}"
BACKUP_DIR="$PROJECT_ROOT/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql"

# Check if database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "❌ Database server is not running"
    exit 1
fi

# Check if database exists
if ! docker exec db-server-postgres psql -U "$ADMIN_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "❌ Database $DB_NAME does not exist"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo "📦 Creating backup of database: $DB_NAME"
echo "   Destination: $BACKUP_FILE"
echo ""

# Create backup
if docker exec db-server-postgres pg_dump -U "$ADMIN_USER" -F p "$DB_NAME" > "$BACKUP_FILE"; then
    # Compress backup
    gzip "$BACKUP_FILE"
    BACKUP_FILE="${BACKUP_FILE}.gz"
    
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    
    echo "✅ Backup created successfully!"
    echo "   File: $BACKUP_FILE"
    echo "   Size: $BACKUP_SIZE"
    echo ""
    echo "💡 Use './scripts/restore-database.sh $PROJECT_NAME $BACKUP_FILE' to restore"
else
    echo "❌ Backup failed"
    exit 1
fi

