# Amir Specification

**Version:** 1.0.0  
**Status:** Authoritative Architecture Specification  
**Owner:** Technical Leadership

---

## 1. Vision

Amir is a control-plane system that creates, manages, coordinates, and governs teams of external AI coding agents. It transforms chaotic, unstructured AI agent interactions into engineering-grade, auditable, and repeatable workflows through contract-driven communication, role-based governance, and GitOps-managed configuration.

Amir does not provide intelligence itself. It provides the infrastructure for:
- Orchestration of heterogeneous AI agents
- Team structure management
- Role definition and enforcement
- Task planning and assignment
- Workflow state management
- Contract-based communication
- Artifact lifecycle governance
- Security and isolation

---

## 2. Goals and Non-Goals

### Goals

✅ **Control Plane Agnosticism** - Support any CLI-based or API-based agent without vendor lock-in

✅ **Contract-Driven Communication** - All agent interactions produce typed, versioned, validated artifacts

✅ **Engineering-Grade Governance** - Apply proven software engineering practices to AI agent management

✅ **GitOps Configuration** - All definitions versioned, reviewed, and promoted via pull requests

✅ **Security-First Architecture** - Zero-trust execution with mandatory sandboxing and secrets brokering

✅ **Observable Operations** - Full audit trails, metrics, and tracing for compliance and debugging

✅ **Scalable Design** - Horizontal scaling from 5 to 1000+ agents with clear evolution paths

### Non-Goals

❌ **Agent Intelligence** - Amir does not provide LLMs or reasoning capabilities

❌ **Human Chat Interface** - Amir is not a chatbot; it orchestrates autonomous agents

❌ **Direct Code Hosting** - Git repositories remain external; Amir orchestrates changes via PRs

❌ **Universal Lifecycle for All Entities** - Runtime entities follow lighter-weight state machines

❌ **Homogeneous Agents** - Amir deliberately supports heterogeneous, external agent tools

---

## 3. Architecture Principles

### 3.1 Clean Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Plane                            │
│  API Gateway │ Orchestration │ Governance │ Monitoring      │
├─────────────────────────────────────────────────────────────┤
│                    Execution Plane                           │
│  Agent Adapters │ Sandboxes │ Runtime Sessions              │
├─────────────────────────────────────────────────────────────┤
│                    External Agents                          │
│  Claude Code CLI │ Codex CLI │ OpenCode │ Gemini CLI       │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Bounded Context Separation

- **Configuration Context**: GitOps-managed definitions (Teams, Roles, Agents, Contracts)
- **Execution Context**: Runtime task execution and agent management
- **Workflow Context**: State machines, DAGs, and human approval gates
- **Security Context**: Sandboxing, secrets, access control, audit logs
- **Observability Context**: Metrics, tracing, cost tracking, quality metrics

### 3.3 Contract-First Design

All inter-component communication uses typed contracts with:
- Explicit schemas (JSON Schema or Protobuf)
- Semantic versioning with backward compatibility
- Runtime validation before acceptance
- Provenance tracking for all artifacts

### 3.4 Two-Track Entity Lifecycle

| Configuration Entities | Runtime Entities |
|---------------------|------------------|
| Agents, Roles, Policies, Contracts, Workflows (templates) | Tasks, TaskExecutions, Artifacts, Sessions |
| GitOps lifecycle (Draft → Validate → Approve → Release) | Execution lifecycle (Pending → Running → Completed/Failed) |
| Versioned in Git, promoted through environments | Ephemeral, tracked in database/event store |

---

## 4. System Overview

### 4.1 Core Components

| Component | Purpose |
|-----------|---------|
| **Amir API** | REST/gRPC interface for external systems |
| **Orchestrator** | Matches tasks to agents based on capabilities |
| **Workflow Engine** | Durably executes workflow state machines |
| **Contract Validator** | Validates contract schemas and semantics |
| **Agent Registry** | Tracks agent capabilities and health status |
| **Sandbox Manager** | Spawns and manages isolated agent execution |
| **Artifact Store** | Persistent storage for artifacts and logs |
| **Secret Broker** | Just-in-time secret injection for agents |
| **Audit Logger** | Immutable, tamper-evident event logging |

### 4.2 Execution Flow

