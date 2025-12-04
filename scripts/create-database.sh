#!/bin/bash
# Create Database for a Project
# Usage: ./scripts/create-database.sh <project_name> <db_user> <db_password> [db_name]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load .env
if [ -f .env ]; then
    source .env
fi

PROJECT_NAME="$1"
DB_USER="$2"
DB_PASSWORD="$3"
DB_NAME="${4:-$PROJECT_NAME}"

if [ -z "$PROJECT_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ]; then
    echo "❌ Usage: ./scripts/create-database.sh <project_name> <db_user> <db_password> [db_name]"
    echo ""
    echo "Example:"
    echo "  ./scripts/create-database.sh crypto-ai-agent crypto crypto_pass crypto_ai_agent"
    exit 1
fi

# Check if database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "❌ Database server is not running"
    echo "💡 Start it with: ./scripts/start.sh"
    exit 1
fi

ADMIN_USER="${DB_SERVER_ADMIN_USER:-dbadmin}"

echo "📊 Creating database for project: $PROJECT_NAME"
echo "   Database: $DB_NAME"
echo "   User: $DB_USER"
echo ""

# Check if database already exists
if docker exec db-server-postgres psql -U "$ADMIN_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "⚠️  Database $DB_NAME already exists"
    read -p "Do you want to recreate it? This will DELETE all data! (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "❌ Cancelled"
        exit 0
    fi
    echo "🗑️  Dropping existing database..."
    docker exec db-server-postgres psql -U "$ADMIN_USER" -c "DROP DATABASE IF EXISTS \"$DB_NAME\";"
    docker exec db-server-postgres psql -U "$ADMIN_USER" -c "DROP USER IF EXISTS \"$DB_USER\";"
fi

# Create database
echo "📝 Creating database..."
docker exec -i db-server-postgres psql -U "$ADMIN_USER" <<-EOSQL
    CREATE DATABASE "$DB_NAME";
    CREATE USER "$DB_USER" WITH ENCRYPTED PASSWORD '$DB_PASSWORD';
    GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$DB_USER";
    ALTER DATABASE "$DB_NAME" OWNER TO "$DB_USER";
EOSQL

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Database created successfully!"
    # Load DB_SERVER_PORT from .env if available
    DB_SERVER_PORT=${DB_SERVER_PORT:-5432}
    
    echo ""
    echo "📍 Connection Information:"
    echo "   Hostname: db-server-postgres (on nginx-network)"
    echo "   Port: ${DB_SERVER_PORT} (configured in database-server/.env)"
    echo "   Database: $DB_NAME"
    echo "   User: $DB_USER"
    echo "   Password: $DB_PASSWORD"
    echo ""
    echo "🔗 Connection String:"
    echo "   postgresql+psycopg://$DB_USER:$DB_PASSWORD@db-server-postgres:${DB_SERVER_PORT}/$DB_NAME"
    echo ""
else
    echo "❌ Failed to create database"
    exit 1
fi

