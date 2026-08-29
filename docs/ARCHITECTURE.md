# Database and Redis Architecture

This document is the infrastructure source of truth for production PostgreSQL
and Redis used by the Alfares ecosystem.

## Runtime topology

Both datastores run in Kubernetes namespace `statex-apps`:

| Component | Deployment | Service DNS | Port | Storage |
| --- | --- | --- | --- | --- |
| PostgreSQL 15 | `db-server-postgres` | `db-server-postgres` | 5432 | `db-server-postgres-pvc` |
| Redis 7 | `db-server-redis` | `db-server-redis` | 6379 | `db-server-redis-pvc` |

The authoritative manifests are
[`k8s/in-cluster-databases.yaml`](../k8s/in-cluster-databases.yaml).

The `database-server-frontend` deployment on port 3390 is an administration
and discovery UI. It is not the database endpoint.

## Application access

Kubernetes workloads use service DNS:

```text
PostgreSQL: db-server-postgres:5432
Redis:      db-server-redis:6379
```

Do not use node IPs or pod IPs in application configuration. Do not route
around failed DNS by connecting directly across the pod CIDR.

Each service owns its database/schema and migrations. Use service-scoped roles
and credentials from Vault. A new service must not copy a shared `dbadmin`
account into examples or runtime configuration.

## Human and agent maintenance

Use one of the approved bounded paths:

1. the configured PostgreSQL MCP after reading its agent guide;
2. `kubectl exec` into the database pod for server-local maintenance;
3. a temporary `kubectl port-forward` when a client connection is required.

Never print connection passwords, Kubernetes Secret `.data`, raw customer
records or production exports into transcripts.

## Migrations

- Migrations are owned and versioned by the consuming service.
- Never run `prisma migrate dev` against production, including
  `--create-only`.
- Apply reviewed production migrations with the service's deployment contract,
  normally `prisma migrate deploy` or the stack-equivalent command.
- Generate migration SQL offline when necessary and validate it against a
  scratch database restored from a schema-only production dump.
- A deployment must refuse to proceed when the live database is behind or the
  migration contract is unresolved.

## Redis behavior

Redis is configured as a bounded cache/coordination store with an
`allkeys-lru` eviction policy. Services must not treat Redis as the sole durable
copy of business data. Replay, lease and idempotency expectations belong in the
owning service's integration contract.

## Ownership and backups

`database-server` owns datastore availability and infrastructure manifests.
Each consuming service owns:

- schema and migration correctness;
- data retention requirements;
- backup/restore acceptance criteria;
- validation that its data is covered by the ecosystem backup process.

Backup integration decisions are recorded in each service's IPS integration
contract and coordinated with `backups-microservice`.

## Deployment boundary

`database-server/deploy.config.sh` deploys only
`database-server-frontend`. Datastore lifecycle remains a repository-specific
operation because PostgreSQL and Redis are shared critical infrastructure.
Never infer that a frontend deployment updated the datastores.
