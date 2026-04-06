# Business: database-server
>
> ⚠️ IMMUTABLE BY AI.

## Goal

Shared PostgreSQL + Redis server for all Statex services. Single managed instance for multi-tenant databases and caching.

## Constraints

- AI must never run destructive SQL (DROP, TRUNCATE, DELETE without WHERE)
- Schema migrations only via service-owned migration scripts
- No direct external access — internal Docker network only

## Consumers

All services in the ecosystem.

## SLA

- Availability: 99.9%
- PostgreSQL port: 5432 (db-server-postgres)
- Redis port: 6379 (db-server-redis)