```
1. Task Created → Workflow Engine
2. Task Requirements → Capability Matcher
3. Agent Selected → Sandbox Manager
4. Contract → Agent via Adapter
5. Agent Executes → Produces Artifact
6. Artifact Validated → Contract Validator
7. State Transition → Workflow Engine
8. All Events Logged → Audit Logger
```

---

## 5. Domain Model

### 5.1 Core Entities

#### Team

A Team is a logical grouping of roles and agents working toward shared objectives. It provides:
- Namespace isolation for tasks and artifacts
- Policy enforcement boundaries
- Budget and quota management
- Environment configuration

**Lifecycle:** Active | Archived | Suspended

**Ownership:** Platform (with tenant scoping)

#### Role

A Role defines a contract of responsibilities: what inputs it accepts, what outputs it produces, what actions it may take, and quality criteria for success.

**Key Attributes:**
- `responsibility`: Primary duty description
- `inputs`: Required contract types
- `outputs`: Produced contract types
- `allowed_actions`: Action verbs permitted
- `quality_criteria`: Machine-checkable success rules

**Lifecycle:** Draft | Published | Deprecated

#### Agent

An Agent is an execution endpoint with declared capabilities. It is NOT a role - it is a concrete executor.

**Key Attributes:**
- `adapter_type`: How to communicate (CLI, MCP, API)
- `capabilities`: Supported action types
- `resource_profile`: CPU, memory, token limits
- `security_profile`: Sandbox requirements, network access
- `health_status`: Current operational state

**Lifecycle:** Registered | Validating | Active | Degraded | Quarantined | Retired

#### Task

A Task is a unit of work assigned to fulfill an objective.

**Key Attributes:**
- `objective`: Natural language description
- `assigned_role`: Role type to perform work
- `inputs`: Required artifacts or contexts
- `outputs`: Expected artifact types
- `constraints`: Rules (SOLID, test coverage, etc.)
- `dependencies`: Other tasks this depends on
- `priority`: Execution priority level
- `deadline`: Optional deadline for completion
- `cost_budget`: Maximum token/cost allowance

**Lifecycle:** Pending | Assigned | Running | Validating | Completed | Failed | Cancelled

#### TaskExecution

A TaskExecution represents an instantiated task run by a specific agent.

**Key Attributes:**
- `task_id`: Parent task reference
- `agent_id`: Executing agent
- `session_id`: Runtime session identifier
- `status`: Current execution state
- `start_time`: When execution began
- `end_time`: When execution ended
- `resource_usage`: Actual tokens, time, memory consumed

**Lifecycle:** Scheduled → Running → Succeeded/Failed/TimedOut → Cleanup

**Owned by:** Execution Context

#### AgentInvocation

An AgentInvocation represents a single execution of an agent.

**Key Attributes:**
- `invocation_id`: Unique identifier
- `task_id`: Parent task reference
- `agent_id`: Executing agent
- `sandbox_id`: Isolated execution environment
- `status`: Current state (Pending, Running, Completed, Failed, Cancelled)
- `progress`: Streaming progress percentage
- `output_stream`: Incremental output from agent

**Lifecycle:** Pending → Running → Completed/Failed/TimedOut/Cancelled

**Owned by:** Execution Context

**Events Produced:**
- AgentInvocation.Started
- AgentInvocation.Progress (for streaming output)
- AgentInvocation.Completed
- AgentInvocation.Failed
- AgentInvocation.Cancelled

#### Workflow

A Workflow defines a template for multi-step processes.

**Key Attributes:**
- `states`: Named states in the workflow
- `transitions`: Rules for state changes
- `tasks`: Task templates with dependencies
- `approval_gates`: Human approval requirements
- `failure_policies`: Retry and compensation rules

**Lifecycle:** Draft | Testing | Published | Deprecated

#### WorkflowInstance

A WorkflowInstance is an active workflow execution.

**Key Attributes:**
- `workflow_id`: Template reference
- `team_id`: Owning team
- `current_state`: Current state in state machine
- `task_instances`: Related task executions
- `variables`: Runtime state data

**Lifecycle:** Created → Running → Paused → Completed/Failed/Cancelled

#### Contract

A Contract defines the schema for structured data exchange.

