# Epic: Orchestration

## As a Developer
- I want to create tasks programmatically
- So that I can automate feature development

## As a Platform Operator
- I want to monitor task execution
- So that I can ensure system reliability

## User Stories

### US-ORCH-001: Create Task via API
```
As a Developer
I want to POST /tasks with objective and role
So that an agent executes the work

Acceptance:
- Task created with PENDING status
- Event Task.Created emitted
- Task appears in task list
```

### US-ORCH-002: Assign Task to Agent
```
As an Orchestrator
I want to match tasks to capable agents
So that work is distributed efficiently

Acceptance:
- Agent invocation created
- Event Task.Assigned emitted
- Agent receives TaskContract
```

### US-ORCH-003: Track Task Progress
```
As a Developer
I want to GET /tasks/{id} for current status
So that I can monitor progress

Acceptance:
- Returns current state (PENDING/ASSIGNED/RUNNING/etc)
- Returns assigned agent
- Returns artifact if completed
```

### US-ORCH-004: Handle Task Failure
```
As a System
I want to retry failed tasks
So that transient failures are handled

Acceptance:
- Task transitions to FAILED state
- Retry count incremented
- New AgentInvocation created if under limit
```

### US-ORCH-005: Enforce Cost Limits
```
As a Platform Owner
I want hard limits on task costs
So that runaway agents don't bankrupt us

Acceptance:
- Task has max_tokens and max_usd
- Adapter kills process at 95% threshold
- Event Task.Failed emitted on limit breach
```

### US-ORCH-006: Isolated Workspace
```
As a Security Officer
I want each task in isolated workspace
So that agents can't interfere with each other

Acceptance:
- Each task gets unique workspace
- Workspace cleaned after task completion
- No shared filesystem between tasks
```

---

## Implementation Notes

- Task aggregate root in Execution Context
- Assignment is value object within Task
- AgentInvocation created per attempt
- Workspace created before invocation
- Cost limits enforced synchronously