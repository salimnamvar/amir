# Amir Architecture Hardening Review

**Date:** 2026-07-19  
**Status:** Architecture Review Complete  
**Author:** Technical Leadership

---

## Executive Summary

The Amir specification has been reviewed against DDD, Clean Architecture, and distributed systems principles. Key gaps identified in event model, aggregate ownership, and agent invocation contracts. Several concepts added to clarify boundaries. Workflow engine decision made: start with internal state machine, migrate to Temporal.

**Status after review:** `READY_FOR_IMPLEMENTATION` with documented evolution paths.

---

## Decisions Made

### Decision 1: Workflow Engine Strategy
**Chosen approach:** Option C - Start simple with internal state machine, design seam for Temporal migration

**Why:** MVP needs to prove core concepts before adding Temporal complexity. Internal state machine sufficient for linear workflows.

**Tradeoffs:**
- Faster MVP delivery
- Lock-in risk if Temporal migration blocked
- Manual durability implementation needed

**Migration Path:**
- Phase 1: In-process state machine with SQLite
- Phase 2: Message queue + externalized state
- Phase 3: Temporal integration for workflows > 50 concurrent

---

### Decision 2: Entity Ownership Model
**Chosen approach:** Strict aggregate roots with clear context ownership

**Why:** Prevents tight coupling and enables independent scaling. Each context owns its entities completely.

**Boundaries established:**
- Configuration Context: Definition entities (immutable after publish)
- Execution Context: Runtime entities (ephemeral)
- Workflow Context: DAG orchestration entities
- Security Context: Sandbox and audit entities
- Observability Context: Metrics and tracing entities

---

### Decision 3: Event-Driven Integration
**Chosen approach:** Event sourcing for critical state transitions, not full event sourcing

**Why:** Enables replay and debugging without full event-sourcing complexity. Events for transitions, not state reconstruction.

---

## Changed Concepts

### Entity: TaskExecution → Added AgentInvocation

Split TaskExecution into:
- **AgentInvocation**: Single agent execution (start, progress, complete, fail, cancel)
- **TaskExecution**: Task orchestration (assign, validate, succeed, fail)

Reason: Agent invocation lifecycle differs from task orchestration. Agent may stream progress, need cancellation mid-flight.

---

### Entity: AgentSession → Made First-Class Entity

AgentSession was mentioned but not defined. Now explicitly:
- Owned by Execution Context
- Manages agent process lifecycle
- Tracks resource usage and health

---

## New Concepts Added

### AgentInvocation Entity

```
Entity: AgentInvocation

Purpose: Represents a single invocation of an agent to perform work.
         Handles streaming output, cancellation, and mid-execution state.

Aggregate Root: Execution Context

Owned By: Execution Context

Mutable Fields:
  status
  progress_percent
  output_stream_position
  resource_usage (real-time)

Immutable Fields:
  id, task_id, agent_id, sandbox_id, started_at

Lifecycle:
  Pending → Running → Streaming → Completed/Failed/TimedOut/Cancelled

Events Produced:
  AgentInvocation.Started
  AgentInvocation.Progress
  AgentInvocation.Completed
  AgentInvocation.Failed
  AgentInvocation.Cancelled
```

---

### Capability Entity

```
Entity: Capability

Purpose: Declares what actions an agent can perform with proficiency levels.
        Enables capability-based routing and matching.

Aggregate Root: Agent Registry (part of Configuration Context)

Owned By: Configuration Context

Mutable Fields:
  None (immutable after publish)

Immutable Fields:
  id, skill_name, proficiency, constraints, tools

Lifecycle:
  Draft → Published → Deprecated
```

---

### Assignment Entity

```
Entity: Assignment

Purpose: Runtime binding of agent to task. Enables re-assignment without
        modifying task definition.

Aggregate Root: Task (part of Execution Context)

Owned By: Execution Context

Mutable Fields:
  status, actual_agent_id

Immutable Fields:
  id, task_id, role_name, assigned_at
```

---

### Approval Entity

```
Entity: Approval

Purpose: Tracks human approval state for workflow gates.
        Enables durable waiting for human input.

Aggregate Root: WorkflowContext

Owned By: Workflow Context

Mutable Fields:
  status, approver_id, approved_at

Immutable Fields:
  id, workflow_instance_id, gate_id, request_at
```

---

### Workspace Entity