**Key Attributes:**
- `type`: Contract type identifier
- `version`: Semantic version (MAJOR.MINOR.PATCH)
- `schema`: JSON Schema or Protobuf definition
- `owner_role`: Role that produces this contract
- `compatible_versions`: Backward compatibility range

**Lifecycle:** Draft | Published | Deprecated

#### Artifact

An Artifact is an instance of a contract produced by an agent.

**Key Attributes:**
- `contract_type`: Schema type identifier
- `contract_version`: Schema version used
- `content`: The actual artifact data
- `provenance`: Producer, session, task references
- `checksum`: Content hash for integrity

**Lifecycle:** Produced | Validated | Accepted | Rejected

#### Policy

A Policy defines constraints and rules for governance.

**Key Attributes:**
- `scope`: What entities this applies to
- `rules`: Constraint definitions
- `enforcement`: How violations are handled

**Lifecycle:** Draft | Active | Inactive

---

## 6. Bounded Contexts

Each bounded context owns its entities completely and communicates through well-defined interfaces. Bounded contexts do NOT share entities.

### 6.1 Configuration Context

**Purpose:** Manages versioned, Git-backed definitions

**Aggregate Roots:** TeamDefinition, RoleDefinition, AgentDefinition, ContractDefinition, WorkflowDefinition, PolicyDefinition, Capability

**Entities:**
- TeamDefinition
- RoleDefinition
- AgentDefinition
- ContractDefinition
- WorkflowDefinition
- PolicyDefinition
- Capability (agent skill declarations)

**Responsibilities:**
- Git repository synchronization
- Schema validation at commit time
- Version promotion across environments
- Change impact analysis
- Capability declaration and discovery

**Owned By:** Platform (multi-tenant scoped)

### 6.2 Execution Context

**Purpose:** Manages runtime task execution

**Aggregate Roots:** Task, AgentInvocation, Workspace

**Entities:**
- Task
- TaskExecution
- AgentInvocation
- AgentSession
- Workspace

**Responsibilities:**
- Agent scheduling and assignment
- Sandbox lifecycle management
- Resource quota enforcement
- Cost tracking per execution
- Streaming output handling

**Owned By:** Execution Context

**Special Note:** Workspace entity provides isolated execution environment per task.

### 6.3 Workflow Context

**Purpose:** Manages workflow state and orchestration

**Aggregate Roots:** Workflow, WorkflowInstance, Approval

**Entities:**
- Workflow
- WorkflowInstance
- StateTransition
- ApprovalGate
- Approval

**Responsibilities:**
- DAG execution and state management
- Human approval coordination
- Compensation and rollback
- Retry policy enforcement

**Owned By:** Workflow Context

**Note:** Uses event-driven transitions. Workflow state changes produce Workflow.Transitioned events.

### 6.4 Security Context

**Purpose:** Enforces security and isolation

**Entities:**
- Sandbox
- SecretBinding
- AccessPolicy
- AuditEvent

**Responsibilities:**
- Container/VM isolation
- Secrets brokering
- File system access control
- Network egress filtering
- Immutable audit logging

### 6.5 Observability Context

**Purpose:** Provides metrics, tracing, and cost tracking

**Aggregate Roots:** Metric, Trace, CostRecord, Alert

**Entities:**
- Metric
- Trace
- CostRecord
- QualityMetric
- Alert

**Responsibilities:**
- OpenTelemetry integration
- Token and API cost tracking
- Quality scoring for artifacts
- Performance metrics
- Debugging support

---

## 7. Core Entities Detail

### 7.1 Agent Entity

```yaml
Agent:
  id: string (UUID)
  name: string
  adapter_type: enum [cli, mcp, api]
  adapter_config:
    binary_path: string (for CLI)
    endpoint: string (for API)
    capabilities_endpoint: string
  capabilities:
    - skill: refactoring
      languages: [python, javascript]
      tools: [file_read, file_write, bash]
    - skill: code_review
      tools: [file_read, comment_create]
  resource_profile:
    max_memory_mb: int
    max_tokens: int
    timeout_seconds: int
  security_profile:
    sandbox_required: boolean
    network_access: enum [none, limited, full]
    allowed_paths: [string]
  status: enum [registered, healthy, busy, degraded, quarantined, offline]
  version: string
  metadata:
    created_at: timestamp
    updated_at: timestamp
```

