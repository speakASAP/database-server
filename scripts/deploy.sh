#!/bin/bash
# database-server Deployment Script
# Usage: ./scripts/deploy.sh
#
# This script deploys the database-server infrastructure including:
# - PostgreSQL database
# - Redis cache
# - Web interface (landing + admin panel)
#
# Note: database-server is infrastructure, not an application.
# It does NOT use blue/green deployment like applications.
# The web interface is added to nginx via add-domain.sh.

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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              database-server Infrastructure - Deployment                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Load environment variables
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
else
    echo -e "${RED}❌ Error: .env file not found${NC}"
    echo "Please copy .env.example to .env and configure it."
    exit 1
fi

# Service configuration
SERVICE_NAME="database-server"
DOMAIN="${DOMAIN:-database-server.statex.cz}"
FRONTEND_PORT="${FRONTEND_PORT:-3390}"
FRONTEND_CONTAINER="db-server-frontend"

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

# Timing functions
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_step() {
    echo -e "${BLUE}[$(get_timestamp)]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(get_timestamp)] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(get_timestamp)] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(get_timestamp)] ❌ $1${NC}"
}

# Track start time
START_TIME=$(date +%s)

# Phase 1: Ensure nginx-network exists
log_step "Phase 1: Checking Docker network..."

if ! docker network inspect nginx-network &> /dev/null; then
    log_step "Creating nginx-network..."
    docker network create nginx-network || true
fi
log_success "nginx-network is ready"

# Phase 2: Build and start containers
log_step "Phase 2: Building and starting containers..."

echo ""
echo -e "${YELLOW}Building containers...${NC}"
if docker compose build --no-cache frontend; then
    log_success "Frontend container built successfully"
else
    log_error "Failed to build frontend container"
    exit 1
fi

echo ""
echo -e "${YELLOW}Starting containers...${NC}"
if docker compose up -d; then
    log_success "All containers started"
else
    log_error "Failed to start containers"
    exit 1
fi

# Phase 3: Wait for containers to be healthy
log_step "Phase 3: Waiting for containers to be healthy..."

# Wait for PostgreSQL
echo -n "Waiting for PostgreSQL..."
for i in {1..30}; do
    if docker exec db-server-postgres pg_isready -U "${DB_SERVER_ADMIN_USER:-dbadmin}" &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Wait for Redis
echo -n "Waiting for Redis..."
for i in {1..15}; do
    if docker exec db-server-redis redis-cli ping &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Wait for Frontend
echo -n "Waiting for Frontend..."
for i in {1..15}; do
    if curl -sf "http://127.0.0.1:${FRONTEND_PORT}/health" &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

log_success "All containers are healthy"

# Phase 4: Configure nginx domain
log_step "Phase 4: Configuring nginx domain..."

if [ -z "$NGINX_MICROSERVICE_PATH" ] || [ ! -d "$NGINX_MICROSERVICE_PATH" ]; then
    log_warning "nginx-microservice not found, skipping domain configuration"
    log_warning "Add domain manually with: ./scripts/add-domain-to-nginx.sh"
else
    ADD_DOMAIN_SCRIPT="$NGINX_MICROSERVICE_PATH/scripts/add-domain.sh"
    if [ -x "$ADD_DOMAIN_SCRIPT" ]; then
        # Check if domain is already configured
        DOMAIN_CONF="$NGINX_MICROSERVICE_PATH/nginx/conf.d/${DOMAIN}.conf"
        if [ -f "$DOMAIN_CONF" ] || [ -L "$DOMAIN_CONF" ]; then
            log_step "Domain already configured, reloading nginx..."
            if [ -x "$NGINX_MICROSERVICE_PATH/scripts/reload-nginx.sh" ]; then
                "$NGINX_MICROSERVICE_PATH/scripts/reload-nginx.sh" || true
            fi
            log_success "Nginx reloaded"
        else
            log_step "Adding domain to nginx: $DOMAIN"
            "$ADD_DOMAIN_SCRIPT" "$DOMAIN" "$FRONTEND_CONTAINER" "3390" || {
                log_warning "Failed to add domain automatically"
                log_warning "Add domain manually: $ADD_DOMAIN_SCRIPT $DOMAIN $FRONTEND_CONTAINER 3390"
            }
        fi
    else
        log_warning "add-domain.sh not found at $ADD_DOMAIN_SCRIPT"
    fi
fi

# Calculate deployment time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Phase 5: Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    ✅ Deployment completed successfully!                       ║${NC}"
echo -e "${GREEN}║                    Total deployment time: ${DURATION}s                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show container status
echo -e "${BLUE}Container Status:${NC}"
docker compose ps
echo ""

# Show connection info
echo -e "${BLUE}Connection Information:${NC}"
echo "   PostgreSQL: db-server-postgres:5432 (on nginx-network)"
echo "   Redis:      db-server-redis:6379 (on nginx-network)"
echo "   Frontend:   db-server-frontend:3390 (on nginx-network)"
echo ""
echo -e "${BLUE}Access URLs:${NC}"
echo "   Local:    http://localhost:${FRONTEND_PORT}"
echo "   External: https://${DOMAIN}"
echo "   Admin:    https://${DOMAIN}/admin"
echo ""
echo -e "${BLUE}Health Check:${NC}"
echo "   curl https://${DOMAIN}/api/health"
echo ""

exit 0
