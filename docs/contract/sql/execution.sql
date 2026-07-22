-- Contract: Execution Context storage DDL
-- Authority: docs/contract/sql/execution.sql
-- Related data contracts: task, agent-session, workspace, artifact, cost-lease schemas

CREATE TABLE tasks (
    id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE,
    title TEXT NOT NULL,
    objective TEXT NOT NULL,
    assigned_role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    team_id UUID,
    tenant_id UUID,
    org_id UUID,
    attempts INTEGER DEFAULT 0,
    max_attempts INTEGER DEFAULT 3,
    -- retry_state (task-scoped); circuit breakers live on agent_scorecards
    last_failure_category TEXT,  -- TerminalFailureCategory incl. behavioral|test_execution
    last_session_id UUID,
    escalated BOOLEAN DEFAULT FALSE,
    cost_budget_max_tokens INTEGER,
    cost_budget_max_usd REAL,
    validation_budget_max_tokens INTEGER,  -- REQUIRED partitioned budget (at least one of tokens/usd)
    validation_budget_max_usd REAL,
    validation_budget_consumed_usd REAL DEFAULT 0,
    validation_lease_id UUID,
    matching_decision_id UUID,
    active_workspace_id UUID,
    previous_workspace_ids UUID[],
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    CHECK (cost_budget_max_tokens IS NOT NULL OR cost_budget_max_usd IS NOT NULL),
    CHECK (validation_budget_max_tokens IS NOT NULL OR validation_budget_max_usd IS NOT NULL),
    -- assigned/running/committing require matching_decision_id
    CHECK (
      status NOT IN ('assigned', 'running', 'committing')
      OR matching_decision_id IS NOT NULL
    ),
    -- terminal failed/cancelled require last_failure_category
    CHECK (
      status NOT IN ('failed', 'cancelled')
      OR last_failure_category IS NOT NULL
    )
);

CREATE INDEX idx_tasks_matching_decision ON tasks(matching_decision_id)
  WHERE matching_decision_id IS NOT NULL;

CREATE TABLE agent_sessions (
    session_id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    task_id UUID REFERENCES tasks(id),
    agent_definition_id UUID,
    matching_decision_id UUID,
    attempt_number INTEGER NOT NULL,
    previous_session_id UUID,
    -- status excludes compensating (workflow-owned); cost lease revoke → cancelled + budget_exceeded
    status TEXT NOT NULL,
    workspace_id UUID NOT NULL,  -- required: 1 session owns exactly 1 workspace
    sandbox_id UUID,
    sandbox_attestation_id UUID,
    compiled_prompt_id UUID,
    cost_lease_id UUID,  -- required when status in (starting, running, waiting_for_input, producing_artifact, validating)
    lease_check_revision INTEGER,  -- P0-COSTLEASE-RACE: must match CostLease.lease_revision before succeeded
    validation_result_id UUID,  -- ID only; never embed full ValidationResult
    feedback_artifact_id UUID,  -- ID only; never embed full Feedback
    cost_record_id UUID,
    last_failure_category TEXT,  -- TerminalFailureCategory; required when status in failed|cancelled|timed_out (app+CHECK)
    max_tokens INTEGER,
    max_usd REAL,
    timeout_seconds INTEGER NOT NULL,
    pending_input JSONB,  -- P0-PENDING-INPUT-DDL: interactive prompts durable
    -- High-frequency telemetry is NOT stored on this row (P0-AGENTSESSION-GOD):
    -- checkpoints → checkpoints table; tool_calls → event stream; usage → cost_records
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    CHECK (max_tokens IS NOT NULL OR max_usd IS NOT NULL),
    CHECK (
      status NOT IN ('starting', 'running', 'waiting_for_input', 'producing_artifact', 'validating')
      OR cost_lease_id IS NOT NULL
    ),
    CHECK (
      status NOT IN ('failed', 'cancelled', 'timed_out')
      OR last_failure_category IS NOT NULL
    ),
    -- P0-PENDING-INPUT-ENFORCEMENT: required fields inside pending_input
    CHECK (
      status IS DISTINCT FROM 'waiting_for_input'
      OR (pending_input IS NOT NULL AND pending_input ? 'prompt_text' AND pending_input ? 'input_kind' AND pending_input ? 'timeout_seconds' AND pending_input ? 'on_timeout')
    )
);

CREATE TABLE workspaces (
    id UUID PRIMARY KEY,
    task_id UUID REFERENCES tasks(id),
    session_id UUID UNIQUE NOT NULL,  -- 1 session : 1 workspace
    repo_url TEXT,
    branch TEXT,
    workdir TEXT,
    status TEXT NOT NULL CHECK (status IN ('created', 'active', 'observed', 'auto_commit_failed', 'cleaned', 'failed')),
    auto_commit JSONB,  -- P0-AUTO-COMMIT-CHECK: committed=true required when status=observed
    baseline_commit TEXT,
    current_commit TEXT,
    baseline_tree_hash TEXT,
    durable_effects JSONB,  -- commit/branch/PR targets for compensation; append-only effects_log
    ephemeral BOOLEAN DEFAULT TRUE,
    sandbox_policy_id UUID,
    sandbox_attestation_id UUID,  -- P1-SANDBOX-ATTESTATION-DDL: attestation reference for sandbox
    effective_allowlist_hash TEXT,
    created_at TIMESTAMP,
    observed_at TIMESTAMP,
    cleaned_at TIMESTAMP,
    -- P0-AUTO-COMMIT-CHECK: workspace can only be observed after successful auto-commit
    CHECK (
      status IS DISTINCT FROM 'observed'
      OR (auto_commit IS NOT NULL AND (auto_commit->>'committed')::boolean = true)
    )
);

