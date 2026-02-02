# Database Server Microservice

Centralized database server serving multiple projects. One PostgreSQL container hosts multiple databases (one per project), and one Redis container for caching.

## ⚠️ Production-Ready Service

This service is **production-ready** and should **NOT** be modified directly.

- **✅ Allowed**: Use scripts from this service's directory
- **❌ NOT Allowed**: Modify code, configuration, or infrastructure directly
- **⚠️ Permission Required**: If you need to modify something, **ask for permission first**

## Features

- ✅ **Centralized PostgreSQL Server** - Single PostgreSQL instance managing multiple project databases
- ✅ **Centralized Redis Server** - Shared Redis instance for caching
- ✅ **Automatic Database Creation** - Scripts to create databases for new projects
- ✅ **Backup Management** - Automated and manual backup scripts
- ✅ **Health Monitoring** - Health checks and status monitoring
- ✅ **Web Interface** - Landing page and admin panel with auth-microservice login, database statistics and health
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

## 🔌 Port Configuration

**Infrastructure Service** (shared by all applications)

| Service | Host Port | Container Port | .env Variable | Description | Access Method |
| ------- | --------- | -------------- | ------------- | ----------- | ------------- |
| **PostgreSQL** | `${DB_SERVER_PORT:-5432}` | `5432` | `DB_SERVER_PORT` | Shared PostgreSQL database | Docker: `db-server-postgres:5432`, SSH: `localhost:${DB_SERVER_PORT:-5432}` |
| **Redis** | `${REDIS_SERVER_PORT:-6379}` | `6379` | `REDIS_SERVER_PORT` | Shared Redis cache | Docker: `db-server-redis:6379`, SSH: `localhost:${REDIS_SERVER_PORT:-6379}` |
| **Frontend** | `${FRONTEND_PORT:-3390}` | `3390` | `FRONTEND_PORT` | Admin panel & landing page | Docker: `db-server-frontend:3390`, External: `https://${DOMAIN}` |

**Note**:

- All ports are configured in `database-server/.env`. The values shown are defaults.
- PostgreSQL and Redis ports are exposed on `127.0.0.1` only (localhost) for security
- Frontend is accessible externally via nginx at `https://${DOMAIN}` (configured in `.env`)
- All applications connect via Docker network hostnames (`db-server-postgres`, `db-server-redis`, `db-server-frontend`)
- SSH tunnel access available for local development: `ssh -L ${DB_SERVER_PORT:-5432}:localhost:${DB_SERVER_PORT:-5432} host-server`

## Frontend (Web Interface)

The database server includes a frontend with:

- **Landing page** (`/`) - Marketing page for potential customers explaining features
- **Admin panel** (`/admin`) - Login with auth-microservice credentials to view:
  - PostgreSQL health status and version
  - Redis health status, version, and memory usage
  - List of all databases with sizes and active connections
  - Real-time health checks

### Access URLs

| Environment | URL |
| ----------- | --- |
| **Production** | `https://${DOMAIN}` (e.g., `https://database-server.statex.cz`) |
| **Local Docker** | `http://localhost:${FRONTEND_PORT:-3390}` |
| **Internal Docker** | `http://db-server-frontend:3390` |

### API Endpoints

| Endpoint | Auth | Description |
| -------- | ---- | ----------- |
| `GET /health` | No | Frontend container health check |
| `GET /api/health` | No | PostgreSQL + Redis health status (public) |
| `GET /api/stats` | Yes (JWT) | Full database statistics (requires auth-microservice token) |
| `POST /auth/*` | - | Proxied to auth-microservice for login/validate/refresh |

### Environment Variables

```bash
# Frontend port (default: 3390)
FRONTEND_PORT=3390

# Auth microservice URL for admin login
AUTH_SERVICE_URL=http://auth-microservice:3370

# Domain for external access (used by nginx)
DOMAIN=database-server.statex.cz
```

## Quick Start

### 1. Clone and Setup

```bash
git clone <repository-url> database-server
cd database-server
cp .env.example .env
# Edit .env with your configuration
```

### 2. Deploy (Recommended)

```bash
./scripts/deploy.sh
```

This will:

- Build and start all containers (PostgreSQL, Redis, Web)
- Wait for health checks to pass
- Configure nginx domain automatically

### 3. Or Start Manually

```bash
./scripts/start.sh
```

### 4. Create Database for Project

```bash
./scripts/create-database.sh crypto-ai-agent crypto crypto_pass
```

### 5. Check Status

```bash
./scripts/status.sh
```

## Deployment

### Production Deployment

