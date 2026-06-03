# Database Server Architecture

## Current Architecture

The Statex ecosystem uses one shared production datastore layer in Kubernetes.

| Datastore | Kubernetes service | Namespace | Port |
| --- | --- | --- | --- |
| PostgreSQL | `db-server-postgres.statex-apps.svc.cluster.local` | `statex-apps` | `5432` |
| Redis | `db-server-redis.statex-apps.svc.cluster.local` | `statex-apps` | `6379` |

Workloads in `statex-apps` may use the short service names `db-server-postgres` and `db-server-redis`.

## PostgreSQL

PostgreSQL is the single relational datastore for the ecosystem. Each service owns its own logical database and credentials. Service credentials are stored in Vault and synced into Kubernetes Secrets by External Secrets Operator.

## Redis

Redis is the shared cache/session datastore. Service credentials and runtime values follow the same Vault to ESO to Kubernetes Secret flow.

## Access Policy

Agents and application workloads must use Kubernetes service DNS only. Do not introduce or document alternate database endpoints.

## Data Ownership

- Each service owns its own schema/database boundary.
- Cross-service reads or writes must go through service APIs or explicit integration contracts.
- Shared datastore credentials must not be copied into prompts, docs, examples, or agent task text.

## Persistence And Backups

Persistence, backup, and restore behavior are managed by Kubernetes manifests and the operations runbooks for the `statex-apps` namespace. Documentation for new services should reference only the Kubernetes service names in this file.
