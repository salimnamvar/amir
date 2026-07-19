# Workflow Engine

## Architecture Overview

The Workflow Engine orchestrates multi-step agent workflows with explicit state management, durable execution, and compensation. When a workflow step fails, compensating actions execute in reverse order to restore consistency.

```
┌──────────────────────┐
│ WorkflowDefinition   │ (Git-managed template, immutable)
└──────────┬───────────┘
           │ instantiate
           ▼
┌──────────────────────┐
│ WorkflowInstance      │ (Durable state, event-sourced)
│ ├── compensation_stack│ (LIFO compensation actions)
│ └── step_results     │ (Ordered execution history)
└──────────┬───────────┘
           │ execute_step
           ▼
┌──────────────────────┐
│ AgentSession(s)      │ (Agent executions per step)
└──────────────────────┘
```

## Workflow Engine Interface

```go
type WorkflowEngine interface {
    // Create a workflow instance from a definition
    CreateWorkflow(definition_id UUID, team_id UUID, idempotency_key string) (UUID, error)
    
    // Execute a task step within the workflow
    ExecuteStep(workflow_id UUID, task_spec TaskSpec) error
    
    // Wait for signal (human approval, external trigger)
    WaitForSignal(workflow_id UUID, signal_name string, timeout time.Duration) error
    
    // Complete the workflow
    CompleteWorkflow(workflow_id UUID) error
    
    // Get current workflow state
    GetState(workflow_id UUID) (WorkflowState, error)
    
    // Handle workflow failure with compensation
    FailWorkflow(workflow_id UUID, error string) error
    
    // Compensate a failed workflow (rollback completed steps)
    CompensateWorkflow(workflow_id UUID) error
    
    // Register signal handler
    RegisterSignalHandler(workflow_id UUID, signal Signal) error
    
    // Resume a paused workflow
    ResumeWorkflow(workflow_id UUID) error
}
```

## Workflow Model

### States

```
REQUESTED → PLANNED → IMPLEMENTATION → TESTING → REVIEW → APPROVED → COMPLETED
                 ↓            ↓              ↓
           COMPENSATING   FAILED/BLOCKED   ESCALATED
                 ↓
              CANCELLED
```

### Task Specification

```python
class TaskSpec(BaseModel):
    """Task specification within workflow step."""
    role: str
    objective: str
    expected_outputs: list[str]
    constraints: dict[str, Any]
    hard_dependencies: list[UUID]
    soft_dependencies: list[UUID]
    compensation: CompensationSpec  # NEW: compensation action for this step
    timeout_seconds: int = 3600
    retry_policy: RetryPolicy = RetryPolicy()
```

### CompensationSpec

Each workflow step defines its compensation action upfront:

```yaml
CompensationSpec:
  type: object
  required: [action_type]
  properties:
    action_type:
      type: string
      enum:
        - git_revert          # Revert commits made by this step
        - branch_delete       # Delete branch created by this step
        - pr_close            # Close PR created by this step
        - artifact_delete     # Delete artifacts produced by this step
        - resource_cleanup    # Clean up cloud resources
        - custom              # Custom compensation logic
    target:
      type: string
      description: "Target specification (commit range, branch pattern, etc.)"
    parameters:
      type: object
      description: "Additional parameters for compensation"
```

### StepResult

Each completed step records its result and compensation action:

```yaml
StepResult:
  type: object
  required: [step_index, status, task_id]
  properties:
    step_index:
      type: integer
    status:
      type: string
      enum: [completed, failed, compensated, skipped]
    task_id:
      type: string
      format: uuid
    agent_session_id:
      type: string
      format: uuid
    artifact_ids:
      type: array
      items:
        type: string
        format: uuid
    compensation_action:
      $ref: "CompensationAction"
    started_at:
      type: string
      format: date-time
    completed_at:
      type: string
      format: date-time
```

## Compensation Model (Saga Pattern)

