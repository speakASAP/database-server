#!/bin/bash
# List All Databases
# Usage: ./scripts/list-databases.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load .env
if [ -f .env ]; then
    source .env
fi

ADMIN_USER="${DB_SERVER_ADMIN_USER:-dbadmin}"

# Check if database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "❌ Database server is not running"
    echo "💡 Start it with: ./scripts/start.sh"
    exit 1
fi

echo "📊 Databases in Database Server:"
echo "================================"
echo ""

# List all databases with sizes
docker exec db-server-postgres psql -U "$ADMIN_USER" -c "
SELECT
    datname AS \"Database\",
    pg_size_pretty(pg_database_size(datname)) AS \"Size\",
    (SELECT count(*) FROM pg_stat_activity WHERE datname = d.datname) AS \"Connections\"
FROM pg_database d
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;
" -t

echo ""
echo "💡 Use './scripts/create-database.sh' to create a new database"

