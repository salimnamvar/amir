# Event Model

## Overview

Events in Amir are immutable facts representing state changes and business occurrences. All events follow a consistent structure enabling distributed tracing, replay, and debugging. Events are Merkle-chained for tamper-evidence.

## Domain Event Envelope

```python
from datetime import datetime
from uuid import UUID, uuid4
from typing import Any

class DomainEvent(BaseModel):
    """Standard envelope for all domain events."""
    
    event_id: UUID = Field(default_factory=uuid4)
    event_type: str
    aggregate_id: UUID
    aggregate_type: str
    correlation_id: UUID
    causation_id: UUID
    producer: str
    version: str = "1.0.0"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict[str, Any]
    signature: str = ""  # Cryptographic signature
    sequence: int = 0    # Monotonic sequence for hash chain
    prev_hash: str = ""  # SHA256 of previous event
```

## Event Taxonomy

### Lifecycle Events (Permanent Retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Task.Created | Orchestrator | task_id, title, objective, idempotency_key |
| Task.Assigned | Orchestrator | task_id, agent_id, role, matching_decision |
| Task.Started | Orchestrator | task_id, session_id |
| Task.Completed | Orchestrator | task_id, artifact_ids |
| Task.Failed | Orchestrator | task_id, error, circuit_breaker_state |
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
| Cost.BudgetExceeded | CostGate | level, team_id, threshold |

### Compensation Events (Permanent)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Compensation.Started | WorkflowEngine | workflow_id, steps_to_compensate |
| Compensation.Executed | CompensationExecutor | workflow_id, action_type, target, status |
| Compensation.Completed | WorkflowEngine | workflow_id, actions_succeeded, actions_failed |

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
Compensation.Completed (correlation_id: W-123)
    ↓
Workflow.Compensated (correlation_id: W-123)
```

## Correlation and Causation

- **correlation_id**: Traces entire workflow from creation
- **causation_id**: Links event to its direct cause

Enables audit trail reconstruction, error tracing, and workflow replay.

## Hash Chain (Merkle Chaining)

Every event includes:
- `sequence`: Monotonically increasing integer
- `prev_hash`: SHA256 of previous event's (event_id + sequence + prev_hash)

Verification: recompute hash chain from first event. Any tampering breaks the chain.

---

## Event Publishing

### Outbox Pattern (Default)

Events are published via outbox for reliable delivery:

```python
class OutboxEventPublisher(EventPublisher):
    """Publish events via outbox table."""
    
    async def publish(self, event: DomainEvent) -> None:
        # Write to outbox (same transaction as state change)
        await self.db.insert("outbox_entries", {
            "event_type": event.event_type,
            "aggregate_id": event.aggregate_id,
            "payload": event.model_dump(),
            "idempotency_key": event.event_id,
            "created_at": datetime.utcnow()
        })
```

### File-Based Publisher (Fallback)

```python
class FileEventPublisher(EventPublisher):
    """Default event publisher to JSONL file."""
    
    def __init__(self, path: str):
        self.path = path
    
    async def publish(self, event: DomainEvent) -> None:
        with open(self.path, "a") as f:
            f.write(event.model_dump_json() + "\n")
```

### Message Queue Publisher (Alternative)

```python
class MQEventPublisher(EventPublisher):
    """Alternative publisher for distributed deployments."""
    
    def __init__(self, connection: Connection):
        self.connection = connection
    
    async def publish(self, event: DomainEvent) -> None:
        channel = await self.connection.channel()
        await channel.default_exchange.publish(
            routing_key=f"amir.{event.aggregate_type.lower()}s",
            body=event.model_dump_json()
        )
```

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
Merkle-chained events with sequence numbers and prev_hash. Periodic root-commit to external transparency log.

### Outbox Pattern (Kimi)
Reliable event publishing via outbox table. Delivery semantics enforced by category.

### Cost Events (All 17 Audits)
First-class cost events with multi-dimensional attribution. Hierarchical aggregation for budget monitoring.
