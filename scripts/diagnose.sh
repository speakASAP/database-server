#!/bin/bash
# Diagnostic script for database-server deployment
# Run on prod: ssh statex, cd ~/database-server && ./scripts/diagnose.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="database-server.statex.cz"

# Detect nginx-microservice
NGINX_PATH=""
for p in "/home/statex/nginx-microservice" "/home/alfares/nginx-microservice" "$HOME/nginx-microservice" "$(dirname "$PROJECT_ROOT")/nginx-microservice"; do
    if [ -d "$p" ]; then
        NGINX_PATH="$p"
        break
    fi
done

echo "=== database-server Diagnostic ==="
echo ""

# 1. Service registry
echo "1. Service Registry"
if [ -n "$NGINX_PATH" ] && [ -f "$NGINX_PATH/service-registry/database-server.json" ]; then
    echo "   Registry exists: $NGINX_PATH/service-registry/database-server.json"
    echo "   Domain: $(jq -r '.domain // "not set"' "$NGINX_PATH/service-registry/database-server.json")"
    echo "   Services: $(jq -r '.services | keys | join(", ")' "$NGINX_PATH/service-registry/database-server.json" 2>/dev/null || echo "N/A")"
else
    echo "   Registry NOT FOUND - deploy-smart auto-creates it. Run deploy.sh"
fi
echo ""

# 2. Containers
echo "2. Docker Containers"
for c in db-server-postgres db-server-redis db-server-frontend db-server-frontend-blue db-server-frontend-green; do
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${c}$"; then
        echo "   OK  $c (running)"
    else
        echo "   --  $c (not running)"
    fi
done
echo ""

# 3. Nginx config
echo "3. Nginx Config for $DOMAIN"
if [ -n "$NGINX_PATH" ]; then
    CONFD="$NGINX_PATH/nginx/conf.d"
    if [ -L "$CONFD/${DOMAIN}.conf" ]; then
        TARGET=$(readlink "$CONFD/${DOMAIN}.conf")
        echo "   Symlink: $CONFD/${DOMAIN}.conf -> $TARGET"
    elif [ -f "$CONFD/${DOMAIN}.conf" ]; then
        echo "   Config: $CONFD/${DOMAIN}.conf (direct file)"
    else
        echo "   NOT FOUND - no nginx config for $DOMAIN"
    fi
    # Blue/green configs
    BLUE_GREEN="$CONFD/blue-green"
    if [ -f "$BLUE_GREEN/${DOMAIN}.blue.conf" ]; then
        echo "   Blue config exists"
    else
        echo "   Blue config NOT FOUND"
    fi
    if [ -f "$BLUE_GREEN/${DOMAIN}.green.conf" ]; then
        echo "   Green config exists"
    else
        echo "   Green config NOT FOUND"
    fi
else
    echo "   nginx-microservice not found"
fi
echo ""

# 4. SSL Certificate
echo "4. SSL Certificate"
CERT_DIR="$NGINX_PATH/certificates/${DOMAIN}"
if [ -n "$NGINX_PATH" ] && [ -d "$CERT_DIR" ]; then
    FULLCHAIN="$CERT_DIR/fullchain.pem"
    if [ -f "$FULLCHAIN" ]; then
        DAYS=$(openssl x509 -enddate -noout -in "$FULLCHAIN" 2>/dev/null | cut -d= -f2)
        echo "   Certificate exists, expires: $DAYS"
        openssl x509 -in "$FULLCHAIN" -noout -subject 2>/dev/null | sed 's/^/   Subject: /'
    else
        echo "   fullchain.pem NOT FOUND"
    fi
else
    echo "   Certificate dir NOT FOUND: $CERT_DIR"
fi
echo ""

# 5. Local connectivity
echo "5. Local Connectivity"
# Try frontend containers
for port in 3390 3391 3392; do
    if curl -sf --connect-timeout 2 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
        echo "   OK  http://127.0.0.1:${port}/health"
    else
        echo "   --  http://127.0.0.1:${port}/health (no response)"
    fi
done
# Nginx HTTPS
if curl -sfk --connect-timeout 2 "https://127.0.0.1:443" -H "Host: $DOMAIN" -o /dev/null 2>/dev/null; then
    echo "   OK  nginx responds for $DOMAIN (localhost)"
else
    echo "   --  nginx may not respond for $DOMAIN"
fi
echo ""

# 6. Recent logs
echo "6. Recent Logs"
echo "   Frontend (blue):"
docker logs db-server-frontend-blue --tail 5 2>&1 | sed 's/^/      /' || echo "      (container not running)"
echo "   Frontend (green):"
docker logs db-server-frontend-green --tail 5 2>&1 | sed 's/^/      /' || echo "      (container not running)"
echo "   Nginx (if running):"
docker logs nginx-microservice-nginx-1 --tail 5 2>&1 | sed 's/^/      /' 2>/dev/null || docker logs nginx-nginx-1 --tail 5 2>&1 | sed 's/^/      /' 2>/dev/null || echo "      (container name unknown)"
echo ""

echo "=== End diagnostic ==="
