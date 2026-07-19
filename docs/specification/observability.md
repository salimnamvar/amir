# Observability

## Event Model

### Event Categories

All events use the `DomainEvent` envelope:

| Category | Events | Retention | Purpose |
|----------|--------|-----------|---------|
| Lifecycle | Task.Created, Task.Completed, Agent.Started | Permanent | Core state tracking |
| Progress | AgentSession.Progress, AgentSession.Checkpoint | Configurable | Debugging, monitoring |
| Security | Secret.Accessed, Sandbox.Created, Access.Denied | Permanent/90 days | Compliance, forensics |
| Cost | Cost.Recorded, Cost.BudgetExceeded, Cost.ReservationCreated | 365 days | Cost control, attribution |
| Quality | Artifact.Validated, Artifact.Rejected, Quality.Measured | Configurable | Quality gates |
| Compensation | Compensation.Started, Compensation.Executed, Compensation.Failed | Permanent | Workflow rollback audit |
| Routing | MatchingDecision.Made, CircuitBreaker.Opened, CircuitBreaker.Closed | Configurable | Agent selection audit |

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
    sequence: int = 0    # Monotonic sequence for hash chain
    prev_hash: str = ""  # Hash of previous event
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
        """Persist event atomically. Compute hash chain."""
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
            "cost": "365_days",
            "quality": "configurable",
            "compensation": "permanent",
            "routing": "configurable"
        }
```

### Outbox Pattern

Domain events are published via outbox pattern for reliable delivery:

```yaml
OutboxEntry:
  type: object
  required: [sequence, event_type, payload, created_at]
  properties:
    sequence:
      type: integer
      description: "Monotonically increasing sequence"
    event_type:
      type: string
    payload:
      type: object
    created_at:
      type: string
      format: date-time
    published_at:
      type: string
      format: date-time
    delivery_status:
      type: string
      enum: [pending, delivered, failed]
    idempotency_key:
      type: string
```

### Delivery Semantics

| Event Category | Delivery | Ordering | Retry |
|---------------|----------|----------|-------|
| Domain | At-least-once | Causal (per-aggregate) | Exponential backoff |
| Audit | At-least-once | Total (global) | Until success |
| Metrics | At-most-once | None | No retry |

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

First-class cost entity with multi-dimensional attribution:

```python
class CostRecord(BaseModel):
    """Token/cost consumption tracking with attribution."""
    id: UUID
    task_id: UUID
    agent_session_id: UUID
    agent_definition_id: UUID
    team_id: UUID
    
    # Consumption
    tokens_input: int
    tokens_output: int
    tokens_total: int
    cost_usd: float
    
    # Attribution
    orchestration_cost_usd: float  # Amir overhead
    worker_cost_usd: float         # Agent/LLM cost
    
    # Timing
    duration_seconds: float
    started_at: datetime
    completed_at: datetime
    
    # Context
    contract_type: str
    workflow_instance_id: UUID | None
    step_index: int | None
```

### Cost Hierarchy

```
Per-Invocation CostRecord
    ↓ (aggregate)
Per-Team Hourly CostSummary
    ↓ (aggregate)
Per-Tenant Daily CostSummary
    ↓ (aggregate)
Per-Org Monthly CostSummary
```

### Cost Summary

```yaml
CostSummary:
  type: object
  properties:
    period:
      type: string
      enum: [hourly, daily, monthly]
    team_id:
      type: string
      format: uuid
    total_tokens:
      type: integer
    total_cost_usd:
      type: number
    orchestration_cost_usd:
      type: number
    worker_cost_usd:
      type: number
    invocation_count:
      type: integer
    avg_cost_per_invocation:
      type: number
    cost_by_agent:
      type: object
      additionalProperties:
        type: number
    cost_by_contract_type:
      type: object
      additionalProperties:
        type: number
