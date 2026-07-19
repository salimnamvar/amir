# Amir Domain Model v1.0

**Status:** Frozen for MVP Implementation  
**Style:** Domain Driven Design with Clean Architecture  
**Language:** Python 3.11+ (Pydantic v2)

---

## Aggregates

### Aggregate: Task

**Root Entity:** `Task`

**Purpose:** Define work to be performed and track its execution.

**Lifecycle:** Pending → Assigned → Running → Validating → Completed | Failed | Cancelled

**Invariants:**
1. Task must have exactly one assigned role
2. All required inputs must be available before Running state
3. Cost budget must not be exceeded during execution
4. Quality gates must be evaluated after completion

**Entities:**
- `Task` (root)
- `Assignment` (value object within Task aggregate)

**Value Objects:**
- `TaskObjective`
- `TaskPriority`
- `CostBudget`
- `RetryPolicy`

```python
# src/amir/domain/entities/task.py
from pydantic import BaseModel, Field
from uuid import UUID
from datetime import datetime
from enum import Enum
from typing import Optional

class TaskStatus(str, Enum):
    PENDING = "pending"
    ASSIGNED = "assigned"
    RUNNING = "running"
    VALIDATING = "validating"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

class Task(BaseModel):
    id: UUID = Field(default_factory=UUID)
    title: str
    objective: str
    assigned_role: str  # Role name reference
    inputs: list[dict] = Field(default_factory=list)  # Artifact references
    expected_outputs: list[str]  # Contract types
    constraints: list[dict] = Field(default_factory=list)
    dependencies: list[dict] = Field(default_factory=list)
    priority: int = Field(default=5, ge=1, le=10)
    deadline: Optional[datetime] = None
    cost_budget: dict  # max_tokens, max_usd
    retry_policy: dict
    status: TaskStatus = TaskStatus.PENDING
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
```

---

### Aggregate: AgentDefinition

**Root Entity:** `AgentDefinition`

**Purpose:** Immutable configuration for an agent type.

**Lifecycle:** Draft → Published → Deprecated

**Invariants:**
1. Adapter type determines required configuration fields
2. Capabilities must be testable during publication
3. Security profile must be valid (sandbox_required=true for untrusted)

**Entities:**
- `AgentDefinition` (root)
- `Capability` (entity within aggregate)

**Value Objects:**
- `AdapterConfig`
- `ResourceProfile`
- `SecurityProfile`

```python
# src/amir/domain/entities/agent_definition.py
class AgentDefinition(BaseModel):
    id: UUID = Field(default_factory=UUID)
    name: str
    adapter_type: str  # cli, mcp, api
    adapter_config: dict
    capabilities: list[dict]  # Skill declarations
    resource_limits: dict  # CPU, memory, tokens, timeout
    security_profile: dict
    version: str
    metadata: dict
    status: str = "published"  # draft, published, deprecated
```

---

### Aggregate: WorkflowInstance

**Root Entity:** `WorkflowInstance`

**Purpose:** Track active workflow execution.

**Lifecycle:** Created → Running → Paused → Completed | Failed | Cancelled

**Invariants:**
1. Current state must have valid transition
2. All task dependencies must eventually resolve
3. Approval gates must be satisfied

**Entities:**
- `WorkflowInstance` (root)
- `Approval` (entity within aggregate)

**Value Objects:**
- `StateTransition`
- `WorkflowVariables`

```python
# src/amir/domain/entities/workflow_instance.py
class WorkflowInstance(BaseModel):
    id: UUID = Field(default_factory=UUID)
    workflow_template_id: UUID
    team_id: UUID
    current_state: str
    variables: dict = Field(default_factory=dict)
    status: str = "created"  # created, running, paused, completed, failed, cancelled
    created_at: datetime = Field(default_factory=datetime.utcnow)
```

---

### Aggregate: Artifact

**Root Entity:** `Artifact`

**Purpose:** Immutable output produced by agent execution.

**Lifecycle:** Produced → Validated → Accepted | Rejected

**Invariants:**
1. Must reference valid contract type and version
2. Must include provenance metadata
3. Must have valid checksum

**Entities:**
- `Artifact` (root - treated as entity with identity but immutable after validation)

**Value Objects:**
- `Provenance`
- `ArtifactContent`

```python
# src/amir/domain/entities/artifact.py
class Artifact(BaseModel):
    id: UUID = Field(default_factory=UUID)
    contract_type: str
    contract_version: str
    content: dict
    provenance: dict  # producer agent, session, task references
    checksum: str
    status: str = "produced"  # produced, validated, accepted, rejected
    created_at: datetime = Field(default_factory=datetime.utcnow)
```

---

## Value Objects

### Ids

```python
# src/amir/domain/value_objects/ids.py
from uuid import UUID
from pydantic import BaseModel

class TaskId(BaseModel):
    value: UUID

class AgentDefinitionId(BaseModel):
    value: UUID

class WorkflowInstanceId(BaseModel):
    value: UUID

class ArtifactId(BaseModel):
    value: UUID

class InvocationId(BaseModel):
    value: UUID
```

### Lifecycle

