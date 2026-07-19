-- Contract: Execution Context storage DDL
-- Authority: docs/contract/sql/execution.sql
-- Related data contracts: task, agent-session, workspace, artifact, cost-lease schemas

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
