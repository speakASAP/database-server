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

## Database Access

**Mandatory MCP workflow** — see [shared/docs/mcp/MCP_POSTGRES.md](../shared/docs/mcp/MCP_POSTGRES.md):

1. `postgres_agent_guide` (always first)
2. `postgres_health_check`
3. `postgres_database_catalog` / `postgres_list_databases`
4. `postgres_query`

Do not use host psql, port-forward, `.env` passwords, or generic postgres MCP servers.

N/A — infrastructure service. No AI agent coordination.

## Active Agents
<!-- Coordinator-maintained -->
None.
