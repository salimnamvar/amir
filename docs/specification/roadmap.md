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
| Full | Kafka + OpenTelemetry |

### Storage

| Option | Technology |
|--------|------------|
| Default | SQLite |
| Extended | PostgreSQL |
| Scale | Sharded PostgreSQL |

---

## Risk Mitigation Milestones

| Risk | Detection | Mitigation |
|------|-----------|------------|
| CLI Parsing Unreliable | <85% success rate | Adapter layer isolation |
| Sandbox Escape | Security tests fail | Non-root mandatory, layered defense |
| Cost Controls | Budget overruns | Hard limits with 95% threshold |
| State Machine Coupling | Migration blocked | Interface seam decouples logic |
| Tenant Isolation | Cross-team data | Namespace isolation in DB |