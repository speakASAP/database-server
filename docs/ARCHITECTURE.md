# Database Server Architecture

## Overview

The Database Server is a centralized microservice that provides PostgreSQL and Redis services for multiple projects. Instead of each project having its own database containers, all projects connect to a single, shared database server.

## Architecture Diagram

```text
┌─────────────────────────────────────────┐
│     Database Server Microservice         │
│                                          │
│  ┌──────────────┐    ┌──────────────┐  │
│  │  PostgreSQL  │    │    Redis     │  │
│  │   (Container) │    │  (Container) │  │
│  │              │    │              │  │
│  │ Databases:   │    │ Databases:   │  │
│  │ - crypto_ai  │    │ - 0-15 (0-15)│  │
│  │ - project2   │    │              │  │
│  │ - project3   │    │              │  │
│  └──────────────┘    └──────────────┘  │
│         │                    │          │
│         └──────────┬─────────┘          │
│                    │                    │
│            nginx-network               │
└────────────────────┼────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐      ┌─────────▼──────┐
│ crypto-ai-agent│      │  project2       │
│                │      │                 │
│ backend-blue   │      │ backend         │
│ backend-green  │      │ frontend        │
└────────────────┘      └─────────────────┘
```

## Key Components

### PostgreSQL Container

- **Container Name**: `db-server-postgres`
- **Purpose**: Hosts multiple databases (one per project)
- **Network**: `nginx-network`
- **Port**: `${DB_SERVER_PORT}` (default: 5432, configured in `.env`), exposed on localhost only
- **Volume**: `db_server_pgdata` (persistent storage)

**Database Structure:**

```text
PostgreSQL Instance
├── postgres (system database)
├── crypto_ai_agent (project database)
├── project2_db (project database)
└── project3_db (project database)
```

Each project database has:

- Own database user
- Isolated permissions
- Separate data storage

### Redis Container

- **Container Name**: `db-server-redis`
- **Purpose**: Shared caching for all projects
- **Network**: `nginx-network`
- **Port**: `${REDIS_SERVER_PORT}` (default: 6379, configured in `.env`), exposed on localhost only
- **Volume**: `db_server_redisdata` (persistent storage)

**Redis Structure:**

- Single Redis instance
- Projects can use different Redis databases (0-15) for isolation
- Configurable memory limits and eviction policies

## Network Architecture

### Docker Network: `nginx-network`

All services connect to the same Docker network for service discovery:

```text
nginx-network
├── nginx (nginx-microservice)
├── db-server-postgres
├── db-server-redis
├── crypto-ai-backend-blue
├── crypto-ai-backend-green
└── ... (other project containers)
```

**Service Discovery:**

- Services can reach each other by container name
- Example: `crypto-ai-backend` connects to `db-server-postgres:${DB_SERVER_PORT:-5432}` (port configured in `database-server/.env`, default: 5432)

## Data Persistence

### Volumes

1. **`db_server_pgdata`**
   - Contains ALL PostgreSQL data
   - All project databases stored here
   - Persistent across container restarts

2. **`db_server_redisdata`**
   - Contains Redis data
   - Persistent if AOF enabled
   - Shared by all projects

### Backup Strategy

- Manual backups via `./scripts/backup-database.sh`
- Backup storage in `./backups/` directory
- Compressed SQL dumps (`.sql.gz`)

## Security Model

### Access Control

1. **Admin User** (`dbadmin`)
   - Full access to all databases
   - Used for database management
   - Strong password required in production

2. **Project Users** (e.g., `crypto`, `project2_user`)
   - Access only to their own database
   - No access to other project databases
   - Isolated permissions

### Network Security

- PostgreSQL port only exposed on localhost (127.0.0.1)
- Redis port only exposed on localhost (127.0.0.1)
- No external access (containers access via Docker network)
- Firewall rules recommended for production

## Benefits

### Resource Efficiency

- **Before**: N projects = N PostgreSQL containers
- **After**: N projects = 1 PostgreSQL container
- Significant resource savings (CPU, memory, disk)

### Centralized Management

- Single point of administration
- Unified backup strategy
- Easier monitoring
- Simplified updates

### Project Isolation

- Each project has its own database
- Separate users and permissions
- Data isolation between projects
- No cross-project data access

### Scalability

- Easy to add new projects
- Centralized connection pooling (future)
- Simplified replication setup (future)
- Easier to migrate to managed services

## Connection Patterns

### From Project Containers

```python
# PostgreSQL
# Port configured in database-server/.env: DB_SERVER_PORT (default: 5432)
DATABASE_URL = "postgresql+psycopg://crypto:crypto_pass@db-server-postgres:${DB_SERVER_PORT:-5432}/crypto_ai_agent"

# Redis
# Port configured in database-server/.env: REDIS_SERVER_PORT (default: 6379)
REDIS_URL = "redis://db-server-redis:${REDIS_SERVER_PORT:-6379}/0"
```

### From Host Machine

```bash
# PostgreSQL (local access only)
# Port configured in database-server/.env: DB_SERVER_PORT (default: 5432)
psql -h 127.0.0.1 -p ${DB_SERVER_PORT:-5432} -U crypto -d crypto_ai_agent

# Redis (local access only)
# Port configured in database-server/.env: REDIS_SERVER_PORT (default: 6379)
redis-cli -h 127.0.0.1 -p ${REDIS_SERVER_PORT:-6379}
```

## Deployment Scenarios

### Scenario 1: Single Server

All services on one server:

- Database server
- Nginx microservice
- All project applications

### Scenario 2: Separate Database Server

Database server on dedicated machine:

- Higher security
- Better performance
- Network configuration required

### Scenario 3: Docker Swarm / Kubernetes

- Database server as service
- Replicated for high availability
- Volume management handled by orchestrator

## Future Enhancements

1. **PostgreSQL Replication**
   - Primary/Standby setup
   - Automatic failover
   - Read replicas

2. **Connection Pooling**
   - PgBouncer integration
   - Optimized connection management

3. **Automated Backups**
   - Scheduled backups
   - Retention policies
   - Backup verification

4. **Multi-Region**
   - Geo-replication
   - Disaster recovery
   - Latency optimization
