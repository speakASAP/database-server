# System: database-server

## Architecture

PostgreSQL 15 + Redis 7 run as **native host processes** on the Alfares server (permanent — not in Docker, not in Kubernetes). Credentials stored in Vault at `secret/prod/database-server`, synced to K8s via External Secrets Operator (ESO).

- PostgreSQL: `db-server-postgres:5432` (Docker network alias) / `192.168.88.53:5432` (from K8s pods)
- Redis: `db-server-redis:6379` (Docker network alias) / `192.168.88.53:6379` (from K8s pods)
- Each service uses its own database (e.g. `flipflop`, `auth`, `catalog`)

> PostgreSQL and Redis are permanently native host processes. There is no plan to migrate them to K8s StatefulSets.

## Integrations

K8s pods connect via: `DB_HOST=192.168.88.53`, `REDIS_HOST=192.168.88.53` (injected from K8s Secret via ESO)  
Docker services connect via: `DB_HOST=db-server-postgres`, `REDIS_HOST=db-server-redis`  
Secrets sourced from Vault: `secret/prod/database-server`

## Current State
<!-- AI-maintained -->
Stage: production · Permanent native host processes (PostgreSQL + Redis)

## Known Issues
<!-- AI-maintained -->
- None
