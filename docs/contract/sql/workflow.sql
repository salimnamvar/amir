-- Contract: Workflow Context storage DDL
-- Authority: docs/contract/sql/workflow.sql
-- Related data contracts: workflow.schema.yaml

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
