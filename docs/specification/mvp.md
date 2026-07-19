# MVP Boundary

## MVP Goals

The MVP proves the core hypothesis: **reliable orchestration of external AI agents producing validated artifacts**.

**Target**: 2 months development for single-team, single-adapter, linear workflow.

## In Scope (Must Have - MVP)

| Feature | Description |
|---------|-------------|
| Single Agent Type | Claude Code CLI only |
| Agent Execution | Execute in Docker sandbox with seccomp |
| Contract Validation | Structural validation |
| Task Management | Create, assign, execute, complete tasks |
| Linear Workflow | 3-state: implement → test → review |
| File-Based Audit | Append-only JSONL logging |
| Hard Cost Limits | Token/USD limits enforced at adapter |
| Non-Root Containers | UID 65534, read-only root |
| Domain Model | Task, AgentInvocation, Workspace, Artifact |
| Event Model | DomainEvent with correlation/causation |
| Adapter Interface | AgentAdapter abstract base class |

## Out of Scope (Removed)

| Feature | Reason for Removal |
|---------|---------------------|
| Streaming Mode B | Out of scope - heartbeat events instead |
| Multi-Environment GitOps | Out of scope - single environment |
| Human Approvals | Out of scope - binary auto-approve only |
| Full Observability Stack | Out of scope - file logs only |
| Policy Engine (OPA) | Out of scope - static policies only |
| Multi-Tenancy | Out of scope - single team only |
| Semantic Validation | Out of scope - structural only |
| Artifact Lineage | Out of scope - not needed |
| Temporal Integration | Out of scope - custom state machine only |

## MVP Architecture

```
┌─────────────────────────────────────────────────┐
│  Control Plane                                    │
│  ┌─────────────┐  ┌──────────────┐             │
│  │ Amir API    │  │ Orchestrator   │             │
│  └─────────────┘  └──────────────┘             │
├─────────────────────────────────────────────────┤
│  Execution Plane                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────┐│
│  │Sandbox Mgr  │  │Agent Adapter  │  │ Workspace││
│  │(Docker)     │  │(Claude CLI)   │  │(isolated││
│  └─────────────┘  └──────────────┘  │ FS)      ││
├─────────────────────────────────────────────────┤
│  Agents                                           │
│  ┌─────────────────────────────────────────────┐ │
│  │ Claude Code CLI (structured output mode)      │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

## MVP Data Flow

```
1. POST /tasks
   {objective, role: "developer"}

2. Orchestrator
   → Create Task entity
   → Assign to Claude agent
   → Emit Task.Created

3. Sandbox Manager
   → Create Docker container (non-root)
   → Clone repo to /workspace
   → Mount as tmpfs

4. Agent Adapter
   → Stream TaskContract to agent
   → Execute agent with timeout
   → Enforce cost limits

5. Agent
   → Produces CodeChangeArtifact

6. Contract Validator
   → Validate structural schema
   → Emit Artifact.Validated

7. Orchestrator
   → Accept/reject artifact
   → Complete task
```

## Success Criteria

| Metric | Target |
|--------|--------|
| Task completion rate | 90% |
| Contract validation success | 95% (structural) |
| Sandbox isolation | 100% non-root |
| Cost limit enforcement | 100% (hard limits) |
| Audit trail completeness | 100% events logged |

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| CLI parsing fails | Deterministic extraction, no regex fallback |
| Sandbox escape | Non-root containers, read-only root, security review |
| Cost explosion | Hard limits enforced at adapter, 95% threshold kill |
| Workflow durability | SQLite persistence on each state change |

---

## Removed From Previous Scope

Based on scope decisions:

1. **Removed**: Multi-environment GitOps (single environment)
2. **Removed**: Human approval gates (binary auto-approve only)
3. **Removed**: Full OpenTelemetry integration (file logs only)
4. **Removed**: Temporal/Temporal integration (custom state machine)
5. **Removed**: OPA policy engine (static policies only)