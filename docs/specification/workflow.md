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
// Interface seam for workflow orchestration
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
    
    // Register signal handler
    RegisterSignalHandler(workflow_id UUID, signal Signal) error
}
```

## Workflow Model

### States

```
REQUESTED → PLANNED → IMPLEMENTATION → TESTING → REVIEW → APPROVED → COMPLETED
                                    ↓              ↓
                              FAILED/BLOCKED/CANCELLED    ESCALATED
```

### Task Specification

```python
class TaskSpec(BaseModel):
    """Task specification within workflow."""
    role: str
    objective: str
    expected_outputs: list[str]
    constraints: dict[str, Any]
    hard_dependencies: list[UUID]
    soft_dependencies: list[UUID]
```

### Retry and Compensation

```python
class RetryPolicy(BaseModel):
    """Retry behavior for tasks/workflows."""
    max_attempts: int = 3
    backoff_seconds: int = 60
    backoff_strategy: str = "exponential"
    retry_on: list[str] = ["FAILED", "TIMEOUT"]

class CompensationAction(BaseModel):
    """Rollback action for failed workflows."""
    action_type: str  # revert_git, cleanup_resources
    target: str
    parameters: dict
```

## Approval Model

```python
class Approval(BaseModel):
    """Approval tracking for workflow gates."""
    id: UUID = Field(default_factory=uuid4)
    workflow_id: UUID
    gate_name: str
    approver_id: str | None = None
    status: str = "PENDING"  # PENDING | AUTO_APPROVED | GRANTED | REJECTED | EXPIRED
    requested_at: datetime
    responded_at: datetime | None = None
    auto_approve: bool = True
    timeout_seconds: int = 86400
```

## State Persistence

### Strategy

- **Storage**: SQLite with synchronous writes (MVP)
- **Checkpoints**: After each state transition
- **Recovery**: On restart, load state from DB
- **Migration Path**: PostgreSQL → Temporal ready via interface seam

### Durability Guarantee

The internal state machine MUST persist state transitions synchronously to maintain durability. Periodic persistence is insufficient for correct workflow semantics.

---

## Critical Implementation Details

### Approval Gates

All transitions use binary approval: `auto_approve: true` for automated workflows, `auto_approve: false` for manual approval via signals.

### DAG Support

The WorkflowDefinition supports DAG structure for workflow design. Linear execution is the default mode.

### Signal Handling

Workflows can be signaled for:
- Manual approval
- External triggers
- Cancellation

---

## Addressing Audit Concerns

### Workflow Seam (All Audits)
The `WorkflowEngine` interface is designed for Temporal migration with explicit state transitions and no internal Temporal-specific concepts.

### Approval Gates (All Audits)
`Approval` entity fully defined with binary auto-approve support.

### DAG Features (Minimax)
DAG features defined in schema but linear execution is MVP default.