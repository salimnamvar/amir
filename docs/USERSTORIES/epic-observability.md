# Epic: Observability

## As a Platform Operator
- I want to monitor system health
- So that I can maintain reliability

## As a Security Officer
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
- Workflow.Transitioned events
- Events stored in append-only log
```

### US-OBSERV-003: Cost Tracking
```
As a Financial Owner
I want cost per task tracked
So that I can control spending

Acceptance:
- CostRecord created per invocation
- Tokens and USD cost recorded
- Daily/monthly totals available
```

### US-OBSERV-004: Correlation Tracing
```
As a Debugger
I want to trace workflows
So that I can debug failures

Acceptance:
- correlation_id on all workflow events
- causation_id links events
- Full trace reconstructible
```

### US-OBSERV-005: MVP Metrics Dashboard
```
As a Developer
I want basic metrics in MVP
So that I can monitor progress

Acceptance:
- Task count by status
- Success/failure rate
- Simple log file analysis
```

---

## Implementation Notes

- MVP: File-based JSONL logging
- Phase 2: Prometheus + Grafana
- All events include correlation_id/causation_id
- Metrics collected synchronously from adapters