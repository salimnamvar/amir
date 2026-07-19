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
```

### US-WORKFLOW-002: Workflow State Persistence
```
As a System
I want workflow state durable
So that restarts don't lose state

Acceptance:
- State saved after each transition
- Workflow resumes after restart
- No duplicate task creation
```

### US-WORKFLOW-003: Auto-Approve Transitions (MVP)
```
As a Developer
I want auto-approval in MVP
So that workflows run without human intervention

Acceptance:
- All transitions auto-approved
- No Approval entity used
- Workflow completes automatically
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
```

---

## Implementation Notes

- MVP: Internal state machine with SQLite
- Phase 2: Temporal integration
- Approval gates are auto-approved in MVP
- All transitions emit Workflow.Transitioned events