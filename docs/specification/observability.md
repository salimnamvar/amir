# Observability

## Event Model

### Event Categories

All events use the `DomainEvent` envelope:

| Category | Events | Retention | Purpose |
|----------|--------|-----------|---------|
| Lifecycle | Task.Created, Task.Completed, Agent.Started | Permanent | Core state tracking |
| Progress | AgentInvocation.Progress | Configurable | Debugging, monitoring |
| Security | Secret.Accessed, Sandbox.Created | Permanent/90 days | Compliance, forensics |
| Metrics | Cost.Recorded, Quality.Measured | Configurable | Cost control, quality gates |

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
    signature: str = ""  # Cryptographic signature for integrity
```

### W3C Trace Context

Events include trace context headers when available:
- `traceparent`: W3C trace identifier
- `tracestate`: Vendor-specific trace state

## Event Storage

### Strategy

Events are stored in an append-only event store with configurable retention policies.

```python
class EventStore:
    """Durable event storage."""
    
    def append(self, event: DomainEvent) -> None:
        """Persist event atomically."""
        pass
    
    def query(self, filter: EventFilter) -> list[DomainEvent]:
        """Query events by criteria."""
        pass
    
    def retention_policy(self) -> RetentionPolicy:
        """Return retention rules by category."""
        return {
            "lifecycle": "permanent",
            "security": "permanent",
            "progress": "configurable",
            "metrics": "90_days"
        }
```

### File-Based Storage (Default)

```python
class FileEventPublisher(EventPublisher):
    """Default event publisher to JSONL file."""
    
    def __init__(self, path: str):
        self.path = path
    
    async def publish(self, event: DomainEvent) -> None:
        """Append event to file atomically."""
        with open(self.path, "a") as f:
            f.write(event.model_dump_json() + "\n")
```

## Metrics Collection

### Cost Recording

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

### Quality Metrics

```python
class QualityMetric(BaseModel):
    """Artifact quality assessment."""
    artifact_id: UUID
    metric_type: str
    score: float
    details: dict
    measured_at: datetime
```

## Quality Criteria Validation

Roles declare quality criteria for artifact validation:

```yaml
quality_criteria:
  min_test_coverage: 80
  max_cyclomatic_complexity: 10
  require_code_review: true
  check_security_patterns: true
```

---

## Addressing Audit Concerns

### Event Model Overreach (GLM)
Simple file-based logging is the default. Retention policies are configurable but not mandatory.

### Quality Validation (All Audits)
Quality metrics are defined but validation is performed by external validators plugged into the ArtifactValidator interface.

### Progress Streaming (GLM)
Progress events exist but are emitted on state transitions. Continuous streaming is available via optional instrumentation.