### 7.2 Role Entity

```yaml
Role:
  id: string (UUID)
  name: string
  responsibility: string
  inputs:
    - contract_type: RepositoryContext
      required: true
    - contract_type: DesignSpec
      required: false
  outputs:
    - contract_type: CodeChangeArtifact
      required: true
  allowed_actions:
    - file_read
    - file_write
    - run_tests
    - create_pr
  quality_criteria:
    - must_pass_tests: boolean
    - min_test_coverage: int (percentage)
    - code_review_required: boolean
  constraints:
    - follow_solid: boolean
    - preserve_api: boolean
  lifecycle: enum [draft, published, deprecated]
  version: string
```

### 7.3 Task Entity

```yaml
Task:
  id: string (UUID)
  objective: string
  assigned_role: string (Role name)
  inputs:
    - artifact: RepositoryContext
      reference: artifact_id
    - artifact: DesignSpec
      reference: artifact_id
  outputs:
    - contract_type: CodeChangeArtifact
  constraints:
    - follow_solid: true
    - add_tests: true
    - preserve_api_compatibility: true
  dependencies:
    - task_id: string
      type: hard
  priority: int (1-10)
  deadline: timestamp
  cost_budget:
    max_tokens: int
    max_usd: decimal
  retry_policy:
    max_attempts: int
    backoff: enum [none, linear, exponential]
  lifecycle: enum [pending, assigned, running, validating, completed, failed, cancelled]
  created_at: timestamp
  updated_at: timestamp
```

---

## 8. Agent Model

### 8.1 Adapter Architecture

```
TaskContract
     │
     ▼
┌─────────────────┐
│  Prompt Compiler │ ◄── Role context, task objective
└─────────────────┘
     │
     ▼
┌─────────────────┐
│   AgentAdapter   │ ◄── CLI/API specific implementation
├─────────────────┤
│ - Execute()     │
│ - HealthCheck() │
│ - ParseOutput() │
│ - ReportUsage() │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│  Sandbox Runtime │ ◄── Container/VM isolation
├─────────────────┤
│ - Filesystem    │
│ - Network       │
│ - Resources     │
└─────────────────┘
     │
     ▼
┌─────────────────┐
│ External Agent  │ ◄── Claude Code, Codex, etc.
└─────────────────┘
```

### 8.2 Agent Lifecycle

```
Registered
    │
    ▼
Validating
    │ (capability tests pass)
    ▼
Active
    │
    ├─────────────────┐
    │                 ▼
    │           Degraded (health check fails)
    │                 ▲
    │                 │
    ▼
Quarantined (security violation or repeated failures)
    │
    ▼
Retired (no longer available)
```

### 8.3 Capability Registry

Each agent declares capabilities through a capability manifest:

```yaml
CapabilityManifest:
  agent_type: string
  version: string
  capabilities:
    - skill: language_proficiency
      languages: 
        - python: expert
        - javascript: intermediate
    - skill: tool_use
      tools:
        - file_read: available
        - file_write: available
        - bash: restricted
        - web_search: unavailable
  resource_limits:
    max_context_tokens: int
    max_output_tokens: int
    timeout_seconds: int
  security_constraints:
    sandbox_capable: boolean
    network_isolation_required: boolean
```

---

## 9. Team Model

### 9.1 Team Structure

A Team is a bounded context for agent collaboration:

```yaml
Team:
  id: string (UUID)
  name: string
  description: string
  roles:
    - role_name: architect
      agent_binding: claudecode-latest
    - role_name: developer
      agent_binding: codex-latest
    - role_name: reviewer
      agent_binding: opencode-latest
  policies:
    - branch_protection
    - cost_limit_daily
    - approval_required
  budget:
    daily_usd_limit: decimal
    monthly_token_limit: int
  environment:
    repositories: [string]
    secrets: [secret_reference]
    variables: {key: value}
```

### 9.2 Role Assignment vs Role Definition

- **RoleDefinition**: Static template defining responsibilities (stored in GitOps)
- **AgentBinding**: Runtime mapping of role to concrete agent (stored in DB)
- **Assignment**: Per-task binding of agent to role execution

This separation enables:
- Same role filled by different agents
- Agent replacement without changing workflow definitions
- Capability-based routing decisions

