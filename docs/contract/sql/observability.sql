-- Contract: Observability Context storage DDL
-- Authority: docs/contract/sql/observability.sql
-- Related data contracts: cost-record, cost-summary, agent-scorecard, cost-lease schemas

CREATE TABLE cost_records (
    id UUID PRIMARY KEY,
    task_id UUID,
    agent_session_id UUID,
    agent_definition_id UUID,
    team_id UUID NOT NULL,
    tenant_id UUID,
    org_id UUID,
    budget_pool TEXT NOT NULL DEFAULT 'execution',  -- execution|validation|compensation|orchestration
    tokens_input INTEGER,
    tokens_output INTEGER,
    tokens_total INTEGER,
    cost_usd DECIMAL,
    orchestration_cost_usd DECIMAL,
    worker_cost_usd DECIMAL,
    validation_cost_usd DECIMAL DEFAULT 0,
    parser_strategy_used TEXT,
    duration_seconds FLOAT,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE INDEX idx_cost_records_tenant ON cost_records(tenant_id, started_at);
CREATE INDEX idx_cost_records_org ON cost_records(org_id, started_at);
CREATE INDEX idx_cost_records_pool ON cost_records(budget_pool, started_at);

CREATE TABLE cost_summaries (
    id UUID PRIMARY KEY,
    period TEXT NOT NULL,
    team_id UUID,
    tenant_id UUID,
    org_id UUID,
    agent_definition_id UUID,
    total_usd DECIMAL NOT NULL,
    orchestration_cost_usd DECIMAL,
    worker_cost_usd DECIMAL,
    validation_cost_usd DECIMAL,
    total_tokens INTEGER,
    session_count INTEGER
);

-- Historical Scorecards (time-series by period)
-- Full metrics read model for routing decisions; distinct from current state view in Execution Context.
CREATE TABLE agent_scorecards (
    agent_definition_id UUID,
    period TEXT,
    total_invocations INTEGER,
    invocation_count INTEGER,  -- alias for exploration_bonus
    successful_invocations INTEGER,
    failed_invocations INTEGER,
    success_rate FLOAT,
    avg_cost_usd FLOAT,
    p95_cost_usd FLOAT,
    avg_duration_seconds FLOAT,
    p95_duration_seconds FLOAT,
    staleness_seconds INTEGER DEFAULT 0,
    failure_patterns JSONB,
    circuit_breaker_state JSONB,
    warm_started BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP,
    PRIMARY KEY (agent_definition_id, period)
);
