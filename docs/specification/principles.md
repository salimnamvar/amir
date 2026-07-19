# Architecture Principles

## 1. Clean Architecture / Hexagonal Architecture

Amir follows Clean Architecture principles with explicit boundaries:

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

### Dependency Rule

- **Control Plane** depends on nothing (pure configuration logic)
- **Execution Plane** depends on interfaces defined by Control Plane
- **External Agents** are completely isolated; never influence core logic

### Ports and Adapters

- **Ports**: WorkflowEngine, AgentAdapter, SandboxManager, ArtifactValidator, EventPublisher
- **Adapters**: ClaudeCodeAdapter, CodexAdapter, APIAgentAdapter, DockerSandbox, FirecrackerSandbox
- All ports are defined in `domain/protocols/` as abstract base classes

## 2. Domain-Driven Design

### Bounded Contexts

Five explicit bounded contexts prevent conceptual leakage:

1. **Configuration Context**: GitOps-managed definitions
2. **Execution Context**: Runtime task orchestration
3. **Workflow Context**: State machines and human approvals
4. **Security Context**: Sandboxing, secrets, access control
5. **Observability Context**: Metrics, tracing, cost tracking

### Aggregate Roots

Each entity belongs to exactly one aggregate root:

| Entity | Aggregate Root | Context |
|--------|---------------|---------|
| TeamDefinition | TeamDefinition | Configuration |
| RoleDefinition | RoleDefinition | Configuration |
| AgentDefinition | AgentDefinition | Configuration |
| ContractDefinition | ContractDefinition | Configuration |
| WorkflowDefinition | WorkflowDefinition | Configuration |
| Task | Task | Execution |
| AgentInvocation | AgentInvocation | Execution |
| Workspace | Workspace | Execution |
| WorkflowInstance | WorkflowInstance | Workflow |
| Approval | Approval | Workflow |

### Invariants

Each aggregate enforces its own invariants; cross-aggregate constraints use eventual consistency via domain events.

## 3. Contract-First Design

### Contract Properties

All contracts declare:

- **Schema**: JSON Schema or YAML Schema (machine-readable)
- **Version**: SemVer with MAJOR.MINOR.PATCH
- **Compatibility**: N-1 minor version backward compatibility
- **Validation**: Structural validation always; semantic validation in Phase 2

### Contract Types

- **AgentContract**: Declares agent capabilities and requirements
- **TaskContract**: Defines task objective and constraints
- **ArtifactContract**: Specifies artifact structure and validation
- **WorkflowContract**: Describes workflow states and transitions
- **RoleContract**: Defines role responsibilities and capabilities

## 4. Two-Track Entity Lifecycle

### Configuration Entities (GitOps Lifecycle)

```
Draft → Validating → Published → Deprecated → Retired
```

- Stored in `amir-config/` Git repository
- Changes via PR with CI validation
- Promoted through environments (deferred to Phase 2)
- Immutable after Published state

### Runtime Entities (Execution Lifecycle)

```
Pending → Running → Completed / Failed / Cancelled
```

- Stored in PostgreSQL/SQLite
- State transitions trigger domain events
- Ephemeral; no promotion model
- Full audit trail via event store

## 5. Event-Driven Architecture

### Event Types

- **Domain Events**: State changes within aggregates (Permanent retention)
- **Integration Events**: Cross-context communication (90-day retention)
- **Audit Events**: Security/compliance relevant (Permanent retention)

### Event Envelope

All events use `DomainEvent` with:

```python
event_id: UUID          # Unique event identifier
event_type: str         # e.g., "Task.Created"
aggregate_id: UUID      # Entity that produced event
aggregate_type: str     # Entity type
correlation_id: UUID    # Trace entire workflow
causation_id: UUID      # Direct cause of this event
producer: str           # Component that emitted event
version: str            # Event schema version
timestamp: datetime     # When event occurred
payload: dict           # Event-specific data
```

## 6. Security Principles

### Zero Trust Execution

- Every agent execution is fully isolated
- No network access unless explicitly required
- Secrets never stored with code
- All actions logged and traceable

### Defense in Depth

1. **Layer 1**: Container isolation (non-root, read-only root)
2. **Layer 2**: Filesystem isolation (ephemeral workspace)
3. **Layer 3**: Network isolation (default-deny egress)
4. **Layer 4**: Runtime monitoring (suspicious behavior detection)

### Just-In-Time Secrets

- Secrets fetched from vault at execution start
- Injected into sandbox via tmpfs (memory-only)
- Revoked immediately after execution completes

## 7. Evolution Paths

Each major component has a documented migration path:

| Component | Phase 1 (MVP) | Phase 2 | Phase 3 | Phase 4 |
|-----------|--------------|---------|---------|---------|
| Workflow | Internal state machine | Message queue | Temporal | Temporal global |
| Sandbox | Docker + seccomp | gVisor | Firecracker | Multi-zone |
| Storage | SQLite | PostgreSQL | CockroachDB | Sharded |
| Events | File (JSONL) | Kafka | Kafka + schema registry | Multi-region |
| Observability | File logs | Prometheus + Loki | OpenTelemetry | Dedicated metrics cluster |

---

## Addressing Audit Concerns

### CLI Parsing Risk (All Audits)

The architecture isolates CLI parsing behind the `AgentAdapter.ParseOutput()` interface. This is acknowledged as technical debt (see Risk Register). The adapter layer is designed to be replaced with more robust solutions.

### Aggregate Boundary Clarity (GLM)

Workspace is now a separate aggregate root, not owned by Task. This allows Security Context to manage sandbox isolation without violating DDD boundaries.

### Over-Engineering Prevention (Minimax)

The Two-Track Lifecycle prevents applying full CI/CD processes to runtime entities that are inherently ephemeral.