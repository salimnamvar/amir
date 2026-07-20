# Event Model

## Overview

Events in Amir are immutable facts representing state changes and business occurrences. All events follow a consistent structure enabling distributed tracing, replay, and debugging. Events are linear hash-chained for tamper-evidence.

## Domain Event Envelope

> **Contract:** [`docs/contract/schemas/domain-event.schema.yaml`](../contract/schemas/domain-event.schema.yaml)

Events are linear hash-chained (`sequence`, `prev_hash`, optional `signature` / `key_ref`). W3C `traceparent` / `tracestate` may be present.


## Event Taxonomy

### Lifecycle Events (Permanent Retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Task.Created | Orchestrator | task_id, title, objective, idempotency_key |
| Task.Assigned | Orchestrator | task_id, agent_id, role, matching_decision |
| Task.Started | Orchestrator | task_id, session_id |
| Task.Completed | Orchestrator | task_id, artifact_ids |
| Task.Failed | Orchestrator | task_id, error, retry_state (last_failure_category), agent_circuit_breaker_state (snapshot from AgentScorecard at failure time — not task-owned) |
| Task.Cancelled | Orchestrator | task_id, reason |
| AgentSession.Started | AgentExecutor | session_id, agent_id, attempt_number |
| AgentSession.Completed | AgentExecutor | session_id, artifact_id |
| AgentSession.Failed | AgentExecutor | session_id, error, feedback_generated |
| AgentSession.Checkpoint | AgentExecutor | session_id, state, workspace_snapshot |
| Artifact.Produced | AgentSession | artifact_id, contract_type, observation_method |
| Artifact.Validated | ContractValidator | artifact_id, valid, validation_duration_ms |
| Artifact.Rejected | ContractValidator | artifact_id, error_categories |
| Workflow.Created | WorkflowEngine | workflow_id, definition_id |
| Workflow.Transitioned | WorkflowEngine | workflow_id, from_state, to_state |
| Workflow.Completed | WorkflowEngine | workflow_id, status |
| Workflow.Compensated | WorkflowEngine | workflow_id, actions_executed, actions_succeeded |
| MatchingDecision.Made | CapabilityMatcher | task_id, agent_id, score, dimension_scores |

### Progress Events (Configurable Retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| AgentSession.Progress | AgentExecutor | session_id, percent, message |
| AgentSession.ToolCall | AgentExecutor | session_id, tool_name, status |

### Security Events (Permanent/90 days)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Sandbox.Created | SandboxManager | sandbox_id, task_id, runtime, attestation |
| Sandbox.Destroyed | SandboxManager | sandbox_id |
| Sandbox.Attested | SandboxManager | sandbox_id, attestation_signature |
| Secret.Accessed | SecretBroker | secret_path, task_id |
| Access.Denied | Authorization | resource, action, subject, reason |
| Egress.RequestLogged | EgressProxy | session_id, destination, tokens_counted |

### Cost Events (365-day retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Cost.Recorded | CostEnforcer | session_id, tokens, cost_usd, attribution |
| Cost.ReservationCreated | CostEnforcer | task_id, estimated_cost, team_id |
| Cost.ReservationCommitted | CostEnforcer | task_id, actual_cost |
| Cost.ReservationReleased | CostEnforcer | task_id, reason |
| Cost.BudgetExceeded | CostGate | level, team_id, threshold, action=cancel_inflight\|reject_new |
| CostLease.Created | CostGate | lease_id, task_id, session_id, reserved_usd, reserved_tokens, scope |
| CostLease.Revoked | CostGate | lease_id, cancellation_reason, scope |
| CostLease.Released | CostGate | lease_id, consumed_usd, consumed_tokens |

### Compensation Events (Permanent)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Compensation.Started | WorkflowEngine | workflow_id, steps_to_compensate |
| Compensation.Executed | CompensationExecutor | workflow_id, action_type, target, status |
| Compensation.Failed | CompensationExecutor | workflow_id, action_type, target, error |
| Compensation.Blocked | WorkflowEngine | workflow_id, failed_action, durable_effect_ref |
| Compensation.Completed | WorkflowEngine | workflow_id, actions_succeeded, actions_failed |
| Escalation.Signal | WorkflowEngine / CostGate | signal_id, target_type, target_id, escalation_type, reason |

### Routing Events (Configurable)

| Event Type | Producer | Payload |
|------------|----------|---------|
| CircuitBreaker.Opened | CircuitBreaker | agent_id, consecutive_failures |
| CircuitBreaker.Closed | CircuitBreaker | agent_id, recovery_reason |
| AgentScorecard.Updated | ScorecardService | agent_id, period, metrics |

## Event Flow

### Task Execution Flow

