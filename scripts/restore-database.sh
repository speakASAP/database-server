#!/bin/bash
# Restore Database from Backup
# Usage: ./scripts/restore-database.sh <project_name> <backup_file> [db_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load .env
if [ -f .env ]; then
    source .env
fi

PROJECT_NAME="$1"
BACKUP_FILE="$2"
DB_NAME="${3:-$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ] || [ -z "$BACKUP_FILE" ]; then
    echo "❌ Usage: ./scripts/restore-database.sh <project_name> <backup_file> [db_name]"
    echo ""
    echo "Example:"
    echo "  ./scripts/restore-database.sh crypto-ai-agent backups/crypto_ai_agent_20250115.sql.gz"
    exit 1
fi

ADMIN_USER="${DB_SERVER_ADMIN_USER:-dbadmin}"

# Check if database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "❌ Database server is not running"
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "❌ Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "⚠️  WARNING: This will OVERWRITE the database $DB_NAME"
echo "   Backup file: $BACKUP_FILE"
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cancelled"
    exit 0
fi

# Drop existing database if it exists
echo "🗑️  Dropping existing database..."
docker exec db-server-postgres psql -U "$ADMIN_USER" -c "DROP DATABASE IF EXISTS \"$DB_NAME\";" || true

# Create database
echo "📝 Creating database..."
docker exec db-server-postgres psql -U "$ADMIN_USER" -c "CREATE DATABASE \"$DB_NAME\";"

# Restore backup
echo "📦 Restoring backup..."

if [[ "$BACKUP_FILE" == *.gz ]]; then
    # Compressed backup
    gunzip -c "$BACKUP_FILE" | docker exec -i db-server-postgres psql -U "$ADMIN_USER" "$DB_NAME"
else
    # Uncompressed backup
    docker exec -i db-server-postgres psql -U "$ADMIN_USER" "$DB_NAME" < "$BACKUP_FILE"
fi

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Database restored successfully!"
else
    echo "❌ Restore failed"
    exit 1
fi

