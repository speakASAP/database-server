# System: database-server

## Architecture

PostgreSQL 15 + Redis 7 run as Docker containers on the host (Phase 3). Credentials stored in Vault at `secret/prod/database-server`, synced to k8s via External Secrets Operator (ESO).

- PostgreSQL: `db-server-postgres:5432` (Docker services) / `192.168.88.53:5432` (k8s pods)
- Redis: `db-server-redis:6379` (Docker services) / `192.168.88.53:6379` (k8s pods)
- Each service uses its own database (e.g. `flipflop`, `auth`, `catalog`)

**Phase 4 (planned):** Migrate to k8s StatefulSet in `statex-infra` namespace. DNS: `postgres.statex-infra.svc.cluster.local`

## Integrations

Docker Compose services connect via env vars: `DB_HOST=db-server-postgres`, `REDIS_HOST=db-server-redis`  
k8s pods connect via env vars: `DB_HOST=192.168.88.53`, `REDIS_HOST=192.168.88.53` (injected from k8s Secret via ESO)  
Secrets sourced from Vault: `secret/prod/database-server`

## Current State
<!-- AI-maintained -->
Stage: production

## Known Issues
<!-- AI-maintained -->
- None