```
Entity: Workspace

Purpose: Isolated filesystem and repository state for task execution.
        Tracks git branch, clean state, and resource limits.

Aggregate Root: TaskExecution (part of Execution Context)

Owned By: Execution Context

Mutable Fields:
  status, git_state

Immutable Fields:
  id, task_id, repository_url, branch
```

---

## Removed Concepts

### Removed: Universal Lifecycle from Runtime Entities

**Reasoning:** Tasks and artifacts do not need "Release", "Deploy", "Monitor", "Retire" stages. These are runtime events, not deployable artifacts.

**New:**
- Configuration entities: Full GitOps lifecycle
- Runtime entities: Simple state machine (Pending → Running → Completed/Failed)

---

## Entity Ownership Model

| Entity | Owner Context | Reason | Aggregate Root |
|--------|---------------|--------|--------------|
| TeamDefinition | Configuration | Versioned in Git, promoted across environments | TeamDefinition |
| RoleDefinition | Configuration | Immutable contract of responsibilities | RoleDefinition |
| AgentDefinition | Configuration | Adapter configuration, capabilities declared | AgentDefinition |
| ContractDefinition | Configuration | Schema and validation rules | ContractDefinition |
| WorkflowDefinition | Configuration | Workflow template, task graphs | WorkflowDefinition |
| PolicyDefinition | Configuration | Governance rules, versioned | PolicyDefinition |
| Task | Execution | Runtime orchestration, created on-demand | Task |
| AgentInvocation | Execution | Single agent execution lifecycle | Task |
| Assignment | Execution | Agent-to-task runtime binding | Task |
| Workspace | Execution | Isolated execution environment | Task |
| WorkflowInstance | Workflow | Active workflow state | WorkflowInstance |
| StateTransition | Workflow | Workflow progression tracking | WorkflowInstance |
| Approval | Workflow | Human approval state | WorkflowInstance |
| Sandbox | Security | Security isolation boundary | Sandbox |
| SecretBinding | Security | Secrets access control | SecretBinding |
| AccessPolicy | Security | Authorization rules | AccessPolicy |
| AuditEvent | Security | Immutable audit trail | AuditEvent |
| Metric | Observability | Performance and quality metrics | Metric |
| Trace | Observability | Distributed tracing data | Trace |
| CostRecord | Observability | Cost accounting | CostRecord |
| Artifact | Execution | Produced by agents, validated | Task |

---

## Contract Improvements

### Contract Ownership

**Decision:** Contracts are owned by the Configuration Context, not individual entities.

**Rationale:** Contract compatibility must be centrally managed. Team A cannot change a contract that Team B depends on without coordinated rollout.

**Ownership:** Contract Registry (aggregate) owns all contract definitions. Individual entities reference contracts by type and version.

---

### Contract Lifecycle

```
ContractLifecycle

Draft: Initial schema definition
  │
  ▼
Validating: Schema + compatibility tests running
  │
  ▼
Published: Available for use by runtime entities
  │
  ▼
Deprecated: Superseded, migration window open
  │
  ▼
Retired: No longer accepted, all references migrated
```

---

### Contract Compatibility Policy

```
ContractCompatibilityPolicy

Breaking Changes (MAJOR bump required):
  - Removing required fields
  - Changing field types
  - Removing validation rules
  
Non-Breaking Changes (MINOR bump):
  - Adding optional fields
  - Adding new contract types
  - Relaxing validation rules
  
Enforcement:
  - Task assignment checks contract compatibility
  - N-1 minor version backward compatibility
  - Major versions require explicit opt-in
```

---

### Contract Discovery

**Mechanism:**
1. Agent registers with declared supported contract versions
2. Orchestrator queries Contract Registry for compatible versions
3. Version negotiation occurs at task assignment time
4. Agent Adapter validates contract before execution

---

## Event Model

### Domain Events

