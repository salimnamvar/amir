# Evolution Roadmap

## Implementation Options

### Workflow Engine
| Option | Technology |
|--------|------------|
| Default | In-process state machine (SQLite) with event sourcing |
| Extended | Message queue + PostgreSQL |
| Alternative | Temporal-compatible interface available |

### Sandbox
| Option | Technology |
|--------|------------|
| Default | gVisor (production), Docker (dev only) |
| Maximum | Firecracker + network policies |

### Event System
| Option | Technology |
|--------|------------|
| Default | JSONL append-only file + Outbox table |
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
| Default | Static AllowDeny policies |
| Extended | OPA integration for ABAC |
| Audit | Merkle-chained events + transparency log |

### Parser
| Option | Technology |
|--------|------------|
| Default | ParserRegistry with 4 strategies (structured_output, tool_call, markdown_block, workspace_observation) |
| Extended | Custom parser plugins per agent type |

---

## Feature Completeness Matrix

All features are designed and specified. Implementation options vary by deployment infrastructure.

| Feature | Infrastructure Options |
|---------|---------------------|
| Multi-Agent | Single adapter, Multiple adapters, Large-scale pool (10+) |
| Runtime | gVisor (production), Firecracker (max security), Docker (dev only) |
| Events | File-based + Outbox, Kafka, Multi-region streaming |
| Storage | SQLite, PostgreSQL, Sharded PostgreSQL |
| Policy | Static rules, OPA integration, Federated policy |
| Observability | Structured logs, Prometheus metrics, Dedicated observability cluster |
| Parser | 4-strategy default chain, Custom parser plugins |
| Audit | File-based (WORM), Merkle-chained events, Transparency log |
| Cost | Structural ceilings, Hierarchical cost gate, Pre-flight estimation + reservation |

---

## Risk Mitigation

| Risk | Detection | Mitigation |
|------|-----------|------------|
| CLI Parsing Unreliable | <85% success rate | ParserRegistry fallback chain + workspace observation |
| Agent Invalid Output | Validation failure | Feedback loop with budgeted retry |
| Sandbox Escape | Security tests fail | Mandatory gVisor, non-root, read-only root |
| Cost Controls Fail | Budget overruns | Hierarchical cost gate with reservation |
| Agent Cascades Failures | 5 consecutive failures | Circuit breaker with quarantine |
| Workflow State Loss | Event store corruption | Event sourcing with checkpoints |
| Duplicate Side Effects | Idempotency check fails | Idempotency keys on all mutable operations |
| Audit Tampering | Hash chain verification | Merkle-chained events + transparency log |
