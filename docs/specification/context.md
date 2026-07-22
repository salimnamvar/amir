# Bounded Contexts

## Overview

Amir is organized into five bounded contexts, each with clear ownership and responsibilities. Contexts communicate via domain events and maintain their own consistency boundaries.

**Execution-first rule:** runtime truth lives in the Execution Context (`AgentSession` as the central aggregate). Other contexts configure, secure, orchestrate, or observe that execution.

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
- Scoring weights: runtime normalizes to sum 1.0 if config drifts (see Team.scoring_weights); MatchingDecision.weights records actuals
- Subjective proficiency enums are prohibited on capability requirements

## 2. Execution Context

**Purpose**: Runtime task orchestration and agent session management

**Owner**: **AgentSession** is the central runtime aggregate; Task is the unit of work that spawns sessions

**Entities**:
- Task - Work unit with required cost_budget **and validation_budget**, retry_state, matching_decision_id
- AgentSession - Central durable execution aggregate (lean: status, limits, refs, recent samples; full telemetry in events)
- AgentInvocation - Request DTO that creates a session (not an aggregate root)
- Workspace - Per-session filesystem with baseline observation and durable_effects
- Artifact - Produced output with lineage, observation_method; claim reconciliation by validation ID ref
- CompiledPrompt - Versioned prompt artifact for reproducibility
- ValidationResult - Structured validation + **canonical** claim_reconciliation
- FeedbackArtifact - Corrections and suggested strategy for retry (refs ValidationResult)
- MatchingDecision - Agent selection audit (hard filters + scores + negotiation + exploration)

**Lifecycle (Task)**: Pending → Assigned → Running → Committing → Succeeded / Failed / Cancelled / Escalated

> Event `Task.Completed` maps to status **`succeeded`**. Each retry attempt = new AgentSession + new Workspace.

**Lifecycle (AgentSession)**: Pending → Starting → Running → WaitingForInput → ProducingArtifact → Validating → Succeeded / Failed / TimedOut / Cancelled

> Compensation is a **WorkflowInstance** concern (durable_effects). AgentSession has no `compensating` status. CostLease revocation → `Cancelled` + `last_failure_category=budget_exceeded`.

**Storage**: SQLite / PostgreSQL

**Events**: Task.Created, Task.Assigned, Task.Started, Task.Completed, Task.Failed, AgentSession.Started, AgentSession.Progress, AgentSession.WaitingForInput, AgentSession.Completed, AgentSession.Failed, AgentSession.Cancelled, AgentSession.Checkpoint, AgentSession.ToolCall, Artifact.Produced, Artifact.Validated, Artifact.Rejected, MatchingDecision.Made, Workspace.Observed, Workspace.AutoCommitFailed (see event.md for full taxonomy)

**Integration Points**:
- Configuration Context: Reads definitions, skills, capabilities
- Workflow Context: Receives task completion events, emits Task.Created
- Security Context: Requests sandbox policy evaluation, secret injection, attestation
- Observability Context: Emits metrics, cost records, quality metrics, scorecard updates

### Workspace Ownership

- **Execution Context owns Workspace** as an aggregate root.
- Cardinality: **Task 1 → 1..* Workspace** via **AgentSession 1 → 1 Workspace**.
- Each retry attempt creates a new session and a new workspace.
- Security Context provides **SandboxPolicy** and evaluates it before workspace/sandbox creation (admission-control pattern). Security does **not** own Workspace.

## 3. Workflow Context

**Purpose**: State machine orchestration, approval handling, and compensation

**Owner**: WorkflowInstance

**Entities**:
- WorkflowDefinition - Template for workflow patterns (immutable)
- WorkflowInstance - Live workflow execution (event-sourced)
- Approval - Approval tracking (binary with escalation)
- EscalationSignal - First-class signal for compensation blocking, SLO breaches, and manual escalation
- CompensationAction - Abstract rollback intent with concrete effect mapping
- StepResult - Ordered execution history with compensation info

**Lifecycle**: Requested → Planned → Implementation → Testing → Review → Approved → Completed / Failed / Cancelled / Escalated / Compensating / **CompensationBlocked** / Rejected

