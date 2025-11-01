# Database Server Microservice

Centralized database server serving multiple projects. One PostgreSQL container hosts multiple databases (one per project), and one Redis container for caching.

## Features

- ✅ **Centralized PostgreSQL Server** - Single PostgreSQL instance managing multiple project databases
- ✅ **Centralized Redis Server** - Shared Redis instance for caching
- ✅ **Automatic Database Creation** - Scripts to create databases for new projects
- ✅ **Backup Management** - Automated and manual backup scripts
- ✅ **Health Monitoring** - Health checks and status monitoring
- ✅ **Zero Downtime** - Database server independent of project deployments
- ✅ **Docker Network Integration** - Connects to nginx-network for service discovery

## Architecture

```
database-server/
├── postgres (container)
│   ├── crypto_ai_agent (database)
│   ├── project2 (database)
│   └── project3 (database)
├── redis (container)
│   └── Multiple databases (0-15)
```

**Benefits:**
- Single PostgreSQL installation
- Efficient resource usage
- Centralized backup management
- Easy database administration
- Project isolation (separate databases)

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url> database-server
cd database-server
cp .env.example .env
# Edit .env with your configuration
```

### 2. Start Database Server

```bash
./scripts/start.sh
```

### 3. Create Database for Project

```bash
./scripts/create-database.sh crypto-ai-agent crypto crypto_pass
```

### 4. Check Status

```bash
./scripts/status.sh
```

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Database Server Admin
DB_SERVER_ADMIN_USER=dbadmin
DB_SERVER_ADMIN_PASSWORD=change_this_secret

# PostgreSQL
DB_SERVER_PORT=5432
POSTGRES_INITDB_ARGS="-E UTF8 --locale=C"

# Redis
REDIS_SERVER_PORT=6379
REDIS_APPENDONLY=no
REDIS_MAXMEMORY=256mb
REDIS_MAXMEMORY_POLICY=allkeys-lru

# Network
NGINX_NETWORK_NAME=nginx-network
```

## Usage

### Start/Stop Infrastructure

```bash
# Start database server
./scripts/start.sh

# Stop database server
./scripts/stop.sh

# Restart database server
./scripts/restart.sh

# Check status
./scripts/status.sh
```

### Database Management

```bash
# Create a new database for a project
./scripts/create-database.sh <project_name> <db_user> <db_password>

# List all databases
./scripts/list-databases.sh

# Backup a database
./scripts/backup-database.sh <project_name>

# Restore a database
./scripts/restore-database.sh <project_name> <backup_file>

# Drop a database (use with caution!)
./scripts/drop-database.sh <project_name>
```

### Connection Examples

**From Project Containers:**

```bash
# PostgreSQL connection string
DATABASE_URL=postgresql+psycopg://crypto:crypto_pass@db-server-postgres:5432/crypto_ai_agent

# Redis connection string
REDIS_URL=redis://db-server-redis:6379/0
```

**Hostnames:**
- PostgreSQL: `db-server-postgres` (on nginx-network)
- Redis: `db-server-redis` (on nginx-network)

## Project Integration

### Adding a New Project

1. **Create Database:**
   ```bash
   ./scripts/create-database.sh my-project myuser mypassword
   ```

2. **Update Project Configuration:**
   ```yaml
   # In project's docker-compose.yml
   environment:
     - DATABASE_URL=postgresql+psycopg://myuser:mypassword@db-server-postgres:5432/my_project
     - REDIS_URL=redis://db-server-redis:6379/0
   networks:
     - nginx-network  # Must connect to same network
   ```

3. **Verify Connection:**
   ```bash
   docker exec my-project-backend python -c "import os; print(os.getenv('DATABASE_URL'))"
   ```

## Backup & Restore

### Automatic Backups

Daily backups are configured via cron or systemd timer (see `scripts/setup-backup-cron.sh`).

### Manual Backup

```bash
# Backup specific database
./scripts/backup-database.sh crypto-ai-agent

# Backup all databases
./scripts/backup-all-databases.sh
```

