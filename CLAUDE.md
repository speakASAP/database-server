# CLAUDE.md (database-server)

→ Ecosystem: [../shared/CLAUDE.md](../shared/CLAUDE.md) | Reading order: `BUSINESS.md` → `SYSTEM.md` → `AGENTS.md` → `TASKS.md` → `STATE.json`

---

## database-server

**Purpose**: Shared PostgreSQL + Redis services for all Statex services. Agents and K8s workloads use Kubernetes service DNS only.  
**PostgreSQL**: `db-server-postgres.statex-apps.svc.cluster.local:5432` or `db-server-postgres:5432` from `statex-apps`  
**Redis**: `db-server-redis.statex-apps.svc.cluster.local:6379` or `db-server-redis:6379` from `statex-apps`  
**Stack**: PostgreSQL 15 · Redis 7 · Kubernetes service access

### Key constraints
- Never run destructive SQL (DROP TABLE, TRUNCATE, DELETE without WHERE) without explicit human approval
- Schema migrations only via each service's own migration scripts — not ad-hoc SQL
- No direct external access — host-only binding, not exposed externally
- Each service owns its own database schema

### Connect from Kubernetes
```bash
psql -h db-server-postgres -p 5432 -U dbadmin -d <database>
redis-cli -h db-server-redis -p 6379
```
Production datastore access uses Kubernetes service DNS only.

### Secrets
Credentials live at `secret/prod/database-server` in Vault (`http://192.168.88.53:8200`).  
Synced to K8s via ESO → `database-server-secret`.
