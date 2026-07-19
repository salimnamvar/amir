# Observability

## Event Model

### Domain Event Categories

All events use the `DomainEvent` envelope:

| Category | Events | Retention | Purpose |
|----------|--------|-----------|---------|
| Lifecycle | Task.Created, Task.Completed, Agent.Started | Permanent | Core state tracking |
| Progress | AgentInvocation.Progress | 30 days | Debugging, monitoring |
| Security | Secret.Accessed, Sandbox.Created | Permanent/90 days | Compliance, forensics |
| Metrics | Cost.Recorded, Quality.Measured | 90 days | Cost control, quality gates |

### Event Envelope Structure

```python
class DomainEvent(BaseModel):
    """Standard envelope for all domain events."""
    event_id: UUID = Field(default_factory=uuid4)
    event_type: str
    aggregate_id: UUID
    aggregate_type: str
    correlation_id: UUID  # For workflow tracing
    causation_id: UUID    # For causality chain
    producer: str         # Component that emitted
    version: str = "1.0.0"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict[str, Any]
```

### W3C Trace Context (Phase 2)

Events will include trace context headers:
- `traceparent`: W3C trace identifier
- `tracestate`: Vendor-specific trace state

## MVP Observability

### Event Logging

```python
class FileEventPublisher(EventPublisher):
    """MVP event publisher to JSONL file."""
    
    def __init__(self, path: str = "/var/log/amir/events.jsonl"):
        self.path = path
    
    async def publish(self, event: DomainEvent) -> None:
        """Append event to file atomically."""
        with open(self.path, "a") as f:
            f.write(event.model_dump_json() + "\n")
```

### Metrics Collection

MVP metrics collected synchronously:

```python
class CostRecord(BaseModel):
    """Token/cost consumption tracking."""
    task_id: UUID
    agent_invocation_id: UUID
    tokens_consumed: int
    cost_usd: float
    duration_seconds: float
    timestamp: datetime
```

### Log Format

All logs are structured JSON:

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "component": "AgentAdapter",
  "event_id": "123e4567-e89b-12d3-a456-426614174000",
  "message": "Agent invocation completed",
  "data": {
    "invocation_id": "...",
    "status": "COMPLETED",
    "duration_seconds": 45
  }
}
```

## Phase 2 Observability

### OpenTelemetry Integration

```python
# W3C trace context propagation
tracer = trace.get_tracer("amir.workflow")

with tracer.start_as_current_span("workflow_execution") as span:
    span.set_attribute("workflow.id", workflow_id)
    span.set_attribute("task.count", len(tasks))
```

### Prometheus Metrics

```prometheus
# HELP amir_tasks_total Number of tasks by status
# TYPE amir_tasks_total counter
amir_tasks_total{status="completed"} 42
amir_tasks_total{status="failed"} 3
amir_tasks_total{status="running"} 2

# HELP amir_cost_usd_total Cost by task type
# TYPE amir_cost_usd_total counter
amir_cost_usd_total{type="implementation"} 12.50
amir_cost_usd_total{type="testing"} 3.25
```

### Grafana Dashboards

- **Task Execution**: Success rate, duration, retry count
- **Cost Tracking**: Daily/Monthly spend, per-agent costs
- **Security**: Failed auth attempts, secret access, sandbox events
- **Workflow**: Active workflows, approval latency

## Quality Metrics (Phase 2)

```python
class QualityMetric(BaseModel):
    """Artifact quality assessment."""
    artifact_id: UUID
    metric_type: str      # test_coverage, code_review, etc.
    score: float          # 0.0 to 1.0
    details: dict
    measured_at: datetime
```

### Quality Criteria Validation

Roles can declare quality criteria:

```yaml
quality_criteria:
  min_test_coverage: 80
  max_cyclomatic_complexity: 10
  require_code_review: true
  check_security_patterns: true
```

## Addressing Audit Concerns

### Event Model Overreach (GLM)

MVP uses simple file-based logging. No tiered retention or complex routing. This matches the stated infrastructure.

### Quality Validation Who (DeepSeek)

Phase 2 adds `TestRunner` component that validates artifacts independently. MVP only does structural validation.

### Progress Streaming (GLM)

MVP does not stream progress. `AgentInvocation.Progress` event exists but is only emitted on completion. Progress streaming (Phase 2) requires sampling to prevent event volume explosion.