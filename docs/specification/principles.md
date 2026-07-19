# Architecture Principles

## 1. Clean Architecture / Hexagonal Architecture

Amir follows Clean Architecture principles with explicit boundaries:

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Plane                            │
│  API Gateway │ Orchestration │ Governance │ Monitoring      │
├─────────────────────────────────────────────────────────────┤
│                    Execution Plane                           │
│  PromptCompiler │ AgentExecutor │ OutputParser │ Sidecar    │
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

- **Ports**: WorkflowEngine, AgentAdapter, SandboxManager, ArtifactValidator, EventPublisher, OutputParser, PromptCompiler, CostGate, PolicyEngine
- **Adapters**: ClaudeCodeAdapter, CodexAdapter, APIAgentAdapter, DockerSandbox, GVisorSandbox, FirecrackerSandbox, OPAEngine, FileEventStore
- All ports defined in `domain/protocols/` as abstract base classes

## 2. Domain-Driven Design

### Bounded Contexts

Five explicit bounded contexts prevent conceptual leakage:
1. **Configuration**: GitOps-managed definitions
2. **Execution**: Runtime task orchestration and agent sessions
3. **Workflow**: State machines, approvals, and compensation
4. **Security**: Sandboxing, secrets, access control, egress, and audit
5. **Observability**: Metrics, cost tracking, quality measurement, agent performance

### Aggregate Roots

Each entity belongs to exactly one aggregate root. Cross-aggregate consistency via domain events and outbox pattern.

## 3. Execution-First, Contract-Governed Design

**Runtime truth is execution; contracts govern and validate it.**

- **AgentSession** is the central durable aggregate (what ran).
- **Contracts** (schemas, versions, validators) define legal shapes and acceptance rules.
- **AgentInvocation** is a request DTO into the session, not a parallel source of truth.
- Configuration entities (Team, Role, Agent) are GitOps-published definitions, not runtime state.

### Contract Properties

All contracts declare:
- **Schema**: JSON Schema 2020-12 (primary) with YAML frontend
- **Version**: SemVer with MAJOR.MINOR.PATCH
- **Compatibility**: N-1 minor version backward compatibility
- **Validation**: Structural + semantic validation via pluggable validators

### Contract Types

- AgentContract, TaskContract, ArtifactContract, WorkflowContract, RoleContract, FeedbackContract, ValidationResultContract, CostRecordContract, MatchingDecisionContract, CompiledPromptContract, SandboxAttestationContract, WorkspaceContract, AgentSessionContract

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
- **Cost Events**: Financial tracking (365-day retention)

### Event Envelope

All events use `DomainEvent` with:
- event_id, event_type, aggregate_id, aggregate_type
- correlation_id, causation_id, producer, version, timestamp, payload
- sequence, prev_hash (for Merkle chain)

### Outbox Pattern

Domain events published via outbox for reliable delivery. Delivery semantics by category.

## 6. Security Principles

### Zero Trust Execution

- Every agent execution is fully isolated
- All outbound traffic through egress proxy (host mode eliminated)
- Secrets never stored with code; injected via tmpfs with TTL
- All actions logged and traceable via Merkle-chained audit

### Defense in Depth

1. Container isolation (gVisor mandatory in production, non-root, read-only root)
2. Filesystem isolation (ephemeral workspace with baseline/current tracking)
3. Network isolation (egress proxy with domain allowlist, mTLS)
4. Runtime monitoring (attestation, circuit breaker, agent scorecard)
5. Cost isolation (hierarchical cost gate with reservation protocol)

### Just-In-Time Secrets

- Secrets fetched from vault at execution start
- Injected into sandbox via tmpfs (memory-only)
- API keys routed through egress proxy for cost attribution
- Revoked immediately after execution completes (TTL-based)

## 7. Workspace Observation

**Principle**: Agent output is untrusted narrative. The filesystem is ground truth.

Artifacts are derived from workspace state (`git diff`, `git status`, file reads) rather than agent stdout claims. This is the single most important reliability mechanism for controlling non-deterministic agents.

## 8. Idempotency by Default

**Principle**: All mutable operations require idempotency keys. Retry is safe.

Every operation that causes side effects (task creation, agent execution, artifact production, compensation) uses idempotency keys to prevent duplicate execution on retry.

## 9. Hierarchical Cost Control

**Principle**: Cost is a runtime invariant, not an advisory limit.

Four-level enforcement: per-invocation → per-team-hourly → per-tenant-daily → per-org-monthly. Pre-flight estimation before execution. Reservation protocol for concurrent tasks.

## 10. Evolution Paths

Each major component has documented migration paths:

| Component | Default | Alternative Options |
|-----------|---------|-------------------|
| Workflow | Internal state machine (SQLite) | Temporal-compatible interface |
| Sandbox | gVisor (production), Docker (dev) | Firecracker for maximum security |
| Storage | SQLite | PostgreSQL, sharded PostgreSQL |
| Events | File (JSONL) + Outbox | Kafka-compatible interface |
| Observability | File logs | Prometheus, OpenTelemetry |
| Policy Engine | Static AllowDeny | OPA/Rego |
| Parser | ParserRegistry strategy chain | Custom parsers per agent type |

---

## Addressing Audit Concerns

### CLI Parsing Risk (All Audits)
Three-layer runtime (PromptCompiler → AgentExecutor → OutputParser) with ParserRegistry strategy chain. Workspace observation as ground truth.

### Aggregate Boundary Clarity (All Audits)
Workspace is an Execution aggregate root (not Security). Security evaluates SandboxPolicy at admission. AgentSession is the central runtime aggregate.

### Over-Engineering Prevention (All Audits)
Two-Track Lifecycle prevents applying full CI/CD to ephemeral runtime entities. Static rules as default; OPA as extension.

### Agent Non-Determinism (All Audits)
AgentSession with full checkpointing. Agent-scoped circuit breaker with quarantine. AgentScorecard for historical routing with version warm-start.

### Cost as First-Class (All Audits)
Hierarchical cost gate with structural ceilings. Reservation protocol. In-flight cancel at higher-level hard thresholds. Sidecar + egress real-time enforcement.

### Adapter Reliability (Round 4)
Explicit adapter pump loop, interactive prompt protocol, feedback injection, and replay metadata. Control plane owns parser strategy and workspace ground truth.
