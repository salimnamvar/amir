# Workflow Engine

## Architecture Overview

The Workflow Engine orchestrates multi-step agent workflows with explicit state management and failure handling.

```
┌─────────────────┐
│WorkflowDefinition│ (Git-managed template)
└────────┬────────┘
         │
         ▼ instantiate
┌─────────────────┐
│WorkflowInstance │ (Durable state)
└────────┬────────┘
         │
         ▼ execute_step
┌─────────────────┐
│   Task(s)       │ (Agent executions)
└─────────────────┘
```

## Workflow Engine Interface

```go
// This Go interface provides the seam for Temporal migration
type WorkflowEngine interface {
    // Create a workflow instance from a definition
    CreateWorkflow(definition_id UUID, team_id UUID) (UUID, error)
    
    // Execute a task step within the workflow
    ExecuteStep(workflow_id UUID, task_spec TaskSpec) error
    
    // Wait for signal (human approval, external trigger)
    WaitForSignal(workflow_id UUID, signal_name string, timeout time.Duration) error
    
    // Complete the workflow
    CompleteWorkflow(workflow_id UUID) error
    
    // Get current workflow state
    GetState(workflow_id UUID) (string, error)
    
    // Handle workflow failure
    FailWorkflow(workflow_id UUID, error string) error
}
```

## MVP Workflow Model

### Linear Three-State Workflow (MVP)

For MVP, workflows are simple and linear:

```
REQUESTED → IMPLEMENTATION → TESTING → COMPLETED
                                    ↓
                              FAILED/BLOCKED/CANCELLED
```

**Implementation**: Internal state machine in `WorkflowEngine` interface.

### Task Specification

```python
class TaskSpec(BaseModel):
    """Task specification within workflow."""
    role: str                           # Required role
    objective: str                      # Work objective
    expected_outputs: list[str]         # Artifact contract types
    constraints: dict[str, Any]         # Additional constraints
    hard_dependencies: list[UUID]       # Must complete first
    soft_dependencies: list[UUID]       # Preferred order
```

## Phase 2 Workflow Model

### DAG Support

```yaml
# WorkflowDefinition supports task DAGs
workflow:
  name: feature-development
  states:
    - name: planning
      tasks: [plan-task]
    - name: implementation
      tasks: [impl-task-1, impl-task-2]
      depends_on: [planning]
    - name: testing
      tasks: [test-task]
      depends_on: [implementation]  # Can be hard or soft
    - name: review
      tasks: []
      approval_gate: true
      depends_on: [testing]
```

### Dependency Types

- **Hard**: Task B cannot start until Task A completes successfully
- **Soft**: Task B can start but warnings are recorded if Task A hasn't completed

### Retry and Compensation

```python
class RetryPolicy(BaseModel):
    """Retry behavior for tasks/workflows."""
    max_attempts: int = 3
    backoff_seconds: int = 60
    backoff_strategy: str = "exponential"  # exponential | linear
    
    # What triggers retry
    retry_on: list[str] = ["FAILED"]  # FAILED, TIMEOUT, etc.

class CompensationAction(BaseModel):
    """Rollback action for failed workflows."""
    # Phase 2 feature
    action_type: str  # revert_git, notify_slack, cleanup_resources
    target: str
    parameters: dict
```

## Phase 2: Human Approval Model

```python
class Approval(BaseModel):
    """Human approval tracking."""
    id: UUID = Field(default_factory=uuid4)
    workflow_id: UUID
    gate_name: str
    approver_id: str | None = None
    status: str = "PENDING"  # PENDING | GRANTED | REJECTED | EXPIRED
    requested_at: datetime
    responded_at: datetime | None = None
    timeout_seconds: int = 86400  # 24 hours default
```

## State Persistence

### MVP Strategy

- **Storage**: SQLite with synchronous writes
- **Checkpoints**: After each state transition
- **Recovery**: On restart, load state from DB

### Phase 2 Strategy

- **Storage**: PostgreSQL with connection pooling
- **Checkpoints**: Snapshot + event log
- **Timers**: Database-based timer queue

### Phase 3 Strategy (Temporal)

- **Storage**: Temporal server
- **Checkpoints**: Automatic via Temporal
- **Timers**: Native Temporal timer API

## Critical Implementation Detail

The internal state machine MUST persist state transitions synchronously to maintain durability. Periodic persistence is insufficient for correct workflow semantics.

---

## Addressing Audit Concerns

### Workflow Seam (All)

The `WorkflowEngine` interface is designed for Temporal migration:
- State transitions are explicit (CreateWorkflow, ExecuteStep, WaitForSignal)
- No internal Temporal-specific concepts leak into domain logic
- Migration verified by implementing linear workflow on both engines

### Approval Gates (DeepSeek)

MVP uses auto-approve for all transitions. `Approval` entity is defined but not used until Phase 2. This clarifies the "rejection path" concern.

### DAG vs Linear Confusion (Minimax)

MVP explicitly implements linear workflow only. DAG features are marked as Phase 2. This resolves the specification contradiction.