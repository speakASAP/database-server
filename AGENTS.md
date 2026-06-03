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

Do not connect through `192.168.88.53`, `127.0.0.1`, `localhost`, Docker network aliases, SSH tunnels, or host ports unless the human explicitly asks for break-glass maintenance. Older docs that mention native host processes or LAN IP access are legacy migration notes.

N/A — infrastructure service. No AI agent coordination.

## Active Agents
<!-- Coordinator-maintained -->
None.
