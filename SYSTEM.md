# System: database-server

## Architecture

PostgreSQL 15 + Redis 7 in Docker. All services connect via `nginx-network`.

- PostgreSQL: `db-server-postgres:5432`
- Redis: `db-server-redis:6379`
- Each service uses its own database (e.g. `flipflop`, `auth`, `catalog`)

## Integrations

All services connect via env vars: `DB_HOST=db-server-postgres`, `REDIS_HOST=db-server-redis`

## Current State
<!-- AI-maintained -->
Stage: production

## Known Issues
<!-- AI-maintained -->
- None
