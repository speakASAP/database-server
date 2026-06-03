# Database Server

Shared production datastore for the Statex ecosystem.

## Current Production State

The production datastore runs inside Kubernetes in the `statex-apps` namespace.

| Datastore | Kubernetes service | Port | Purpose |
| --- | --- | --- | --- |
| PostgreSQL | `db-server-postgres.statex-apps.svc.cluster.local` | `5432` | Shared relational datastore with one logical database per service |
| Redis | `db-server-redis.statex-apps.svc.cluster.local` | `6379` | Shared cache/session datastore |

Short service names are valid only from workloads in `statex-apps`:

- `db-server-postgres:5432`
- `db-server-redis:6379`

## Access Policy

Agents and services must use Kubernetes service DNS only for datastore access. Use the approved `postgres` MCP server for agent database discovery/query. Do not use non-Kubernetes database endpoints.

Credentials are sourced from Vault through External Secrets Operator into Kubernetes Secrets. Services consume them through Kubernetes manifests and runtime environment variables.

## Service Configuration

Application manifests should use:

```yaml
DB_HOST: db-server-postgres
DB_PORT: "5432"
REDIS_HOST: db-server-redis
REDIS_PORT: "6379"
```

Use the full service DNS names when a workload is outside the namespace but still inside the cluster.

## Database Ownership

Each application uses its own logical PostgreSQL database on the shared Kubernetes PostgreSQL service. Cross-service database access is not allowed unless the owning service explicitly defines that contract.

## Operational Notes

- Source of truth for runtime access is Kubernetes manifests plus Vault/ESO secrets.
- Documentation must not publish alternate database connection methods.
- New service documentation must point to the Kubernetes service names above.
