# MVP Architecture Boundary

**Version:** 1.0.0  
**Status:** Enforced for Phase 1 Implementation

---

## Included: MVP Core Domain

### Entities

| Entity | Location | Status |
|--------|----------|--------|
| `Task` | `domain/entities/task.py` | ✅ Included |
| `Assignment` | `domain/entities/task.py` | ✅ Included (value object in Task) |
| `AgentDefinition` | `domain/entities/agent_definition.py` | ✅ Included |
| `Capability` | `domain/entities/agent_definition.py` | ✅ Included (entity in aggregate) |
| `WorkflowInstance` | `domain/entities/workflow_instance.py` | ✅ Included (linear only) |
| `Approval` | `domain/entities/workflow_instance.py` | ❌ Deferred (auto-approve in MVP) |
| `Artifact` | `domain/entities/artifact.py` | ✅ Included |
| `AgentInvocation` | `domain/entities/invocation.py` | ✅ Included |

### Value Objects

| Value Object | Status |
|--------------|--------|
| `TaskId` | ✅ Included |
| `AgentDefinitionId` | ✅ Included |
| `WorkflowInstanceId` | ✅ Included |
| `ContractVersion` | ✅ Included |
| `CostBudget` | ✅ Included |
| `RetryPolicy` | ✅ Included |

### Events

| Event | Status |
|-------|--------|
| `TaskCreated` | ✅ Included |
| `TaskAssigned` | ✅ Included |
| `TaskCompleted` | ✅ Included |
| `TaskFailed` | ✅ Included |
| `AgentStarted` | ✅ Included |
| `AgentCompleted` | ✅ Included |
| `AgentFailed` | ✅ Included |
| `AgentCancelled` | ❌ Deferred |
| `ArtifactProduced` | ✅ Included |
| `ArtifactValidated` | ✅ Included |
| `WorkflowTransitioned` | ✅ Included |

---

## Included: MVP Infrastructure (Implemented)

### Adapters

| Adapter | Status | Notes |
|---------|--------|-------|
| `AgentAdapter` protocol | ✅ Included | Abstract interface |
| `ClaudeCodeAdapter` | ✅ Included | First implementation |

### Workers

| Worker | Status | Notes |
|--------|--------|-------|
| `SandboxManager` | ✅ Included | Docker-based |
| `ArtifactValidator` | ✅ Included | JSON Schema validation |

### Storage

| Storage | MVP Implementation | Notes |
|---------|-------------------|-------|
| Definitions | Git files in `amir-config/` | YAML/JSON format |
| Runtime State | SQLite (via SQLModel) | Local file database |
| Artifacts | Local filesystem | `./artifacts/` directory |
| Events | Append-only file | `./logs/events.log` |

---

## Included: MVP Services

| Service | Status |
|---------|--------|
| `TaskService` | ✅ Included (create, assign, complete) |
| `OrchestrationService` | ✅ Included (agent matching, retry logic) |
| `WorkflowService` | ✅ Included (linear state machine) |
| `AgentRegistry` | ✅ Included (in-memory + file cache) |

---

## Excluded: Explicitly NOT in MVP

### Orchestration Features

```
❌ Multi-role teams
❌ Role assignment at team level
❌ Dynamic capability matching
❌ Agent load balancing
❌ Parallel task execution
❌ DAG workflows
❌ Human approval gates
❌ Compensation/rollback
```

### Infrastructure Features

```
❌ Temporal workflow engine
❌ Kafka/NATS message bus
❌ Kubernetes orchestration
❌ gVisor/Firecracker sandboxing
❌ HashiCorp Vault integration
❌ OpenTelemetry tracing
❌ Prometheus metrics
❌ Policy engine (OPA)
❌ Multi-tenant isolation
❌ Cost tracking/budgeting
❌ Artifact lineage
❌ Contract registry service
❌ Notification system
```

### Non-Core Features

```
❌ Web UI
❌ YAML CLI
❌ Plugin system
❌ Agent auto-discovery
❌ Capability auto-detection
❌ Sandbox escape detection
❌ Secret scanning
❌ Code quality metrics
❌ Performance optimization
❌ Caching layer
```

---

## MVP User Flow

### Input

```bash
# Create task via API or CLI
POST /tasks
{
  "objective": "Refactor authentication module",
  "assigned_role": "developer"
}
```

### Execution

```
1. Task created in SQLite
2. Agent selected (hardcoded: claude-code)
3. Docker container spawned
4. Task + constraints sent to agent
5. Agent produces CodeChangeArtifact
6. Validator checks JSON Schema
7. Task marked completed
8. Event logged
```

### Output

```json
{
  "task_id": "uuid",
  "status": "completed",
  "outputs": [
    {
      "artifact_id": "uuid",
      "type": "CodeChangeArtifact",
      "changes": [...]
    }
  ]
}
```

---

## MVP Success Criteria

The MVP is complete when:

1. **Task creation works** - Tasks can be created and stored
2. **Agent execution works** - Claude Code runs in Docker sandbox
3. **Artifact production works** - CodeChangeArtifact is produced
4. **Validation works** - Output passes JSON Schema validation
5. **Events are logged** - All state changes produce events
6. **Linear workflow works** - Task completes without manual intervention

---

## Evolution Path (Post-MVP)

### Phase 1.5 (+2 months)

- Add Codex adapter
- Add Role/Assignment entities
- Add SQLite → PostgreSQL migration
- Add basic metrics

### Phase 2 (+3 months)

- Add Workflow DAG support
- Add human approvals
- Add cost tracking
- Add OpenTelemetry

### Phase 3 (+6 months)

- Integrate Temporal
- Add multi-tenancy
- Add policy engine
- Add artifact provenance

---

## Package Structure (MVP)

```
src/amir/
├── main.py              # Entry point
├── api/
│   └── task_controller.py
├── application/
│   ├── task_service.py
│   └── workflow_service.py
├── domain/
│   ├── entities/
│   │   ├── task.py
│   │   ├── agent_definition.py
│   │   ├── workflow_instance.py
│   │   ├── artifact.py
│   │   └── invocation.py
│   ├── value_objects/
│   │   ├── ids.py
│   │   └── contract_version.py
│   ├── events/
│   │   ├── task_events.py
│   │   └── agent_events.py
│   └── protocols/
│       ├── agent_adapter.py
│       └── sandbox_manager.py
├── infrastructure/
│   ├── adapters/
│   │   └── claude_code.py
│   ├── persistence/
│   │   └── sqlite.py
│   └── sandbox/
│       └── docker.py
└── config/
    └── amir-config/
        ├── agents/
        ├── roles/
        └── contracts/
```