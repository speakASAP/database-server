# Database Server — Single Source of Truth

> **This is the only file that documents production PostgreSQL and Redis access.**
> All other docs must link here. Do not duplicate connection details elsewhere.

## Production State

PostgreSQL 15 and Redis 7 run in Kubernetes namespace `statex-apps`, backed by PVCs.
Manifest: `database-server/k8s/in-cluster-databases.yaml`.

| Datastore | Short name (from `statex-apps`) | Full DNS | Port |
| --- | --- | --- | --- |
| PostgreSQL | `db-server-postgres` | `db-server-postgres.statex-apps.svc.cluster.local` | `5432` |
| Redis | `db-server-redis` | `db-server-redis.statex-apps.svc.cluster.local` | `6379` |

Short names work only from pods in `statex-apps`. Use full DNS from other namespaces in the same cluster.

## Access Policy

- **Only** Kubernetes service DNS — no host IP, localhost, Docker endpoints, or port-forward as production access.
- Each service owns its own logical database and credentials.
- Cross-service reads or writes go through service APIs or explicit integration contracts.
- Never copy database credentials into prompts, docs, examples, or agent task files.

## Configuration

### ConfigMap (non-secrets)

```yaml
DB_HOST: db-server-postgres
DB_PORT: "5432"
REDIS_HOST: db-server-redis
REDIS_PORT: "6379"
```

### Vault + External Secrets Operator (secrets)

- Vault path: `secret/prod/<service-name>`
- ESO syncs to Kubernetes Secret → injected as pod environment variables
- Do not construct alternate `DATABASE_URL` values from raw Vault exports

## New Service Checklist

1. Add `DB_HOST`, `DB_PORT`, `REDIS_HOST`, `REDIS_PORT` to the service ConfigMap.
2. Add secret keys to Vault and the service ExternalSecret.
3. Configure the application to read runtime values from Kubernetes-injected env vars.
4. Run schema migrations against `db-server-postgres` inside the cluster.

## Persistence

- PostgreSQL PVC: `db-server-postgres-pvc` (20Gi, `local-path` StorageClass)
- Redis PVC: `db-server-redis-pvc` (2Gi, `local-path` StorageClass)
- Deployment strategy: `Recreate` (single replica)

## Backups

Backup and restore are handled by `backups-microservice` and kubectl exec against the `db-server-postgres` deployment. See `backups-microservice` docs for schedules and retention.

## Verification

```bash
# From any pod in statex-apps
kubectl exec -it <pod> -n statex-apps -- nc -zv db-server-postgres 5432
kubectl exec -it <pod> -n statex-apps -- nc -zv db-server-redis 6379

# PostgreSQL health
kubectl exec -n statex-apps deployment/db-server-postgres -- pg_isready -U dbadmin
```

## Agents

**Mandatory:** use MCP server `postgres` for all database discovery and queries.
Full guide: [shared/docs/mcp/MCP_POSTGRES.md](../../shared/docs/mcp/MCP_POSTGRES.md).

First tool call: `postgres_agent_guide`. Do not use host psql, port-forward, or `.env` passwords.
