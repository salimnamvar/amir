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

Git repository structure under `amir-config/`:
- agents/
- roles/
- contracts/
- workflows/
- teams/

### Execution Context Storage

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

### Workflow Context Storage

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
    effect TEXT
);

CREATE TABLE secret_bindings (
    id UUID PRIMARY KEY,
    task_id UUID,
    secret_path TEXT,
    injected_at TIMESTAMP
);
```

## Migration Paths

### SQLite to PostgreSQL
Use Alembic for schema migration with dual-write strategy during transition.

### File to Message Queue
JSONL file with atomic appends can be replaced by Kafka producer with same schema.

### Single-Region to Multi-Region
- Database sharding by team/tenant
- Event replication between regions
- Consistent hashing for workflow routing

---

## Addressing Audit Concerns

### Workspace Persistence (All Audits)
Workspace state persisted in database enables reproduction of failed agent executions and workspace reuse across task retries.

### Audit Immutability (All Audits)
Append-only file storage with restricted permissions. Cryptographic signatures provide tamper detection.