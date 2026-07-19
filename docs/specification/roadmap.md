# Evolution Roadmap

## Implementation Options

### Workflow Engine
| Option | Technology |
|--------|------------|
| Default | In-process state machine (SQLite) |
| Extended | Message queue + PostgreSQL |
| Alternative | Temporal-compatible interface available |

### Sandbox
| Option | Technology |
|--------|------------|
| Default | Docker + seccomp (non-root required) |
| Enhanced | gVisor microVMs |
| Maximum | Firecracker + network policies |

### Event System
| Option | Technology |
|--------|------------|
| Default | JSONL append-only file |
| Extended | Kafka-compatible interface |
| Full | Kafka + Schema Registry + OpenTelemetry |

### Storage
| Option | Technology |
|--------|------------|
| Default | SQLite |
| Extended | PostgreSQL |
| Scale | Sharded PostgreSQL |

### Security
| Option | Feature |
|--------|---------|
| Default | Static allow/deny policies |
| Extended | OPA integration for ABAC |
| Audit | Cryptographic signing per event |

---

## Feature Completeness Matrix

All features are designed and specified. Implementation options vary by deployment scale.

| Feature | Default | Extended | Scale |
|---------|---------|----------|-------|
| Multi-Agent | 1 adapter | Multiple | 10+ |
| Sandbox | Docker | gVisor | Firecracker |
| Events | File | Kafka | Multi-region |
| Storage | SQLite | PostgreSQL | Sharded |
| Policy | Static | OPA | Federated |
| Observability | Logs | Prometheus | Dedicated cluster |

---

## Risk Mitigation

| Risk | Detection | Mitigation |
|------|-----------|------------|
| CLI Parsing Unreliable | <85% success rate | Adapter layer isolation |
| Sandbox Escape | Security tests fail | Non-root mandatory, layered defense |
| Cost Controls Fail | Budget overruns | Hard limits with threshold kill |
| State Machine Coupling | Migration blocked | Interface seam decouples logic |