| Event Name | Producer | Consumers | Payload | Retention | Ordering |
|------------|----------|-----------|---------|-----------|----------|
| Task.Created | API/User | Workflow Engine, Audit | Task ID, Role, Objective | Permanent | Required |
| Task.Assigned | Orchestration | Execution, Audit | Task ID, Agent ID | Permanent | Required |
| Task.Started | Execution | Workflow, Audit, Metrics | Task ID, Session ID | Permanent | Required |
| Task.Completed | Execution | Workflow, Audit, Metrics | Task ID, Artifact IDs | Permanent | Required |
| Task.Failed | Execution | Workflow, Audit, Alert | Task ID, Error, Attempts | Permanent | Required |
| AgentInvocation.Started | Sandbox Manager | Metrics, Audit | Invocation ID, Agent ID | 90 days | Required |
| AgentInvocation.Progress | Agent Adapter | Metrics, Audit | Invocation ID, Percent, Output | 30 days | Not required |
| AgentInvocation.Completed | Agent Adapter | Orchestration, Audit | Invocation ID, Artifact | 90 days | Required |
| AgentInvocation.Failed | Agent Adapter | Orchestration, Audit | Invocation ID, Error | 90 days | Required |
| Workflow.Transitioned | Workflow Engine | Audit, Metrics | Workflow ID, From, To | Permanent | Required |
| Approval.Requested | Workflow Engine | Notification, Audit | Approval ID, Gate | Permanent | Required |
| Approval.Granted | Human/User | Workflow, Audit | Approval ID, Approver | Permanent | Required |
| Artifact.Produced | Agent | Validation, Audit | Artifact ID, Content Ref | Permanent | Required |
| Artifact.Validated | Validator | Workflow | Artifact ID, Status | Permanent | Required |
| Policy.Violated | Security | Alert, Audit | Policy ID, Entity, Details | Permanent | Required |

### Integration Events

| Event Name | Producer | Consumers | Purpose |
|------------|----------|-----------|---------|
| TaskQueued | API | Orchestrator | Enqueue task for processing |
| AgentHealthCheck | Orchestrator | Registry | Update agent status |
| CostLimitExceeded | Metrics | Security | Alert on budget breach |
| SandboxViolation | Sandbox | Security, Alert | Report security incident |

### Event Storage

- **Permanent**: Domain events in append-only log (initially file, later Kafka)
- **90 days**: Execution events in database
- **30 days**: Progress/interim events in Redis/cache

---

## Runtime Decisions

### Agent Invocation Contract

```yaml
AgentInvocationContract:
  invocation_id: string (UUID)
  task_id: string
  agent_id: string
  sandbox_id: string
  contract_type: string (which contract to process)
  input_payload: object (contract content)
  execution_parameters:
    timeout_seconds: int
    max_tokens: int
    streaming_mode: boolean
  callbacks:
    - on_progress: string (Webhook URL or queue name)
    - on_complete: string
    - on_error: string
    - on_cancel: string
```

### Streaming Support

Agents may produce streaming output:
- **Mode A (Batch)**: Agent completes, produces single artifact
- **Mode B (Streaming)**: Agent provides progress updates, may produce multiple artifacts

Initial MVP supports Mode A only. Mode B added in Phase 2.

---

## Persistence Decisions

### Storage Responsibilities Matrix

| Data Type | Storage | Reason |
|-----------|---------|--------|
| Definitions (Teams, Roles, Agents, Contracts, Workflows, Policies) | Git (amir-config/) | Versioned, reviewed, promoted via PR |
| Runtime State (Tasks, WorkflowInstances, Invocations) | PostgreSQL/RQLite | ACID transactions, queries |
| Artifacts (Code changes, test results) | Object Storage (S3/MinIO) | Large objects, versioning, deduplication |
| Audit Events | Append-only log (file initially, then Kafka) | Immutability, compliance |
| Metrics | Time-series DB (Prometheus) | Query performance, retention policies |
| Traces | Tempo/Jaeger | Distributed tracing, sampling |
| Secrets | External Vault | Security isolation, rotation |
| Session State (Agent memory) | Redis | Fast access, TTL |

### Critical Storage Decisions

1. **No Git for runtime state**: Git is too slow and creates merge conflicts at scale
2. **Separate artifact storage**: Artifacts are large, need content-addressable storage
3. **Immutable audit**: Audit events never modified, only appended
4. **Transactional boundaries**: Task state changes happen in ACID transactions

---

## Security Decisions

### Security Principles

```
SecurityPrinciple: Authentication
- All API access requires valid tokens (JWT/OAuth)
- Agent registration requires platform authentication
- Human approvals require role-based authorization

SecurityPrinciple: Authorization
- RBAC for human users
- ABAC for agent capabilities
- Policy engine for complex rules (OPA)

SecurityPrinciple: Isolation
- Every agent execution in isolated container
- No shared filesystem between executions
- Network egress filtering by default

SecurityPrinciple: Least Privilege
- Agents get minimum required capabilities
- Secrets injected per-task, not per-agent
- Repository access scoped to task branch

SecurityPrinciple: Auditability
- All state changes produce audit events
- All agent actions logged immutably
- Audit log tamper-evident (hash chain)

SecurityPrinciple: NonRepudiation
- All approvals signed by authenticated user
- All agent outputs include provenance
- All artifacts checksummed
```

