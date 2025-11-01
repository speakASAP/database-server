#!/bin/bash
# Start Database Server
# Usage: ./scripts/start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🚀 Starting Database Server..."

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "⚠️  Warning: .env file not found"
    echo "📋 Copying .env.example to .env"
    cp .env.example .env
    echo "⚠️  Please edit .env with your configuration before continuing"
    exit 1
fi

# Check if docker compose is available
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed or not in PATH"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Error: Docker Compose is not installed or not in PATH"
    exit 1
fi

# Check if nginx-network exists
if ! docker network inspect nginx-network &> /dev/null; then
    echo "📡 Creating nginx-network..."
    docker network create nginx-network || true
fi

# Start containers
echo "🐘 Starting PostgreSQL..."
echo "🔴 Starting Redis..."

if docker compose up -d; then
    echo ""
    echo "✅ Database Server started successfully!"
    echo ""
    echo "📊 Checking status..."
    sleep 3
    docker compose ps
    
    echo ""
    echo "🔍 Health checks:"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
    
    echo ""
    echo "📍 Connection Info:"
    echo "   PostgreSQL: db-server-postgres:5432 (on nginx-network)"
    echo "   Redis: db-server-redis:6379 (on nginx-network)"
    echo ""
    echo "💡 Use './scripts/status.sh' to check detailed status"
else
    echo "❌ Failed to start Database Server"
    echo "📋 Check logs: docker compose logs"
    exit 1
fi