**Storage**: PostgreSQL (durable state) + Event Store (event sourcing)

**Events**: Workflow.Created, Workflow.Transitioned, Workflow.Completed, Workflow.Compensated, Approval.Requested, Approval.Granted, Approval.Rejected, Compensation.Started, Compensation.Executed, Compensation.Failed, **Compensation.Blocked**, **Escalation.Signal**

## 4. Security Context

**Purpose**: Sandbox policy, secrets, access control, audit, and egress control

**Owner**: AccessPolicy, EgressProxy, SecretBinding (not Workspace)

**Entities**:
- SandboxPolicy - Rules evaluated before sandbox/workspace creation
- AccessPolicy - RBAC/ABAC rules (static or OPA)
- SecretBinding - Per-session secret grants with TTL (see secret-binding.schema.yaml)
- AuditEvent - Security-relevant state changes (linear hash-chained)
- EgressProxy - Network egress control and token counting
- SandboxAttestation - Runtime integrity verification

**Storage**: PostgreSQL for policies; Vault for secrets; Append-only log for audit; Object Storage for permanent audit

**Events**: Sandbox.PolicyEvaluated, Access.Denied, Secret.Accessed, Egress.RequestLogged, Sandbox.Attested, Workspace.Created (observed; ownership in Execution), Workspace.Cleaned (observed)

### Key Management (Attestation & Audit)

Platform signing keys for SandboxAttestation and linear hash-chain audit roots:

- Stored in KMS/HSM; referenced by `signing_key_ref` (never embedded private keys).
- Rotation: dual-valid window where `previous_key_ref` verifies historical signatures.
- Compromise: mark key revoked; re-sign only new events; historical chain remains verifiable with revoked-but-known public keys.
- Algorithm default: Ed25519.

## 5. Observability Context

**Purpose**: Metrics, cost tracking, quality measurement, and agent performance

**Owner**: CostRecord (accounting), AgentScorecard (routing)

**Entities**:
- Metric - Time-series data point
- CostRecord - Token/cost consumption with multi-dimensional attribution (authoritative)
- CostSummary - Aggregated cost by period/team/agent
- CostLease - **Synchronous cost lease for in-flight session cancellation** (Observability authority; Execution holds `cost_lease_id`; storage may co-locate in execution SQL with Observability ownership — see cost-lease.schema.yaml)
- QualityMetric - Artifact quality assessment
- AgentScorecard - Historical performance metrics + **circuit breaker state**
- ValidationMetric - Validation pipeline performance
- ReplayMetadata - Agent execution reproduction data

**Storage**: Prometheus (metrics), PostgreSQL (cost records, scorecards), Object Storage (replay data)

**Events**: Metric.Recorded, Artifact.Validated, Cost.Recorded, Cost.BudgetExceeded, Cost.ReservationCreated, Cost.ReservationCommitted, AgentScorecard.Updated, CircuitBreaker.Opened, CircuitBreaker.Closed

### Circuit Breaker Ownership

Circuit breakers are **agent-scoped** and live only on `AgentScorecard`. Tasks use `retry_state` for attempt accounting. Open breakers are hard filters during assignment.

---

## Context Interaction Patterns

### Task Creation Flow

```
API → ExecutionContext(Task.Created with cost_budget required)
    → ConfigurationContext(read AgentDefinition, RoleDefinition)
    → ExecutionContext(hard_filter → score → negotiate_contract)
    → ExecutionContext(MatchingDecision.Made)
    → SecurityContext(SandboxPolicy.Evaluate)
    → ExecutionContext(Workspace.Created for session)
    → SecurityContext(SecretBroker.inject_for_session)
    → ExecutionContext(AgentSession.Started + SandboxAttestation)
```

### Agent Execution Flow

