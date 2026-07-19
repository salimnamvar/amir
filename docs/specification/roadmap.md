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
| Default | ParserRegistry with 2 strategies (structured_output, markdown_block) |
| Extended | 5 strategies including tool_call_interception, workspace_observation, llm_coercion |
| Full | Custom parsers per agent type |

---

## Feature Completeness Matrix

All features are designed and specified. Implementation options vary by deployment scale.

| Feature | Default | Extended | Scale |
|---------|---------|----------|-------|
| Multi-Agent | 1 adapter | Multiple | 10+ |
| Runtime | gVisor | gVisor + Firecracker | Multi-runtime |
| Events | File + Outbox | Kafka | Multi-region |
| Storage | SQLite | PostgreSQL | Sharded |
| Policy | Static | OPA | Federated |
| Observability | Logs | Prometheus | Dedicated cluster |
| Parser | 2 strategies | 5 strategies | Custom |
| Audit | File | Merkle-chained | Transparency log |
| Cost | Basic tracking | Hierarchical gate | ML prediction |

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
