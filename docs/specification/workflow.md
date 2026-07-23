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


> **Interface contract:** [`docs/contract/interfaces/workflow-engine.yaml`](../contract/interfaces/workflow-engine.yaml)


## Workflow Model

### States

```
REQUESTED → PLANNED → IMPLEMENTATION → TESTING → REVIEW → APPROVED → COMPLETED
                 ↓            ↓              ↓
           COMPENSATING   FAILED         ESCALATED
                 ↓
        COMPENSATION_BLOCKED  (durable-effect compensation failed; human EscalationSignal)
                 ↓
              CANCELLED / FAILED (after human resolution)
```

### Task Specification


> **Contract:** [`docs/contract/schemas/execution/task.schema.yaml`](../contract/schemas/execution/task.schema.yaml)


### CompensationSpec

Each workflow step declares compensation **intent** upfront. Concrete git/PR/artifact actions are resolved when the step records `durable_effects` on its Workspace. Compensation never depends on the ephemeral sandbox filesystem still existing.


> **Contract:** [`docs/contract/schemas/orchestration/compensation-action.schema.yaml`](../contract/schemas/orchestration/compensation-action.schema.yaml)


### StepResult

Each completed step records its result and compensation action:


> **Contract:** [`docs/contract/schemas/orchestration/step-result.schema.yaml`](../contract/schemas/orchestration/step-result.schema.yaml)


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

Default policy: `continue_on_compensation_failure=false`. Durable-effect failures (git_revert, branch_delete, pr_close, …) **block** the workflow and escalate to humans — they must not be silently skipped.

```python
class CompensationExecutor:
    """Executes compensation actions in reverse order."""
    
    async def compensate(self, workflow: WorkflowInstance) -> CompensationResult:
        results = []
        continue_on_failure = workflow.compensation_config.continue_on_compensation_failure  # default False
        
        # Execute in reverse order (LIFO)
        for action in reversed(workflow.compensation_stack):
            try:
                result = await self.execute_action(action)
                action.executed_at = datetime.utcnow()
                action.status = "completed"
                results.append(result)
            except CompensationError as e:
                action.status = "failed"
                action.error = str(e)
                results.append(CompensationActionResult(success=False, error=str(e)))
                emit(Compensation.Failed(...))
                if not continue_on_failure:
                    # Durable-effect failure → blocked state + human escalation
                    workflow.status = "CompensationBlocked"
                    emit(Compensation.Blocked(...))
                    emit(Escalation.Signal(
                        escalation_type="compensation_blocked",
                        target_type="workflow_instance",
                        target_id=workflow.id,
                        reason=str(e),
                        assigned_to=workflow.team_oncall_id,  # required recipient
                        remediation_plan=action.remediation_steps,
                        safe_abort_available=True,
                    ))
                    return CompensationResult(blocked=True, ...)
                # Explicit opt-in only: log and continue remaining actions
        
        return CompensationResult(
            workflow_id=workflow.id,
            actions_executed=len(results),
            actions_succeeded=sum(1 for r in results if r.success),
            actions_failed=sum(1 for r in results if not r.success),
            blocked=False,
        )
```

### Compensation Failure Path (COMPENSATION_BLOCKED)

| Condition | Behavior |
|-----------|----------|
| Durable-effect compensation fails | Emit `Compensation.Failed` |
| Target missing (stale PR/branch/commit) | Pre-check `verification.exists=false` → status **`verification_failed`**; emit EscalationSignal |
| `continue_on_compensation_failure=false` (default) | Enter **CompensationBlocked**; emit `Escalation.Signal` (`compensation_blocked`) with `remediation_plan` |
| Human acknowledges | Resume compensation, abort workflow, or manual remediate (`EscalationSignal.resolution`) |
| `continue_on_compensation_failure=true` | Explicit opt-in only; log failure and continue stack (not recommended for git/PR effects) |
| Mid-flight CostLease kill | Compensate from `Workspace.durable_effects.effects_log` (append-only during execution) |
| `Workspace.status=auto_commit_failed` | Do **not** clean ephemeral FS; remediation before compensation targets are trusted |

### Pre-execution verification (stale git/PR refs)

Before each concrete action (`git_revert`, `branch_delete`, `pr_close`, …):

1. Resolve `target` using `target_kind` (commit_sha, branch_name, pr_number, …).
2. Check remote existence; record `verification.{exists, remote_checked, verified_at}`.
3. If `exists=false` → set action `status=verification_failed`, require `error` + `remediation_steps`, escalate (do not silently skip).
4. Merge commits, force-push races, and already-closed PRs are **verification/escalation** cases, not silent success.

