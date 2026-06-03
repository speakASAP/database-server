# Agents: database-server


## Knowledge Retrieval (query before reading files)
Query the RAG service first to reuse indexed ecosystem context before reading raw files:

```bash
curl -s -X POST http://docs-rag-microservice.statex-apps.svc.cluster.local:3397/retrieval/agent-context \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query": "YOUR QUESTION HERE", "maxTokens": 3000}'
```

- Internal URL: `http://docs-rag-microservice.statex-apps.svc.cluster.local:3397`
- Public URL: `https://docs-rag.alfares.cz`
- Full guide: `docs-rag-microservice/docs/RAG_USAGE.md`


## Database Access Policy

Agents and Kubernetes workloads must use only Kubernetes service DNS for production datastore access:

- PostgreSQL: `db-server-postgres.statex-apps.svc.cluster.local:5432` or `db-server-postgres:5432` from `statex-apps`.
- Redis: `db-server-redis.statex-apps.svc.cluster.local:6379` or `db-server-redis:6379` from `statex-apps`.

Use Kubernetes service DNS for production datastore access: `db-server-postgres:5432`, `db-server-redis:6379`, and `qdrant:6333` in `statex-apps`.

N/A — infrastructure service. No AI agent coordination.

## Active Agents
<!-- Coordinator-maintained -->
None.
