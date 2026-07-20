# System Boundary

## Design Goal

Amir is a **complete** control plane for reliable orchestration of external AI agents. Agents produce validated artifacts through workspace observation and structured feedback. The design describes the full intended system — not a reduced interim subset.

**Core hypothesis**: Unreliable CLI/API agents can be governed into engineering-grade outcomes when execution is session-centric, observation is filesystem-grounded, cost is structural, and security is mandatory.

## In Scope (Complete System)

| Feature | Description |
|---------|-------------|
| Multi-agent adapters | Claude Code CLI, Codex, OpenCode, Gemini CLI, MCP, API agents |
| Three-Layer Runtime | PromptCompiler → AgentExecutor → OutputParser |
| AgentSession | Central durable execution aggregate with checkpoints |
| AgentInvocation | Request DTO that creates a session |
| Workspace Observation | Artifacts derived from git/tree observation with claim reconciliation |
| ParserRegistry | Default 4-strategy chain (structured_output → tool_call_interception → markdown_block → workspace_observation); llm_coercion opt-in with approval only |
| Validation Feedback Loop | Structural + semantic validation with budgeted retry and escalation |
| Circuit Breaker | Per-agent failure counting on AgentScorecard (threshold=5) |
| Task Management | Create, assign (hard filter → score → negotiate), execute, complete |
| Workflow Engine | Linear and DAG workflows with saga compensation |
| Compensation | Abstract workflow intents → durable git/PR/artifact effects |
| Human Approvals | Approval entity with escalation |
| Audit | linear hash-chained events with KMS-backed signing keys |
| Cost Control | Hierarchical gate with structural ceilings, CostLease sync hard kill, **required** validation_budget partition, revoke_by_scope cascade |
| Sandbox | Mandatory gVisor (prod) / Firecracker option; docker only for development |
| Egress Proxy | All traffic through Amir proxy; default-deny allowlist |
| Domain Model | Task, AgentSession, Workspace, Artifact, CostRecord, MatchingDecision, … |
| Event Model | DomainEvent with correlation/causation and outbox |
| Adapter Interface | pump / respond_input / inject_feedback / cancel |
| Idempotency | All mutable operations keyed |
| Agent Scorecard | Historical metrics + warm-start across agent versions |
| Semantic Validation | Pluggable validators with timeout and budget |
| Replay | CompiledPrompt + ReplayMetadata |

## Explicit Non-Goals

| Non-Goal | Rationale |
|----------|-----------|
| Embedding foundation models in-process | Amir orchestrates external agents; it is not an LLM host |
| Replacing VCS/CI | Git and CI remain systems of record for code promotion |
| Universal MCP mandate | CLI agents remain first-class |
| Public open protocol publication | Internal coherence first |
| ML-based cost prediction | Historical p95 + buffer sufficient |
| eBPF escape detection as core | Optional hardening where kernels allow |

## Architecture

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
│  │Compiler  │ │Adapter     │ │Parser    │ │Proxy     │ │
│  └──────────┘ └────────────┘ └──────────┘ └──────────┘ │
├─────────────────────────────────────────────────────────┤
│  Sandbox (gVisor) + Sidecar                               │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ Agent CLI + token counting + I/O intercept            │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Canonical Data Flow

```
1. POST /tasks
   {objective, role, idempotency_key, cost_budget: {max_usd | max_tokens}}

2. Orchestrator
   → Create Task
   → hard_filter → score_agent → negotiate_contract
   → MatchingDecision
   → Reserve cost (estimate + buffer)
   → Create AgentSession + Workspace
   → Compile Prompt
   → Adapter.pump until terminal
   → Observe workspace; reconcile claims
   → Validate (structural + semantic)
   → Accept artifact or Feedback → new session
   → Commit/release cost; update scorecard
```
