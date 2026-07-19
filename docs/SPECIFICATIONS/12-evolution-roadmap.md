# Evolution Roadmap

## Phase 1: MVP (Current)

**Target**: 2 months  
**Scale**: 5 agents, 1 team, 1 repository

### Components
- Single adapter: Claude Code CLI
- Docker sandbox with seccomp
- SQLite for state
- File-based event logging (JSONL)
- Linear 3-state workflow
- Structural contract validation only
- Auto-approve for all transitions

### Success Criteria
- Agent executions complete 90% successfully
- Artifacts structurally validated
- Hard cost limits enforced
- Audit trail complete

---

## Phase 2: Multi-Agent (3-4 months)

**Target**: 50 agents, 3 teams, multiple repositories

### New Features

| Feature | Description |
|---------|-------------|
| **Multiple Adapters** | Codex, OpenCode, Gemini CLI support |
| **gVisor/Firecracker** | Enhanced sandbox isolation |
| **PostgreSQL** | Replace SQLite for state |
| **Kafka Events** | Real event streaming |
| **Human Approvals** | ApprovalGate entity with timeouts |
| **Semantic Validation** | Test execution, quality criteria |
| **Multi-Tenant** | Team isolation, RBAC |
| **Cost Tracking** | Full cost dashboard with alerts |

### Workflow Enhancements
```yaml
workflow_features:
  - dag_tasks: true
  - hard_dependencies: true
  - soft_dependencies: true
  - approval_gates: true
  - compensation_actions: true  # Phase 2
```

### Security Enhancements
```yaml
sandbox_features:
  - runtime: gVisor  # was: Docker
  - network_allowlist: true
  - file_scanning: true
  - prompt_injection_detection: true
```

---

## Phase 3: Enterprise (6-8 months)

**Target**: 500 agents, 20 teams, production scale

### New Features

| Feature | Description |
|---------|-------------|
| **Temporal Engine** | Full workflow durability |
| **Full Observability** | OpenTelemetry, Prometheus, Grafana |
| **Policy Engine** | OPA integration for ABAC |
| **Artifact Lineage** | Full artifact ancestry tracking |
| **Plugin System** | Custom validator plugins |
| **Multi-Environment GitOps** | Dev/Staging/Prod promotion |

### Architecture Evolution
```
SQLite → PostgreSQL → CockroachDB (sharded)
Docker → gVisor → Firecracker (multi-zone)
File Events → Kafka → Kafka + Schema Registry
Local Sandbox → Distributed Sandbox Pool
```

---

## Phase 4: Global Scale (12+ months)

**Target**: 1000+ agents, global deployment

### New Features

| Feature | Description |
|---------|-------------|
| **Multi-Region Control Plane** | Geographic distribution |
| **Federated Workflow Engine** | Cross-cluster workflows |
| **SOC 2 Compliance** | Audit, security certifications |
| **Auto-Scaling Sandbox Pools** | Dynamic resource allocation |
| **ML Cost Optimization** | Predictive budgeting |
| **Vendor Marketplace** | Agent adapter marketplace |

### Architecture Evolution
```
Single Control Plane → Federated Control Planes
Monolithic DB → Sharded Database
Single Queue → Distributed Message Bus
Standby Recovery → Active-Active Clustering
```

---

## Component Evolution Paths

### Workflow Engine

| Phase | Technology |
|-------|------------|
| 1 | In-process state machine (SQLite) |
| 2 | Message queue + PostgreSQL |
| 3 | Temporal (durable workflows) |
| 4 | Temporal global (multi-region) |

### Sandbox

| Phase | Technology |
|-------|------------|
| 1 | Docker + seccomp (non-root) |
| 2 | gVisor microVMs |
| 3 | Firecracker + network policies |
| 4 | Firecracker + runtime monitoring |

### Event System

| Phase | Technology |
|-------|------------|
| 1 | JSONL append-only file |
| 2 | Kafka (basic) |
| 3 | Kafka + Schema Registry + OpenTelemetry |
| 4 | Multi-region event mesh |

### Storage

| Phase | Technology |
|-------|------------|
| 1 | SQLite |
| 2 | PostgreSQL |
| 3 | CockroachDB (geo-partitioned) |
| 4 | Sharded PostgreSQL with multi-region |

---

## Risk Mitigation Milestones

| Risk | Detection | Mitigation Milestone |
|------|-----------|-------------------|
| CLI Parsing Unreliable | <85% success rate | Phase 1 checkpoint |
| Sandbox Escape Possible | Security tests fail | Phase 1 security review |
| Cost Controls Fail | Budget overruns | Phase 1 cost ceiling |
| Temporal Migration Blocked | State machine too coupled | End of Phase 1 |
| Multi-Tenant Isolation | Cross-team data leak | Phase 2 security audit |