### Compensation Stack

WorkflowInstance maintains a LIFO compensation stack. Each completed step pushes its compensation action. On failure, compensation executes in reverse order.

```
Step 1 completes → push CompensateStep1
Step 2 completes → push CompensateStep2
Step 3 fails    → pop CompensateStep2, execute
                → pop CompensateStep1, execute
                → Workflow.Failed emitted
```

### Git-Native Compensation

For code-producing workflows, compensation uses Git operations:

| Step Action | Compensation | Description |
|------------|-------------|-------------|
| Create branch | `git branch -D` | Delete feature branch |
| Commit changes | `git revert <commit>` | Revert commit on main |
| Push to remote | Force-push revert | Update remote with revert |
| Create PR | Close PR | Close pull request |
| Merge PR | Revert merge commit | Revert the merge |

### Compensation Execution

```python
class CompensationExecutor:
    """Executes compensation actions in reverse order."""
    
    async def compensate(self, workflow: WorkflowInstance) -> CompensationResult:
        results = []
        
        # Execute in reverse order (LIFO)
        for action in reversed(workflow.compensation_stack):
            try:
                result = await self.execute_action(action)
                action.executed_at = datetime.utcnow()
                action.status = "completed"
                results.append(result)
            except CompensationError as e:
                # Log but continue compensating
                # Partial compensation is better than no compensation
                action.status = "failed"
                action.error = str(e)
                results.append(result)
        
        return CompensationResult(
            workflow_id=workflow.id,
            actions_executed=len(results),
            actions_succeeded=sum(1 for r in results if r.success),
            actions_failed=sum(1 for r in results if not r.success)
        )
```

### Compensation Guarantees

- **Best-effort**: Compensation attempts all actions even if some fail
- **Logged**: Every compensation action is logged with before/after state
- **Auditable**: Compensation events emitted for each action
- **Idempotent**: Compensation actions are idempotent (reverting twice is safe)

## Retry and Failure Handling

### RetryPolicy

```python
class RetryPolicy(BaseModel):
    """Retry behavior for tasks/workflows."""
    max_attempts: int = 3
    backoff_seconds: int = 60
    backoff_strategy: str = "exponential"  # exponential | linear | fixed
    retry_on: list[str] = ["FAILED", "TIMEOUT"]
    escalate_after: int = 2  # Escalate to different agent after N failures
```

### Failure Handling Flow

```
Step fails
    ↓
Check retry_policy
    ↓
retry_allowed?
    ├─ YES → Retry same agent (attempt + 1)
    │         ↓
    │     Still failing after escalate_after?
    │         ├─ YES → Escalate to different agent
    │         │         ↓
    │         │     Still failing?
    │         │         └─ Compensate + Fail workflow
    │         └─ NO → Continue retrying
    └─ NO → Compensate + Fail workflow
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
    context: dict = {}  # What the approver sees
```

### Approval Escalation

For critical workflows, approval can escalate:

```yaml
ApprovalEscalation:
  type: object
  properties:
    escalation_chain:
      type: array
      items:
        type: object
        properties:
          approver_id:
            type: string
          timeout_seconds:
            type: integer
          fallback:
            type: string
            enum: [next_approver, auto_approve, reject]
    quorum:
      type: integer
      description: "Required number of approvals"
    justification_required:
      type: boolean
      default: false
```

## Durable Execution

### State Persistence Strategy

- **Storage**: SQLite/PostgreSQL with synchronous writes
- **Checkpoints**: After each state transition
- **Event Sourcing**: Every state change emits a DomainEvent
- **Recovery**: On restart, replay events to reconstruct state
- **Migration Path**: PostgreSQL → Temporal-compatible via interface seam

### Durability Guarantee

The internal state machine MUST persist state transitions synchronously to maintain durability. Periodic persistence is insufficient for correct workflow semantics.

### Durable Execution Primitives