```python
# src/amir/domain/value_objects/lifecycle.py
from enum import Enum

class EntityLifecycle(str, Enum):
    # Configuration entities
    DRAFT = "draft"
    PUBLISHED = "published"
    DEPRECATED = "deprecated"
    
    # Runtime entities
    PENDING = "pending"
    ACTIVE = "active"
    COMPLETED = "completed"
    FAILED = "failed"
```

### ContractVersion

```python
# src/amir/domain/value_objects/contract_version.py
from pydantic import BaseModel
from semver import Version

class ContractVersion(BaseModel):
    major: int
    minor: int
    patch: int
    
    @classmethod
    def parse(cls, version_str: str) -> "ContractVersion":
        v = Version.parse(version_str)
        return cls(major=v.major, minor=v.minor, patch=v.patch)
    
    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"
```

---

## Domain Events

All events use the standard envelope:

```python
# src/amir/domain/events/event_envelope.py
from pydantic import BaseModel
from uuid import UUID
from datetime import datetime

class DomainEvent(BaseModel):
    event_id: UUID = Field(default_factory=UUID)
    event_type: str
    aggregate_id: UUID  # ID of the aggregate that produced this event
    aggregate_type: str  # Task, AgentDefinition, WorkflowInstance, Artifact
    correlation_id: UUID  # For tracing request chains
    causation_id: UUID  # ID of event that caused this one
    producer: str  # Component that produced this
    version: str = "1.0.0"  # Event schema version
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict
```

### Task Events

```python
# src/amir/domain/events/task_events.py
from .event_envelope import DomainEvent

class TaskCreated(DomainEvent):
    event_type: str = "task.created"

class TaskAssigned(DomainEvent):
    event_type: str = "task.assigned"

class TaskCompleted(DomainEvent):
    event_type: str = "task.completed"

class TaskFailed(DomainEvent):
    event_type: str = "task.failed"
```

### Agent Events

```python
# src/amir/domain/events/agent_events.py
from .event_envelope import DomainEvent

class AgentStarted(DomainEvent):
    event_type: str = "agent.started"

class AgentCompleted(DomainEvent):
    event_type: str = "agent.completed"

class AgentFailed(DomainEvent):
    event_type: str = "agent.failed"
```

---

## Protocols / Interfaces

### Agent Adapter

```python
# src/amir/domain/protocols/agent_adapter.py
from abc import ABC, abstractmethod
from uuid import UUID

class AgentAdapter(ABC):
    @abstractmethod
    async def start_invocation(
        self,
        invocation_id: UUID,
        task: dict,
        contract_type: str,
        workspace: dict
    ) -> None:
        """Start agent execution"""
        pass
    
    @abstractmethod
    async def get_result(
        self,
        invocation_id: UUID
    ) -> dict:
        """Get execution result"""
        pass
    
    @abstractmethod
    async def cancel(
        self,
        invocation_id: UUID
    ) -> None:
        """Cancel running invocation"""
        pass
    
    @abstractmethod
    def supports_contract(self, contract_type: str, version: str) -> bool:
        """Check contract compatibility"""
        pass
```

### Workflow Engine

```python
# src/amir/domain/protocols/workflow_engine.py
from abc import ABC, abstractmethod
from uuid import UUID

class WorkflowEngine(ABC):
    @abstractmethod
    async def create_workflow(self, workflow_def: dict, team_id: UUID) -> UUID:
        """Create workflow instance"""
        pass
    
    @abstractmethod
    async def transition_state(
        self,
        workflow_id: UUID,
        task_completed: UUID
    ) -> str:
        """Update state and return next state"""
        pass
    
    @abstractmethod
    async def wait_for_approval(
        self,
        workflow_id: UUID,
        gate_id: str
    ) -> bool:
        """Wait for human approval"""
        pass
```

### Artifact Validator

```python
# src/amir/domain/protocols/artifact_validator.py
from abc import ABC, abstractmethod

class ArtifactValidator(ABC):
    @abstractmethod
    async def validate(
        self,
        artifact: dict,
        contract_type: str,
        contract_version: str
    ) -> tuple[bool, list[str]]:
        """Validate artifact against contract"""
        pass
```

---

## Entity Relationship Summary

```
Configuration Context:
    AgentDefinition -> Capability (1..*)
    RoleDefinition -> required capability (references)
    ContractDefinition -> Schema (embedded)

Execution Context:
    Task -> Assignment (1..1)
    Task -> AgentInvocation (1..*) (via correlation_id)
    Task -> Artifact (0..*) (produced artifacts)
    AgentInvocation -> Workspace (1..1)
```

---

## Invariants Summary

| Entity | Invariant | Enforced By |
|--------|-----------|-----------|
| Task | Must have assigned role before Running | Task aggregate |
| Task | Cost budget must be positive | Value object validation |
| AgentDefinition | Must have valid adapter config | Domain service |
| Artifact | Must reference valid contract | Domain service |
| WorkflowInstance | State transitions must be valid | Workflow engine |

---

## Design Decisions

1. **No TaskExecution entity** - Task aggregate handles execution state via status field
2. **AgentInvocation is separate** - Single agent execution is distinct from task orchestration
3. **Artifact is immutable after production** - Content changes create new artifact
4. **Assignment is value object** - Simple binding, no lifecycle
5. **Events for all state changes** - Enables debugging and replay