-- Circuit breaker lives with agent performance, not tasks
-- Note: This is a CURRENT_STATE view for quick lookup; full metrics in Observability Context agent_scorecards
CREATE TABLE agent_scorecards_current (
    agent_definition_id UUID PRIMARY KEY,
    success_rate REAL,
    total_invocations INTEGER DEFAULT 0,
    staleness_seconds INTEGER DEFAULT 0,
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
    supersedes UUID[],  -- P1-SUPERSEDES-ARRAY: multi-artifact supersession
    observation_method TEXT,
    validation_result_id UUID,  -- canonical claim_reconciliation lives on validation_results
    coercion_approval_id UUID,  -- required when observation_method=synthesized
    sandbox_attestation_id UUID,
    status TEXT DEFAULT 'produced',
    created_at TIMESTAMP,
    CHECK (
      observation_method IS DISTINCT FROM 'synthesized'
      OR coercion_approval_id IS NOT NULL
    )
);

CREATE TABLE checkpoints (
    checkpoint_id UUID PRIMARY KEY,
    session_id UUID REFERENCES agent_sessions(session_id),
    sequence INTEGER NOT NULL,  -- monotonic per session for replay ordering
    state TEXT NOT NULL,
    payload JSONB,  -- bounded; large state via external refs
    workspace_snapshot TEXT,
    created_at TIMESTAMP,
    UNIQUE (session_id, sequence)
);

-- Full tool-call history (session document holds only a recent ring buffer of IDs)
CREATE TABLE tool_call_events (
    tool_call_id UUID PRIMARY KEY,
    session_id UUID REFERENCES agent_sessions(session_id) NOT NULL,
    sequence INTEGER NOT NULL,  -- monotonic per session for replay ordering
    tool_name TEXT NOT NULL,
    tool_input JSONB,
    tool_output JSONB,
    status TEXT NOT NULL,
    started_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP,
    UNIQUE (session_id, sequence)
);

CREATE INDEX idx_tool_call_session_seq ON tool_call_events(session_id, sequence);

CREATE TABLE cost_leases (
    lease_id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    task_id UUID NOT NULL,
    agent_session_id UUID,  -- required when status=active (hard-kill target)
    budget_pool TEXT NOT NULL,  -- execution|validation
    reserved_usd REAL NOT NULL,
    reserved_tokens INTEGER NOT NULL,
    consumed_usd REAL DEFAULT 0,
    consumed_tokens INTEGER DEFAULT 0,
    kill_threshold_pct REAL DEFAULT 95,
    lease_revision INTEGER NOT NULL DEFAULT 0,
    revocation_revision INTEGER,
    revocation_timestamp TIMESTAMP,
    sidecar_ack_deadline_ms INTEGER DEFAULT 5000,
    scope TEXT NOT NULL,  -- invocation|team|tenant|org
    team_id UUID,
    tenant_id UUID,
    org_id UUID,
    status TEXT NOT NULL,  -- active|revoked|expired|released (no separate cancelled boolean)
    cancellation_reason TEXT,
    retryable BOOLEAN,
    fail_closed_on_unavailable BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP,
    expires_at TIMESTAMP,
    CHECK (
      status IS DISTINCT FROM 'revoked'
      OR (
        cancellation_reason IS NOT NULL
        AND revocation_revision IS NOT NULL
        AND revocation_timestamp IS NOT NULL
      )
    ),
    CHECK (
      status IS DISTINCT FROM 'active'
      OR agent_session_id IS NOT NULL
    )
);
-- P0-LEASE-REVISION-MONOTONICITY: Trigger to enforce lease_revision increments by exactly 1 per mutation
CREATE OR REPLACE FUNCTION enforce_lease_revision_monotonicity()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.lease_revision IS NOT NULL THEN
    IF NEW.lease_revision != OLD.lease_revision + 1 THEN
      RAISE EXCEPTION 'lease_revision must increment by exactly 1 per mutation (got % from %)', 
        NEW.lease_revision, OLD.lease_revision;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER cost_lease_revision_check
  BEFORE UPDATE ON cost_leases
  FOR EACH ROW EXECUTE FUNCTION enforce_lease_revision_monotonicity();

-- CostLease authority: Observability Context owns the CostLease aggregate and lifecycle.
-- Execution Context holds cost_lease_id reference on AgentSession and Task.
-- Hierarchical cascade: CostEnforcer.revoke_by_scope revokes all active leases for team/tenant/org.


CREATE TABLE idempotency_keys (
    key TEXT PRIMARY KEY,
    operation_type TEXT NOT NULL,
    scope TEXT DEFAULT 'global',  -- global|tenant|team|task|agent
    outcome JSONB,
    created_at TIMESTAMP,
    expires_at TIMESTAMP
);

CREATE TABLE validation_results (
    validation_id UUID PRIMARY KEY,
    target_type TEXT NOT NULL,
    target_id UUID NOT NULL,
    session_id UUID,
    task_id UUID,
    valid BOOLEAN NOT NULL,
    validators JSONB NOT NULL,
    error_categories JSONB NOT NULL,
    claim_reconciliation JSONB,  -- canonical; artifacts reference this row by id
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);
