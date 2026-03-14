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

# Load NODE_ENV from .env file to determine environment
NODE_ENV=""
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env" 2>/dev/null || true
    set +a
    NODE_ENV="${NODE_ENV:-}"
fi

# Pull from remote in production; preserve local changes (stash uncommitted if any, then reapply).
# Only sync if NODE_ENV is set to "production"
if [ -d ".git" ]; then
    if [ "$NODE_ENV" = "production" ]; then
        echo -e "${BLUE}Production environment detected (NODE_ENV=production)${NC}"
        echo -e "${BLUE}Pulling from remote (local changes preserved)...${NC}"
        git fetch origin
        BRANCH=$(git rev-parse --abbrev-ref HEAD)
        STASHED=0
        if [ -n "$(git status --porcelain)" ]; then
            git stash push -u -m "deploy.sh: stash before pull"
            STASHED=1
        fi
        git pull origin "$BRANCH"
        if [ "$STASHED" = "1" ]; then
            git stash pop
        fi
        echo -e "${GREEN}✓ Repository updated from origin/$BRANCH (local changes preserved)${NC}"
        echo ""
    else
        echo -e "${YELLOW}Development environment detected (NODE_ENV=${NODE_ENV:-not set})${NC}"
        echo -e "${YELLOW}Skipping git sync - local changes will be preserved${NC}"
        echo ""
    fi
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         database-server - Production Deployment           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Service name (used by deploy-smart.sh) and display name for messages
SERVICE_NAME="database-server"
DISPLAY_NAME="$(echo "${SERVICE_NAME:0:1}" | tr 'a-z' 'A-Z')${SERVICE_NAME:1}"

# Detect nginx-microservice path
NGINX_MICROSERVICE_PATH=""

