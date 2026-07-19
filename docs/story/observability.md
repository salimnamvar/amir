# Epic: Observability

## As a Platform Operator
- I want to monitor system health
- So that I can maintain reliability

## As a Compliance Officer
- I want audit trails
- So that I can investigate incidents

## User Stories

### US-OBSERV-001: Structured Logging
```
As a Developer
I want structured JSON logs
So that I can analyze failures

Acceptance:
- All logs are JSON format
- Logs include event_id and correlation_id
- Logs written to /var/log/amir/
```

### US-OBSERV-002: Event Sourcing
```
As a System
I want all state changes as events
So that I can replay workflows

Acceptance:
- Task.Created, Task.Completed events
- AgentSession.Checkpoint events
- Workflow.Transitioned events
- Compensation.Executed events
- Events stored in append-only log
```

### US-OBSERV-003: Cost Tracking
```
As a Financial Owner
I want cost per task tracked
So that I can control spending

Acceptance:
- CostRecord created per invocation
- Orchestration/worker cost separated
- Hierarchical aggregation (team/tenant/org)
- Daily/monthly totals available
```

### US-OBSERV-004: Agent Performance Metrics
```
As a Platform Operator
I want agent scorecards
So that routing decisions are data-driven

Acceptance:
- AgentScorecard tracks success rate, cost, latency
- Failure patterns tracked
- Circuit breaker state visible
- Scorecard updated after each session
```

### US-OBSERV-005: Correlation Tracing
```
As a Debugger
I want to trace workflows
So that I can debug failures

Acceptance:
- correlation_id on all workflow events
- causation_id links events
- Full trace reconstructible
- W3C trace context included
```

### US-OBSERV-006: Validation Metrics
```
As a Developer
I want validation pipeline metrics
So that I can tune parser strategies

Acceptance:
- Parser strategy used recorded
- Parser attempt count tracked
- Structural/semantic pass rates
- Feedback generation rate
```

### US-OBSERV-007: Replay Capability
```
As a Developer
I want to replay agent execution
So that I can debug issues

Acceptance:
- ReplayMetadata on every AgentSession
- Model, prompt, seed, tool calls captured
- Replay endpoint reconstructs execution
- Sandbox profile hash for environment matching
```

### US-OBSERV-008: Outbox Pattern
```
As a System
I want reliable event delivery
So that events are never lost

Acceptance:
- Events published via outbox table
- Delivery semantics by category
- Domain: at-least-once, causal ordering
- Audit: at-least-once, total ordering
- Metrics: at-most-once
```

## Implementation Notes
- MVP: File-based JSONL logging with outbox
- All events include correlation_id/causation_id
- CostRecord with orchestration/worker separation
- AgentScorecard derived from cost and quality events
- Replay metadata for debugging
