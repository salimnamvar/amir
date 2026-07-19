# Event Model

## Overview

Events in Amir are immutable facts representing state changes and business occurrences. All events follow a consistent structure enabling distributed tracing, replay, and debugging.

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
    signature: str = ""  # Optional cryptographic signature
```

## Event Taxonomy

### Lifecycle Events (Permanent Retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Task.Created | Orchestrator | task_id, title, objective |
| Task.Assigned | Orchestrator | task_id, agent_id, role |
| Task.Started | Orchestrator | task_id, invocation_id |
| Task.Completed | Orchestrator | task_id, artifact_ids |
| Task.Failed | Orchestrator | task_id, error |
| Task.Cancelled | Orchestrator | task_id, reason |
| AgentInvocation.Started | AgentAdapter | invocation_id, agent_id |
| AgentInvocation.Completed | AgentAdapter | invocation_id, artifact_id |
| AgentInvocation.Failed | AgentAdapter | invocation_id, error |
| Artifact.Produced | AgentInvocation | artifact_id, contract_type |
| Artifact.Validated | ContractValidator | artifact_id, valid |
| Workflow.Created | WorkflowEngine | workflow_id, definition_id |
| Workflow.Completed | WorkflowEngine | workflow_id, status |

### Progress Events (Configurable Retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| AgentInvocation.Progress | AgentAdapter | invocation_id, percent, message |

### Security Events (Permanent/90 days)

| Event Type | Producer | Payload |
|------------|----------|---------|
| Sandbox.Created | SandboxManager | sandbox_id, task_id |
| Sandbox.Destroyed | SandboxManager | sandbox_id |
| Secret.Accessed | SecretBroker | secret_path, task_id |
| Access.Denied | Authorization | resource, action, subject, reason |

## Event Flow

### Task Creation Flow

```
Task.Created (correlation_id: W-123, causation_id: null)
    ↓
Task.Assigned (correlation_id: W-123, causation_id: Task.Created event_id)
    ↓
AgentInvocation.Started (correlation_id: W-123, causation_id: Task.Assigned event_id)
```

## Correlation and Causation

- **correlation_id**: Traces entire workflow from creation
- **causation_id**: Links event to its direct cause

Enables audit trail reconstruction, error tracing, and workflow replay.

---

## Event Publishing

### File-Based Publisher (Default)

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

---

## Event Retention Policies

| Category | Retention | Purpose |
|----------|-----------|---------|
| Lifecycle | Permanent | Audit trail |
| Security | Permanent | Compliance, forensics |
| Progress | Configurable | Debugging, monitoring |

---

## Addressing Audit Concerns

### Event Ordering (All Audits)
Single-writer per aggregate ensures ordering. Persistent storage provides atomicity.

### Progress Events (All Audits)
Progress events exist but retention is configurable. Sampling can be applied for high-volume scenarios.