---

## 10. Role Model

### 10.1 Role Contract

A RoleContract specifies what a role must do:

```yaml
RoleContract:
  role: string
  responsibility: string
  required_inputs: [ContractType]
  expected_outputs: 
    - contract_type: CodeChangeArtifact
      required: true
  allowed_actions: [action_verb]
  quality_criteria:
    - metric: test_pass_rate
      threshold: 100%
    - metric: code_coverage
      threshold: 80%
  constraints:
    - follow_solid: true
    - max_file_changes: 50
  owner: string (team or user)
```

### 10.2 Role Enforcement

Roles are enforced through:
1. Input validation before task dispatch
2. Action interception during execution
3. Output validation after completion
4. Quality criteria evaluation post-execution

---

## 11. Task Model

### 11.1 Task Lifecycle

```
Pending
    │ (task created)
    ▼
Assigned
    │ (agent selected, resources ready)
    ▼
Running
    │ (task executing in sandbox)
    ▼
Validating
    │ (output validated against contract)
    ├───────┬─────────────┐
    │       │             │
    ▼       ▼             ▼
Completed Failed        Rejected
                       (contract validation)
```

### 11.2 Task Execution Flow

1. **Task Creation**: Objective and constraints defined
2. **Role Matching**: Find agents capable of fulfilling role
3. **Resource Allocation**: Reserve sandbox and budget
4. **Execution**: Agent runs in isolated environment
5. **Output Capture**: Collect stdout, artifacts, logs
6. **Validation**: Verify output matches contract
7. **Quality Check**: Evaluate against role criteria
8. **State Transition**: Update workflow state
9. **Cleanup**: Destroy sandbox, release resources

---

## 12. Workflow Model

### 12.1 Workflow States

Standard workflow states for software engineering:

```
REQUESTED
    │
    ▼
PLANNED
    │
    ▼
ARCHITECTURE_REVIEW
    │ (optional)
    ▼
IMPLEMENTATION ──► TESTING
    │                │
    │                ▼
    └──────────► REVIEW
    │                │
    ▼                ▼
APPROVED ◄──────── COMMITTED
    │
    ▼
COMPLETED
```

Failure states:
- `FAILED`: Unrecoverable error
- `BLOCKED`: Waiting for external resource
- `CANCELLED`: User cancelled
- `ESCALATED`: Requires human intervention

### 12.2 DAG Task Dependencies

```yaml
Workflow:
  tasks:
    - id: architecture-design
      role: architect
      dependencies: []
      
    - id: implementation
      role: developer
      dependencies:
        - task_id: architecture-design
          type: hard
      
    - id: testing
      role: developer
      dependencies:
        - task_id: implementation
          type: hard
          
    - id: review
      role: reviewer
      dependencies:
        - task_id: testing
          type: hard
        - task_id: implementation
          type: soft  # Can proceed with warnings
```

### 12.3 Retry and Compensation

```yaml
retry_policy:
  max_attempts: 3
  backoff: exponential
  backoff_base_seconds: 30
  retry_on:
    - contract_validation_failed
    - test_failure
    - timeout
  notify_on_failure:
    - after_attempts: 2
      channel: slack
```

---

## 13. Contract Architecture

### 13.1 Contract Types

| Contract Type | Purpose | Producer | Consumer |
|---------------|---------|----------|----------|
| TaskContract | Task specification | User/Orchestrator | Agent |
| ArtifactContract | Structured output | Agent | Orchestrator/Validation |
| AgentContract | Agent capability declaration | Agent | Registry |
| RoleContract | Role responsibilities | Governance | Orchestrator |
| WorkflowContract | Workflow definition | Platform | Workflow Engine |
| PolicyContract | Rules and constraints | Governance | Security |

### 13.2 Contract Versioning

Semantic versioning strategy:
- **MAJOR**: Breaking changes to required fields
- **MINOR**: Additive changes (new optional fields)
- **PATCH**: Documentation or non-breaking fixes

Backward compatibility rules:
- N-1 minor version compatibility for patch level
- Explicit migration required for major version changes
- Contract negotiation at task assignment time

### 13.3 Contract Validation

