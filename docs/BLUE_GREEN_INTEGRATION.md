# Database Server - Blue/Green Deployment Integration

## Overview

The database-server provides shared PostgreSQL and Redis infrastructure for blue/green deployments. This document explains how database-server integrates with blue/green deployment systems.

## Architecture

```text
database-server/
├── postgres (db-server-postgres)
│   └── Shared across all blue/green deployments
├── redis (db-server-redis)
│   └── Shared cache for all deployments
└── Data persistence
    ├── /data/db-server/postgres
    └── Redis data (in-memory or persisted)
```

## Integration with Blue/Green Deployments

### Automatic Detection

Blue/green deployment scripts (in nginx-microservice) automatically detect database-server:

1. **First Check**: Looks for `docker-compose.infrastructure.yml` in service directory
2. **Fallback**: Checks for shared `db-server-postgres` and `db-server-redis` containers
3. **Auto-Start**: Can start database-server if configured, or reports error if missing

### Container Names

The deployment scripts look for these specific container names:

- **PostgreSQL**: `db-server-postgres`
- **Redis**: `db-server-redis`

These names are defined in `database-server/docker-compose.yml`.

### Network Requirement

Both database-server and application containers must be on the same Docker network:

- **Network Name**: `nginx-network`
- **Configuration**: Both services use `external: true` for this network

## Connection Strings

Applications connect to database-server using Docker service names:

### PostgreSQL

```bash
# Connection string format
postgresql://username:password@db-server-postgres:5432/database_name

# Environment variable example
DATABASE_URL=postgresql://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent
```

### Redis

```bash
# Connection string format
redis://db-server-redis:6379/0

# Environment variable example
REDIS_URL=redis://db-server-redis:6379/0
```

## Deployment Scenarios

### Scenario 1: Fresh Start

**Setup:**

```bash
# 1. Start database-server first
cd /path/to/database-server
./scripts/start.sh

# 2. Verify it's running
./scripts/status.sh

# 3. Run blue/green deployment
cd /path/to/nginx-microservice
./scripts/blue-green/deploy.sh crypto-ai-agent
```

**What Happens:**

- Deployment script detects `db-server-postgres` is running
- Skips infrastructure start
- Proceeds with blue/green deployment

### Scenario 2: Database-Server Restart

**Situation:** Database-server was stopped and needs restart during deployment.

**Solution:**

```bash
# Restart database-server (non-interactive)
cd /path/to/database-server
docker compose down
docker compose up -d

# Wait for health checks
sleep 10
docker compose ps

# Continue with deployment
cd /path/to/nginx-microservice
./scripts/blue-green/deploy.sh crypto-ai-agent
```

**Note:** Database-server restart script (`restart.sh`) requires interactive confirmation. For automation, use `docker compose down/up`.

### Scenario 3: Shared Infrastructure Failure

**Situation:** Database-server containers are unhealthy or stopped.

**Detection:**

```bash
# Check database-server status
cd /path/to/database-server
./scripts/status.sh

# Check container health
docker ps | grep db-server
```

**Recovery:**

```bash
# Restart database-server
docker compose restart

# If restart doesn't work, full restart
docker compose down
docker compose up -d

# Verify health
docker compose ps
docker exec db-server-postgres pg_isready
docker exec db-server-redis redis-cli ping
```

## Blue/Green Deployment Impact

### During Blue/Green Deployment

**What Stays Running:**

- ✅ `db-server-postgres` (always)
- ✅ `db-server-redis` (always)
- ✅ Active color containers (blue or green)

**What Gets Changed:**

- 🔄 Application containers (backend, frontend) switch between blue/green
- 🔄 Nginx upstream configuration updates

**What Gets Stopped:**

- ❌ Old color containers (after successful deployment)
- ❌ Never: Database or Redis containers

### Data Consistency

**Important:** Both blue and green containers connect to the **same database and Redis instances**. This ensures:

- ✅ **Data consistency** - No data loss during deployments
- ✅ **Session continuity** - Redis cache shared across deployments
- ✅ **Single source of truth** - One database for all deployments

**Warning:** Blue and green should use the same database credentials and connection strings.

## Health Checks

### Database-Server Health Checks

The deployment scripts verify database-server is healthy:

```bash
# PostgreSQL health check
docker exec db-server-postgres pg_isready -U dbadmin

# Redis health check
docker exec db-server-redis redis-cli ping
```

### Application Health Checks

Applications should check database connectivity:

```bash
# Backend health endpoint should verify DB connection
curl http://crypto-ai-backend-blue:8100/health
curl http://crypto-ai-backend-green:8100/health
```

## Backup and Restore

### During Blue/Green Deployments

**Backup Strategy:**

1. Database backups are independent of blue/green deployments
2. Backup before major deployments (recommended)
3. Restore procedures don't affect blue/green containers

```bash
# Backup database before deployment
cd /path/to/database-server
./scripts/backup-database.sh crypto-ai-agent

# Run deployment
cd /path/to/nginx-microservice
./scripts/blue-green/deploy.sh crypto-ai-agent

# Restore if needed (doesn't affect running containers)
./scripts/restore-database.sh crypto-ai-agent backups/crypto-ai-agent_YYYY-MM-DD.sql
```