```

### Agent Performance Metrics

AgentScorecard derived from cost and quality events:

```yaml
AgentScorecard:
  type: object
  properties:
    agent_definition_id:
      type: string
      format: uuid
    period:
      type: string
      enum: [24h, 7d, 30d]
    
    # Success metrics
    total_invocations:
      type: integer
    successful_invocations:
      type: integer
    success_rate:
      type: number
      minimum: 0.0
      maximum: 1.0
    
    # Cost metrics
    avg_cost_usd:
      type: number
    p95_cost_usd:
      type: number
    total_cost_usd:
      type: number
    
    # Latency metrics
    avg_duration_seconds:
      type: number
    p95_duration_seconds:
      type: number
    
    # Quality metrics
    avg_validation_score:
      type: number
    structural_validation_rate:
      type: number
    semantic_validation_rate:
      type: number
    
    # Failure patterns
    failure_patterns:
      type: array
      items:
        $ref: "FailurePattern"
    
    # Circuit breaker
    circuit_breaker:
      $ref: "CircuitBreakerState"
```

### Quality Metrics

```python
class QualityMetric(BaseModel):
    """Artifact quality assessment."""
    id: UUID
    artifact_id: UUID
    agent_session_id: UUID
    metric_type: str  # structural_validation, semantic_validation, test_coverage, etc.
    score: float
    passed: bool
    details: dict
    measured_at: datetime
    validator_version: str
```

### Validation Metrics

Track validation pipeline performance:

```yaml
ValidationMetric:
  type: object
  properties:
    session_id:
      type: string
      format: uuid
    parser_strategy_used:
      type: string
      description: "Which parser strategy succeeded"
    parser_attempts:
      type: integer
      description: "How many strategies were tried"
    structural_valid:
      type: boolean
    semantic_valid:
      type: boolean
    validation_duration_ms:
      type: integer
    feedback_generated:
      type: boolean
    retry_triggered:
      type: boolean
```

## Quality Criteria Validation

Roles declare quality criteria for artifact validation:

```yaml
QualityCriteria:
  type: object
  properties:
    min_test_coverage:
      type: integer
      minimum: 0
      maximum: 100
    max_cyclomatic_complexity:
      type: integer
    require_code_review:
      type: boolean
    check_security_patterns:
      type: boolean
    semantic_validators:
      type: array
      items:
        type: object
        properties:
          name:
            type: string
          type:
            type: string
            enum: [structural, test_execution, quality, behavioral]
          timeout_seconds:
            type: integer
            default: 300
          budget_usd:
            type: number
            default: 0.10
          config:
            type: object
```

## Replay and Debugging

### Replay Metadata

Every AgentSession captures replay metadata for debugging:

```yaml
ReplayMetadata:
  type: object
  properties:
    session_id:
      type: string
      format: uuid
    model_identifier:
      type: string
      description: "LLM model used"
    prompt_hash:
      type: string
      description: "SHA256 of compiled prompt"
    full_prompt:
      type: string
      description: "Complete prompt sent to agent"
    seed:
      type: integer
      description: "Random seed (if applicable)"
    tool_calls:
      type: array
      items:
        $ref: "ToolCall"
    sandbox_profile_hash:
      type: string
      description: "SHA256 of sandbox configuration"
    agent_version:
      type: string
```

### Debug Query API

```yaml
DebugQuery:
  type: object
  properties:
    session_id:
      type: string
      format: uuid
    include_checkpoints:
      type: boolean
      default: true
    include_tool_calls:
      type: boolean
      default: true
    include_raw_output:
      type: boolean
      default: false
    include_validation_details:
      type: boolean
      default: true
```

---

## Addressing Audit Concerns

### Event Model Overreach (GLM)
Simple file-based logging is the default. Retention policies are configurable but not mandatory.

### Quality Validation (All Audits)
Quality metrics defined with pluggable validators. Semantic validation has timeout and budget constraints.

### Progress Streaming (GLM)
Progress events emitted on state transitions. Continuous streaming available via optional instrumentation.

### Cost as First-Class (All 17 Audits)
CostRecord with multi-dimensional attribution. Hierarchical cost summaries. AgentScorecard derived from cost events.

### Audit Tamper-Evidence (Minimax/GLM)
Merkle-chained events with sequence numbers and prev_hash. Periodic root-commit to external transparency log.

### Replay Capability (Minimax)
Full replay metadata on every AgentSession. Enables exact reproduction of agent execution for debugging.
