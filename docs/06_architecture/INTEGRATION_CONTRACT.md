# Integration Contract: database-server


## Purpose
Record reviewed ecosystem capability decisions for database-server.

## Capability Decisions
| Capability | Decision | Reason |
|---|---|---|
| auth | not-applicable | No documented dependency on auth exists in this repository current architecture. |
| postgres | required | Existing repository documentation identifies postgres as part of this repository boundary or required ecosystem operation. |
| redis | required | Existing repository documentation identifies redis as part of this repository boundary or required ecosystem operation. |
| logging | not-applicable | No documented dependency on logging exists in this repository current architecture. |
| notifications | not-applicable | No documented dependency on notifications exists in this repository current architecture. |
| ai | not-applicable | No documented dependency on ai exists in this repository current architecture. |
| payments | not-applicable | No documented dependency on payments exists in this repository current architecture. |
| catalog | not-applicable | No documented dependency on catalog exists in this repository current architecture. |
| orders | not-applicable | No documented dependency on orders exists in this repository current architecture. |
| warehouse | not-applicable | No documented dependency on warehouse exists in this repository current architecture. |
| invoices | not-applicable | No documented dependency on invoices exists in this repository current architecture. |
| object-storage | not-applicable | No documented dependency on object-storage exists in this repository current architecture. |
| event-bus | not-applicable | No documented dependency on event-bus exists in this repository current architecture. |
| docs-rag | required | Existing repository documentation identifies docs-rag as part of this repository boundary or required ecosystem operation. |
| monitoring | required | Existing repository documentation identifies monitoring as part of this repository boundary or required ecosystem operation. |
| backups | required | Existing repository documentation identifies backups as part of this repository boundary or required ecosystem operation. |

## Data Ownership
Ownership remains limited to the repository purpose stated in BUSINESS.md and SYSTEM.md.

## Authentication and Authorization
Use existing approved identity and credential boundaries; do not document secret values.

## Synchronous Dependencies
Required synchronous or operational dependencies are identified in the capability matrix.

## Asynchronous Dependencies
Only the reviewed event-bus decision defines an asynchronous dependency.

## Degraded Operation
A missing required capability degrades only its dependent documented behavior and must not cause secret disclosure or ownership bypass.

## Validation
Use IPS planning validation plus applicable repository architecture and health checks.