```
ExecutionContext(AgentSession.Started)
    → PromptCompiler(CompiledPrompt created)
    → AgentAdapter.pump until completed | needs_input | failed
    → If needs_input: auto-response rules or WaitingForInput escalation
    → OutputParser(strategy chain)
    → Workspace observation + claim reconciliation
    → ExecutionContext(ValidationResult emitted)
    → If INVALID: FeedbackArtifact → new AgentSession + new Workspace
    → If VALID: Artifact.Produced → Artifact.Validated
    → ObservabilityContext(CostRecord committed; AgentScorecard updated)
```

### Workflow Execution Flow

```
WorkflowContext(Workflow.Created)
    → ExecutionContext(Task.Created x N)
    → ExecutionContext(Workspace.Created x N sessions)
    → ExecutionContext(Task.Completed events)
    → WorkflowContext(Workflow.Transitioned; durable_effects recorded)
    → If step failed: WorkflowContext(Compensation abstract intents)
    → ExecutionContext(maps intents → git/PR/artifact actions)
    → WorkflowContext(Workflow.Completed or Workflow.Failed)
```

### Compensation Flow

```
WorkflowContext(Workflow.StepFailed)
    → WorkflowContext(Workflow.Compensating)
    → For each completed step N..1 (LIFO):
        → Read durable_effects for step N (commit/branch/PR/artifact)
        → ExecutionContext(execute concrete compensation)
        → If compensation action fails:
            → If continue_on_compensation_failure=false:
                → WorkflowContext(Compensation.Blocked)
                → WorkflowContext(Escalation.Signal to human)
                → WorkflowInstance enters CompensationBlocked state
            → Else: log and continue (default: false)
        → Ephemeral Workspace cleanup is independent and usually already done
    → If all compensation succeeded:
        → WorkflowContext(Workflow.Failed)
    → ObservabilityContext(Compensation metrics recorded)
```

### Cost Control Flow

```
ExecutionContext(Task.Assigned)
    → ObservabilityContext(Cost.ReservationCreated with buffer)
    → ObservabilityContext(CostLease.Created; shared-state gate for synchronous hard kill)
    → ExecutionContext(AgentSession.Started + cost_lease_id)
    → Sidecar + Egress (token counting) every 100ms
    → ObservabilityContext(Cost.Recorded per batch; lease checked synchronously)
    → If invocation limit: kill process (sync lease gate)
    → If team/tenant/org hard limit: CostEnforcer.revoke_by_scope (sync hard kill all matching leases)
    → ObservabilityContext(CostLease.Released; Cost.Committed or Released)
```

**Trust boundary**: The CostLease shared-state gate lives in Observability Context. Execution Context holds a lease token reference (`AgentSession.cost_lease_id`, required while status ∈ starting/running/waiting_for_input/producing_artifact/validating). The sidecar/egress proxy checks the lease **synchronously** on each metering tick (≤100ms) via `CostEnforcer.check_lease`; cancellation is immediate when lease status is `revoked`. Lease service unavailability is **fail-closed** (no further metered consumption). Kill triggers at `kill_threshold_pct` (default 95%) of reserved budget.

**Kill protocol (normative)**:
1. Observability revokes lease (`status=revoked`, `revocation_revision`, `cancellation_reason`).
2. Sidecar observes revoke on next tick (or push); sends SIGTERM to sandbox process — **does not write Execution DB**.
3. `AgentAdapter.cancel(handle, cancellation_reason, grace_period_seconds=5)` → SIGTERM → wait → SIGKILL → orphan reap; returns `cancel_acknowledged`.
4. AgentExecutor observes process exit, sets `AgentSession.status=cancelled` and `last_failure_category=budget_exceeded` (not `failed`; skip normal validation path).
5. Workflow compensation runs against `Workspace.durable_effects` (append-logged incrementally during execution so mid-flight kills still have targets).

**Budget pools**: Execution and validation use separate CostLeases (`budget_pool=execution|validation`). Validation spend cannot consume the execution lease. Exhausted validation budget fails validation with `budget_exceeded` without killing execution.

**Post-cancel**: Default `retry_on` excludes `budget_exceeded` (no automatic retry into the same wall). Team/tenant/org kills emit `EscalationSignal` (`cost_limit_exceeded`) with `assigned_to` and remediation plan.