Three levels of validation:
1. **Structural**: Schema validation (JSON Schema/Protobuf)
2. **Semantic**: Business rules (tests pass, quality criteria met)
3. **Policy**: Security/compliance checks (no secrets leaked, no forbidden patterns)

---

## 14. Artifact Model

### 14.1 Artifact Types

| Type | Description | Typical Producer |
|------|-------------|------------------|
| CodeChangeArtifact | File modifications with explanations | Developer agent |
| TestResultArtifact | Test execution results | Test runner |
| DesignDocumentArtifact | Architecture decisions | Architect agent |
| ReviewFeedbackArtifact | Code review comments | Reviewer agent |
| RiskAssessmentArtifact | Identified risks and mitigations | Any role |
| ExecutionLogArtifact | Agent execution logs | System |

### 14.2 Artifact Provenance

Every artifact includes provenance metadata:

```yaml
Artifact:
  id: string (UUID)
  contract_type: string
  contract_version: string
  content: object
  provenance:
    produced_by:
      agent_id: string
      session_id: string
      role: string
    task_reference: string
    workflow_reference: string
    timestamp: timestamp
    sandbox_id: string
  checksum: string
  signature: string (optional)
```

---

## 15. CI/CD Governance

### 15.1 Configuration Lifecycle

For definition entities (Roles, Agents, Contracts, Policies, Workflows):

```
Draft
  │
  ▼
Validate (CI runs schema + compatibility tests)
  │
  ▼
Review (Peer review via PR)
  │
  ▼
Approve (Merge to main branch)
  │
  ▼
Release (Tagged version)
  │
  ▼
Deploy (Applied to control plane)
  │
  ▼
Monitor (Health checks)
  │
  ▼
Retire (Deprecated, migration path)
```

### 15.2 Environment Promotion

Three environments supported:

| Environment | Purpose | Promotion Criteria |
|-------------|---------|-------------------|
| Development | Testing changes | Branch merge |
| Staging | Integration testing | CI validation + smoke tests |
| Production | Live agent workloads | All tests pass + approvals |

### 15.3 Approval Gates

Approval gates can be:
- **Human-only**: Requires explicit human approval
- **Auto-approved**: Criteria-based automated approval
- **Hybrid**: Auto-approval with rollback on failure

---

## 16. Runtime Architecture

### 16.1 Execution Model

```
┌──────────────────────────────────────────┐
│           Amir Control Plane             │
├──────────────────────────────────────────┤
│  Orchestrator │ Workflow Engine │ Registry │
└────────┬───────┴─────────┬───────┴─────┬────┘
         │                 │             │
         ▼                 ▼             ▼
┌─────────────────────────────────────────────────┐
│              Sandbox Manager                       │
│  (Spawns containers with resource limits)        │
└─────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│              Agent Sandbox                       │
│  ┌──────────────────────────────────────────┐  │
│  │  Agent Adapter                            │  │
│  │  (CLI/MCP/API translation)               │  │
│  │  ┌────────────────────────────────────┐  │  │
│  │  │  Claude Code / Codex / OpenCode    │  │  │
│  │  └────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────┘  │
│  Filesystem: Isolated, read-only except workdir │
│  Network: Egress filtered, whitelist enforced   │
└─────────────────────────────────────────────────┘
```

### 16.2 Sandbox Requirements

**Mandatory for all agent executions:**
- Container isolation (Docker/Podman)
- Filesystem isolation (read-only root, ephemeral workdir)
- Network isolation (default-deny, explicit allowlist)
- Resource limits (CPU, memory, time)
- Secrets injection via broker

**Recommended hardening:**
- seccomp profiles
- AppArmor/SELinux
- User namespace isolation
- gVisor/Firecracker for untrusted agents

### 16.3 Workspace Isolation

Each task execution receives:
- Clean git clone of target repository
- Dedicated work directory
- Ephemeral filesystem (changes discarded after validation)
- Scoped credentials (read-only for review, read-write for dev)

---

## 17. Security Model

### 17.1 Threat Model

| Threat | Mitigation |
|--------|------------|
| Prompt injection | Input sanitization, prompt templating |
| File system access | Workspace isolation, read-only mounts |
| Secret exfiltration | Secrets broker, no env var access |
| Resource exhaustion | Quotas, container limits |
| Network attacks | Egress filtering, allowlist |

