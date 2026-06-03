# Project Integration Guide

Use this guide when a service needs the shared production datastore.

## Kubernetes Datastore Access

All production services connect through Kubernetes service DNS in the `statex-apps` namespace.

| Datastore | Host | Port |
| --- | --- | --- |
| PostgreSQL | `db-server-postgres` | `5432` |
| Redis | `db-server-redis` | `6379` |

Use full DNS names only when required by Kubernetes context:

- `db-server-postgres.statex-apps.svc.cluster.local:5432`
- `db-server-redis.statex-apps.svc.cluster.local:6379`

## Required Configuration

Non-secret values belong in the service ConfigMap:

```yaml
DB_HOST: db-server-postgres
DB_PORT: "5432"
REDIS_HOST: db-server-redis
REDIS_PORT: "6379"
```

Secret values belong in Vault at `secret/prod/<service-name>` and are synced to Kubernetes by External Secrets Operator.

## Service Rules

- Do not document alternate datastore endpoints.
- Grant agents the approved `postgres` MCP access when they need database discovery/query.
- Do not copy database credentials into prompts, docs, examples, or task files.
- Do not access another service's database directly; use service APIs or approved contracts.

## New Service Checklist

1. Add non-secret datastore host and port values to the service Kubernetes ConfigMap.
2. Add secret keys to Vault and the service ExternalSecret.
3. Configure the application to read runtime values from Kubernetes-injected environment variables.
4. Document only the Kubernetes service names above.