### Restore During Deployment

**Scenario:** Need to restore database during active deployment.

**Procedure:**

1. Both blue and green may be connected to database
2. Restore is safe (stops current connections temporarily)
3. Applications will reconnect automatically

```bash
# Restore database
./scripts/restore-database.sh crypto-ai-agent backup_file.sql

# Applications automatically reconnect
# No need to restart containers
```

## Troubleshooting

### Issue: "Shared infrastructure is not running"

**Error Message:**

```text
ERROR Infrastructure compose file not found: docker-compose.infrastructure.yml
And shared database-server is not running
```

**Solution:**

```bash
# Start database-server
cd /path/to/database-server
./scripts/start.sh

# Verify containers are running
docker ps | grep db-server

# Retry deployment
cd /path/to/nginx-microservice
./scripts/blue-green/deploy.sh crypto-ai-agent
```

### Issue: "Cannot connect to database"

**Error:** Applications can't connect to `db-server-postgres`.

**Check:**

```bash
# Verify database-server is running
docker ps | grep db-server-postgres

# Check network connectivity
docker exec crypto-ai-backend-blue ping -c 2 db-server-postgres

# Verify credentials
docker exec db-server-postgres psql -U dbadmin -l
```

**Fix:**

```bash
# Restart database-server if needed
cd /path/to/database-server
docker compose restart

# Check application environment variables
docker exec crypto-ai-backend-blue env | grep DATABASE
```

### Issue: "Database locked" or "Too many connections"

**Error:** Database connection limits reached.

**Investigation:**

```bash
# Check active connections
docker exec db-server-postgres psql -U dbadmin -c "SELECT count(*) FROM pg_stat_activity;"

# Check max connections
docker exec db-server-postgres psql -U dbadmin -c "SHOW max_connections;"
```

**Solution:**

- Close unused connections
- Increase `max_connections` in PostgreSQL config if needed
- Ensure blue and green don't create excessive connections

### Issue: "Redis connection failed"

**Error:** Applications can't connect to Redis.

**Check:**

```bash
# Verify Redis is running
docker ps | grep db-server-redis

# Test Redis connectivity
docker exec db-server-redis redis-cli ping

# Check from application container
docker exec crypto-ai-backend-blue ping -c 2 db-server-redis
```

**Fix:**

```bash
# Restart Redis if needed
docker compose restart redis

# Or restart entire database-server
cd /path/to/database-server
docker compose restart
```

## Best Practices

### 1. Start Database-Server First

Always ensure database-server is running before deployments:

```bash
# Check status
cd /path/to/database-server
./scripts/status.sh

# Start if needed
./scripts/start.sh

# Then deploy
cd /path/to/nginx-microservice
./scripts/blue-green/deploy.sh crypto-ai-agent
```

### 2. Monitor Database During Deployments

```bash
# Watch database connections
watch -n 2 'docker exec db-server-postgres psql -U dbadmin -c "SELECT count(*) FROM pg_stat_activity;"'

# Monitor database size
docker exec db-server-postgres psql -U dbadmin -c "SELECT pg_size_pretty(pg_database_size(\"current_database()\"));"
```

### 3. Backup Before Major Deployments

```bash
# Create backup
cd /path/to/database-server
./scripts/backup-database.sh crypto-ai-agent

# Store backup timestamp
echo "Backup created: $(date)" >> deployment_log.txt

# Proceed with deployment
```

### 4. Connection Pooling

Both blue and green containers should use connection pooling:

- **Recommended**: SQLAlchemy connection pool (backend)
- **Max Connections**: Configure based on deployment needs
- **Pool Size**: Typically 5-10 connections per container

### 5. Never Stop Database During Deployment

**DO NOT:**

```bash
# ❌ DON'T stop database during deployment
docker stop db-server-postgres
```

**DO:**

```bash
# ✅ Only restart if absolutely necessary (and not during deployment)
docker compose restart postgres
```

## Configuration Reference

### Docker Compose Configuration

```yaml
services:
  postgres:
    container_name: db-server-postgres  # Required name for detection
    networks:
      - nginx-network  # Required network
    restart: always  # Auto-restart on failure
  
  redis:
    container_name: db-server-redis  # Required name for detection
    networks:
      - nginx-network  # Required network
    restart: always  # Auto-restart on failure
```

### Environment Variables

Applications need these environment variables:

```bash
# PostgreSQL
DATABASE_URL=postgresql://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent
DB_HOST=db-server-postgres
DB_PORT=5432

# Redis
REDIS_URL=redis://db-server-redis:6379/0
REDIS_HOST=db-server-redis
REDIS_PORT=6379
```

## Related Documentation

- [Database Server README](../README.md)
- [Blue/Green Deployment Guide](../crypto-ai-agent/docs/BLUE_GREEN_DEPLOYMENT_GUIDE.md)
- [Nginx Microservice Blue/Green Guide](../nginx-microservice/docs/BLUE_GREEN_DEPLOYMENT.md)
