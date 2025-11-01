#!/bin/bash
# Drop Database (Use with Caution!)
# Usage: ./scripts/drop-database.sh <project_name> [db_name]

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
    echo "❌ Usage: ./scripts/drop-database.sh <project_name> [db_name]"
    exit 1
fi

ADMIN_USER="${DB_SERVER_ADMIN_USER:-dbadmin}"

# Check if database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "❌ Database server is not running"
    exit 1
fi

# Check if database exists
if ! docker exec db-server-postgres psql -U "$ADMIN_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "⚠️  Database $DB_NAME does not exist"
    exit 0
fi

echo "⚠️  ⚠️  ⚠️  WARNING: This will PERMANENTLY DELETE the database $DB_NAME ⚠️  ⚠️  ⚠️"
echo "   All data will be lost and cannot be recovered!"
echo ""
read -p "Type 'DELETE' to confirm: " confirm

if [ "$confirm" != "DELETE" ]; then
    echo "❌ Cancelled"
    exit 0
fi

# Get database user (try to find it)
DB_USER=$(docker exec db-server-postgres psql -U "$ADMIN_USER" -t -c \
    "SELECT usename FROM pg_user WHERE usename = '$PROJECT_NAME' OR usename LIKE '${PROJECT_NAME}_%';" | tr -d ' ' | head -1)

echo "🗑️  Dropping database: $DB_NAME"

# Drop database
docker exec db-server-postgres psql -U "$ADMIN_USER" -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"

# Drop user if it exists and matches project name pattern
if [ -n "$DB_USER" ]; then
    echo "🗑️  Dropping user: $DB_USER"
    docker exec db-server-postgres psql -U "$ADMIN_USER" -c "DROP USER IF EXISTS \"$DB_USER\";"
fi

echo ""
echo "✅ Database dropped successfully"

