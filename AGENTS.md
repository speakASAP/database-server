# Repository Agent Instructions

Shared rules live here:

- Codex profile: `/home/ssf/.codex/AGENTS.md`
- Cross-agent standard: `/home/ssf/.ai-agent-standards/CROSS_AGENT_AUTOMATION_STANDARD.md`
- Repository operations: `AGENT_OPERATIONS.md`

Read those first, then follow the repository-specific notes below and the current planning/status files.


## Repository-Specific Notes

# Agents: database-server

## Knowledge Retrieval

Use `docs-rag-microservice` for bounded discovery when it is healthy, then
verify deployment, security, database, integration and public-contract facts
against the cited Git source. Git remains authoritative.

Authority and fallback rules:
`/home/ssf/Documents/Github/shared/docs/DOCUMENTATION_AUTHORITY.md`.

Do not generate tokens in documentation or assume an unconfident/failed RAG
response means that source documentation does not exist.

## Database Access

**Agents:** start at  — MCP `postgres` → `postgres_agent_guide` first.

**Infrastructure (this repo):** [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

Do not use host psql, localhost, port-forward, `.env` passwords, or generic postgres MCP servers.

N/A — infrastructure service. No AI agent coordination.

## Active Agents
<!-- Coordinator-maintained -->
None.
