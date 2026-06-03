# Business: database-server
>
> ⚠️ IMMUTABLE BY AI.

## Goal

Shared PostgreSQL + Redis server for all Statex services. Single managed instance for multi-tenant databases and caching.

## Constraints

- AI must never run destructive SQL (DROP, TRUNCATE, DELETE without WHERE)
- Schema migrations only via service-owned migration scripts
- Database access for Kubernetes workloads uses only Kubernetes service DNS in `statex-apps`: `db-server-postgres` and `db-server-redis`
- Credentials managed exclusively in Vault at `secret/prod/database-server` — never stored in committed files

## Consumers

All services in the ecosystem.

## SLA

- Availability: 99.9%
- PostgreSQL port: 5432 (db-server-postgres)
- Redis port: 6379 (db-server-redis)
