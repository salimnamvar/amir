# Event Model

## Overview

Events in Amir are immutable facts that represent state changes and business occurrences. All events follow a consistent structure enabling distributed tracing, replay, and debugging.

## Domain Event Envelope

All events use the standard `DomainEvent` structure:

```python
from datetime import datetime
from uuid import UUID, uuid4
from typing import Any

class DomainEvent(BaseModel):
    """Standard envelope for all domain events."""
    
    event_id: UUID = Field(default_factory=uuid4)
    event_type: str              # e.g., "Task.Created"
    aggregate_id: UUID           # Entity that produced this
    aggregate_type: str          # Type of aggregate
    correlation_id: UUID         # End-to-end workflow trace
    causation_id: UUID           # Direct cause of this event
    producer: str                # Component that emitted
    version: str = "1.0.0"      # Event schema version
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict[str, Any]      # Event-specific data
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

### Progress Events (30-Day Retention)

| Event Type | Producer | Payload |
|------------|----------|---------|
| AgentInvocation.Progress | AgentAdapter | invocation_id, percent, message |

### Security Events

| Event Type | Producer | Payload |
|------------|----------|---------|
| Sandbox.Created | SandboxManager | sandbox_id, task_id |
| Sandbox.Destroyed | SandboxManager | sandbox_id |
| Secret.Accessed | SecretBroker | secret_path, task_id |
| Access.Denied | Authorization | resource, action, subject, reason |

## Event Flow Examples

### Task Creation Flow

```
1. Task.Created
   correlation_id: WORKFLOW-123
   causation_id: null

2. Task.Assigned  
   correlation_id: WORKFLOW-123
   causation_id: Task.Created event_id

3. AgentInvocation.Started
   correlation_id: WORKFLOW-123
   causation_id: Task.Assigned event_id
```

### Workflow Completion Flow

```
Task.Completed → Task.Completed (next task) → ... → Workflow.Completed
```

## Correlation and Causation

- **correlation_id**: Traces the entire workflow from creation
- **causation_id**: Links event to its direct cause

This enables:
- Full audit trail reconstruction
- Error chain tracing
- Replay of specific workflows

## MVP Event Publishing

```python
class FileEventPublisher(EventPublisher):
    """MVP: Simple file-based event publishing."""
    
    def __init__(self, path: str = "/var/log/amir/events.jsonl"):
        self.path = path
    
    async def publish(self, event: DomainEvent) -> None:
        with open(self.path, "a") as f:
            f.write(event.model_dump_json() + "\n")
    
    async def publish_batch(self, events: list[DomainEvent]) -> None:
        # Write all events atomically
        lines = [e.model_dump_json() for e in events]
        with open(self.path, "a") as f:
            f.write("\n".join(lines) + "\n")
```

## Phase 2 Event Publishing

```python
class KafkaEventPublisher(EventPublisher):
    """Phase 2: Kafka with schema registry."""
    
    def __init__(self, brokers: list[str]):
        self.producer = KafkaProducer(brokers)
    
    async def publish(self, event: DomainEvent) -> None:
        topic = f"amir.{event.aggregate_type.lower()}s"
        await self.producer.send(topic, event.model_dump_json())
```

---

## Addressing Audit Concerns

### Event Model Overreach (GLM)

MVP uses a single append-only file. No tiered retention or complex routing.

### Event Ordering (GLM)

Single-writer per aggregate ensures ordering. SQLite transactions provide atomicity.

### Progress Streaming (GLM, DeepSeek)

MVP does not stream progress. `AgentInvocation.Progress` exists but is only emitted once on completion. Phase 2 adds sampling for high-volume scenarios.