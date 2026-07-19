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

## Extended Features (Available in Design)

| Feature | Description |
|---------|-------------|
| Multiple Agents | Codex, OpenCode, Gemini CLI supported via adapters |
| DAG Workflows | WorkflowDefinition supports task dependencies |
| Human Approvals | Approval entity with manual gating |
| Semantic Validation | Quality metrics and test execution |
| Multi-Tenant | Namespace isolation for teams |
| Advanced Policies | OPA integration option |
| Temporal Engine | WorkflowEngine interface compatible |
| Full Observability | Prometheus, OpenTelemetry integration |

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