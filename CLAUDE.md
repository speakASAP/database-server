# CLAUDE.md (database-server)

Ecosystem defaults: sibling [`../CLAUDE.md`](../CLAUDE.md) and [`../shared/docs/PROJECT_AGENT_DOCS_STANDARD.md`](../shared/docs/PROJECT_AGENT_DOCS_STANDARD.md).

Read this repo's `BUSINESS.md` → `SYSTEM.md` → `AGENTS.md` → `TASKS.md` → `STATE.json` first.

---

## database-server

**Purpose**: Shared PostgreSQL + Redis instance for all Statex services. Internal Docker network only — no external exposure.  
**PostgreSQL**: port 5432 · host `db-server-postgres`  
**Redis**: port 6379 · host `db-server-redis`  
**Stack**: PostgreSQL · Redis · Docker

### Key constraints
- Never run destructive SQL (DROP TABLE, TRUNCATE, DELETE without WHERE) without explicit human approval
- Schema migrations only via each service's own migration scripts — not ad-hoc SQL
- No direct external access — internal Docker network (`nginx-network`) only
- Each service owns its own database schema

### Connect from a container
```bash
psql -h db-server-postgres -p 5432 -U dbadmin -d <database>
redis-cli -h db-server-redis -p 6379
```

### Connect via SSH tunnel (local dev only)
```bash
ssh -L 5432:localhost:5432 statex   # legacy — prefer docker exec
psql -h localhost -p 5432 -U dbadmin -d <database>
```