```yaml
DurableExecutionConfig:
  type: object
  properties:
    start_to_close_timeout_seconds:
      type: integer
      description: "Maximum time from step start to completion"
    schedule_to_close_timeout_seconds:
      type: integer
      description: "Maximum time from step scheduling to completion"
    heartbeat_timeout_seconds:
      type: integer
      description: "Maximum time between heartbeats from running step"
    checkpoint_interval_seconds:
      type: integer
      default: 30
      description: "How often to checkpoint running state"
```

### Recovery Process

```
1. On system restart:
   a. Load all WorkflowInstances from DB
   b. For each instance in non-terminal state:
      - Replay events since last checkpoint
      - Reconstruct state machine
      - Resume from last consistent state
   c. For steps that were Running but lost contact:
      - Check agent session status
      - If agent still running: reattach
      - If agent failed: trigger failure handling
      - If agent unknown: timeout and fail

2. Event replay guarantees:
   - Events are idempotent (applying same event twice is safe)
   - Checkpoints capture full state (no need to replay from beginning)
   - Compensation actions are idempotent
```

## Signal Handling

Workflows can be signaled for:
- Manual approval (Approval signal)
- External triggers (ExternalEvent signal)
- Cancellation (Cancel signal)
- Pause/Resume (Pause/Resume signal)

### Signal as Durable Primitive

Signals are persisted before delivery. If the workflow engine crashes between signal receipt and processing, the signal is re-delivered on recovery.

---

## Critical Implementation Details

### DAG Support

The WorkflowDefinition supports DAG structure for workflow design. Linear execution is the default mode.

```
         ┌─── Step B ───┐
Step A ──┤              ├─── Step D
         └─── Step C ───┘
```

Dependencies are enforced: a step cannot start until all its hard dependencies complete.

### Idempotent Step Execution

Each step execution uses the task's idempotency key to prevent duplicate execution:

```python
async def execute_step(self, workflow_id: UUID, task_spec: TaskSpec) -> None:
    idempotency_key = f"step_{workflow_id}_{task_spec.sequence}"
    
    # Check if already executed
    existing = await self.idempotency_store.get(idempotency_key)
    if existing:
        return existing.outcome  # Already executed, return stored result
    
    # Execute and store result
    result = await self._do_execute_step(workflow_id, task_spec)
    await self.idempotency_store.put(idempotency_key, result)
    return result
```

### Workflow-as-Event-Sourced Aggregate

WorkflowInstance state is derived from events, not stored directly:

```
Event: Workflow.Created → state: Requested
Event: Workflow.StepStarted → state: Implementation
Event: Workflow.StepCompleted → push compensation
Event: Workflow.StepStarted → state: Testing
Event: Workflow.StepCompleted → push compensation
Event: Workflow.Approved → state: Approved
Event: Workflow.Completed → state: Completed
```

On failure:
```
Event: Workflow.StepFailed → state: Compensating
Event: Compensation.Executed (step N) → pop compensation
Event: Compensation.Executed (step N-1) → pop compensation
Event: Workflow.Compensated → state: Failed
```

---

## Addressing Audit Concerns

### Workflow Durability (All 17 Audits)
Event-sourced WorkflowInstance with synchronous checkpointing. Recovery via event replay. Durable execution primitives (timeouts, heartbeats).

### Compensation Model (All 17 Audits)
Saga pattern with LIFO compensation stack. Git-native compensation for code workflows. Best-effort compensation with full audit trail.

### Idempotent Execution (Claude/Kimi)
All step executions use idempotency keys. Stored with outcome to prevent duplicate side effects.

### Approval Gates (All Audits)
Binary approval with escalation chains. Quorum support for multi-approver scenarios.

### DAG Features (Minimax)
Full DAG support with dependency enforcement. Linear execution as default.

### Signal Durability (Kimi)
Signals persisted before delivery. Crash-safe signal processing via event sourcing.