### Compensation Guarantees

- **Default block-and-escalate**: Durable-effect failures do not silently continue
- **Logged**: Every compensation action is logged with before/after state
- **Auditable**: Compensation events (`Started` / `Executed` / `Failed` / `Blocked` / `Completed`) for each path
- **Idempotent**: Compensation actions are idempotent (reverting twice is safe)
- **Human signal**: `EscalationSignal` is the mandatory human escalation channel when blocked

## Retry and Failure Handling

### RetryPolicy


> **Contract:** [`docs/contract/schemas/execution/task.schema.yaml#retry_policy`](../contract/schemas/execution/task.schema.yaml#retry_policy)


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

### Fleet Deployment Retry and Fallback

Fleet deployment operations MUST have defined retry and fallback semantics:

| Component | Retry Policy | Fallback Path | Circuit Breaker |
|-----------|-------------|---------------|-----------------|
| FleetDeployRequest | exponential backoff, max 3 retries | Rollback to previous version | Per-fleet |
| FleetScaleRequest | exponential backoff, max 2 retries | Maintain current scale | Per-fleet |
| AgentStartRequest | linear backoff, max 2 retries | Fail task | Per-agent |
| AgentStopRequest | immediate retry, max 1 retry | Force kill | Per-agent |
| PoolScaleRequest | exponential backoff, max 2 retries | Maintain current pool | Per-pool |

**Retry policy:**
- `max_retries`: Maximum number of retry attempts
- `backoff_strategy`: exponential | linear | fixed
- `backoff_seconds`: Initial backoff duration
- `retryable_errors`: List of error codes that trigger retry
- `non_retryable_errors`: List of error codes that fail immediately

**Fallback paths:**
- Fleet deployment failure → rollback to previous version, emit `Fleet.DeployFailed`
- Fleet scale failure → maintain current scale, emit `Fleet.ScaleFailed`
- Agent start failure → fail task with `infrastructure` category
- Agent stop failure → force kill process, emit `AgentSession.Cancelled`

**Circuit breaker:**
- Per-entity (fleet, agent, pool) circuit breakers
- Open after 3 consecutive failures
- Half-open after 60 seconds
- Close on successful probe

## Approval Model


> **Contract:** [`docs/contract/schemas/orchestration/approval.schema.yaml`](../contract/schemas/orchestration/approval.schema.yaml)


### Approval Escalation

For critical workflows, approval can escalate:


> **Contract:** [`docs/contract/schemas/orchestration/approval.schema.yaml#escalation`](../contract/schemas/orchestration/approval.schema.yaml#escalation)


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


> **Contract:** [`docs/contract/schemas/execution/durable-execution-config.schema.yaml`](../contract/schemas/execution/durable-execution-config.schema.yaml)


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

### Request Handler Idempotency

All request handlers that perform mutable operations MUST include an idempotency key:

| Handler | Idempotency Key | Scope | Description |
|---------|----------------|-------|-------------|
| AgentStartRequest | `idempotency_key` | team | Prevent duplicate agent creation |
| AgentStopRequest | `idempotency_key` | team | Prevent duplicate stop signals |
| PoolScaleRequest | `idempotency_key` | team | Prevent duplicate scaling operations |
| FleetDeployRequest | `idempotency_key` | team | Prevent duplicate fleet deployments |
| SessionCreateRequest | `idempotency_key` | task | Prevent duplicate session creation |

On receipt, handlers MUST check if a request with the same key has already been processed. If so, return the cached result instead of re-executing. Use the `IdempotencyKey` contract for storage and TTL.

> **Contract:** [`docs/contract/schemas/eventing/idempotency-key.schema.yaml`](../contract/schemas/eventing/idempotency-key.schema.yaml)

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
Saga pattern with LIFO compensation stack. Git-native compensation for durable effects. Default block-and-escalate on compensation failure (CompensationBlocked + EscalationSignal); continue_on_failure is explicit opt-in only.

### Idempotent Execution (Claude/Kimi)
All step executions use idempotency keys. Stored with outcome to prevent duplicate side effects.

### Approval Gates (All Audits)
Binary approval with escalation chains. Quorum support for multi-approver scenarios.

### DAG Features (Minimax)
Full DAG support with dependency enforcement. Linear execution as default.

### Signal Durability (Kimi)
Signals persisted before delivery. Crash-safe signal processing via event sourcing.
