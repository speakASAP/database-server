# System: database-server

status: reviewed
completeness_level: complete

## Purpose
Shared PostgreSQL and Redis infrastructure for the ecosystem.

## Responsibilities
Provide managed PostgreSQL and Redis through Kubernetes service DNS.

## Non-Responsibilities
Unrelated business domains and consumer-owned data remain outside this repository boundary.

## Inputs
Documented service requests, repository configuration, and approved operational inputs.

## Outputs
Documented service, infrastructure, or governance outcomes for ecosystem consumers.

## Dependencies
Reviewed capability decisions are recorded in docs/06_architecture/INTEGRATION_CONTRACT.md.

## Upstream Traceability
BUSINESS.md and existing repository architecture documentation define the current intent.

## Downstream Artifacts
The integration contract, invariants, and bootstrap planning chain are the canonical IPS outputs.

## Validation Criteria
Run the IPS planning validator and use existing repository-specific checks when changing runtime behavior.

## Open Questions
No new runtime or ownership decision is made by this documentation-only adoption.