### 17.2 Secrets Management

```
Agent needs secret
      │
      ▼
Secret Broker
      │
      ▼
Fetch from Vault/AWS Secrets Manager
      │
      ▼
Inject into sandbox (ephemeral)
      │
      ▼
Secret available only during task
      │
      ▼
Revoke after task completion
```

### 17.3 Access Control

- **RBAC**: Roles define permissions
- **ABAC**: Attributes on tasks/workflows
- **Policy Engine**: OPA/Rego for complex rules
- **Audit Logging**: All actions logged immutably

---

## 18. Observability

### 18.1 Metrics Categories

| Category | Metrics |
|----------|---------|
| Execution | Task duration, success rate, retry count |
| Cost | Token usage, USD spend, budget utilization |
| Quality | Artifact quality score, test pass rate |
| Security | Policy violations, sandbox breaches |
| Performance | Queue wait time, scheduling latency |

### 18.2 Tracing Model

OpenTelemetry spans for:
- Task creation to completion
- Agent invocation and response
- Contract validation
- Human approval wait time
- Each workflow state transition

### 18.3 Alerting Rules

- Agent health check failures
- Cost budget threshold exceeded
- Security policy violations
- Workflow stuck in state > 24h
- Retry limit reached

---

## 19. Event Model

Amir uses events for loose coupling between contexts and for audit purposes.

### 19.1 Event Types

| Category | Events | Producer | Consumers |
|----------|--------|----------|-----------|
| Domain | Task.Created, Task.Assigned, Task.Completed, Task.Failed | Execution Context | Workflow, Audit, Metrics |
| Domain | AgentInvocation.Started, AgentInvocation.Completed, AgentInvocation.Failed | Execution Context | Orchestration, Audit |
| Domain | Workflow.Transitioned | Workflow Context | Audit, Metrics |
| Domain | Approval.Requested, Approval.Granted, Approval.Rejected | Workflow Context | Notification, Audit |
| Domain | Artifact.Produced, Artifact.Validated | Execution Context | Validation, Workflow, Audit |
| Integration | TaskQueued, SandboxViolation | Various | Security, Alert |
| Audit | All state-changing events | All contexts | immutable log |

### 19.2 Event Contract

```yaml
Event:
  event_id: string (UUID)
  event_type: string (e.g., "Task.Created")
  timestamp: timestamp
  correlation_id: string (for tracing related events)
  payload: object (event-specific data)
  producer_context: string
  producer_version: string
```

### 19.3 Event Storage

- **Audit Events**: Append-only log (file initially, Kafka for scale)
- **Metrics**: Time-series database (Prometheus)
- **Traces**: Distributed tracing system (Tempo/Jaeger)

---

## 20. Workflow Engine Decision

### 20.1 MVP Approach

**Decision:** Internal state machine for MVP

**Reason:** Prove core concepts without Temporal complexity. Basic state persistence via SQLite.

**Limitation:** No durable execution across restarts, limited scalability.

### 20.2 Evolution Path

**Phase 1:** In-process state machine with periodic persistence

**Phase 2:** Externalize state to database + message queue

**Phase 3:** Integrate Temporal for durable workflows

### 20.3 Interface Seam

```go
// WorkflowEngine interface allows seamless migration
type WorkflowEngine interface {
    CreateWorkflow(definition WorkflowDefinition) (WorkflowInstance, error)
    ExecuteStep(instance WorkflowInstance, step Step) error
    WaitForSignal(instance WorkflowInstance, signal string) error
    CompleteWorkflow(instance WorkflowInstance) error
}
```

---

## 21. Persistence Architecture

### 21.1 Storage Map

| Entity Type | Storage | Access Pattern |
|-------------|---------|----------------|
| Definitions | Git (YAML/JSON) | Read-heavy, versioned |
| Runtime State | PostgreSQL/RQLite | ACID transactions |
| Artifacts | Object Storage (S3) | Large blobs, versioning |
| Events/Audit | Append-only log | Write-heavy, immutable |
| Metrics | Time-series DB | Query by time range |

### 21.2 Key Decisions

1. **No Git for runtime state** - Git is too slow, creates merge conflicts
2. **Separate artifact store** - Content-addressable, deduplication
3. **Transactional boundaries** - Task state changes atomic
4. **Event sourcing for audit** - Not for state reconstruction

