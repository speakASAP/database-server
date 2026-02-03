#!/bin/bash
# database-server Deployment Script
# Usage: ./scripts/deploy.sh
#
# Deploys database-server using nginx-microservice blue/green deployment system.
# This handles: postgres+redis (via ensure-infrastructure), frontend (blue/green),
# SSL certificate (Let's Encrypt), and nginx configuration.
#
# Same flow as statex, notifications-microservice, etc.

set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Deploy only code from repository: sync with remote (discard local changes on server)
if [ -d ".git" ]; then
    echo -e "${BLUE}Syncing with remote repository...${NC}"
    git fetch origin
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    git reset --hard "origin/$BRANCH"
    echo -e "${GREEN}✓ Repository synced to origin/$BRANCH${NC}"
    echo ""
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              database-server - Production Deployment                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Service name (used by deploy-smart.sh)
SERVICE_NAME="database-server"

# Detect nginx-microservice path
NGINX_MICROSERVICE_PATH=""

if [ -d "/home/statex/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="/home/statex/nginx-microservice"
elif [ -d "/home/alfares/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="/home/alfares/nginx-microservice"
elif [ -d "$HOME/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="$HOME/nginx-microservice"
elif [ -d "$(dirname "$PROJECT_ROOT")/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="$(dirname "$PROJECT_ROOT")/nginx-microservice"
elif [ -d "$PROJECT_ROOT/../nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="$(cd "$PROJECT_ROOT/../nginx-microservice" && pwd)"
fi

# Validate nginx-microservice path
if [ -z "$NGINX_MICROSERVICE_PATH" ] || [ ! -d "$NGINX_MICROSERVICE_PATH" ]; then
    echo -e "${RED}❌ Error: nginx-microservice not found${NC}"
    echo ""
    echo "Please ensure nginx-microservice is installed in one of these locations:"
    echo "  - /home/statex/nginx-microservice"
    echo "  - /home/alfares/nginx-microservice"
    echo "  - $HOME/nginx-microservice"
    echo "  - $(dirname "$PROJECT_ROOT")/nginx-microservice (sibling directory)"
    echo ""
    echo "Or set NGINX_MICROSERVICE_PATH environment variable:"
    echo "  export NGINX_MICROSERVICE_PATH=/path/to/nginx-microservice"
    exit 1
fi

# Check if deploy-smart.sh exists
DEPLOY_SCRIPT="$NGINX_MICROSERVICE_PATH/scripts/blue-green/deploy-smart.sh"
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo -e "${RED}❌ Error: deploy-smart.sh not found at $DEPLOY_SCRIPT${NC}"
    exit 1
fi

if [ ! -x "$DEPLOY_SCRIPT" ]; then
    echo -e "${YELLOW}⚠️  Making deploy-smart.sh executable...${NC}"
    chmod +x "$DEPLOY_SCRIPT"
fi

echo -e "${GREEN}✅ Found nginx-microservice at: $NGINX_MICROSERVICE_PATH${NC}"
echo -e "${GREEN}✅ Deploying service: $SERVICE_NAME${NC}"
echo ""

# Validate docker-compose files exist
echo -e "${BLUE}Validating docker-compose files...${NC}"
if [ ! -f "$PROJECT_ROOT/docker-compose.blue.yml" ]; then
    echo -e "${RED}❌ Error: docker-compose.blue.yml not found in $PROJECT_ROOT${NC}"
    exit 1
fi
if [ ! -f "$PROJECT_ROOT/docker-compose.green.yml" ]; then
    echo -e "${RED}❌ Error: docker-compose.green.yml not found in $PROJECT_ROOT${NC}"
    exit 1
fi

if ! docker compose -f "$PROJECT_ROOT/docker-compose.blue.yml" config --quiet 2>/dev/null; then
    echo -e "${RED}❌ Error: docker-compose.blue.yml is invalid${NC}"
    exit 1
fi
if ! docker compose -f "$PROJECT_ROOT/docker-compose.green.yml" config --quiet 2>/dev/null; then
    echo -e "${RED}❌ Error: docker-compose.green.yml is invalid${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker-compose files are valid${NC}"
echo ""

# Run deploy-smart.sh (handles: ensure-infrastructure, SSL cert, prepare-green, switch-traffic, etc.)
echo -e "${YELLOW}Starting blue/green deployment...${NC}"
echo ""

cd "$NGINX_MICROSERVICE_PATH"

if "$DEPLOY_SCRIPT" "$SERVICE_NAME"; then
    # Ensure real Let's Encrypt certificate (never serve self-signed to users)
    DOMAIN=$(grep -E "^DOMAIN=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" | sed 's|^https\?://||' | sed 's|/$||' || true)
    DOMAIN="${DOMAIN:-database-server.statex.cz}"
    CERT_DIR="$NGINX_MICROSERVICE_PATH/certificates/${DOMAIN}"
    FULLCHAIN="$CERT_DIR/fullchain.pem"

    if [ -f "$FULLCHAIN" ]; then
        CERT_DAYS=$(openssl x509 -enddate -noout -in "$FULLCHAIN" 2>/dev/null | cut -d= -f2)
        CERT_EPOCH=$(date -d "$CERT_DAYS" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$CERT_DAYS" +%s 2>/dev/null || echo "0")
        CURRENT_EPOCH=$(date +%s)
        DAYS_VALID=$(( (CERT_EPOCH - CURRENT_EPOCH) / 86400 ))

        if [ "${DAYS_VALID:-0}" -lt 30 ]; then
            echo -e "${YELLOW}Requesting Let's Encrypt certificate (no self-signed)...${NC}"
            if [ -f "$NGINX_MICROSERVICE_PATH/.env" ]; then
                set -a
                source "$NGINX_MICROSERVICE_PATH/.env" 2>/dev/null || true
                set +a
            fi
            EMAIL="${CERTBOT_EMAIL:-admin@example.com}"
            if docker compose -f "$NGINX_MICROSERVICE_PATH/docker-compose.yml" run --rm certbot /scripts/request-cert.sh "$DOMAIN" "$EMAIL"; then
                "$NGINX_MICROSERVICE_PATH/scripts/reload-nginx.sh" 2>/dev/null || true
                echo -e "${GREEN}✅ Let's Encrypt certificate installed${NC}"
            else
                echo -e "${RED}❌ Let's Encrypt certificate request failed. Deployment aborted - no self-signed certs.${NC}"
                echo "Ensure: DNS for $DOMAIN points here, port 80 accessible from internet."
                exit 1
            fi
        fi
    fi

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         ✅ Deployment completed successfully!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "database-server deployed. Check status with:"
    echo "  cd $NGINX_MICROSERVICE_PATH"
    echo "  ./scripts/status-all-services.sh"
    echo ""
    echo "Frontend: https://${DOMAIN}"
    exit 0
else
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                 ❌ Deployment failed!                      ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check service registry: $NGINX_MICROSERVICE_PATH/service-registry/$SERVICE_NAME.json"
    echo "  2. Verify DOMAIN in database-server/.env (e.g., database-server.statex.cz)"
    echo "  3. Ensure DNS points to server, port 80 accessible (Let's Encrypt)"
    echo "  4. Health check: cd $NGINX_MICROSERVICE_PATH && ./scripts/blue-green/health-check.sh $SERVICE_NAME"
    exit 1
fi
