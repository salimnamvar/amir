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
- Idempotency key required
- Event Task.Created emitted
- Task appears in task list
```

### US-ORCH-002: Assign Task to Agent
```
As an Orchestrator
I want to match tasks to capable agents
So that work is distributed efficiently

Acceptance:
- MatchingDecision emitted with dimension scores
- Multi-dimensional scoring algorithm used
- AgentScorecard consulted for historical metrics
- Circuit breaker checked (open = reject)
- AgentSession created for selected agent
```

### US-ORCH-003: Track Task Progress
```
As a Developer
I want to GET /tasks/{id} for current status
So that I can monitor progress

Acceptance:
- Returns current state (PENDING/ASSIGNED/RUNNING/etc)
- Returns assigned agent
- Returns AgentSession checkpoints
- Returns artifact if completed
```

### US-ORCH-004: Handle Task Failure
```
As a System
I want to retry failed tasks with feedback
So that agents can correct their mistakes

Acceptance:
- ValidationResult emitted with error categories
- FeedbackArtifact created with corrections
- Retry allowed within max_attempts budget
- Escalation to different agent after escalate_after
- Circuit breaker opens after failure_threshold
```

### US-ORCH-005: Enforce Cost Limits
```
As a Platform Owner
I want hard limits on task costs
So that runaway agents do not bankrupt us

Acceptance:
- Hierarchical cost gate (4 levels)
- Pre-flight cost estimation
- Sidecar proxy counts tokens in real-time
- Process killed at 95% threshold
- CostRecord emitted with attribution
```

### US-ORCH-006: Isolated Workspace
```
As a Security Officer
I want each task in isolated workspace
So that agents cannot interfere with each other

Acceptance:
- Each task gets unique workspace
- Baseline commit recorded before execution
- Current commit recorded after execution
- Workspace cleaned after task completion
- No shared filesystem between tasks
```

### US-ORCH-007: Idempotent Operations
```
As a System
I want all operations idempotent
So that retries are safe

Acceptance:
- Task creation uses idempotency key
- AgentSession uses idempotency key
- Artifact production uses idempotency key
- Duplicate operations return stored result
```

## Implementation Notes
- Task aggregate root in Execution Context
- Assignment is value object within Task
- AgentSession created per attempt (with checkpoint chain)
- Workspace created before invocation with baseline tracking
- Cost limits enforced hierarchically
- All operations idempotent by default
