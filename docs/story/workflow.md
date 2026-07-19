# Epic: Workflow

## As a Developer
- I want to define feature workflows
- So that complex features are orchestrated

## As a Project Manager
- I want to track workflow progress
- So that I know feature status

## User Stories

### US-WORKFLOW-001: Create Linear Workflow
```
As a Developer
I want to define 3-state workflow
So that features go through impl/test/review

Acceptance:
- Workflow with states: impl → test → review
- Tasks auto-created per state
- Workflow progresses on task completion
- Compensation actions defined per step
```

### US-WORKFLOW-002: Workflow State Persistence
```
As a System
I want workflow state durable
So that restarts don't lose state

Acceptance:
- Event-sourced WorkflowInstance
- State derived from events (not stored directly)
- Recovery via event replay
- Checkpointing after each state transition
```

### US-WORKFLOW-003: Compensation on Failure
```
As a Platform Operator
- I want failed workflows to compensate
- So that system remains consistent

Acceptance:
- Compensation stack (LIFO) maintained
- Abstract intents (rollback_workspace_effects, …) mapped to durable_effects
- Concrete actions: git revert, branch delete, PR close, artifact delete
- Targets durable commits/branches/PRs — not already-cleaned workspaces
- Best-effort: all actions attempted even if some fail
- Compensation events emitted for audit
```

### US-WORKFLOW-004: Task Dependencies
```
As a Developer
I want task dependencies
So that workflows execute in correct order

Acceptance:
- Hard dependencies block execution
- Workflow waits for dependencies
- Cycle detection prevents deadlock
- DAG support with dependency enforcement
```

### US-WORKFLOW-005: Workflow Recovery
```
As a System
I want failed workflows recoverable
So that manual recovery is possible

Acceptance:
- Failed workflow can be retried
- Workflow state can be inspected
- Manual intervention supported
- Compensation can be re-triggered
```

### US-WORKFLOW-006: Auto-Approve Transitions
```
As a Developer
I want auto-approval in automated workflows
So that workflows run without human intervention

Acceptance:
- All transitions auto-approved by default
- Approval entity used only for manual gates
- Workflow completes automatically
```

### US-WORKFLOW-007: Idempotent Step Execution
```
As a System
I want step execution to be idempotent
So that retries don't cause duplicate side effects

Acceptance:
- Each step uses idempotency key
- Duplicate execution returns stored result
- No duplicate artifacts produced
- No duplicate cost records
```

### US-WORKFLOW-008: Durable Execution Primitives
```
As a System
I want workflow steps to have timeouts and heartbeats
So that hung steps are detected

Acceptance:
- start_to_close_timeout_seconds per step
- heartbeat_timeout_seconds for long-running steps
- Steps that exceed timeout are killed
- Workflow transitions to failed/compensating
```

## Implementation Notes

- Event-sourced WorkflowInstance with compensation stack
- Git-native compensation for code workflows
- Idempotent step execution via idempotency keys
- Durable execution with timeouts and heartbeats
- Recovery via event replay on restart
