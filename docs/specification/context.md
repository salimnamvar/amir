# Bounded Contexts

## Overview

Amir is organized into five bounded contexts, each with clear ownership and responsibilities.

## 1. Configuration Context

**Purpose**: GitOps-managed, immutable definitions

**Owner**: Platform

**Entities**:
- TeamDefinition - Team namespace, policies, budget caps
- RoleDefinition - Contract of responsibilities with inputs/outputs
- AgentDefinition - Agent configuration, capabilities, adapter settings
- ContractDefinition - Schema definitions with SemVer
- WorkflowDefinition - Workflow template with states and transitions
- Capability - Skill/tool declarations for routing

**Lifecycle**: Draft → Validating → Published → Deprecated → Retired

**Storage**: Git repository (`amir-config/`)

**Events**: Definition.Created, Definition.Updated, Definition.Published, Definition.Deprecated

## 2. Execution Context

**Purpose**: Runtime task orchestration and agent management

**Owner**: Task (aggregate root)

**Entities**:
- Task - Work unit awaiting execution
- AgentInvocation - Single process execution of agent
- Workspace - Isolated filesystem for agent execution

**Lifecycle**: Pending → Running → Completed / Failed / Cancelled

**Storage**: SQLite / PostgreSQL

**Events**: Task.Created, Task.Assigned, Task.Started, Task.Completed, Task.Failed, AgentInvocation.Started, AgentInvocation.Progress, AgentInvocation.Completed, Artifact.Produced

**Integration Points**:
- Configuration Context: Reads definitions
- Workflow Context: Receives task completion events
- Security Context: Requests workspace creation
- Observability Context: Emits metrics and cost records

## 3. Workflow Context

**Purpose**: State machine orchestration and approval handling

**Owner**: WorkflowInstance

**Entities**:
- WorkflowDefinition - Template for workflow patterns
- WorkflowInstance - Live workflow execution
- Approval - Approval tracking (binary: auto_approve or manual)

**Lifecycle**: Requested → Planned → Implementation → Testing → Review → Approved → Completed / Failed / Cancelled / Escalated

**Storage**: PostgreSQL (durable state)

**Events**: Workflow.Created, Workflow.Transitioned, Workflow.Completed, Approval.Requested, Approval.Granted, Approval.Rejected

**Workflow Engine Interface**:

```go
type WorkflowEngine interface {
    CreateWorkflow(definition_id UUID, team_id UUID) (UUID, error)
    ExecuteStep(workflow_id UUID, task_spec TaskSpec) error
    WaitForSignal(signal_name string, timeout time.Duration) error
    CompleteWorkflow(workflow_id UUID) error
}
```

## 4. Security Context

**Purpose**: Workspace isolation, secrets, access control, audit

**Owner**: Workspace (isolation), AccessPolicy (authorization)

**Entities**:
- Workspace - Execution isolation primitive
- AccessPolicy - RBAC/ABAC rules
- SecretBinding - Per-task secret grants
- AuditEvent - Security-relevant state changes

**Storage**: PostgreSQL for policies; Vault for secrets; Append-only log for audit

**Events**: Workspace.Created, Workspace.Cleaned, Access.Denied, Secret.Accessed

## 5. Observability Context

**Purpose**: Metrics, cost tracking, quality measurement

**Owner**: CostRecord (accounting)

**Entities**:
- Metric - Time-series data point
- CostRecord - Token/cost consumption tracking
- QualityMetric - Artifact quality assessment

**Storage**: Prometheus (metrics), PostgreSQL (cost records)

**Events**: Metric.Recorded, Artifact.Validated

---

## Context Interaction Patterns

### Task Creation Flow

API → ExecutionContext(Task.Created)
    → ConfigurationContext(read AgentDefinition)
    → SecurityContext(create Workspace)
    → ExecutionContext(AgentInvocation.Started)

### Workflow Execution Flow

WorkflowContext(Workflow.Created)
    → ExecutionContext(Task.Created x N)
    → SecurityContext(Workspace.Created x N)
    → ExecutionContext(Task.Completed events)
    → WorkflowContext(Workflow.Transitioned)

### Contract Validation Flow

AgentInvocation.Completed
    → ObservabilityContext(Artifact.Validated)
    → ExecutionContext(Artifact.Accepted/Rejected)