# Persistence

## Storage Responsibilities

Each bounded context uses appropriate storage for its data:

```
┌─────────────────────────────────────────────────────────────┐
│  Configuration Context                                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │amir-config/  │────▶│     Git      │                      │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Execution Context                                          │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Entities   │────▶│  SQLite/PG   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Artifacts  │────▶│Object Storage│ (large payloads)     │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Workflow Context                                           │
│  ┌──────────────┐     ┌──────────────┐  ┌──────────────┐   │
│  │   Instances  │────▶│  PostgreSQL   │  │ Event Store  │   │
│  └──────────────┘     └──────────────┘  │ (event source)│   │
│                                          └──────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  Security Context                                           │
│  ┌──────────────┐     ┌──────────────┐ ┌──────────────┐    │
│  │   Policies   │────▶│  PostgreSQL    │ │ HashiCorp    │    │
│  └──────────────┘     └──────────────┘ │   Vault      │    │
│  ┌──────────────┐     ┌──────────────┐ └──────────────┘    │
│  │    Audit     │────▶│  JSONL File   │ (append-only)      │
│  └──────────────┘     └──────────────┘                     │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │Egress Proxy  │────▶│  PostgreSQL   │ (request log)       │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Observability Context                                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Metrics    │────▶│  Prometheus   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │ Cost Records │────▶│  PostgreSQL   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │  Scorecards  │────▶│  PostgreSQL   │ (read model)        │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Traces     │────▶│ OpenTelemetry  │                      │
│  └──────────────┘     └──────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Data Models

### Configuration Context Storage

Git repository structure under `amir-config/`:
- agents/
- roles/
- contracts/
- workflows/
- teams/
- skills/
- prompts/

### Execution Context Storage

**SQLite Schema**:

```sql
CREATE TABLE tasks (
    id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE,
    title TEXT NOT NULL,
    objective TEXT NOT NULL,
    assigned_role TEXT NOT NULL,
    status TEXT NOT NULL,
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 3,
    -- retry_state (task-scoped); circuit breakers live on agent_scorecards
    last_failure_category TEXT,  -- structural|semantic|policy|quality|timeout|infrastructure|cancelled|budget_exceeded
    last_session_id UUID,
    escalated BOOLEAN DEFAULT FALSE,
    cost_budget_max_tokens INTEGER,
    cost_budget_max_usd REAL,
    validation_budget_max_tokens INTEGER,  -- partitioned from execution budget
    validation_budget_max_usd REAL,
    matching_decision_id UUID,
    active_workspace_id UUID,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CHECK (cost_budget_max_tokens IS NOT NULL OR cost_budget_max_usd IS NOT NULL)
);

CREATE TABLE agent_sessions (
    session_id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    task_id UUID REFERENCES tasks(id),
    agent_definition_id UUID,
    matching_decision_id UUID,
    attempt_number INTEGER NOT NULL,
    previous_session_id UUID,
    status TEXT NOT NULL,
    workspace_id UUID,
    sandbox_id UUID,
    sandbox_attestation_id UUID,
    compiled_prompt_id UUID,
    cost_lease_id UUID,  -- sync hard-kill gate reference
    validation_result_id UUID,
    cost_record_id UUID,
    max_tokens INTEGER,
    max_usd REAL,
    timeout_seconds INTEGER NOT NULL,
    -- High-frequency telemetry is NOT stored as unbounded JSON on this row:
    -- checkpoints → checkpoints table; tool_calls → event stream; usage history → cost_records
    resource_usage_snapshot JSONB,  -- latest meters only
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    CHECK (max_tokens IS NOT NULL OR max_usd IS NOT NULL)
);

CREATE TABLE workspaces (
    id UUID PRIMARY KEY,
    task_id UUID REFERENCES tasks(id),
    session_id UUID UNIQUE NOT NULL,  -- 1 session : 1 workspace
    repo_url TEXT,
    branch TEXT,
    workdir TEXT,
    status TEXT NOT NULL CHECK (status IN ('created', 'active', 'observed', 'cleaned', 'failed')),
    baseline_commit TEXT,
    current_commit TEXT,
    baseline_tree_hash TEXT,
    durable_effects JSONB,  -- commit/branch/PR targets for compensation
    ephemeral BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP,
    observed_at TIMESTAMP,
    cleaned_at TIMESTAMP
);

-- Circuit breaker lives with agent performance, not tasks
-- Note: This is a CURRENT_STATE view for quick lookup; full metrics in Observability Context agent_scorecards
CREATE TABLE agent_scorecards_current (
    agent_definition_id UUID PRIMARY KEY,
    success_rate REAL,
    circuit_breaker_state TEXT DEFAULT 'closed',
    circuit_breaker_failures INTEGER DEFAULT 0,
    warm_started BOOLEAN DEFAULT FALSE,
    last_updated TIMESTAMP
);

CREATE TABLE artifacts (
    id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE,
    contract_type TEXT NOT NULL,
    contract_version TEXT NOT NULL,
    content JSONB,
    provenance JSONB,
    checksum TEXT,
    derived_from UUID[],
    supersedes UUID,
    observation_method TEXT,
    status TEXT DEFAULT 'produced',
    created_at TIMESTAMP
);

CREATE TABLE checkpoints (
    checkpoint_id UUID PRIMARY KEY,
    session_id UUID REFERENCES agent_sessions(session_id),
    state TEXT NOT NULL,
    payload JSONB,
    workspace_snapshot TEXT,
    created_at TIMESTAMP
);

