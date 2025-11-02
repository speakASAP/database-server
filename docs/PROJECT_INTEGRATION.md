# Project Integration Guide

How to integrate your project with the centralized Database Server.

## Prerequisites

1. Database Server is running (`./scripts/start.sh`)
2. Database created for your project (`./scripts/create-database.sh`)
3. Project containers can access `nginx-network`

## Step 1: Create Database

```bash
cd /path/to/database-server

# Create database for your project
./scripts/create-database.sh crypto-ai-agent crypto crypto_pass crypto_ai_agent
```

This creates:

- Database: `crypto_ai_agent`
- User: `crypto`
- Password: `crypto_pass`

## Step 2: Update Project Configuration

### Update `.env` File

```bash
# In your project's .env file

# Database connection (use centralized server)
DATABASE_URL=postgresql+psycopg://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent

# Redis connection (use centralized server)
REDIS_URL=redis://db-server-redis:6379/0

# Remove any local database configuration
# POSTGRES_DB=...  # Remove this
# POSTGRES_USER=... # Remove this
# POSTGRES_PASSWORD=... # Remove this
```

### Update `docker-compose.yml`

Remove database and Redis services from your project's compose file:

```yaml
# REMOVE these services:
# postgres:
#   image: postgres:15
#   ...
#
# redis:
#   image: redis:7
#   ...

# KEEP only application services:
services:
  backend:
    # ...
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - REDIS_URL=${REDIS_URL}
    networks:
      - nginx-network  # Must be on same network!

  frontend:
    # ...
    networks:
      - nginx-network

networks:
  nginx-network:
    external: true  # Use external network
```

## Step 3: Verify Connection

### Test Database Connection

```bash
# From your project container
docker exec crypto-ai-backend python -c "
import os
print('DATABASE_URL:', os.getenv('DATABASE_URL'))
"

# Test connection
docker exec crypto-ai-backend python -c "
import psycopg
conn = psycopg.connect(os.getenv('DATABASE_URL'))
print('Connected successfully!')
"
```

### Test Redis Connection

```bash
# From your project container
docker exec crypto-ai-backend python -c "
import redis
r = redis.from_url(os.getenv('REDIS_URL'))
print('Redis connected:', r.ping())
"
```

## Step 4: Update Blue/Green Deployments

If using blue/green deployments:

### Remove from `docker-compose.blue.yml` and `docker-compose.green.yml`

```yaml
# REMOVE:
# postgres:
#   ...
# redis:
#   ...

# KEEP only:
services:
  backend:
    environment:
      - DATABASE_URL=postgresql+psycopg://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent
      - REDIS_URL=redis://db-server-redis:6379/0
    networks:
      - nginx-network
```

### Update `ensure-infrastructure.sh`

The script should check for `db-server-postgres` instead of project-specific postgres:

```bash
# Check if centralized database server is running
if ! docker ps --format "{{.Names}}" | grep -q "^db-server-postgres$"; then
    echo "Database server is not running"
    echo "Start it with: cd /path/to/database-server && ./scripts/start.sh"
    exit 1
fi
```

## Step 5: Application Code Changes

No code changes needed if using environment variables!

Your existing code should work:

```python
# This will automatically use the centralized server
import os
DATABASE_URL = os.getenv("DATABASE_URL")
REDIS_URL = os.getenv("REDIS_URL")
```

## Migration from Local Database

If migrating from local database to centralized server:

### 1. Backup Local Database

```bash
# In your project directory
docker compose exec postgres pg_dump -U crypto crypto_ai_agent > backup.sql
```

### 2. Create Database on Centralized Server

```bash
cd /path/to/database-server
./scripts/create-database.sh crypto-ai-agent crypto crypto_pass crypto_ai_agent
```

### 3. Restore Backup

```bash
# Copy backup to database-server
cp backup.sql /path/to/database-server/backups/

# Restore
cd /path/to/database-server
./scripts/restore-database.sh crypto-ai-agent backups/backup.sql crypto_ai_agent
```

### 4. Update Configuration

Update `.env` and `docker-compose.yml` as shown in Step 2.

### 5. Restart Project

```bash
cd /path/to/your-project
docker compose down
docker compose up -d
```

### 6. Verify

Test that your application works with the centralized database.

## Connection String Formats

### PostgreSQL

```text
postgresql+psycopg://[user]:[password]@db-server-postgres:[port]/[database]

Examples:
- SQLAlchemy: postgresql+psycopg://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent
- Direct: postgresql://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent
```

### Redis

```text
redis://[host]:[port]/[db_number]

Examples:
- Default: redis://db-server-redis:6379/0
- DB 1: redis://db-server-redis:6379/1
- With password: redis://:password@db-server-redis:6379/0
```

## Troubleshooting

### Connection Refused

**Problem**: `psycopg.OperationalError: connection refused`

**Solutions**:

1. Check database server is running: `docker ps | grep db-server-postgres`
2. Check network: `docker network inspect nginx-network`
3. Verify container is on network: `docker network inspect nginx-network | grep your-project`

### Database Does Not Exist

**Problem**: `database "crypto_ai_agent" does not exist`

**Solution**: Create database:

```bash
cd /path/to/database-server
./scripts/create-database.sh crypto-ai-agent crypto crypto_pass crypto_ai_agent
```

### Authentication Failed

**Problem**: `password authentication failed`

**Solutions**:

1. Verify credentials match database server
2. Check user exists: `./scripts/list-databases.sh`
3. Recreate user if needed

### Network Issues

**Problem**: Cannot connect from project container

**Solutions**:

1. Ensure project is on `nginx-network`
2. Verify network exists: `docker network ls | grep nginx-network`
3. Connect container: `docker network connect nginx-network your-container`

## Best Practices

1. **Use Environment Variables**
   - Never hardcode connection strings
   - Use `.env` files for configuration

2. **Separate Credentials**
   - Each project should have its own database user
   - Never share credentials between projects

3. **Connection Pooling**
   - Use connection pooling in your application
   - Configure appropriate pool sizes

4. **Health Checks**
   - Implement health checks that verify database connectivity
   - Handle connection failures gracefully

5. **Backups**
   - Regular backups of your project database
   - Test restore procedures

6. **Monitoring**
   - Monitor database connections
   - Track query performance
   - Set up alerts for failures

## Example: Complete Integration

### Project Structure

```text
crypto-ai-agent/
├── .env
│   ├── DATABASE_URL=postgresql+psycopg://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent
│   └── REDIS_URL=redis://db-server-redis:6379/0
├── docker-compose.yml
│   ├── backend (connects to db-server-postgres)
│   └── frontend
└── ...
```

### Connection Flow

```text
crypto-ai-backend container
    │
    │ (via nginx-network)
    │
    ▼
db-server-postgres:5432
    │
    └──> crypto_ai_agent database
```

This architecture provides:

- ✅ Centralized database management
- ✅ Resource efficiency
- ✅ Easy scalability
- ✅ Project isolation
- ✅ Simplified backups
