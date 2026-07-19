-- Contract: Observability Context storage DDL
-- Authority: docs/contract/sql/observability.sql
-- Related data contracts: cost-record, agent-scorecard schemas

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
