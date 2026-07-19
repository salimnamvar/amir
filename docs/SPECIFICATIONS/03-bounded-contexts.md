# Bounded Contexts

## Overview

Amir is organized into five bounded contexts, each with clear ownership and responsibilities. Context diagrams use DDD notation: each context is an aggregate root boundary with explicit dependencies.

## 1. Configuration Context

**Purpose**: GitOps-managed, immutable definitions

**Owner**: Platform with team scoping (multi-tenant, Phase 2)

**Entities**:

| Entity | Purpose |
|--------|---------|
| TeamDefinition | Team namespace, policies, budget caps |
| RoleDefinition | Contract of responsibilities with inputs/outputs |
| AgentDefinition | Agent configuration, capabilities, adapter settings |
| ContractDefinition | Schema definitions with SemVer |
| WorkflowDefinition | Workflow template with states and transitions |
| Capability | Skill/tool declarations for routing |

**Lifecycle**: Draft → Validating → Published → Deprecated → Retired

**Storage**: Git repository (`amir-config/`)

**Events**: Definition.Created, Definition.Updated, Definition.Published, Definition.Deprecated

**Integration Points**:
- Execution Context: Reads definitions for task dispatch
- Security Context: Provides policy configuration
- Observability Context: Provides validation rules

## 2. Execution Context

**Purpose**: Runtime task orchestration and agent management

**Owner**: Task (aggregate root)

**Entities**:

| Entity | Purpose |
|--------|---------|
| Task | Work unit awaiting execution |
| AgentInvocation | Single process execution of agent |
| Workspace | Isolated filesystem for agent execution |

**Lifecycle**: Pending → Running → Completed / Failed / Cancelled

**Storage**: PostgreSQL (Phase 2) / SQLite (MVP)

**Events**: Task.Created, Task.Assigned, Task.Started, Task.Completed, Task.Failed, AgentInvocation.Started, AgentInvocation.Progress, AgentInvocation.Completed, Artifact.Produced

**Integration Points**:
- Configuration Context: Reads definitions
- Workflow Context: Receives task completion events
- Security Context: Requests sandbox creation
- Observability Context: Emits metrics and cost records

**Key Invariants**:

1. Task must have exactly one Assignment before running
2. AgentInvocation must reference valid Task and AgentDefinition
3. Workspace must be created before AgentInvocation starts
4. Artifact must pass structural validation before Task.Completed

## 3. Workflow Context

**Purpose**: State machine orchestration and human approvals

**Owner**: WorkflowInstance

**Entities**:

| Entity | Purpose |
|--------|---------|
| WorkflowDefinition | Template for workflow patterns |
| WorkflowInstance | Live workflow execution |
| Approval | Human approval tracking (Phase 2) |

**Lifecycle**: Requested → Planned → Implementation → Testing → Review → Approved → Completed / Failed / Cancelled / Escalated

**Storage**: PostgreSQL (durable state)

**Events**: Workflow.Created, Workflow.Transitioned, Workflow.Completed, Approval.Requested, Approval.Granted, Approval.Rejected

**Integration Points**:
- Execution Context: Triggers and receives task events
- Configuration Context: Reads workflow templates
- Security Context: Enforces approval policies
- Observability Context: Emits workflow metrics

**Workflow Engine Seam**:

```go
type WorkflowEngine interface {
    CreateWorkflow(definition_id UUID, team_id UUID) (UUID, error)
    ExecuteStep(workflow_id UUID, task_spec TaskSpec) error
    WaitForSignal(signal_name string, timeout time.Duration) error
    CompleteWorkflow(workflow_id UUID) error
}
```

## 4. Security Context

**Purpose**: Sandboxing, secrets, access control, audit

**Owner**: Sandbox (Phase 2) / Workspace (MVP)

**Entities**:

| Entity | Purpose |
|--------|---------|
| Sandbox | Execution isolation primitive (Phase 2) |
| AccessPolicy | RBAC/ABAC rules |
| SecretBinding | Per-task secret grants |
| AuditEvent | Security-relevant state changes |

**Lifecycle**: Sandbox.Created → Running → Destroyed

**Storage**: PostgreSQL for policies; Vault for secrets; Append-only log for audit

**Events**: Sandbox.Created, Sandbox.Destroyed, Access.Denied, Secret.Accessed

**Integration Points**:
- Execution Context: Provides sandbox for agent execution
- All Contexts: Enforces access control on all operations

**Security Architecture**:

```
┌─────────────────┐
│  API Gateway    │
├─────────────────┤
│ Authorization   │ ← Validates JWT/API key, enforces policies
├─────────────────┤
│ Resource Mgr    │ ← Checks quotas, assigns agents
├─────────────────┤
│ Sandbox Manager │ ← Creates isolated execution environment
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Agent Sandbox  │ ← Non-root container, ephemeral FS
│ (Docker/gVisor) │ → Just-in-time secret injection via tmpfs
└─────────────────┘
```

## 5. Observability Context

**Purpose**: Metrics, tracing, cost tracking, quality measurement

**Owner**: Metric (Phase 2)

**Entities**:

| Entity | Purpose |
|--------|---------|
| Metric | Time-series data point |
| CostRecord | Token/cost consumption tracking |
| QualityMetric | Artifact quality assessment (Phase 2) |

**Lifecycle**: N/A (ephemeral aggregates)

**Storage**: Prometheus (metrics), PostgreSQL (cost records), Object Storage (traces)

**Events**: Metric.Recorded

**Integration Points**:
- All Contexts: Receives events for metrics
- Security Context: Provides audit data
- Configuration Context: Provides baseline metrics for comparison

**Event Retention** (Phase 2):

| Event Tier | Retention | Storage |
|------------|-----------|---------|
| Permanent | Indefinite | Object Storage (WORM) |
| Operational | 90 days | PostgreSQL/Kafka |
| Debug | 30 days | Redis/Log files |

---

## Context Interaction Patterns

### 1. Task Creation Flow

```
API → ExecutionContext(Task.Created)
    → ConfigurationContext(read AgentDefinition)
    → SecurityContext(create Sandbox)
    → ExecutionContext(AgentInvocation.Started)
```

### 2. Workflow Execution Flow

```
WorkflowContext(Workflow.Created)
    → ExecutionContext(Task.Created x N)
    → SecurityContext(Sandbox.Created x N)
    → ExecutionContext(Task.Completed events)
    → WorkflowContext(Workflow.Transitioned)
```

### 3. Contract Validation Flow

```
AgentInvocation.Completed
    → ObservabilityContext(Artifact.Validated) [Phase 2]
    → ExecutionContext(Artifact.Accepted/Rejected)
```

---

## Addressing Audit Concerns

### Workspace Aggregate Root (GLM, DeepSeek)

Workspace is explicitly NOT owned by Task. It's a separate aggregate in Execution Context that Security Context interacts with for isolation. This prevents DDD boundary violations.

### Contract Registry (All)

Contract validation is split across contexts:
- **Structural validation**: Execution Context (always)
- **Semantic validation**: Observability Context (Phase 2)
- **Policy validation**: Security Context

This clarifies the "validation trust boundary" concern raised in audits.