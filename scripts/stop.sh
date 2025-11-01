#!/bin/bash
# Stop Database Server
# Usage: ./scripts/stop.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "🛑 Stopping Database Server..."

# Confirmation prompt for safety
read -p "⚠️  This will stop the database server. Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cancelled"
    exit 0
fi

if docker compose down; then
    echo ""
    echo "✅ Database Server stopped successfully"
    echo ""
    echo "⚠️  Note: Database data is preserved in Docker volumes"
    echo "💡 Use './scripts/start.sh' to start again"
else
    echo "❌ Failed to stop Database Server"
    exit 1
fi

