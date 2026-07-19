# Bounded Contexts

## Overview

Amir is organized into five bounded contexts, each with clear ownership and responsibilities. Contexts communicate via domain events and maintain their own consistency boundaries.

## 1. Configuration Context

**Purpose**: GitOps-managed, immutable definitions

**Owner**: Platform

**Entities**:
- TeamDefinition - Team namespace, policies, budget caps, scoring weights
- RoleDefinition - Contract of responsibilities with inputs/outputs, prompt template reference
- AgentDefinition - Agent configuration, capabilities, adapter settings, supported output modes
- ContractDefinition - Schema definitions with SemVer and semantic validators
- WorkflowDefinition - Workflow template with states, transitions, and compensation specs
- Capability - Hierarchical skill declarations with tool requirements and eval suites
- SkillDefinition - Versioned skill with output contracts and composition

**Lifecycle**: Draft → Validating → Published → Deprecated → Retired

**Storage**: Git repository (`amir-config/`)

**Events**: Definition.Created, Definition.Updated, Definition.Published, Definition.Deprecated

**Invariants**:
- All referenced roles must exist and be Published
- All agent_bindings must reference valid AgentDefinitions
- Budget limits must be non-negative
- Scoring weights must sum to 1.0

## 2. Execution Context

**Purpose**: Runtime task orchestration and agent management

**Owner**: Task (aggregate root)

**Entities**:
- Task - Work unit awaiting execution (with idempotency key and circuit breaker)
- AgentSession - Full execution lifecycle with checkpoints, tool calls, and replay metadata
- Workspace - Isolated filesystem for agent execution (with baseline/current commit tracking)
- Artifact - Produced output with lineage (derived_from, supersedes) and observation method
- CompiledPrompt - Versioned prompt artifact for reproducibility
- ValidationResult - Structured error categories for feedback loop
- FeedbackArtifact - Corrections and suggested strategy for retry
- MatchingDecision - Agent selection with dimension scores and explanation
- AgentScorecard - Historical performance metrics (read model, derived from events)

**Lifecycle**: Pending → Running → Completed / Failed / Cancelled

**Storage**: SQLite / PostgreSQL

**Events**: Task.Created, Task.Assigned, Task.Started, Task.Completed, Task.Failed, AgentSession.Started, AgentSession.Progress, AgentSession.Completed, AgentSession.Checkpoint, Artifact.Produced, Artifact.Validated, Artifact.Rejected, MatchingDecision.Made, CircuitBreaker.Opened

**Integration Points**:
- Configuration Context: Reads definitions, skills, capabilities
- Workflow Context: Receives task completion events, emits Task.Created
- Security Context: Requests workspace creation, secret injection
- Observability Context: Emits metrics, cost records, quality metrics

## 3. Workflow Context

**Purpose**: State machine orchestration, approval handling, and compensation

**Owner**: WorkflowInstance

**Entities**:
- WorkflowDefinition - Template for workflow patterns (immutable)
- WorkflowInstance - Live workflow execution (event-sourced)
- Approval - Approval tracking (binary with escalation)
- CompensationAction - Rollback action for failed workflows (LIFO stack)
- StepResult - Ordered execution history with compensation info

**Lifecycle**: Requested → Planned → Implementation → Testing → Review → Approved → Completed / Failed / Cancelled / Escalated

**Storage**: PostgreSQL (durable state) + Event Store (event sourcing)

**Events**: Workflow.Created, Workflow.Transitioned, Workflow.Completed, Workflow.Compensated, Approval.Requested, Approval.Granted, Approval.Rejected, Compensation.Started, Compensation.Executed, Compensation.Failed

**Workflow Engine Interface**:

```go
type WorkflowEngine interface {
    CreateWorkflow(definition_id UUID, team_id UUID, idempotency_key string) (UUID, error)
    ExecuteStep(workflow_id UUID, task_spec TaskSpec) error
    WaitForSignal(workflow_id UUID, signal_name string, timeout time.Duration) error
    CompleteWorkflow(workflow_id UUID) error
    CompensateWorkflow(workflow_id UUID) error
    GetState(workflow_id UUID) (WorkflowState, error)
}
```

