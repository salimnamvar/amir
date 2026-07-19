# Amir Architecture Specification

**Version:** 2.0.0  
**Status:** Authoritative Technical Specification  
**Owner:** Technical Leadership

---

## Audit Findings Synthesis

### Round 3 Audit Findings (17 Independent Architecture Audits)

#### Fully Accepted Findings

| Finding | Source | Implementation |
|---------|--------|---------------|
| Agent Session as Durable Unit of Work | All 17 | `AgentSession` aggregate with state machine: Pending → Starting → Running → WaitingForInput → ProducingArtifact → Validating → Succeeded / Failed / Compensating / TimedOut. Every tool call, partial output, and checkpoint recorded as immutable event. |
| Validation → Feedback → Re-Invocation Loop | All 17 | `ValidationResult` contract with structured error categories (structural, semantic, policy), `FeedbackArtifact` with corrections and suggested strategy, `ReinvocationPolicy` with budgeted retry (max attempts, escalation to different agent or human). |
| Three-Layer Agent Runtime | Xiaomi/Tinker/Gemini | Architecture: PromptCompiler → AgentExecutor → OutputParser. Each layer is independently testable and replaceable. PromptCompiler renders structured prompts; AgentExecutor manages process lifecycle; OutputParser extracts artifacts from output. |
| Workspace Observation Layer | Tinker/Qwen | Artifacts derived from workspace state (`git diff`, `git status`, file reads) rather than agent stdout claims. Agent output is treated as untrusted; ground truth is the filesystem. |
| ParserRegistry with Strategy Chain | Kimi/GLM/Gemini | Deterministic extraction pipeline: structured_output → tool_call_interception → markdown_block extraction → LLM_coercion (cheap model reformatting) → reject. Each strategy is versioned and testable. |
| Multi-Dimensional Capability Scoring | All 17 | Replace flat `proficiency` enum with weighted scoring: `score(agent, task, context, history) → (score, explanation, projected_cost, projected_latency)`. Historical ValidationResults feed the scorer. Configurable weights per dimension. |
| Runtime Cost Gate | All 17 | Hierarchical enforcement: per-invocation → per-team-hourly → per-tenant-daily → per-org-monthly. Hard chokepoints with reservation/commit/release protocol. Pre-flight estimation before invocation. |
| Durable Workflow with Compensation | All 17 | Saga pattern with compensation stack. Each workflow step defines a `compensate` action. Git-native compensation: `git revert`, branch delete, PR close. Event-sourced WorkflowInstance with append-only log. |
| Circuit Breaker per Agent | Xiaomi/Sakana | After 5 consecutive failures, agent quarantined. Recovery requires manual reset or health check pass. Prevents cascading failures across task queue. |
| Mandatory Egress Proxy | Gemini/Qwen-1/Qwen-0/GLM | `network_mode: host` removed entirely. All outbound traffic through Amir egress proxy with domain allowlist, mTLS, token counting, PII/secret scrubbing. Agent API keys routed through proxy for cost visibility. |
| Idempotency Keys | Claude/Kimi | All mutable operations (Task creation, AgentInvocation, Artifact production) require idempotency keys. Prevents duplicate side effects on retry. |
| Agent Scorecard with Historical Metrics | ChatGPT/Grok | `AgentScorecard` tracks: historical success rate, average cost, p95 latency, failure pattern distribution, last N validation results. Feeds capability scoring algorithm. |
| Structured Output Mode Negotiation | Xiaomi/Gemini | Agents declare output modes (json_schema, tool_use, markdown_yaml, free_text). Adapter selects best mode. Fallback chain per agent type. |
| Git-Native Compensation | Kimi | Branch-per-task (`amir/{task_id}/{role_name}`). Compensation = `git revert` + branch delete + PR close. Commit signing for audit trail. |
| Prompt Compiler as First-Class | Minimax/Kimi | Takes Role + Task + Agent + Memory + Workspace + InputContract → `CompiledPrompt` artifact. Versioned, stored, reproducible. Enables replay and A/B testing of prompt strategies. |
| Verifiable Audit Log | Minimax/GLM | Merkle-chained events with `prev_hash`, sequence numbers, periodic root-commit to external transparency log. Algorithm and key reference declared per event. |
| Semantic Validation as First-Class | All 17 | Structural validation alone is insufficient. Semantic validators run tests, check quality criteria, verify behavioral contracts. Pluggable validator architecture with timeout and budget. |
| Agent Execution Sidecar | DeepSeek/Gemini | In-sandbox proxy for progress monitoring, token counting, log aggregation, and cancellation. Solves CLI fragility by intercepting I/O at the process level. |
| Replay/Reproducibility Metadata | Minimax | Capture model identifier, seed, prompt hash, full prompt, tool calls, responses, sandbox profile hash. Enable `replay=true` for debugging and regression testing. |

#### Partially Accepted Findings

