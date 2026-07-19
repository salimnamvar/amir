# MVP Boundary

## MVP Goals

The MVP proves the core hypothesis: **reliable orchestration of external AI agents producing validated artifacts**.

**Target**: 2 months development for single-team, single-adapter, linear workflow.

## In Scope (Must Have - MVP)

| Feature | Description | Implementation Status |
|---------|-------------|---------------------|
| Single Agent Type | Claude Code CLI only | ✅ Ready |
| Agent Execution | Execute in Docker sandbox with seccomp | ✅ Ready |
| Contract Validation | Structural validation only | ✅ Ready |
| Task Management | Create, assign, execute, complete tasks | ✅ Ready |
| Linear Workflow | 3-state: implement → test → review | ✅ Ready |
| File-Based Audit | Append-only JSONL logging | ✅ Ready |
| Hard Cost Limits | Token/USD limits enforced at adapter | ✅ Ready |
| Non-Root Containers | UID 65534, read-only root | ✅ Ready |
| Domain Model | Task, AgentInvocation, Workspace, Artifact | ✅ Ready |
| Event Model | DomainEvent with correlation/causation | ✅ Ready |
| Adapter Interface | AgentAdapter abstract base class | ✅ Ready |

## Out of Scope (Deferred)

| Feature | Reason for Deferral | Target Phase |
|---------|---------------------|--------------|
| Streaming Mode B | Progress streaming adds complexity | Phase 2 |
| Multi-Environment GitOps | Single environment sufficient | Phase 2 |
| Human Approvals | Auto-approve in MVP | Phase 2 |
| Full Observability Stack | File logs sufficient | Phase 2 |
| Policy Engine (OPA) | Static policies only | Phase 3 |
| Multi-Tenancy | Single team for MVP | Phase 2 |
| Semantic Validation | Requires test runners | Phase 2 |
| Artifact Lineage | Not needed for single-run | Phase 2 |
| Temporal Integration | Proven state machine first | Phase 3 |

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
   → Validate structrual schema
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

## Deferred Schemas (Phase 2+)

The following schemas exist but are **not used in MVP**:

| Schema | Reason for Deferral |
|--------|-------------------|
| `audit-event.schema.yaml` | MVP uses simple JSONL append-only logging |
| `approval.schema.yaml` | MVP auto-approves all transitions |
| `workspace.schema.yaml` | Defined but managed implicitly by Sandbox Manager |

All other schemas under `docs/contract/schemas/` are required for MVP.

---

## What Was Removed From Previous Scope

Based on audit feedback:

1. **Removed**: Full event retention tiers (MVP: single file)
2. **Removed**: Streaming progress events (MVP: completion only)
3. **Removed**: Multi-environment GitOps (MVP: single environment)
4. **Removed**: Human approval gates (MVP: auto-approve)
5. **Removed**: Full OpenTelemetry integration (MVP: structured file logs)