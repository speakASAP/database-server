#!/bin/bash
# Add Database Server Web Domain to Nginx
# Usage: ./scripts/add-domain-to-nginx.sh
#
# This script adds the database-server web interface domain to nginx-microservice.
# It uses the DOMAIN variable from .env and registers it with nginx.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Load .env
if [ -f .env ]; then
    set -a
    source .env
    set +a
fi

DOMAIN="${DOMAIN:-database-server.statex.cz}"
FRONTEND_PORT="${FRONTEND_PORT:-3390}"
CONTAINER_NAME="db-server-frontend"

# Determine nginx-microservice path
if [ -n "$NGINX_MICROSERVICE_PATH" ]; then
    NGINX_PATH="$NGINX_MICROSERVICE_PATH"
elif [ -d "../nginx-microservice" ]; then
    NGINX_PATH="$(cd ../nginx-microservice && pwd)"
elif [ -d "/home/statex/nginx-microservice" ]; then
    NGINX_PATH="/home/statex/nginx-microservice"
else
    echo "❌ nginx-microservice not found"
    echo "   Set NGINX_MICROSERVICE_PATH in .env or ensure it's in a sibling directory"
    exit 1
fi

echo "📡 Adding domain to nginx"
echo "   Domain: $DOMAIN"
echo "   Container: $CONTAINER_NAME"
echo "   Port: $FRONTEND_PORT"
echo "   Nginx path: $NGINX_PATH"
echo ""

# Check if frontend container is running
if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠️  Frontend container not running. Start database-server first:"
    echo "   ./scripts/start.sh"
    exit 1
fi

# Add domain to nginx using nginx-microservice script
if [ -x "$NGINX_PATH/scripts/add-domain.sh" ]; then
    "$NGINX_PATH/scripts/add-domain.sh" "$DOMAIN" "$CONTAINER_NAME" "$FRONTEND_PORT"
else
    echo "❌ nginx-microservice add-domain.sh not found or not executable"
    echo "   Expected: $NGINX_PATH/scripts/add-domain.sh"
    exit 1
fi

echo ""
echo "✅ Domain added successfully!"
echo "   Access: https://$DOMAIN"
echo "   Admin:  https://$DOMAIN/admin"