### Restore

```bash
./scripts/restore-database.sh crypto-ai-agent backups/crypto-ai-agent_2025-01-15.sql
```

## Monitoring

### Health Checks

```bash
# Check PostgreSQL health
docker exec db-server-postgres pg_isready

# Check Redis health
docker exec db-server-redis redis-cli ping
```

### Logs

```bash
# PostgreSQL logs
docker logs db-server-postgres

# Redis logs
docker logs db-server-redis

# Follow logs
docker logs -f db-server-postgres
```

### Status Script

```bash
./scripts/status.sh
# Shows:
# - Container status
# - Database list
# - Connection info
# - Disk usage
```

## Network Requirements

The database server must be on the same Docker network as your projects:

```bash
# Network should already exist (created by nginx-microservice)
docker network inspect nginx-network

# If not, create it:
docker network create nginx-network
```

## Security

### Production Checklist

- [ ] Change `DB_SERVER_ADMIN_PASSWORD` in `.env`
- [ ] Use strong passwords for project databases
- [ ] Restrict PostgreSQL port to localhost only (default)
- [ ] Restrict Redis port to localhost only (default)
- [ ] Enable SSL connections (future enhancement)
- [ ] Set up firewall rules
- [ ] Regular security updates
- [ ] Backup encryption (future enhancement)

### Access Control

- Admin user (`dbadmin`) has full access to all databases
- Project users have access only to their own database
- No external port exposure (containers access via Docker network)

## Directory Structure

```
database-server/
├── docker-compose.yml          # Main compose file
├── .env.example                # Environment template
├── .env                        # Environment config (gitignored)
├── README.md                   # This file
├── docs/                       # Documentation
│   ├── ARCHITECTURE.md
│   ├── BACKUP_RESTORE.md
│   └── PROJECT_INTEGRATION.md
├── scripts/                    # Management scripts
│   ├── start.sh               # Start server
│   ├── stop.sh                # Stop server
│   ├── restart.sh             # Restart server
│   ├── status.sh              # Status check
│   ├── create-database.sh     # Create project database
│   ├── list-databases.sh      # List all databases
│   ├── backup-database.sh     # Backup database
│   ├── restore-database.sh   # Restore database
│   ├── drop-database.sh       # Drop database
│   └── db-server/             # Internal scripts
│       ├── init-databases.sh  # Auto-init script
│       └── redis.conf         # Redis config
├── backups/                    # Backup storage
│   └── .gitkeep
└── logs/                       # Log storage
    └── .gitkeep
```

## Troubleshooting

### Database Server Won't Start

```bash
# Check logs
docker logs db-server-postgres
docker logs db-server-redis

# Check network
docker network inspect nginx-network

# Check ports
netstat -an | grep 5432
```

### Connection Issues

```bash
# Test from another container
docker run --rm --network nginx-network postgres:15 \
  psql -h db-server-postgres -U crypto -d crypto_ai_agent -c "SELECT 1;"
```

### Permission Issues

```bash
# Grant permissions
docker exec -it db-server-postgres psql -U dbadmin -c \
  "GRANT ALL PRIVILEGES ON DATABASE crypto_ai_agent TO crypto;"
```

## Future Enhancements

- [ ] PostgreSQL replication (primary/standby)
- [ ] Automated backup with retention policy
- [ ] Backup encryption
- [ ] SSL/TLS connections
- [ ] Monitoring dashboard
- [ ] Performance metrics
- [ ] Connection pooling
- [ ] Database migration tools
- [ ] Redis cluster mode
- [ ] Multi-version PostgreSQL support

## Contributing

1. Follow the existing code structure
2. Add tests for new scripts
3. Update documentation
4. Use meaningful commit messages

## License

[Your License Here]

## Support

For issues or questions:
- Check logs: `docker logs db-server-postgres`
- Check status: `./scripts/status.sh`
- Review documentation in `docs/`

