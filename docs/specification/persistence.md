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
├─────────────────────────────────────────────────────────────┤
│  Workflow Context                                           │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Instances  │────▶│  PostgreSQL    │                      │
│  └──────────────┘     └──────────────┘                      │
├─────────────────────────────────────────────────────────────┤
│  Security Context                                           │
│  ┌──────────────┐     ┌──────────────┐ ┌──────────────┐    │
│  │   Policies   │────▶│  PostgreSQL    │ │ HashiCorp    │    │
│  └──────────────┘     └──────────────┘ │   Vault      │    │
│  ┌──────────────┐     ┌──────────────┐ └──────────────┘    │
│  │    Audit     │────▶│  JSONL File   │ (append-only)      │
├─────────────────────────────────────────────────────────────┤
│  Observability Context                                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Metrics    │────▶│  Prometheus   │                      │
│  └──────────────┘     └──────────────┘                      │
│  ┌──────────────┐     ┌──────────────┐                      │
│  │   Traces     │────▶│ OpenTelemetry  │                      │
│  └──────────────┘     └──────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

## Data Models

### Configuration Context Storage

```yaml
# Git repository structure: amir-config/
agents/
  claude-code.yaml
  codex.yaml
roles/
  developer.yaml
  reviewer.yaml
contracts/
  code-change-artifact.yaml
  test-result-artifact.yaml
workflows/
  feature-development.yaml
teams/
  platform-team.yaml
```

### Execution Context Storage (MVP)

**SQLite Schema**:

```sql
CREATE TABLE tasks (
    id UUID PRIMARY KEY,
    title TEXT NOT NULL,
    objective TEXT NOT NULL,
    assigned_role TEXT NOT NULL,
    status TEXT NOT NULL,
    attempts INTEGER DEFAULT 0,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE agent_invocations (
    invocation_id UUID PRIMARY KEY,
    task_id UUID REFERENCES tasks(id),
    agent_definition_id UUID,
    status TEXT NOT NULL,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

CREATE TABLE workspaces (
    id UUID PRIMARY KEY,
    task_id UUID REFERENCES tasks(id),
    repo_url TEXT,
    branch TEXT,
    workdir TEXT,
    created_at TIMESTAMP,
    cleaned_at TIMESTAMP
);
```

### Workflow Context Storage (Phase 2)

```sql
CREATE TABLE workflow_instances (
    id UUID PRIMARY KEY,
    definition_id UUID,
    team_id UUID,
    current_state TEXT,
    state_data JSONB,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

CREATE TABLE workflow_tasks (
    id UUID PRIMARY KEY,
    workflow_instance_id UUID REFERENCES workflow_instances(id),
    task_id UUID REFERENCES tasks(id),
    sequence INTEGER,
    status TEXT
);
```

### Security Context Storage

```sql
CREATE TABLE access_policies (
    id UUID PRIMARY KEY,
    resource TEXT,
    action TEXT,
    subject TEXT,
    conditions JSONB,
    effect TEXT  -- allow|deny
);

CREATE TABLE secret_bindings (
    id UUID PRIMARY KEY,
    task_id UUID,
    secret_path TEXT,
    injected_at TIMESTAMP
);
```

## Migration Paths

### SQLite to PostgreSQL (Phase 2)

```python
# Use Alembic for schema migration
# SQLite → PostgreSQL with minimal downtime
# Strategy: dual-write during transition, then cut-over
```

### File to Kafka (Phase 2)

```python
# Phase 1: JSONL file with atomic appends
# Phase 2: Kafka producer with same schema
# Consumers read from either source during transition
```

### Single-Region to Multi-Region (Phase 4)

- Database sharding by team/tenant
- Event replication between regions
- Consistent hashing for workflow routing

---

## Addressing Audit Concerns

### Workspace Persistence (Minimax)

Workspace state is persisted in PostgreSQL. This enables:
- Reproducing failed agent executions
- Workspace reuse across task retries
- Cleanup reconciliation after crashes

### Audit Immutability (GLM)

MVP uses append-only file with restricted permissions (0644). Hash chaining deferred to Phase 2 to maintain MVP simplicity.