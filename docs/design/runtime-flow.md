# Amir Runtime Flow

**Scope:** MVP Implementation Flows

---

## Task Lifecycle

```
1. Task Created
   │
   ▼
   Status: PENDING
   ├── Awaiting resource allocation
   └── Awaiting agent matching

2. Agent Selected
   │
   ▼
   Status: ASSIGNED
   ├── Assignment created
   └── Sandbox reserved

3. Agent Started
   │
   ▼
   Status: RUNNING
   ├── AgentInvocation.Started emitted
   └── Sandbox executing

4. Agent Completed
   │
   ▼
   Status: VALIDATING
   ├── Artifact produced
   └── ArtifactValidator.validate() called

5. Artifact Validated
   │   ├── Valid → COMPLETED
   │   └── Invalid → FAILED (with retry logic)
   ▼
   TaskCompleted event emitted
```

### Implementation Points

- **State transitions** are atomic (database transactions)
- **Events emitted** after each successful transition
- **Retries** handled by orchestration loop
- **Timeouts** enforced by Sandbox Manager

---

## Agent Invocation Lifecycle

```
AgentInvocation Lifecycle:

1. Invocation Created
   │
   ▼
   Status: PENDING
   └── Waiting for sandbox resource

2. Sandbox Ready
   │
   ▼
   Status: RUNNING
   ├── AgentAdapter.start_invocation() called
   └── stdout/stderr accessible

3. Agent Outputs Result
   │
   ▼
   Status: COMPLETED
   ├── Artifact extracted from output
   ├── ResourceUsage captured
   └── AgentCompleted event emitted

4. Error Path
   │
   ▼
   Status: FAILED
   ├── Error details captured
   ├── Retry logic triggered (if attempts < max)
   └── AgentFailed event emitted

5. Cancel Path
   │
   ▼
   Status: CANCELLED
   └── AgentAdapter.cancel() called
```

### Implementation Points

- **Streaming output** supported via callbacks
- **Cancellation** is best-effort (SIGTERM then SIGKILL)
- **Timeout** enforced by Sandbox Manager (hard limit)
- **Progress events** for long-running agents

---

## Artifact Lifecycle

```
1. Artifact Produced
   │
   ▼
   Status: PRODUCED
   ├── Content captured from agent output
   ├── Provenance recorded
   └── ArtifactCreated event emitted

2. Validation Started
   │
   ▼
   Status: VALIDATING
   ├── Structural validation (schema)
   ├── Semantic validation (business rules)
   └── Security validation (no secrets)

3. Validation Result
   │   ├── Pass → ACCEPTED
   │   └── Fail → REJECTED
   ▼
   ArtifactValidated event emitted
```

### Implementation Points

- **Schema validation** uses JSON Schema library
- **Semantic validation** custom per-contract
- **Security validation** scans for patterns
- **Accepted artifacts** stored in object store

---

## Workflow Lifecycle (Linear MVP)

```
Workflow States (MVP):

REQUESTED
    │
    ▼
PLANNED
    │
    ▼
IMPLEMENTATION
    │
    ▼
TESTING
    │
    ▼
REVIEW
    │
    ▼
COMPLETED
```

### Implementation Points

- **Linear transitions** for MVP
- **State persistence** in database
- **Task templates** mapped to roles
- **No parallel execution** in MVP
- **No human approvals** in MVP (auto-approve after validation)

---

## Cross-Context Flow

```
┌─────────────────────┐
│   API / CLI Input   │
└─────────┬───────────┘
          │ TaskCreated
          ▼
┌─────────────────────┐
│  Orchestration      │
│  (Task Service)     │
└─────────┬───────────┘
          │ AssignmentCreated
          ▼
┌─────────────────────┐
│  Sandbox Manager    │
│  (Execution)        │
└─────────┬───────────┘
          │ SandboxReady
          ▼
┌─────────────────────┐
│  Agent Adapter      │
│  (Infrastructure)   │
└─────────┬───────────┘
          │ AgentCompleted
          ▼
┌─────────────────────┐
│  Artifact Validator │
│  (Domain Service)   │
└─────────┬───────────┘
          │ ArtifactValidated
          ▼
┌─────────────────────┐
│  Workflow Engine    │
│  (Workflow Context) │
└─────────┬───────────┘
          │ TaskCompleted
          ▼
┌─────────────────────┐
│  Audit Logger       │
│  (Security Context) │
└─────────────────────┘
```

---

## Error Handling Flow

```
Agent Error:
    AgentFailed event
    ├── Retry check (attempts < max)
    ├── Yes → New invocation
    └── No → TaskFailed event
            Workflow transition to FAILED

Validation Error:
    ArtifactRejected event
    ├── TaskFailed event
    └── Workflow may retry or abort

Timeout:
    SandboxKill event
    ├── AgentFailed event with timeout reason
    └── Retry or fail logic
```

---

## Event Flow Examples

### Successful Task

```
1. TaskCreated {task_id, role: "developer"}
2. AgentStarted {invocation_id, task_id, agent: "claude"}
3. ArtifactProduced {artifact_id, task_id, contract: "CodeChangeArtifact"}
4. ArtifactValidated {artifact_id, valid: true}
5. AgentCompleted {invocation_id, status: "success"}
6. TaskCompleted {task_id, status: "completed"}
```

### Failed Task (Retried)

```
1. TaskCreated {task_id, role: "developer"}
2. AgentStarted {invocation_id: 1, task_id}
3. AgentFailed {invocation_id: 1, error: "timeout"}
4. AgentStarted {invocation_id: 2, task_id}
5. ArtifactProduced {artifact_id, task_id}
6. ArtifactValidated {artifact_id, valid: true}
7. AgentCompleted {invocation_id: 2, status: "success"}
8. TaskCompleted {task_id, status: "completed"}
```