#!/bin/bash
# Database Server Status
# Usage: ./scripts/status.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "📊 Database Server Status"
echo "================================"
echo ""

# Check if containers are running
if ! docker compose ps | grep -q "db-server"; then
    echo "⚠️  Database Server is not running"
    echo "💡 Use './scripts/start.sh' to start"
    exit 0
fi

echo "🐳 Container Status:"
docker compose ps
echo ""

# PostgreSQL Status
echo "🐘 PostgreSQL Status:"
if docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    if docker exec db-server-postgres pg_isready -U ${DB_SERVER_ADMIN_USER:-dbadmin} > /dev/null 2>&1; then
        echo "   ✅ PostgreSQL is healthy"
        
        # List databases
        echo ""
        echo "   📋 Databases:"
        docker exec db-server-postgres psql -U ${DB_SERVER_ADMIN_USER:-dbadmin} -d ${DB_SERVER_INIT_DB:-postgres} -t -c \
            "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" | \
            sed 's/^/      - /' | sed 's/ *$//'
        
        # Show disk usage
        echo ""
        echo "   💾 Disk Usage:"
        docker exec db-server-postgres psql -U ${DB_SERVER_ADMIN_USER:-dbadmin} -d ${DB_SERVER_INIT_DB:-postgres} -t -c \
            "SELECT pg_size_pretty(pg_database_size('postgres'));" | sed 's/^/      Total: /'
    else
        echo "   ⚠️  PostgreSQL is running but not healthy"
    fi
else
    echo "   ❌ PostgreSQL container is not running"
fi
echo ""

# Redis Status
echo "🔴 Redis Status:"
if docker ps --format "{{.Names}}" | grep -q "^db-server-redis$"; then
    if docker exec db-server-redis redis-cli ping > /dev/null 2>&1; then
        echo "   ✅ Redis is healthy"
        
        # Show info
        echo ""
        echo "   📊 Redis Info:"
        docker exec db-server-redis redis-cli info server | grep -E "redis_version|used_memory_human" | \
            sed 's/^/      /'
    else
        echo "   ⚠️  Redis is running but not healthy"
    fi
else
    echo "   ❌ Redis container is not running"
fi
echo ""

# Frontend Status
echo "🌐 Frontend Status:"
if docker ps --format "{{.Names}}" | grep -q "^db-server-frontend$"; then
    if curl -sf http://127.0.0.1:${FRONTEND_PORT:-3390}/health > /dev/null 2>&1; then
        echo "   ✅ Frontend is healthy"
    else
        echo "   ⚠️  Frontend is running but not responding"
    fi
else
    echo "   ❌ Frontend container is not running"
fi
echo ""

# Network Status
echo "🔗 Network Status:"
if docker network inspect nginx-network &> /dev/null; then
    echo "   ✅ nginx-network exists"
    echo "   📋 Connected containers:"
    docker network inspect nginx-network --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | \
        grep -E "db-server" | sed 's/^/      - /'
else
    echo "   ⚠️  nginx-network not found"
fi
echo ""

# Load ports from .env if available
if [ -f .env ]; then
  source .env
fi
DB_SERVER_PORT=${DB_SERVER_PORT:-5432}
REDIS_SERVER_PORT=${REDIS_SERVER_PORT:-6379}
FRONTEND_PORT=${FRONTEND_PORT:-3390}
DOMAIN=${DOMAIN:-database-server.statex.cz}

# Connection Info
echo "📍 Connection Information:"
echo "   PostgreSQL:"
echo "      Hostname: db-server-postgres (on nginx-network)"
echo "      Port: ${DB_SERVER_PORT}"
echo "      Local: 127.0.0.1:${DB_SERVER_PORT}"
echo ""
echo "   Redis:"
echo "      Hostname: db-server-redis (on nginx-network)"
echo "      Port: ${REDIS_SERVER_PORT}"
echo "      Local: 127.0.0.1:${REDIS_SERVER_PORT}"
echo ""
echo "   Frontend:"
echo "      Hostname: db-server-frontend (on nginx-network)"
echo "      Port: 3390 (container) / ${FRONTEND_PORT} (host)"
echo "      Local: http://127.0.0.1:${FRONTEND_PORT}"
echo "      External: https://${DOMAIN}"
echo ""