### Security Architecture

```
┌─────────────────────────────────────┐
│         API Gateway                   │
│  (Authentication, Rate Limiting)     │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│         Authorization                 │
│  (RBAC, ABAC, Policy Engine)        │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│         Resource Manager            │
│  (Quota check, Budget validation)  │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│         Sandbox Manager             │
│  (Container spawn, Isolation)       │
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│         Agent Sandbox               │
│  (Process isolation,                 │
│   Filesystem isolation,             │
│   Network isolation)                │
└─────────────────────────────────────┘
```

---

## MVP Definition

### Must Have (Phase 1 - 2 months target)

1. **Configuration Context**
   - Role definition (single role type: developer)
   - Agent definition (single adapter: Claude Code)
   - Contract definition (single: CodeChangeArtifact)
   - Basic policy (branch protection)

2. **Execution Context**
   - Task creation and assignment
   - Agent invocation in Docker sandbox
   - Artifact production and validation
   - Basic resource limits (timeout only)

3. **Workflow Context**
   - Simple linear workflow (3 states: implement → test → review)
   - Basic state transition

4. **Security Context**
   - Docker container isolation
   - Basic filesystem isolation
   - Secret injection placeholder

5. **Observability Context**
   - Basic structured logging
   - Simple metrics (success/failure)

### Should Have (Phase 1.5 - optional)

1. **Multiple roles** (architect, reviewer)
2. **Multiple agents** (Codex)
3. **DAG workflows**
4. **Human approval gates**
5. **Basic cost tracking**

### Removed from MVP

- ❌ Full observability stack
- ❌ Policy engine integration
- ❌ Multi-environment GitOps
- ❌ Cost budgeting
- ❌ Artifact lineage
- ❌ Advanced retry/compensation
- ❌ Parallel task execution
- ❌ Audit trail immutability (initially file-based)

### MVP Boundary

The minimal Amir MVP proves:
1. Agent can execute in isolated sandbox
2. Agent produces valid CodeChangeArtifact
3. Artifact passes validation
4. Workflow transitions correctly
5. All events logged (file-based)

**No human approvals, no complex policies, no cost tracking.**

---

## Remaining Risks

### Risk 1: CLI Output Parsing
**Severity:** HIGH  
**Mitigation:** 
- Use structured output mode where available (Claude Code --output-format json)
- Implement retry with feedback ("Your last output wasn't valid YAML")
- Fallback to regex extraction for malformed output

### Risk 2: Sandbox Escape
**Severity:** CRITICAL  
**Mitigation:**
- Start with Docker + seccomp
- Plan gVisor integration for Phase 2
- Runtime monitoring for suspicious behavior

### Risk 3: Contract Drift
**Severity:** MEDIUM  
**Mitigation:**
- Contract tests in CI pipeline
- Version pinning for production workflows
- Compatibility matrix for agent versions

### Risk 4: Cost Explosion
**Severity:** HIGH  
**Mitigation:**
- Hard token limits per task
- Simple budget tracking in MVP
- Alert escalation paths

### Risk 5: Temporal Migration Blockage
**Severity:** MEDIUM  
**Mitigation:**
- Design clear interface seam
- Keep state transition logic separate
- Document migration path

---

## Architecture Status

**FINAL STATUS: `READY_FOR_IMPLEMENTATION`**

The specification provides:
- ✅ Clear bounded contexts with ownership
- ✅ Event model for loose coupling
- ✅ Agent invocation contract for runtime
- ✅ Aggregate boundaries defined
- ✅ Storage responsibilities assigned
- ✅ Security principles codified
- ✅ MVP scope sharply defined

**Evolution paths documented for:**
- Workflow engine (internal → Temporal)
- Sandbox hardening (Docker → gVisor/Firecracker)
- Observability (logs → OpenTelemetry stack)
- Persistence (SQLite → PostgreSQL → Distributed)

---

## Files Modified

```
docs/spec/SPECIFICATION.md
  - Added AgentInvocation entity
  - Clarified aggregate boundaries
  - Added Workspace entity

docs/spec/contracts/
  - agent-contract.md: Added adapter interface
  - task-contract.md: Clarified runtime expectations
  - workflow-contract.md: Added DAG support
```

## Files Added

```
docs/spec/ARCHITECTURE_REVIEW.md (this document)
```