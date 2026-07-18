#!/bin/bash
# Diagnostic script for database-server deployment
# Run on prod: ssh alfares, cd ~/database-server && ./scripts/diagnose.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="database-server.alfares.cz"

# Check Kubernetes deployment status
echo "1. Kubernetes Deployment Status"
if kubectl get deployment database-server -n statex-apps &>/dev/null 2>&1; then
    echo "   Deployment found in statex-apps namespace"
    kubectl get deployment database-server -n statex-apps -o wide 2>/dev/null || echo "   Could not retrieve deployment status"
else
    echo "   Deployment not found in Kubernetes"
fi
echo ""

# Legacy Docker detection (for backwards compatibility)
NGINX_PATH=""
for p in "~/Documents/Github/nginx-microservice" "/home/alfares/nginx-microservice" "$HOME/nginx-microservice" "$(dirname "$PROJECT_ROOT")/nginx-microservice"; do
    if [ -d "$p" ]; then
        NGINX_PATH="$p"
        break
    fi
done

if [ -n "$NGINX_PATH" ]; then
    echo "WARNING: Detected legacy nginx-microservice at $NGINX_PATH"
    echo "   nginx-microservice has been archived as of 2026-06-17"
    echo "   Consider migrating to Kubernetes deployments"
    echo ""
fi
echo "=== database-server Diagnostic ==="
echo ""

# 2. Database Service Status (Kubernetes)
echo "2. Database Services (Kubernetes)"
if kubectl get svc db-server-postgres -n statex-apps &>/dev/null 2>&1; then
    echo "   PostgreSQL service: OK"
    kubectl get svc db-server-postgres -n statex-apps -o wide 2>/dev/null | tail -1
else
    echo "   PostgreSQL service: NOT FOUND"
fi

if kubectl get svc db-server-redis -n statex-apps &>/dev/null 2>&1; then
    echo "   Redis service: OK"
    kubectl get svc db-server-redis -n statex-apps -o wide 2>/dev/null | tail -1
else
    echo "   Redis service: NOT FOUND"
fi
echo ""

# Legacy: Service registry (archived)
echo "3. Service Registry (Legacy - nginx-microservice)"
echo "2. Docker Containers"
for c in db-server-postgres db-server-redis db-server-frontend db-server-frontend-blue db-server-frontend-green; do
    if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${c}$"; then
        echo "   OK  $c (running)"
    else
        echo "   --  $c (not running)"
    fi
done
echo ""

# 5. Nginx Configuration (Legacy - archived)
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

# 6. SSL Certificates (Kubernetes via cert-manager)
echo "Checking Kubernetes SSL certificates..."
kubectl get secret -n statex-apps -l app=database-server 2>/dev/null | grep tls || echo "   No TLS secrets found for database-server"

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
# Legacy nginx logs (deprecated)
echo ""

echo "=== End diagnostic ==="