| Finding | Source | Partial Implementation |
|---------|--------|---------------------|
| Full OPA/Rego Policy Engine | Sakana/GLM/Grok | Adopted as pluggable policy layer for security transitions and capability routing. Not mandatory in core; available as extension point. Default uses static AllowDeny rules. |
| Multi-Turn Interactive Agents | Kimi/Gemini | `AgentConversation` entity designed for interactive agents (Claude Code REPL mode). Auto-response rules, clarification protocol, conversation mode selection. Not required for single-turn agents. |
| PromptTemplate System | Kimi | Simplified as PromptCompiler input, not standalone entity. Templates stored in `amir-config/prompts/` with versioning. No A/B testing in initial design. |
| Event Delivery Guarantees | Kimi | Outbox pattern with sequence numbers. Delivery semantics by category: domain=at-least-once+causal, audit=at-least-once+total, metrics=at-most-once. |
| Computable Contracts | Perplexity | `EvaluationTask` contract type for agent-mediated validation. Non-LLM validators preferred for structural checks; LLM validators for semantic checks with budget limits. |
| Artifact Lineage Graph | DeepSeek/Xiaomi | `derived_from` and `supersedes` fields on Artifact. DAG of artifact dependencies for impact analysis and provenance tracking. |

#### Rejected Findings

| Finding | Source | Reason for Rejection |
|---------|--------|---------------------|
| Replace CLI with MCP universally | Gemini | MCP support added as `adapter_type: mcp`, but CLI remains first-class for existing agents (Claude Code, Codex). Mandating MCP would break compatibility with currently supported agents. |
| Full Temporal migration in design | Tinker | WorkflowEngine interface seam preserved. Temporal is an implementation option, not a design requirement. Internal state machine with SQLite is sufficient for the designed system. |
| Firecracker as default sandbox | Sakana | gVisor adopted as default hardened runtime. Firecracker remains available for maximum security. Docker retained for development environments only. |
| CQRS for all artifacts | Qwen-0 | Object storage for large artifacts adopted, but full CQRS pattern adds unnecessary complexity. Metadata in DB, payload in Object Storage is sufficient. |
| eBPF-based escape detection | Mistral | Valuable but requires kernel-level capabilities not available in all deployment environments. Listed as optional hardening, not core design. |
| ML-based cost prediction | Mistral | Historical averaging sufficient for cost estimation. ML models add operational complexity without proportional accuracy gain for predictable workloads. |
| Open protocol publication | Minimax | Aspirational but premature. Focus on internal coherence first. Protocol publication is a future consideration, not a design constraint. |

#### Removed Findings (Explicitly Out of Scope)

| Finding | Source | Reason for Removal |
|---------|---------|-------------------|
| Memory entity as aggregate | Kimi | Ephemeral state handled by AgentSession and workspace. No separate Memory aggregate needed. |
| Docker as default runtime | Kimi/Xiaomi | Docker default replaced with gVisor. Docker available only in dev mode. |
| `network_mode: host` | All | Removed entirely. All outbound traffic through egress proxy. |
| ApprovalGate complexity | GLM | Binary approval sufficient. Escalation chains handled by workflow-level logic, not approval entity. |

### New Architectural Decisions (Round 3)

1. **AgentSession as Core Runtime Entity**: AgentSession replaces AgentInvocation as the primary runtime execution entity. Tracks full lifecycle including partial progress, tool calls, checkpoints, and feedback iterations. Each Session owns a workspace clone.

2. **Three-Layer Agent Runtime**: PromptCompiler (renders structured prompts from contracts) → AgentExecutor (manages process lifecycle, sidecar proxy) → OutputParser (extracts artifacts via ParserRegistry strategy chain).

3. **Workspace Observation as Artifact Source**: Artifacts are derived from workspace state (`git diff`, `git status`, file reads) rather than agent stdout. Agent output is treated as untrusted narrative; the filesystem is ground truth.

4. **Mandatory Egress Proxy**: All agent network traffic routes through Amir's egress proxy. Provides domain allowlisting, mTLS, token counting, PII/secret scrubbing, and API key cost attribution. `network_mode: host` eliminated.

5. **Hierarchical Cost Gate**: Four-level enforcement: per-invocation → per-team-hourly → per-tenant-daily → per-org-monthly. Reservation protocol ensures budget consistency across concurrent tasks.

6. **ParserRegistry with Versioned Strategies**: Deterministic extraction pipeline with fallback chain. Each strategy is independently versioned, testable, and replaceable. LLM-based coercion available as last-resort fallback.

7. **AgentScorecard for Routing**: Historical performance metrics (success rate, cost, latency, failure patterns) feed the capability scoring algorithm. Agents with poor track records are automatically downweighted.

8. **Git-Native Compensation**: Workflow compensation uses Git operations: `git revert`, branch delete, PR close. Commit signing provides audit trail for compensation actions.

9. **Idempotency by Default**: All mutable operations require idempotency keys. Stored with operation outcome to prevent duplicate side effects on retry.

