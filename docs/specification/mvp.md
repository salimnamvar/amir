# MVP Boundary

## MVP Goals

The MVP proves the core hypothesis: **reliable orchestration of external AI agents producing validated artifacts through workspace observation and structured feedback.**

**Target**: 2 months development for single-team, single-adapter, linear workflow.

## In Scope (Must Have - MVP)

| Feature | Description |
|---------|-------------|
| Single Agent Type | Claude Code CLI only |
| Three-Layer Runtime | PromptCompiler → AgentExecutor → OutputParser |
| AgentSession | Durable execution with checkpoints |
| Workspace Observation | Artifacts derived from git diff |
| ParserRegistry | 2 strategies: structured_output + markdown_block |
| Validation Feedback Loop | Structural validation with retry |
| Circuit Breaker | Per-agent failure counting (threshold=5) |
| Task Management | Create, assign, execute, complete tasks |
| Linear Workflow | 3-state: implement → test → review |
| File-Based Audit | Append-only JSONL logging |
| Cost Tracking | CostRecord with token counting |
| Non-Root Containers | UID 65534, read-only root |
| gVisor Sandbox | Mandatory in production |
| Egress Proxy | All traffic through Amir proxy |
| Domain Model | Task, AgentSession, Workspace, Artifact, CostRecord |
| Event Model | DomainEvent with correlation/causation |
| Adapter Interface | AgentAdapter abstract base class |
| Idempotency | All mutable operations keyed |

## Extended Features (Available in Design)

| Feature | Description |
|---------|-------------|
| Multiple Agents | Codex, OpenCode, Gemini CLI supported via adapters |
| Full ParserRegistry | 5 strategies including LLM coercion and tool call interception |
| DAG Workflows | WorkflowDefinition supports task dependencies |
| Compensation | Git-native compensation with saga pattern |
| Human Approvals | Approval entity with escalation chains |
| Semantic Validation | Pluggable validators with timeout and budget |
| Agent Scorecard | Historical performance metrics for routing |
| Multi-Tenant | Namespace isolation for teams |
| Advanced Policies | OPA integration option |
| Temporal Engine | WorkflowEngine interface compatible |
| Full Observability | Prometheus, OpenTelemetry integration |
| Merkle-Chained Audit | Hash chain for tamper-evidence |
| Replay Capability | Full execution replay for debugging |
| Multi-Dimensional Scoring | Weighted algorithm with 7 dimensions |

## MVP Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Control Plane                                            │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Amir API    │  │ Orchestrator   │  │ Cost Gate    │   │
│  └─────────────┘  └──────────────┘  └──────────────┘   │
├─────────────────────────────────────────────────────────┤
│  Execution Plane                                          │
│  ┌──────────┐ ┌────────────┐ ┌──────────┐ ┌──────────┐ │
│  │Prompt    │ │Agent       │ │Output    │ │Egress    │ │
│  │Compiler  │ │Executor    │ │Parser    │ │Proxy     │ │
│  └──────────┘ └────────────┘ └──────────┘ └──────────┘ │
├─────────────────────────────────────────────────────────┤
│  Sandbox (gVisor)                                         │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ Agent CLI + Sidecar (token counting)                 │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## MVP Data Flow

```
1. POST /tasks
   {objective, role: "developer", idempotency_key: "..."}

2. Orchestrator
   → Create Task entity
   → MatchingDecision.Made (score agent)
   → Emit Task.Assigned

3. PromptCompiler
   → Render CompiledPrompt from Task + Role + Agent
   → Store CompiledPrompt artifact

4. Sandbox Manager (gVisor)
   → Create sandbox (non-root, read-only root)
   → Clone repo to /workspace
   → Record baseline commit
   → Inject secrets via tmpfs
   → Inject API keys via tmpfs (routed through proxy)

5. Agent Executor
   → Spawn agent process with sidecar
   → Sidecar counts tokens in real-time
   → Agent executes work

6. Output Parser (ParserRegistry)
   → Strategy 1: structured_output (if agent supports)
   → Strategy 2: markdown_block extraction
   → If both fail: workspace observation (git diff)

7. Workspace Observation
   → git diff baseline..current
   → Derive CodeChangeArtifact from diff
   → Compare with agent claims

8. Contract Validator
   → Structural validation
   → Emit Artifact.Validated or Artifact.Rejected

9. If REJECTED:
   → FeedbackArtifact created
   → Retry within budget (max_attempts=3)
   → Feedback injected into PromptCompiler

10. If VALID:
    → Artifact accepted
    → CostRecord emitted
    → Task.Completed
```

## Success Criteria

| Metric | Target |
|--------|--------|
| Task completion rate | 90% (via retry) |
| Contract validation success | 95% (structural) |
| Workspace observation reliability | 90% (fallback for parsing) |
| Sandbox isolation | 100% non-root, gVisor |
| Cost limit enforcement | 100% (hierarchical) |
| Audit trail completeness | 100% events logged |
| Idempotent operations | 100% (all mutable ops) |

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| CLI parsing fails | ParserRegistry with fallback chain + workspace observation |
| Agent produces invalid output | Validation feedback loop with budgeted retry |
| Sandbox escape | Mandatory gVisor, non-root, read-only root |
| Cost explosion | Hierarchical cost gate with reservation protocol |
| Agent cascades failures | Circuit breaker with quarantine |
| Workflow durability | Event-sourced state with checkpointing |
| Duplicate side effects | Idempotency keys on all mutable operations |
