# CLAUDE.md (database-server)

→ Ecosystem: [../shared/CLAUDE.md](../shared/CLAUDE.md) | Reading order: `BUSINESS.md` → `SYSTEM.md` → `AGENTS.md` → `TASKS.md` → `STATE.json`

---

## database-server

**Purpose**: Shared PostgreSQL + Redis instance for all Statex services. Native host processes on Alfares server — not in Docker, not in K8s. No external exposure.  
**PostgreSQL**: port 5432 · host `db-server-postgres` (Docker network) / `192.168.88.53` (K8s pods)  
**Redis**: port 6379 · host `db-server-redis` (Docker network) / `192.168.88.53` (K8s pods)  
**Stack**: PostgreSQL 15 · Redis 7 · native host processes (permanent)

### Key constraints
- Never run destructive SQL (DROP TABLE, TRUNCATE, DELETE without WHERE) without explicit human approval
- Schema migrations only via each service's own migration scripts — not ad-hoc SQL
- No direct external access — host-only binding, not exposed externally
- Each service owns its own database schema

### Connect from a container
```bash
psql -h db-server-postgres -p 5432 -U dbadmin -d <database>
redis-cli -h db-server-redis -p 6379
```
For k8s pods: use host IP `192.168.88.53:5432` / `192.168.88.53:6379` instead of container hostname.

### Secrets
Credentials live at `secret/prod/database-server` in Vault (`http://192.168.88.53:8200`).  
Synced to K8s via ESO → `database-server-secret`.
