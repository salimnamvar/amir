# Observability

## Event Model

### Event Categories

All events use the `DomainEvent` envelope:

| Category | Events | Retention | Purpose |
|----------|--------|-----------|---------|
| Lifecycle | Task.Created, Task.Completed, Agent.Started | Permanent | Core state tracking |
| Progress | AgentSession.Progress, AgentSession.Checkpoint | Configurable | Debugging, monitoring |
| Security | Secret.Accessed, Sandbox.Created, Access.Denied | Permanent/90 days | Compliance, forensics |
| Cost | Cost.Recorded, Cost.BudgetExceeded, Cost.ReservationCreated | 365 days | Cost control, attribution |
| Quality | Artifact.Validated, Artifact.Rejected, Quality.Measured | Configurable | Quality gates |
| Compensation | Compensation.Started, Compensation.Executed, Compensation.Failed | Permanent | Workflow rollback audit |
| Routing | MatchingDecision.Made, CircuitBreaker.Opened, CircuitBreaker.Closed | Configurable | Agent selection audit |

### Event Envelope Structure


> **Contract:** [`docs/contract/schemas/domain-event.schema.yaml`](../contract/schemas/domain-event.schema.yaml)


### W3C Trace Context

Events include trace context headers when available:
- `traceparent`: W3C trace identifier
- `tracestate`: Vendor-specific trace state

## Event Storage

### Strategy

Events are stored in an append-only event store with configurable retention policies.

Append-only store; hash chain computed on write. Envelope: domain-event contract. Outbox: outbox-entry + `sql/outbox.sql`.


### Outbox Pattern

Domain events are published via outbox pattern for reliable delivery:


> **Contract:** [`docs/contract/schemas/outbox-entry.schema.yaml`](../contract/schemas/outbox-entry.schema.yaml)


### Delivery Semantics

| Event Category | Delivery | Ordering | Retry |
|---------------|----------|----------|-------|
| Domain | At-least-once | Causal (per-aggregate) | Exponential backoff |
| Audit | At-least-once | Total (global) | Until success |
| Metrics | At-most-once | None | No retry |

### File-Based Storage (Default)

Default publisher may append JSONL; schema is still `DomainEvent`.


## Metrics Collection

### Cost Recording

First-class cost entity with multi-dimensional attribution:


> **Contract:** [`docs/contract/schemas/cost-record.schema.yaml`](../contract/schemas/cost-record.schema.yaml)


### Cost Hierarchy

```
Per-Invocation CostRecord
    ↓ (aggregate)
Per-Team Hourly CostSummary
    ↓ (aggregate)
Per-Tenant Daily CostSummary
    ↓ (aggregate)
Per-Org Monthly CostSummary
```

### Cost Summary


> **Contract:** [`docs/contract/schemas/cost-summary.schema.yaml`](../contract/schemas/cost-summary.schema.yaml)


### Agent Performance Metrics

AgentScorecard derived from cost and quality events:


> **Contract:** [`docs/contract/schemas/agent-scorecard.schema.yaml`](../contract/schemas/agent-scorecard.schema.yaml)


### Quality Metrics


> **Contract:** [`docs/contract/schemas/quality-metric.schema.yaml`](../contract/schemas/quality-metric.schema.yaml)


### Validation Metrics

Track validation pipeline performance:


> **Contract:** [`docs/contract/schemas/validation-metric.schema.yaml`](../contract/schemas/validation-metric.schema.yaml)


## Quality Criteria Validation

Roles declare quality criteria for artifact validation:


> **Contract:** [`docs/contract/schemas/role.schema.yaml#quality_criteria`](../contract/schemas/role.schema.yaml#quality_criteria)


## Replay and Debugging

### Replay Metadata

Every AgentSession captures replay metadata for debugging:


> **Contract:** [`docs/contract/schemas/replay-metadata.schema.yaml`](../contract/schemas/replay-metadata.schema.yaml)


### Debug Query API


> **Contract:** (see related schema; DebugQuery is not a standalone dump)


---

## Addressing Audit Concerns

### Event Model Overreach (GLM)
Simple file-based logging is the default. Retention policies are configurable but not mandatory.

### Quality Validation (All Audits)
Quality metrics defined with pluggable validators. Semantic validation has timeout and budget constraints.

### Progress Streaming (GLM)
Progress events emitted on state transitions. Continuous streaming available via optional instrumentation.

### Cost as First-Class (All 17 Audits)
CostRecord with multi-dimensional attribution. Hierarchical cost summaries. AgentScorecard derived from cost events.

### Audit Tamper-Evidence (Minimax/GLM)
linear hash-chained events with sequence numbers and prev_hash. Periodic root-commit to external transparency log.

### Replay Capability (Minimax)
Full replay metadata on every AgentSession. Enables exact reproduction of agent execution for debugging.
