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
- All ports defined in `domain/protocols/` as abstract base classes

## 2. Domain-Driven Design

### Bounded Contexts

Five explicit bounded contexts prevent conceptual leakage:
1. **Configuration**: GitOps-managed definitions
2. **Execution**: Runtime task orchestration
3. **Workflow**: State machines and approvals
4. **Security**: Sandboxing, secrets, access control
5. **Observability**: Metrics, tracing, cost tracking

### Aggregate Roots

Each entity belongs to exactly one aggregate root.

## 3. Contract-First Design

### Contract Properties

All contracts declare:
- **Schema**: JSON Schema or YAML Schema
- **Version**: SemVer with MAJOR.MINOR.PATCH
- **Compatibility**: N-1 minor version backward compatibility
- **Validation**: Structural + semantic validation via validators

### Contract Types

- AgentContract, TaskContract, ArtifactContract, WorkflowContract, RoleContract

## 4. Two-Track Entity Lifecycle

### Configuration Entities (GitOps Lifecycle)

```
Draft → Validating → Published → Deprecated → Retired
```

- Stored in `amir-config/` Git repository
- Changes via PR with CI validation
- Single environment; external CI/CD handles promotion

### Runtime Entities (Execution Lifecycle)

```
Pending → Running → Completed / Failed / Cancelled
```

- Stored in SQLite/PostgreSQL
- State transitions trigger domain events
- Full audit trail via event store

## 5. Event-Driven Architecture

### Event Types

- **Domain Events**: State changes (Permanent)
- **Integration Events**: Cross-context communication (90-day retention)
- **Audit Events**: Security/compliance relevant (Permanent)

### Event Envelope

All events use `DomainEvent` with:
- event_id, event_type, aggregate_id, aggregate_type
- correlation_id, causation_id, producer, version, timestamp, payload

## 6. Security Principles

### Zero Trust Execution

- Every agent execution is fully isolated
- No network access unless explicitly required
- Secrets never stored with code
- All actions logged and traceable

### Defense in Depth

1. Container isolation (non-root, read-only root)
2. Filesystem isolation (ephemeral workspace)
3. Network isolation (default-deny egress)
4. Runtime monitoring (suspicious behavior detection)

### Just-In-Time Secrets

- Secrets fetched from vault at execution start
- Injected into sandbox via tmpfs (memory-only)
- Revoked immediately after execution completes

## 7. Evolution Paths

Each major component has documented migration paths:

| Component | Default | Alternative Options |
|-----------|---------|-------------------|
| Workflow | Internal state machine | Temporal-compatible interface |
| Sandbox | Docker + seccomp | gVisor, Firecracker |
| Storage | SQLite | PostgreSQL |
| Events | File (JSONL) | Kafka-compatible interface |
| Observability | File logs | Prometheus, OpenTelemetry |

---

## Addressing Audit Concerns

### CLI Parsing Risk (All Audits)
The architecture isolates CLI parsing behind `AgentAdapter.ParseOutput()`. Acknowledged technical debt.

### Aggregate Boundary Clarity (All Audits)
Workspace is now a separate aggregate root, not owned by Task.

### Over-Engineering Prevention (All Audits)
Two-Track Lifecycle prevents applying full CI/CD to ephemeral runtime entities.