## 4. Security Context

**Purpose**: Workspace isolation, secrets, access control, audit, and egress control

**Owner**: Workspace (isolation), AccessPolicy (authorization), EgressProxy (network)

**Entities**:
- Workspace - Execution isolation primitive (with security context)
- AccessPolicy - RBAC/ABAC rules (static or OPA)
- SecretBinding - Per-task secret grants with TTL
- AuditEvent - Security-relevant state changes (Merkle-chained)
- EgressProxy - Network egress control and token counting
- SandboxAttestation - Runtime integrity verification

**Storage**: PostgreSQL for policies; Vault for secrets; Append-only log for audit; Object Storage for permanent audit

**Events**: Workspace.Created, Workspace.Cleaned, Access.Denied, Secret.Accessed, Egress.RequestLogged, Sandbox.Attested

## 5. Observability Context

**Purpose**: Metrics, cost tracking, quality measurement, and agent performance

**Owner**: CostRecord (accounting), AgentScorecard (routing)

**Entities**:
- Metric - Time-series data point
- CostRecord - Token/cost consumption with multi-dimensional attribution
- CostSummary - Aggregated cost by period/team/agent
- QualityMetric - Artifact quality assessment
- AgentScorecard - Historical performance metrics (read model)
- ValidationMetric - Validation pipeline performance
- ReplayMetadata - Agent execution reproduction data

**Storage**: Prometheus (metrics), PostgreSQL (cost records, scorecards), Object Storage (replay data)

**Events**: Metric.Recorded, Artifact.Validated, Cost.Recorded, Cost.BudgetExceeded, AgentScorecard.Updated

---

## Context Interaction Patterns

### Task Creation Flow

```
API → ExecutionContext(Task.Created)
    → ConfigurationContext(read AgentDefinition, RoleDefinition)
    → ExecutionContext(MatchingDecision.Made via scoring algorithm)
    → SecurityContext(Workspace.Created)
    → SecurityContext(SecretBroker.inject_for_task)
    → ExecutionContext(AgentSession.Started)
```

### Agent Execution Flow

```
ExecutionContext(AgentSession.Started)
    → PromptCompiler(CompiledPrompt created)
    → AgentExecutor(Agent process spawned with sidecar)
    → OutputParser(Output parsed via ParserRegistry)
    → ExecutionContext(ValidationResult emitted)
    → If INVALID: FeedbackArtifact created → new AgentSession
    → If VALID: Artifact.Produced → Artifact.Validated
    → ExecutionContext(CostRecord emitted)
    → ObservabilityContext(AgentScorecard updated)
```

### Workflow Execution Flow

```
WorkflowContext(Workflow.Created)
    → ExecutionContext(Task.Created x N)
    → SecurityContext(Workspace.Created x N)
    → ExecutionContext(Task.Completed events)
    → WorkflowContext(Workflow.Transitioned)
    → If step failed: WorkflowContext(Compensation started)
    → WorkflowContext(Workflow.Completed or Workflow.Failed)
```

### Compensation Flow

```
WorkflowContext(Workflow.StepFailed)
    → WorkflowContext(Workflow.Compensating)
    → WorkflowContext(Compensation.Executed step N)
    → SecurityContext(Workspace cleaned for step N)
    → WorkflowContext(Compensation.Executed step N-1)
    → SecurityContext(Workspace cleaned for step N-1)
    → WorkflowContext(Workflow.Failed)
    → ObservabilityContext(Compensation metrics recorded)
```

### Cost Control Flow

```
ExecutionContext(Task.Assigned)
    → ObservabilityContext(Cost.ReservationCreated)
    → ExecutionContext(AgentSession.Started)
    → AgentExecutor(Sidecar token counting)
    → ObservabilityContext(Cost.Recorded per token batch)
    → If budget exceeded: ExecutionContext(Cost.LimitReached)
    → ExecutionContext(Task.Completed or Task.Failed)
    → ObservabilityContext(Cost.Committed actual amount)
    → ObservabilityContext(AgentScorecard cost metrics updated)
```