-- Full tool-call history (session document holds only a recent ring buffer)
CREATE TABLE tool_call_events (
    tool_call_id UUID PRIMARY KEY,
    session_id UUID REFERENCES agent_sessions(session_id) NOT NULL,
    tool_name TEXT NOT NULL,
    tool_input JSONB,
    tool_output JSONB,
    status TEXT NOT NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
);

CREATE TABLE cost_leases (
    lease_id UUID PRIMARY KEY,
    task_id UUID NOT NULL,
    agent_session_id UUID,
    reserved_usd REAL NOT NULL,
    reserved_tokens INTEGER NOT NULL,
    consumed_usd REAL DEFAULT 0,
    consumed_tokens INTEGER DEFAULT 0,
    scope TEXT NOT NULL,  -- invocation|team|tenant|org
    status TEXT NOT NULL,  -- active|revoked|expired|released
    cancelled BOOLEAN DEFAULT FALSE,
    cancellation_reason TEXT,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE TABLE idempotency_keys (
    key TEXT PRIMARY KEY,
    operation_type TEXT NOT NULL,
    outcome JSONB,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
);
```

### Workflow Context Storage

```sql
CREATE TABLE workflow_instances (
    id UUID PRIMARY KEY,
    definition_id UUID,
    team_id UUID,
    current_state TEXT,
    state_data JSONB,
    compensation_stack JSONB DEFAULT '[]',
    step_results JSONB DEFAULT '[]',
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE workflow_tasks (
    id UUID PRIMARY KEY,
    workflow_instance_id UUID REFERENCES workflow_instances(id),
    task_id UUID REFERENCES tasks(id),
    sequence INTEGER,
    status TEXT,
    compensation_action JSONB
);
```

### Event Store (Outbox Pattern)

```sql
CREATE TABLE outbox_entries (
    sequence SERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    aggregate_id UUID NOT NULL,
    aggregate_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP,
    delivery_status TEXT DEFAULT 'pending'
);

CREATE INDEX idx_outbox_pending ON outbox_entries(delivery_status, created_at)
    WHERE delivery_status = 'pending';
```

### Security Context Storage

```sql
CREATE TABLE access_policies (
    id UUID PRIMARY KEY,
    resource TEXT,
    action TEXT,
    subject TEXT,
    conditions JSONB,
    effect TEXT
);

CREATE TABLE secret_bindings (
    id UUID PRIMARY KEY,
    task_id UUID,
    session_id UUID,
    secret_name TEXT,
    secret_ref TEXT,
    injected_at TIMESTAMP,
    expires_at TIMESTAMP,
    access_method TEXT CHECK (access_method IN ('env', 'file', 'proxy')),
    access_path TEXT,
    single_use BOOLEAN DEFAULT FALSE,
    status TEXT CHECK (status IN ('active', 'used', 'expired', 'revoked')),
    created_by TEXT,
    revoked_at TIMESTAMP
);

CREATE TABLE egress_log (
    id SERIAL PRIMARY KEY,
    session_id UUID,
    destination TEXT,
    method TEXT,
    status_code INTEGER,
    tokens_counted INTEGER,
    cost_usd DECIMAL,
    logged_at TIMESTAMP
);
```

### Observability Context Storage

```sql
CREATE TABLE cost_records (
    id UUID PRIMARY KEY,
    task_id UUID,
    agent_session_id UUID,
    agent_definition_id UUID,
    team_id UUID,
    tokens_input INTEGER,
    tokens_output INTEGER,
    tokens_total INTEGER,
    cost_usd DECIMAL,
    orchestration_cost_usd DECIMAL,
    worker_cost_usd DECIMAL,
    duration_seconds FLOAT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- Historical Scorecards (time-series by period)
-- Full metrics read model for routing decisions; distinct from current state view in Execution Context.
CREATE TABLE agent_scorecards (
    agent_definition_id UUID,
    period TEXT,
    total_invocations INTEGER,
    successful_invocations INTEGER,
    success_rate FLOAT,
    avg_cost_usd FLOAT,
    p95_cost_usd FLOAT,
    avg_duration_seconds FLOAT,
    p95_duration_seconds FLOAT,
    failure_patterns JSONB,
    circuit_breaker_state JSONB,
    updated_at TIMESTAMP,
    PRIMARY KEY (agent_definition_id, period)
);
```

## Migration Paths

### SQLite to PostgreSQL
Use Alembic for schema migration with dual-write strategy during transition.

### File to Message Queue
JSONL file with atomic appends can be replaced by Kafka producer with same schema. Outbox table provides reliability during transition.

### Single-Region to Multi-Region
- Database sharding by team/tenant
- Event replication between regions
- Consistent hashing for workflow routing
- Cost records replicated for global queries

---

## Addressing Audit Concerns

### Workspace Persistence (All Audits)
Workspace state persisted with baseline/current commit tracking enables reproduction of failed agent executions and workspace reuse across task retries.

### Audit Immutability (All Audits)
Append-only file storage with restricted permissions. Merkle-chained events with cryptographic signatures provide tamper-evidence.

### Event Sourcing (Tinker/Kimi)
WorkflowInstance state derived from events. Event store provides full audit trail and enables replay for debugging.

### Outbox Pattern (Kimi)
Reliable event publishing via outbox table. Delivery semantics enforced by category.

### Cost Records (All 17 Audits)
Multi-dimensional CostRecord with orchestration/worker cost separation. Hierarchical aggregation for budget monitoring.
