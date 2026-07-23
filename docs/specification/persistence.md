# Persistence

## Storage Responsibilities

Each bounded context uses appropriate storage for its data:

```
┌─────────────────────────────────────────────────────────────┐
│  Configuration Context                                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │amir-config/  │────▶│     Git      │                      │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Execution Context                                          │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Entities   │────▶│  SQLite/PG   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Artifacts  │────▶│Object Storage│ (large payloads)     │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Workflow Context                                           │
│  ┌──────────────┐     ┌──────────────┐  ┌──────────────┐   │
│  │   Instances  │────▶│  PostgreSQL   │  │ Event Store  │   │
│  └──────────────┘     └──────────────┘  │ (event source)│   │
│                                          └──────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  Security Context                                           │
│  ┌──────────────┐     ┌──────────────┐ ┌──────────────┐    │
│  │   Policies   │────▶│  PostgreSQL    │ │ HashiCorp    │    │
│  └──────────────┘     └──────────────┘ │   Vault      │    │
│  ┌──────────────┐     ┌──────────────┐ └──────────────┘    │
│  │    Audit     │────▶│  JSONL File   │ (append-only)      │
│  └──────────────┘     └──────────────┘                     │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │Egress Proxy  │────▶│  PostgreSQL   │ (request log)       │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Observability Context                                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Metrics    │────▶│  Prometheus   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │ Cost Records │────▶│  PostgreSQL   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │  Scorecards  │────▶│  PostgreSQL   │ (read model)        │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Traces     │────▶│ OpenTelemetry  │                      │
│  └──────────────┘     └──────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Storage Contracts

Structural authority for tables and columns is **not** in this document.

| Context | Database contract | Related data contracts |
|---------|-------------------|------------------------|
| Execution | [`sql/execution.sql`](../contract/sql/execution.sql) | task, agent-session, workspace, artifact, checkpoint, tool-call, cost-lease, idempotency-key |
| Workflow | [`sql/workflow.sql`](../contract/sql/workflow.sql) | workflow, step-result, compensation-action |
| Outbox | [`sql/outbox.sql`](../contract/sql/outbox.sql) | outbox-entry, domain-event |
| Security | [`sql/security.sql`](../contract/sql/security.sql) | access-policy, secret-binding |
| Observability | [`sql/observability.sql`](../contract/sql/observability.sql) | cost-record, agent-scorecard |

Configuration Context remains Git (`amir-config/`: agents, roles, contracts, workflows, teams, skills, prompts).


## CQRS Boundary

Read and write operations are separated to optimize for their respective workloads:

### Write Model (Commands)
- Task, AgentSession, Workspace, CostLease, WorkflowInstance
- Optimized for consistency and durability
- Event-sourced for audit trail

### Read Model (Queries)
- AgentScorecard, CostSummary, TaskStatus, WorkflowStatus
- Optimized for query performance
- Projected from write model via events

### Projection Rules
1. Query handlers MUST access read models only
2. Command handlers MUST access write models only
3. Projections MUST be eventually consistent (bounded staleness)
4. Read models MUST be rebuilt from events on schema change

### Consistency Guarantees
- **Strong consistency**: Write model (event sourcing)
- **Eventual consistency**: Read model (projection lag < 1s)
- **Read-your-writes**: Query after command returns projected state

## Migration Paths

### SQLite to PostgreSQL
Use Alembic for schema migration with dual-write strategy during transition.

### File to Message Queue
JSONL file with atomic appends can be replaced by Kafka producer with same schema. Outbox table provides reliability during transition.

### Single-Region to Multi-Region
- Database sharding by team/tenant
- Event replication between regions
- Consistent hashing for workflow routing
- Cost records replicated for global queries

---

## Addressing Audit Concerns

### Workspace Persistence (All Audits)
Workspace state persisted with baseline/current commit tracking enables reproduction of failed agent executions and durable_effects and observation retention across task retries (each attempt still gets a **new** Workspace; no filesystem reuse).

### Audit Immutability (All Audits)
Append-only file storage with restricted permissions. linear hash-chained events with cryptographic signatures provide tamper-evidence.

### Event Sourcing (Tinker/Kimi)
WorkflowInstance state derived from events. Event store provides full audit trail and enables replay for debugging.

### Outbox Pattern (Kimi)
Reliable event publishing via outbox table. Delivery semantics enforced by category.

### Cost Records (All 17 Audits)
Multi-dimensional CostRecord with orchestration/worker cost separation. Hierarchical aggregation for budget monitoring.