---

## 19. Event Model

Amir uses events for loose coupling between contexts and for audit purposes.

### 19.1 Event Types

| Category | Events | Producer | Consumers |
|----------|--------|----------|-----------|
| Domain | Task.Created, Task.Assigned, Task.Completed, Task.Failed | Execution Context | Workflow, Audit, Metrics |
| Domain | AgentInvocation.Started, AgentInvocation.Completed, AgentInvocation.Failed | Execution Context | Orchestration, Audit |
| Domain | Workflow.Transitioned | Workflow Context | Audit, Metrics |
| Domain | Approval.Requested, Approval.Granted, Approval.Rejected | Workflow Context | Notification, Audit |
| Domain | Artifact.Produced, Artifact.Validated | Execution Context | Validation, Workflow, Audit |
| Integration | TaskQueued, SandboxViolation | Various | Security, Alert |
| Audit | All state-changing events | All contexts | immutable log |

### 19.2 Event Contract

```yaml
Event:
  event_id: string (UUID)
  event_type: string (e.g., "Task.Created")
  timestamp: timestamp
  correlation_id: string (for tracing related events)
  payload: object (event-specific data)
  producer_context: string
  producer_version: string
```

### 19.3 Event Storage

- **Audit Events**: Append-only log (file initially, Kafka for scale)
- **Metrics**: Time-series database (Prometheus)
- **Traces**: Distributed tracing system (Tempo/Jaeger)

---

## 19. Scalability Model

### 19.1 Scale Tiers

| Tier | Agents | Architecture |
|------|--------|--------------|
| Small (5) | Monolith, local execution, SQLite | Single binary, direct CLI |
| Medium (50) | Distributed, queue-based, Postgres | Message queue, container pools |
| Enterprise (1000+) | Microservices, event-driven | Kubernetes, sharded state, global scheduler |

### 19.2 Scaling Strategies

**Horizontal Scaling:**
- Stateless control plane services
- Shared database (PostgreSQL/CockroachDB)
- Message queue (NATS/Kafka) for task distribution
- Agent pools per type for warm starts

**Performance Optimization:**
- Contract schema caching
- Artifact deduplication
- Parallel task execution
- Warm sandbox containers

---

## 20. Evolution Strategy

### 20.1 MVP (Phase 1)

**Scope:**
- Single team orchestration
- 2-3 agent types (Claude Code, Codex)
- Linear workflow (Plan → Implement → Review)
- One contract type (CodeChangeArtifact)
- Docker sandboxing
- Git-based definitions

**Timeline:** 3-4 months

### 20.2 Phase 2

**Additions:**
- Multiple teams and roles
- DAG workflows
- Persistent agent sessions
- Cost tracking
- Basic observability stack

### 20.3 Phase 3

**Additions:**
- Temporal workflow engine
- Distributed execution
- Multi-tenant support
- Advanced policy engine
- Artifact provenance

### 20.4 Phase 4

**Additions:**
- Federated agent pools
- Multi-region deployment
- Auto-scaling
- ML-based cost optimization
- Compliance certifications

---

## Appendix A: Entity Relationships

```
Team 1 ──► contains ──► RoleDefinition
                      │
                      └── uses ──► Contract
                      
AgentDefinition ──► implements ──► RoleDefinition (at runtime)
                 │
                 └── declared_in ──► AgentContract

Task ──► requires ──► Role
      │
      ├── consumes ──► Artifact (input)
      └── produces ──► Artifact (output)

Workflow ──► contains ──► Task templates
          │
          └── enforces ──► Policy
          
Artifact ──► validated_by ──► Contract
```

---

## Appendix B: Configuration Directory Structure

```
amir-config/
├── agents/
│   ├── claude-code.yaml
│   └── codex.yaml
├── roles/
│   ├── developer.yaml
│   ├── architect.yaml
│   └── reviewer.yaml
├── contracts/
│   ├── code-change.yaml
│   └── test-result.yaml
├── workflows/
│   └── software-delivery.yaml
├── teams/
│   └── engineering.yaml
├── policies/
│   ├── cost-limits.yaml
│   └── branch-protection.yaml
└── schemas/
    └── (JSON Schema/Protobuf definitions)
```