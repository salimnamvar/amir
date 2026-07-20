-- Contract: Workflow Context storage DDL
-- Authority: docs/contract/sql/workflow.sql
-- Related data contracts: workflow, approval, compensation-action, escalation-signal, step-result schemas

CREATE TABLE workflow_instances (
    id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    definition_id UUID,
    name TEXT,
    version TEXT,
    team_id UUID,
    current_state TEXT,
    instance_status TEXT NOT NULL DEFAULT 'pending',
    -- instance_status: pending|running|awaiting_approval|succeeded|failed|
    --                   compensating|compensation_blocked|escalated|rejected|cancelled
    state_data JSONB,
    compensation_stack JSONB DEFAULT '[]',  -- LIFO CompensationAction refs
    step_results JSONB DEFAULT '[]',        -- ordered StepResult refs by sequence
    current_step_id TEXT,
    durable_execution_config_ref TEXT,
    continue_on_compensation_failure BOOLEAN DEFAULT FALSE,
    escalation_on_blocked BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE workflow_tasks (
    id UUID PRIMARY KEY,
    workflow_instance_id UUID REFERENCES workflow_instances(id),
    task_id UUID REFERENCES tasks(id),
    step_id TEXT,
    sequence INTEGER NOT NULL,
    status TEXT,  -- pending|running|succeeded|failed|compensated|compensation_blocked|skipped
    compensation_action JSONB,
    durable_effects_snapshot JSONB,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE TABLE step_results (
    step_result_id UUID PRIMARY KEY,
    workflow_instance_id UUID REFERENCES workflow_instances(id),
    step_id TEXT NOT NULL,
    task_id UUID,
    session_id UUID,
    status TEXT NOT NULL,
    sequence INTEGER NOT NULL,
    compensation JSONB,
    durable_effects_snapshot JSONB,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE TABLE compensation_actions (
    id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    workflow_instance_id UUID REFERENCES workflow_instances(id),
    action_type TEXT NOT NULL,
    target_ref TEXT NOT NULL,
    workflow_step_id TEXT,
    produced_in_session_id UUID,
    durable_effects_snapshot JSONB,
    concrete_actions JSONB,
    status TEXT DEFAULT 'pending',
    error TEXT,
    remediation_steps JSONB,
    executed_at TIMESTAMP
);

CREATE TABLE approvals (
    approval_id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    workflow_id UUID NOT NULL,
    gate_name TEXT NOT NULL,
    approval_type TEXT DEFAULT 'workflow_gate',  -- workflow_gate|coercion|manual
    status TEXT NOT NULL DEFAULT 'pending',
    -- pending|auto_approved|granted|rejected|expired|cancelled
    auto_approve BOOLEAN DEFAULT FALSE,  -- safe default: explicit opt-in
    approver_id TEXT,
    approver_role TEXT,
    requested_at TIMESTAMP,
    responded_at TIMESTAMP,
    expires_at TIMESTAMP,
    timeout_seconds INTEGER DEFAULT 86400,
    context JSONB
);

CREATE TABLE escalation_signals (
    signal_id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    target_type TEXT NOT NULL,  -- agent_session|workflow_instance
    target_id UUID NOT NULL,
    escalation_type TEXT NOT NULL,
    reason TEXT,
    assigned_to TEXT NOT NULL,
    notification_channel TEXT,
    response_deadline TIMESTAMP,
    remediation_plan JSONB,
    safe_abort_available BOOLEAN DEFAULT TRUE,
    triggered_at TIMESTAMP,
    acknowledged_at TIMESTAMP,
    acknowledged_by TEXT,
    resolution TEXT DEFAULT 'pending',
    resolution_notes TEXT
);