```
Task.Created (correlation_id: W-123, causation_id: null)
    ↓
Task.Assigned (correlation_id: W-123, causation_id: Task.Created)
    ↓
MatchingDecision.Made (correlation_id: W-123, causation_id: Task.Assigned)
    ↓
AgentSession.Started (correlation_id: W-123, causation_id: MatchingDecision.Made)
    ↓
AgentSession.Checkpoint (correlation_id: W-123, causation_id: AgentSession.Started)
    ↓
AgentSession.Completed (correlation_id: W-123, causation_id: AgentSession.Started)
    ↓
Artifact.Produced (correlation_id: W-123, causation_id: AgentSession.Completed)
    ↓
Artifact.Validated (correlation_id: W-123, causation_id: Artifact.Produced)
    ↓
Cost.Recorded (correlation_id: W-123, causation_id: AgentSession.Completed)
```

### Failure and Feedback Flow

```
Artifact.Rejected (correlation_id: W-123, causation_id: Artifact.Produced)
    ↓
AgentSession.Failed (correlation_id: W-123, causation_id: Artifact.Rejected)
    ↓
Cost.Recorded (correlation_id: W-123, causation_id: AgentSession.Failed)
    ↓
AgentSession.Started (correlation_id: W-123, causation_id: AgentSession.Failed, attempt=2)
```

### Compensation Flow

```
Workflow.StepFailed (correlation_id: W-123)
    ↓
Compensation.Started (correlation_id: W-123)
    ↓
Compensation.Executed (correlation_id: W-123, step N)
    ↓
Compensation.Executed (correlation_id: W-123, step N-1)
    ↓
  [on durable-effect failure and continue_on_compensation_failure=false]
    → Compensation.Failed → Compensation.Blocked → Escalation.Signal
  [else all succeeded]
    → Compensation.Completed → Workflow.Compensated
```

## Correlation and Causation

- **correlation_id**: Traces entire workflow from creation
- **causation_id**: Links event to its direct cause

Enables audit trail reconstruction, error tracing, and workflow replay.

## Hash Chain (Linear Hash Chaining)

Events form a **linear hash chain per aggregate_id** (not a Merkle tree). Scope of the chain is the aggregate instance.

Every event includes:
- `sequence`: Monotonically increasing integer within the aggregate
- `prev_hash`: SHA256 of previous event for this aggregate_id (`null` for the root event)
- `causation_id`: may be `null` for root events

**Concurrency constraint (normative):** Single-writer per aggregate is required. Serialize outbox inserts via row-level lock on the aggregate row (or Kafka/DB partition keyed by `aggregate_id`) before writing the next chain event. Concurrent multi-pod writers without this serialization will break the chain.

Verification: recompute hash chain from first event for the aggregate. Any tampering breaks the chain. Periodic root-commit of chain tips to an external transparency log is optional hardening.

---

## Event Publishing

### Outbox Pattern (Default)

Events are published via outbox for reliable delivery:

Publisher implementations (outbox / file JSONL / message queue) all accept `DomainEvent` and follow delivery semantics in the taxonomy tables. Outbox storage contract: [`sql/outbox.sql`](../contract/sql/outbox.sql) + [`outbox-entry.schema.yaml`](../contract/schemas/outbox-entry.schema.yaml).


### File-Based Publisher (Fallback)

Publisher implementations (outbox / file JSONL / message queue) all accept `DomainEvent` and follow delivery semantics in the taxonomy tables. Outbox storage contract: [`sql/outbox.sql`](../contract/sql/outbox.sql) + [`outbox-entry.schema.yaml`](../contract/schemas/outbox-entry.schema.yaml).


### Message Queue Publisher (Alternative)

Publisher implementations (outbox / file JSONL / message queue) all accept `DomainEvent` and follow delivery semantics in the taxonomy tables. Outbox storage contract: [`sql/outbox.sql`](../contract/sql/outbox.sql) + [`outbox-entry.schema.yaml`](../contract/schemas/outbox-entry.schema.yaml).


## Event Retention Policies

| Category | Retention | Ordering | Delivery |
|----------|-----------|----------|----------|
| Lifecycle | Permanent | Causal (per-aggregate) | At-least-once |
| Security | Permanent | Total (global) | At-least-once |
| Cost | 365 days | Causal | At-least-once |
| Compensation | Permanent | Total | At-least-once |
| Progress | Configurable | None | At-most-once |
| Routing | Configurable | None | At-most-once |

---

## Addressing Audit Concerns

### Event Ordering (All Audits)
Single-writer per aggregate ensures ordering. Persistent storage provides atomicity. Outbox pattern ensures reliable delivery.

### Audit Tamper-Evidence (Minimax/GLM)
linear hash-chained events with sequence numbers and prev_hash. Periodic root-commit to external transparency log.

### Outbox Pattern (Kimi)
Reliable event publishing via outbox table. Delivery semantics enforced by category.

### Cost Events (All 17 Audits)
First-class cost events with multi-dimensional attribution. Hierarchical aggregation for budget monitoring.