```bash
# Connect to production server
ssh statex

# Pull latest changes
cd ~/database-server && git pull

# Deploy (builds, starts, configures nginx)
./scripts/deploy.sh
```

### What `deploy.sh` Does

Uses `nginx-microservice/scripts/blue-green/deploy-smart.sh` (same as statex, auth-microservice):

1. **Phase 0**: Ensure infrastructure – starts postgres+redis (if needed), ensures SSL certificate
2. **Phase 1**: Prepare green – builds and starts frontend (blue or green)
3. **Phase 2**: Switch traffic to new deployment
4. **Phase 3**: Monitor health
5. **Phase 4**: Verify HTTPS URL
6. **Phase 5**: Cleanup old deployment

**SSL Certificate**: Handled by deploy-smart (ensure-infrastructure). Ensure:

- DNS for `database-server.statex.cz` points to your server
- Port 80 is accessible (required for Let's Encrypt validation)

### Manual Domain Configuration

If deploy-smart fails, use add-domain for standalone setup:

```bash
# Add domain to nginx manually (when not using deploy-smart)
./scripts/add-domain-to-nginx.sh
```

### Blue/Green Files

- `docker-compose.yml` – full stack (postgres, redis, frontend) for local dev
- `docker-compose.blue.yml` – frontend only, container `db-server-frontend-blue`
- `docker-compose.green.yml` – frontend only, container `db-server-frontend-green`

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Service identification
NODE_ENV=production
DOMAIN=database-server.statex.cz
SERVICE_NAME=database-server

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

# Frontend
AUTH_SERVICE_URL=http://auth-microservice:3370
FRONTEND_PORT=3390
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
# Port configured in database-server/.env: DB_SERVER_PORT (default: 5432)
DATABASE_URL=postgresql+psycopg://crypto:crypto_pass@db-server-postgres:${DB_SERVER_PORT:-5432}/crypto_ai_agent

# Redis connection string
# Port configured in database-server/.env: REDIS_SERVER_PORT (default: 6379)
REDIS_URL=redis://db-server-redis:${REDIS_SERVER_PORT:-6379}/0
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
   # Ports configured in database-server/.env: DB_SERVER_PORT (default: 5432), REDIS_SERVER_PORT (default: 6379)
   environment:
     - DATABASE_URL=postgresql+psycopg://myuser:mypassword@db-server-postgres:${DB_SERVER_PORT:-5432}/my_project
     - REDIS_URL=redis://db-server-redis:${REDIS_SERVER_PORT:-6379}/0
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
├── docker-compose.yml          # Full stack (postgres, redis, frontend) - local dev
├── docker-compose.blue.yml     # Frontend only - blue deployment
├── docker-compose.green.yml    # Frontend only - green deployment
├── .env.example                # Environment template
├── .env                        # Environment config (gitignored)
├── README.md                   # This file
├── docs/                       # Documentation
│   ├── ARCHITECTURE.md
│   ├── BACKUP_RESTORE.md
│   └── PROJECT_INTEGRATION.md
├── nginx/                      # Nginx configuration
│   └── nginx-api-routes.conf   # API routes for web interface
├── web/                        # Frontend (landing + admin panel)
│   ├── server.js               # Express server, /auth proxy, /api/stats
│   ├── package.json            # Node.js dependencies
│   ├── Dockerfile              # Container build file
│   └── public/                 # Static files
│       ├── index.html          # Landing page
│       ├── admin.html          # Admin panel
│       ├── css/style.css       # Styles
│       └── js/admin.js         # Admin JavaScript
├── scripts/                    # Management scripts
│   ├── deploy.sh               # Full deployment script
│   ├── start.sh                # Start server
│   ├── stop.sh                 # Stop server
│   ├── restart.sh              # Restart server
│   ├── status.sh               # Status check
│   ├── add-domain-to-nginx.sh  # Add web domain to nginx
│   ├── create-database.sh      # Create project database
│   ├── list-databases.sh       # List all databases
│   ├── backup-database.sh      # Backup database
│   ├── restore-database.sh     # Restore database
│   ├── drop-database.sh        # Drop database
│   └── db-server/              # Internal scripts
│       └── init-databases.sh   # Auto-init script
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

# Check ports (port configured in database-server/.env: DB_SERVER_PORT, default: 5432)
netstat -an | grep ${DB_SERVER_PORT:-5432}
```

### Connection Issues

```bash
# Test from another container
# Port configured in database-server/.env: DB_SERVER_PORT (default: 5432)
docker run --rm --network nginx-network postgres:15 \
  psql -h db-server-postgres -p ${DB_SERVER_PORT:-5432} -U crypto -d crypto_ai_agent -c "SELECT 1;"
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
