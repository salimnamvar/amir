# Vision, Goals, and Non-Goals

## Vision

Amir is a control-plane system that creates, manages, coordinates, and governs teams of external AI coding agents. It transforms chaotic, unstructured AI agent interactions into engineering-grade, auditable, and repeatable workflows through contract-driven communication, role-based governance, and GitOps-managed configuration.

Amir does **not** provide intelligence itself. It provides the infrastructure for reliable, scalable orchestration of heterogeneous AI agents.

The core architectural insight: **CLI agents are unreliable, non-deterministic programs that produce unstructured output.** Amir must treat agent output as untrusted narrative and derive ground truth from workspace observation.

## Goals

✅ **Control Plane Agnosticism** - Support CLI, MCP, and API-based agents without vendor lock-in through the Adapter pattern

✅ **Contract-Driven Communication** - All agent interactions produce typed, versioned, validated artifacts with provenance tracking

✅ **Engineering-Grade Governance** - Apply proven software engineering practices (GitOps, CI/CD, security) to AI agent management

✅ **GitOps Configuration** - All definitions versioned, reviewed, and promoted via pull requests with semantic versioning

✅ **Security-First Architecture** - Zero-trust execution with mandatory gVisor isolation, egress proxy, and just-in-time secrets

✅ **Observable Operations** - Full audit trails, Merkle-chained events, and structured logging for compliance

✅ **Scalable Design** - Horizontal scaling from 5 to 1000+ agents with documented evolution paths

✅ **Two-Track Lifecycle** - Configuration entities follow GitOps promotion, Runtime entities follow lightweight state machines

✅ **Reliable Agent Execution** - AgentSession with checkpointing, circuit breaker, and replay metadata for non-deterministic agents

✅ **Intelligent Recovery** - Validation failure → feedback → re-invocation loop with budgeted retry and escalation

✅ **Workspace Observation** - Artifacts derived from filesystem state, not agent claims

✅ **Cost Governance** - Hierarchical enforcement with reservation protocol, not advisory limits

## Complete Feature Set

### Agent Management
- Multi-agent type support (Claude, Codex, OpenCode, Gemini CLI)
- Three-layer runtime: PromptCompiler → AgentExecutor → OutputParser
- ParserRegistry with 4-strategy default chain (llm_coercion opt-in only)
- Workspace observation as ground truth
- Capability-based routing with multi-dimensional scoring
- AgentScorecard with historical performance metrics
- Circuit breaker per agent
- Replay metadata for debugging

### Workflow Orchestration
- Linear and DAG workflow support
- Event-sourced WorkflowInstance with compensation stack
- Git-native compensation (revert, branch delete, PR close)
- Approval gates with escalation chains
- Idempotent step execution
- Durable execution with timeouts and heartbeats

### Security & Isolation
- Mandatory gVisor/Firecracker in production (Docker dev-only)
- Mandatory egress proxy (host mode eliminated)
- Just-in-time secret injection with TTL
- Runtime attestation for sandbox integrity
- Merkle-chained audit events
- Pluggable policy engine (static default, OPA optional)

### Observability
- Structured event logging with outbox pattern
- Hierarchical cost tracking with orchestration/worker separation
- AgentScorecard with success rate, cost, latency metrics
- Validation pipeline metrics
- Replay capability for debugging
- W3C trace context integration

### Cost Governance
- Hierarchical cost gate (4 levels)
- Pre-flight cost estimation
- Reservation protocol for concurrent tasks
- Sidecar proxy for real-time token counting
- Per-task hard limits with team-level budgets
- CostRecord with multi-dimensional attribution

### Multi-Tenant Support
- Namespace isolation
- Team-level quotas and scoring weights
- RBAC/ABAC authorization

---

## Non-Goals

❌ **Agent Intelligence** - Amir does not provide LLMs or reasoning capabilities; it orchestrates external agents

❌ **Human Chat Interface** - Amir is not a conversational UI; all interactions are programmatic via contracts

❌ **Direct Code Hosting** - Git repositories remain external; Amir orchestrates changes via PRs, not direct commits

❌ **Universal Lifecycle for All Entities** - Runtime entities use simple state machines, not full GitOps lifecycles

❌ **Homogeneous Agents** - Amir deliberately supports heterogeneous, external agent tools (Claude, Codex, OpenCode, Gemini, etc.)

❌ **Full Temporal Migration** - WorkflowEngine interface seam preserved; Temporal is an implementation option, not a design requirement

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Agent Execution Reliability | 90% success rate (via retry) |
| Contract Validation | Structural + Semantic |
| Artifact Recovery | Automatic via workspace observation + feedback loop |
| Sandbox Security | Mandatory gVisor/Firecracker in production |
| Cost Control | Hierarchical enforcement with reservation |
| Audit Completeness | Merkle-chained events with tamper-evidence |

---

## Relationship to Audit Feedback

The vision has been hardened based on three rounds of architecture audits:

### Round 1-2 (Foundation)
- Two-Track Lifecycle
- Bounded Context Separation
- Contract-First Design
- AgentInvocation as Runtime Entity

### Round 3 (17 Independent Audits - Major Reinforcement)
- **Agent Session Model** (All 17): AgentSession with checkpointing, replay, circuit breaker
- **Validation Feedback Loop** (All 17): Structured error → correction → retry with budget
- **Three-Layer Runtime** (Xiaomi/Tinker/Gemini): PromptCompiler → AgentExecutor → OutputParser
- **Workspace Observation** (Tinker/Qwen): Artifacts from git diff, not agent claims
- **ParserRegistry** (Kimi/GLM/Gemini): 4-strategy default chain; llm_coercion opt-in
- **Capability Scoring** (All 17): Multi-dimensional weighted algorithm with historical metrics
- **Cost Gate** (All 17): Hierarchical enforcement with reservation protocol
- **Durable Workflow** (All 17): Saga pattern with git-native compensation
- **Mandatory Egress Proxy** (Gemini/Qwen): Host mode eliminated
- **Idempotency** (Claude/Kimi): All mutable operations keyed
- **Circuit Breaker** (Xiaomi/Sakana): Per-agent failure quarantine
- **Agent Scorecard** (ChatGPT/Grok): Historical performance for routing
- **Verifiable Audit** (Minimax/GLM): Merkle-chained events
- **Prompt Compiler** (Minimax/Kimi): Reproducible prompt artifacts