if [ -d "/home/statex/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="/home/statex/nginx-microservice"
elif [ -d "/home/alfares/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="/home/alfares/nginx-microservice"
elif [ -d "/home/belunga/nginx-microservice" ]; then
    NGINX_MICROSERVICE_PATH="/home/belunga/nginx-microservice"
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
    echo "  - /home/belunga/nginx-microservice"
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

# Timing and logging functions
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S.%3N'
}

get_timestamp_seconds() {
    date +%s.%N
}

# Phase timing tracking using temp file (works in subshells)
PHASE_TIMING_FILE=$(mktemp /tmp/deploy-phases-XXXXXX)
trap "rm -f $PHASE_TIMING_FILE" EXIT

start_phase() {
    local phase_name="$1"
    local timestamp=$(get_timestamp_seconds)
    echo "$phase_name|START|$timestamp" >> "$PHASE_TIMING_FILE"
    local msg="⏱️  PHASE START: $phase_name"
    echo -e "${YELLOW}$msg${NC}" >&2
}

end_phase() {
    local phase_name="$1"
    local timestamp=$(get_timestamp_seconds)
    echo "$phase_name|END|$timestamp" >> "$PHASE_TIMING_FILE"
    local start_line=$(grep "^${phase_name}|START|" "$PHASE_TIMING_FILE" | tail -1)
    if [ -n "$start_line" ]; then
        local start_time=$(echo "$start_line" | cut -d'|' -f3)
        local duration=$(awk "BEGIN {printf \"%.2f\", $timestamp - $start_time}")
        local msg="⏱️  PHASE END: $phase_name (duration: ${duration}s)"
        echo -e "${GREEN}$msg${NC}" >&2
    fi
}

print_phase_summary() {
    if [ ! -f "$PHASE_TIMING_FILE" ] || [ ! -s "$PHASE_TIMING_FILE" ]; then
        echo ""
        echo -e "${YELLOW}⚠️  No phase timing data available${NC}"
        echo ""
        return
    fi
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}📊 DEPLOYMENT PHASE TIMING SUMMARY${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    local current_phase=""
    local start_time=""
    local total_phase_time=0
    while IFS='|' read -r phase_name event timestamp; do
        if [ "$event" = "START" ]; then
            current_phase="$phase_name"
            start_time="$timestamp"
        elif [ "$event" = "END" ] && [ -n "$start_time" ] && [ -n "$current_phase" ]; then
            local duration=$(awk "BEGIN {printf \"%.2f\", $timestamp - $start_time}")
            total_phase_time=$(awk "BEGIN {printf \"%.2f\", $total_phase_time + $duration}")
            printf "  ${GREEN}%-45s${NC} ${YELLOW}%10.2fs${NC}\n" "$phase_name:" "$duration"
            current_phase=""
            start_time=""
        fi
    done < "$PHASE_TIMING_FILE"
    if [ "$(echo "$total_phase_time > 0" | bc 2>/dev/null || echo "0")" = "1" ]; then
        echo -e "${BLUE}────────────────────────────────────────────────────────────${NC}"
        printf "  ${GREEN}%-45s${NC} ${YELLOW}%10.2fs${NC}\n" "Total (all phases):" "$total_phase_time"
    fi
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Run deploy-smart.sh (handles: ensure-infrastructure, SSL cert, prepare-green, switch-traffic, etc.)
start_phase "Pre-deployment Setup"
echo -e "${YELLOW}Starting blue/green deployment...${NC}"
echo ""

cd "$NGINX_MICROSERVICE_PATH"
end_phase "Pre-deployment Setup"

START_TIME=$(get_timestamp_seconds)
"$DEPLOY_SCRIPT" "$SERVICE_NAME" 2>&1 | {
    build_started=0
    start_containers_started=0
    health_check_started=0
    while IFS= read -r line; do
        echo "$line"
        if echo "$line" | grep -qE "Phase 0:.*Infrastructure"; then start_phase "Phase 0: Infrastructure Check"
        elif echo "$line" | grep -qE "Phase 0 completed|✅ Phase 0 completed"; then end_phase "Phase 0: Infrastructure Check"
        elif echo "$line" | grep -qE "Phase 1:.*Preparing|Phase 1:.*Prepare"; then start_phase "Phase 1: Prepare Green Deployment"
        elif echo "$line" | grep -qE "Phase 1 completed|✅ Phase 1 completed"; then end_phase "Phase 1: Prepare Green Deployment"
        elif echo "$line" | grep -qE "Phase 2:.*Switching|Phase 2:.*Switch"; then start_phase "Phase 2: Switch Traffic to Green"
        elif echo "$line" | grep -qE "Phase 2 completed|✅ Phase 2 completed"; then end_phase "Phase 2: Switch Traffic to Green"
        elif echo "$line" | grep -qE "Phase 3:.*Monitoring|Phase 3:.*Monitor"; then start_phase "Phase 3: Monitor Health"
        elif echo "$line" | grep -qE "Phase 3 completed|✅ Phase 3 completed"; then end_phase "Phase 3: Monitor Health"
        elif echo "$line" | grep -qE "Phase 4:.*Verifying|Phase 4:.*Verify"; then start_phase "Phase 4: Verify HTTPS"
        elif echo "$line" | grep -qE "Phase 4 completed|✅ Phase 4 completed"; then end_phase "Phase 4: Verify HTTPS"
        elif echo "$line" | grep -qE "Phase 5:.*Cleaning|Phase 5:.*Cleanup"; then start_phase "Phase 5: Cleanup"
        elif echo "$line" | grep -qE "Phase 5 completed|✅ Phase 5 completed"; then end_phase "Phase 5: Cleanup"
        elif echo "$line" | grep -qE "Building containers|Image.*Building" && [ "$build_started" -eq 0 ]; then start_phase "Build Containers"; build_started=1
        elif echo "$line" | grep -qE "All services built|✅ All services built" && [ "$build_started" -eq 1 ]; then end_phase "Build Containers"; build_started=2
        elif echo "$line" | grep -qE "Starting containers|Container.*Starting" && [ "$start_containers_started" -eq 0 ]; then start_phase "Start Containers"; start_containers_started=1
        elif echo "$line" | grep -qE "Container.*Started|Waiting.*services to start" && [ "$start_containers_started" -eq 1 ]; then end_phase "Start Containers"; start_containers_started=2
        elif echo "$line" | grep -qE "Checking.*health|Health check" && [ "$health_check_started" -eq 0 ]; then start_phase "Health Checks"; health_check_started=1
        elif echo "$line" | grep -qE "health check passed|✅.*health" && [ "$health_check_started" -eq 1 ]; then end_phase "Health Checks"; health_check_started=2
        fi
    done
}
DEPLOY_EXIT_CODE=${PIPESTATUS[0]}
END_TIME=$(get_timestamp_seconds)
TOTAL_DURATION=$(awk "BEGIN {printf \"%.2f\", $END_TIME - $START_TIME}")

if [ $DEPLOY_EXIT_CODE -eq 0 ]; then
    TOTAL_DURATION_FORMATTED=$(awk "BEGIN {printf \"%.2f\", $TOTAL_DURATION}")
    print_phase_summary 2>&1
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
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Database server deployment completed successfully!               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${GREEN}Total deployment time: ${TOTAL_DURATION_FORMATTED}s${NC}"
    echo ""
    echo "database-server deployed. Check status with:"
    echo "  cd $NGINX_MICROSERVICE_PATH"
    echo "  ./scripts/status-all-services.sh"
    echo ""
    echo "Frontend: https://${DOMAIN}"
    exit 0
else
    TOTAL_DURATION_FORMATTED=$(awk "BEGIN {printf \"%.2f\", $TOTAL_DURATION}")
    echo ""
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}   ❌ Database server deployment failed! Failed after: ${TOTAL_DURATION_FORMATTED}s${NC}"
    echo -e "${RED}════════════════════════════════════════════════════════════${NC}"
    print_phase_summary
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║               ❌ Database server deployment failed!                  ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check service registry: $NGINX_MICROSERVICE_PATH/service-registry/$SERVICE_NAME.json"
    echo "  2. Verify DOMAIN in database-server/.env (e.g., database-server.statex.cz)"
    echo "  3. Ensure DNS points to server, port 80 accessible (Let's Encrypt)"
    echo "  4. Health check: cd $NGINX_MICROSERVICE_PATH && ./scripts/blue-green/health-check.sh $SERVICE_NAME"
    exit 1
fi
