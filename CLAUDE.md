# CLAUDE.md (database-server)

→ Ecosystem: [../shared/CLAUDE.md](../shared/CLAUDE.md) | Reading order: `BUSINESS.md` → `SYSTEM.md` → `AGENTS.md` → `TASKS.md` → `STATE.json`

---

## database-server

**Purpose**: Shared PostgreSQL + Redis in Kubernetes for all Statex services.

**Single source of truth:** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

### Key constraints

- Never run destructive SQL (DROP TABLE, TRUNCATE, DELETE without WHERE) without explicit human approval
- Schema migrations only via each service's own migration scripts — not ad-hoc SQL
- Each service owns its own database schema
- Credentials live in Vault (`secret/prod/<service>`) → ESO → K8s Secret
