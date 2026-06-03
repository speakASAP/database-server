# System: database-server

## Architecture

PostgreSQL 15 and Redis 7 are the shared production datastore services for the Statex ecosystem. For agents and Kubernetes workloads, the only normal access path is Kubernetes service DNS in the `statex-apps` namespace.

- PostgreSQL: `db-server-postgres.statex-apps.svc.cluster.local:5432` or short name `db-server-postgres:5432` from `statex-apps`
- Redis: `db-server-redis.statex-apps.svc.cluster.local:6379` or short name `db-server-redis:6379` from `statex-apps`
- Each service uses its own database (e.g. `flipflop`, `auth`, `catalog`)

> Do not use `192.168.88.53`, `127.0.0.1`, `localhost`, Docker network aliases, SSH tunnels, or host ports for production database work unless the human explicitly asks for break-glass maintenance.

## Integrations

K8s pods connect via Kubernetes service DNS: `DB_HOST=db-server-postgres`, `REDIS_HOST=db-server-redis`, or the full `*.statex-apps.svc.cluster.local` names. Secrets are sourced from Vault through External Secrets Operator (ESO); do not construct alternate database URLs from raw Vault values.

## Current State
<!-- AI-maintained -->
Stage: production · Shared PostgreSQL + Redis via Kubernetes service DNS

## Known Issues
<!-- AI-maintained -->
- Some historical docs and manifests still mention host-IP database access. Treat those as legacy notes and update them when touched.