10. **Semantic Validation as Core Concern**: Pluggable validator architecture with timeout and budget. Structural validation alone is insufficient for LLM-produced artifacts. Validators run tests, check quality criteria, and verify behavioral contracts.

---

## Audit Feedback Disposition

### Fully Accepted Findings

| Finding | Source | Implementation |
|---------|--------|---------------|
| Two-Track Entity Lifecycle | Round 1 | Configuration: GitOps (Draft→Published→Deprecated) / Runtime: Simple state machines |
| Bounded Context Separation | Round 1 | Five contexts: Configuration, Execution, Workflow, Security, Observability |
| DomainEvent Envelope | Round 1 | Standard envelope with correlation_id, causation_id for tracing |
| Workflow Engine Interface | Round 1 | WorkflowEngine interface with configurable persistence |
| Contract Versioning | Round 1 | SemVer with N-1 compatibility enforced |
| Agent Session Model | Round 3 | AgentSession aggregate with full state machine and checkpointing |
| Validation Feedback Loop | Round 3 | ValidationResult → FeedbackArtifact → ReinvocationPolicy |
| Multi-Dimensional Capability Scoring | Round 3 | Weighted scoring with historical metrics |
| Runtime Cost Gate | Round 3 | Hierarchical enforcement with reservation protocol |
| Workspace Observation | Round 3 | Artifacts derived from git diff, not agent claims |
| ParserRegistry | Round 3 | Versioned strategy chain for output extraction |
| Mandatory Egress Proxy | Round 3 | All traffic through Amir proxy; host mode eliminated |
| Idempotency Keys | Round 3 | All mutable operations require idempotency keys |
| Git-Native Compensation | Round 3 | Revert, branch delete, PR close as compensation actions |
| Circuit Breaker | Round 3 | Per-agent failure counting with quarantine |
| Agent Scorecard | Round 3 | Historical metrics feed capability scoring |

### Partially Accepted Findings

| Finding | Source | Partial Implementation |
|---------|--------|---------------------|
| OPA Policy Engine | Round 3 | Pluggable extension; static rules as default |
| Multi-Turn Agents | Round 3 | AgentConversation entity; single-turn default |
| Event Outbox Pattern | Round 3 | Outbox with delivery semantics by category |
| Computable Contracts | Round 3 | EvaluationTask contract type for agent validation |
| Artifact Lineage | Round 3 | derived_from/supersedes fields on Artifact |

### Rejected Findings

| Finding | Source | Reason |
|---------|--------|--------|
| Replace CLI with MCP | Gemini | CLI remains first-class; MCP added as adapter option |
| Full Temporal migration | Tinker | Interface seam preserved; Temporal is implementation option |
| Firecracker as default | Sakana | gVisor adopted as default; Firecracker for max security |
| CQRS for all artifacts | Qwen-0 | Metadata-in-DB + payload-in-ObjectStorage sufficient |
| eBPF escape detection | Mistral | Optional hardening, not core design |
| ML cost prediction | Mistral | Historical averaging sufficient |
| Open protocol publication | Minimax | Premature; focus on internal coherence |

---

## Specification Status

**Status:** `COMPLETE_AND_CONSISTENT`

All core architectural concerns are designed:

- ✅ **Bounded Context Separation**: Clean ownership boundaries defined
- ✅ **Aggregate Roots**: Each entity has exactly one owner
- ✅ **Agent Session Model**: Durable execution with checkpointing and feedback
- ✅ **Validation Feedback Loop**: Structured error → correction → retry with budget
- ✅ **Workspace Observation**: Artifacts derived from filesystem, not agent claims
- ✅ **ParserRegistry**: Versioned extraction strategy chain
- ✅ **Capability Scoring**: Multi-dimensional weighted algorithm with historical metrics
- ✅ **Cost Gate**: Hierarchical enforcement with reservation protocol
- ✅ **Durable Workflow**: Saga pattern with git-native compensation
- ✅ **Mandatory Egress Proxy**: All traffic through Amir proxy
- ✅ **Idempotency**: All mutable operations keyed
- ✅ **Circuit Breaker**: Per-agent failure quarantine
- ✅ **Semantic Validation**: Pluggable validators with budget
- ✅ **Event Model**: Consistent DomainEvent envelope with full retention policy
- ✅ **Contract Versioning**: SemVer with N-1 compatibility
- ✅ **Agent Scorecard**: Historical performance metrics for routing

---

## Quick Links

- [Vision & Goals](vision.md)
- [Architecture Principles](principles.md)
- [Bounded Contexts](context.md)
- [Domain Model](model.md)
- [Agent Runtime](agent.md)
- [Workflow Engine](workflow.md)
- [Security Model](security.md)
- [Observability](observability.md)
- [Persistence](persistence.md)
- [Event Model](event.md)
- [Evolution Roadmap](roadmap.md)
