# Agent Runtime

## Architecture Overview

The Agent Runtime executes external CLI agents in isolated environments, extracts structured artifacts from their output, and provides intelligent recovery when agents produce invalid results. The core insight: CLI agents are unreliable, non-deterministic programs that produce unstructured output. Amir must treat agent output as untrusted narrative and derive ground truth from workspace observation.

```
┌──────────────────────────────────────────────────────────────────┐
│                        Agent Runtime                              │
│                                                                    │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────────┐ │
│  │  Prompt     │  │    Agent      │  │    Output                │ │
│  │  Compiler   │→ │   Executor    │→ │    Parser                │ │
│  │             │  │  (+ Sidecar)  │  │  (ParserRegistry)        │ │
│  └─────────────┘  └──────────────┘  └──────────────────────────┘ │
│        ↑                  ↑                      ↓                  │
│  Contract + Role    Sandbox + Egress     ValidationResult         │
│  + Agent Def        Proxy                + FeedbackArtifact       │
└──────────────────────────────────────────────────────────────────┘
```

### Three-Layer Runtime

| Layer | Responsibility | Inputs | Outputs |
|-------|---------------|--------|---------|
| **PromptCompiler** | Renders structured prompts from contracts, roles, agent config, and workspace context | Task contract, Role definition, AgentDefinition, Workspace snapshot | `CompiledPrompt` artifact (versioned, stored, reproducible) |
| **AgentExecutor** | Manages process lifecycle, sidecar proxy, token counting, cancellation | CompiledPrompt, SandboxConfig, ResourceLimits | Raw agent output (stdout + stderr + tool calls) |
| **OutputParser** | Extracts structured artifacts via strategy chain | Raw output, expected contract type, ParserRegistry | `ValidationResult` or `FeedbackArtifact` |

## AgentSession as Core Runtime Entity

**Execution-first design:** AgentSession is the central durable aggregate of the runtime. AgentInvocation is an immutable request DTO that *creates* a session; it is not an alternate source of truth. Cost, validation, workspace observation, checkpoints, and compensation hooks all hang off the session.

AgentSession tracks the full lifecycle of agent execution including partial progress, tool calls, interactive prompts, checkpoints, and feedback iterations.

### AgentSession State Machine

```
Pending → Starting → Running → WaitingForInput
    ↓         ↓         ↓            ↓
    ↓         ↓    ProducingArtifact  ↓
    ↓         ↓         ↓            ↓
    ↓         ↓      Validating      ↓
    ↓         ↓      ↓       ↓       ↓
    ↓         ↓  Succeeded  Failed   ↓
    ↓         ↓      ↓       ↓       ↓
    ↓         ↓      ↓    FeedbackLoop
    ↓         ↓      ↓       ↓
    ↓         ↓      ↓  Correcting → Running (retry)
    ↓         ↓      ↓       ↓
    ↓         ↓      ↓  Escalated (different agent/human)
    ↓         ↓      ↓
    ↓    TimedOut  Cancelled
    ↓
 Compensating → Compensated
```

### AgentSession Aggregate

```
AgentSession (Aggregate Root)
├── session_id: UUID (idempotency key)
├── task_id: UUID
├── agent_definition_id: UUID
├── attempt_number: int
├── previous_session_id: UUID | None (for feedback chain)
├── status: SessionStatus
├── workspace_id: UUID
├── sandbox_id: UUID
├── compiled_prompt_id: UUID
├── checkpoints: list[Checkpoint]
├── tool_calls: list[ToolCall]
├── partial_outputs: list[PartialOutput]
├── validation_result: ValidationResult | None
├── feedback_artifact: FeedbackArtifact | None
├── resource_usage: ResourceUsage
├── cost_record: CostRecord
└── replay_metadata: ReplayMetadata
```

### Checkpoint

Every significant state change is recorded as an immutable checkpoint:

```python
class Checkpoint(BaseModel):
    checkpoint_id: UUID
    session_id: UUID
    state: SessionStatus
    timestamp: datetime
    payload: dict[str, Any]  # State-specific data
    workspace_snapshot: str  # Git commit hash at this point
```

### ToolCall

Tracks agent tool usage for debugging and replay:

```python
class ToolCall(BaseModel):
    tool_call_id: UUID
    session_id: UUID
    tool_name: str
    tool_input: dict
    tool_output: dict | None
    started_at: datetime
    completed_at: datetime | None
    status: str  # running | completed | failed
```

### ReplayMetadata

Enables exact reproduction of agent execution:

```python
class ReplayMetadata(BaseModel):
    model_identifier: str
    prompt_hash: str  # SHA256 of compiled prompt
    full_prompt: str
    seed: int | None
    tool_calls: list[ToolCall]
    sandbox_profile_hash: str
    agent_version: str
```

## Adapter / Runtime Boundary

CLI agents are unreliable: they may hang on interactive prompts, rewrite history, emit free-form text, or lose session state. The Adapter is the **only** process that speaks agent-specific protocols; the control plane speaks only AgentSession contracts.

### Responsibilities Split

| Concern | Owner | Notes |
|---------|-------|-------|
| Prompt rendering | PromptCompiler | Produces versioned CompiledPrompt |
| Process lifecycle, PTY, signals | AgentAdapter + AgentExecutor | Agent-specific |
| Interactive prompts | AgentAdapter | Auto-response rules or escalate to `waiting_for_input` |
| Feedback re-injection | AgentAdapter | Compiles FeedbackArtifact into next turn / stdin |
| Token metering & kill | Sidecar + Egress proxy | Hard ceilings from session.resource_limits |
| Artifact extraction | OutputParser + Workspace Observation | Control plane owns strategy |
| Session continuity | AgentSession checkpoints | Adapter may map native agent session IDs |
| Replay | ReplayMetadata + CompiledPrompt | Adapter records raw I/O under session_id |

### AgentAdapter Interface

```python
class AgentAdapter(ABC):
    """Boundary between Amir runtime and an external agent process/API."""

    @abstractmethod
    async def start_session(self, session: AgentSession, prompt: CompiledPrompt) -> None:
        """Spawn or attach agent. Non-blocking. Must record sandbox_attestation_id."""
        pass

    @abstractmethod
    async def pump(self, session_id: UUID) -> AdapterEvent:
        """
        Drive the agent until the next control-plane event:
        - output_chunk | tool_call | needs_input | completed | failed | timed_out
        """
        pass

    @abstractmethod
    async def respond_input(self, session_id: UUID, response: str) -> None:
        """Answer an interactive prompt when status=waiting_for_input."""
        pass

    @abstractmethod
    async def inject_feedback(self, session_id: UUID, feedback: FeedbackArtifact) -> None:
        """
        For multi-turn adapters: inject corrections into the live conversation.
        For single-turn CLI: no-op; control plane starts a new session with feedback compiled in.
        """
        pass

    @abstractmethod
    async def cancel(self, session_id: UUID) -> None:
        """Cancel running session. Best-effort SIGTERM then SIGKILL."""
        pass

    @abstractmethod
    async def get_raw_output(self, session_id: UUID) -> RawAgentOutput:
        """Return captured stdout/stderr/tool stream for OutputParser."""
        pass

    @abstractmethod
    def supports_contract(self, contract_type: str, version: str) -> bool:
        pass

    @abstractmethod
    def supports_output_mode(self, mode: OutputMode) -> bool:
        pass

    @abstractmethod
    def map_native_session(self, session_id: UUID) -> str | None:
        """Optional native agent session/conversation id for continuity."""
        pass
```

### Interactive Prompt Protocol

When a CLI agent blocks on stdin (confirmations, choices, clarifications):

1. Adapter detects prompt pattern → emits `needs_input` → session status `waiting_for_input`.
2. Control plane evaluates **auto-response rules** (role/task scoped, deny-by-default for destructive ops).
3. If a rule matches → `respond_input` immediately.
4. If no rule → escalate per task policy (timeout, human approval, or fail).
5. Secrets are never auto-answered into agent stdin; they flow only via SecretBinding tmpfs / proxy.

### Session Continuity and Replay

- Each Amir AgentSession has its own workspace and sandbox.
- Adapters that support native multi-turn sessions may map `session_id → native_id` for in-attempt continuity only.
- Retries always create a **new** AgentSession (and workspace); feedback is compiled into a new CompiledPrompt, not mutated into the prior prompt.
- Replay uses CompiledPrompt + ReplayMetadata + recorded tool_calls; adapters must not depend on unreproducible host state.

## PromptCompiler

The PromptCompiler is Amir's interface to LLMs. It takes structured contracts and renders them into prompts that agents can understand.

### CompiledPrompt Artifact

```yaml
CompiledPrompt:
  prompt_id: UUID
  version: str  # SemVer
  template_hash: str  # SHA256 of template + inputs
  system_prompt: str
  user_prompt: str
  output_contract:
    type: str
    version: str
    json_schema: str  # Embedded schema for structured output
  tools_allowed: list[str]
  context_budget: int  # Max tokens for context
  metadata:
    role_name: str
    task_id: str
    agent_definition_id: str
```

### Prompt Compilation Process

```
1. Load RoleDefinition (responsibility, quality_criteria, allowed_actions)
2. Load TaskContract (objective, inputs, expected_outputs, constraints)
3. Load AgentDefinition (adapter_type, capabilities, output_mode)
4. Load WorkspaceSnapshot (repo state, file listing, relevant diffs)
5. Load previous FeedbackArtifact (if retry)
6. Render template with all inputs
7. Validate against context budget
8. Store CompiledPrompt artifact
9. Return for AgentExecutor
```

## OutputParser and ParserRegistry

The ParserRegistry manages versioned extraction strategies. Each strategy is independently testable and replaceable.

### ParserRegistry Interface

```python
class ParserRegistry(ABC):
    """Registry of output extraction strategies."""
    
    @abstractmethod
    def get_parser(self, agent_adapter_type: str, output_mode: OutputMode) -> OutputParser:
        """Get appropriate parser for agent type and output mode."""
        pass
    
    @abstractmethod
    def register_parser(self, agent_adapter_type: str, output_mode: OutputMode, parser: OutputParser) -> None:
        """Register a new parser strategy."""
        pass
```

### OutputParser Interface

```python
class OutputParser(ABC):
    """Single extraction strategy."""
    
    @abstractmethod
    def parse(self, raw_output: RawAgentOutput, expected_contract: ContractType) -> ParseResult:
        """Attempt to extract structured artifact from raw output."""
        pass
    
    @abstractmethod
    def can_handle(self, raw_output: RawAgentOutput) -> float:
        """Return confidence score (0.0-1.0) that this parser can handle the output."""
        pass
```

### Strategy Chain (Fallback Order)

Parser strategy is a **state machine owned by the control plane**, never by the agent:

```
1. Structured Output Mode (JSON schema enforced by agent)
   └─ Agent returns JSON conforming to schema
   └─ Confidence: 0.95

2. Tool Call Interception (submit_artifact tool)
   └─ Agent calls submit_artifact(json_payload) tool
   └─ Intercepted before reaching filesystem
   └─ Confidence: 0.90

3. Markdown Block Extraction
   └─ Strip fenced json/yaml code blocks
   └─ Parse first valid block
   └─ Confidence: 0.70

4. Workspace Observation (ground truth for code/filesystem work)
   └─ Derive artifact from git diff / tree hash / file reads
   └─ Ignore agent stdout narrative
   └─ Confidence: 0.85 (for code changes)

5. LLM Coercion (last resort, budgeted)
   └─ Cheap model reformatting within coercion budget (default $0.05, timeout 30s)
   └─ Takes raw text + target schema → structured JSON
   └─ Confidence: 0.60
   └─ Coercion cost billed to orchestration_cost_usd

6. Reject
   └─ All strategies failed
   └─ Emit Artifact.Rejected + ValidationResult
   └─ Trigger FeedbackLoop
```

### OutputMode Negotiation

Agents declare supported output modes. Control plane selects best available. **`free_text` is not a control-plane mode** — unstructured stdout may still arrive, but extraction falls through the strategy chain (markdown → workspace → coercion → reject).

```yaml
OutputMode:
  enum:
    - json_schema            # Agent enforces JSON Schema compliance
    - tool_use               # Agent uses submit_artifact tool
    - markdown_yaml          # Agent wraps output in markdown code blocks
    - workspace_observation  # Prefer filesystem derivation (coding tasks)
```

## Workspace Observation Layer

The most critical reliability mechanism. Artifacts are derived from workspace state, not agent claims.

### Principle

Agent output is treated as untrusted narrative. The filesystem is ground truth.

### Observation Process

```
1. Before Agent Execution:
   - Record baseline_commit and baseline_tree_hash
   - Snapshot relevant file listing

2. After Agent Execution:
   - Prefer tree-hash / working-tree observation even if agent did not commit
   - Run git diff (committed and unstaged), git status
   - Read modified files; handle binaries as opaque blobs (hash only)
   - Ignore .git mutations by the agent (treat as policy violation)

3. Claim Reconciliation (mandatory for CodeChangeArtifact):
   - Parse agent/parser claims (if any)
   - Diff claimed_paths vs observed_paths
   - If diverge: authoritative_source = workspace; record divergence_summary
   - Emit ValidationResult.claim_reconciliation

4. Artifact Construction:
   - files[] from workspace observation (not agent claims)
   - changes summary from diff
   - tests from file listing + test runner when configured
   - commit_message from agent output only if present (non-authoritative)
```

### Observation Reliability Rules

| Situation | Behavior |
|-----------|----------|
| Agent edits but does not commit | Observe working tree vs baseline_tree_hash |
| Gitignored paths changed | Include if quality_criteria requires; else note in warnings |
| Binary files changed | Record path + content hash; skip textual diff |
| Agent mutates `.git` | Policy failure; session fails; no artifact acceptance |
| Claims ⊆ observation | Accept; note extra unclaimed changes if policy requires |
| Claims ⊄ observation | Reject claim paths; synthesize from observation; feedback may cite divergence |

### Synthetic Artifact Generation

When agent output parsing fails or claims diverge:

```python
def synthesize_artifact(workspace: Workspace, baseline: str) -> CodeChangeArtifact:
    """Construct artifact from workspace observation (authoritative)."""
    diff = workspace.git_diff(baseline)
    status = workspace.git_status()
    
    return CodeChangeArtifact(
        contract_type="CodeChangeArtifact",
        contract_version="1.0.0",
        content={
            "files": extract_files_from_diff(diff),
            "changes": summarize_diff(diff),
            "tests": detect_test_changes(status),
            "commit_message": extract_commit_message(workspace)
        },
        observation_method="synthesized",
        claim_reconciliation={
            "claims_match_observation": False,
            "authoritative_source": "workspace",
            "baseline_commit": baseline,
            "current_commit": workspace.current_head(),
        },
    )
```

## Validation-Failure → Re-Invocation Feedback Loop

Critical mechanism for handling agents that produce invalid artifacts.

### Behavior

```
1. AgentSession completes (or OutputParser processes raw output)
2. Contract Validator runs structural validation
3. Semantic Validators run (if configured):
   - Test execution validator
   - Quality criteria validator
   - Behavioral contract validator
4. If INVALID:
   a. ValidationResult emitted with structured error categories
   b. FeedbackGenerator creates FeedbackArtifact:
      - error_context: Detailed description of what's wrong
      - corrections: Specific suggestions for fix
      - suggested_strategy: Which parser strategy might work better
      - previous_raw_output: Agent's output for context
   c. ReinvocationPolicy evaluated:
      - max_retry_attempts: Configurable (default 3)
      - budget_remaining: Check cost budget allows retry
      - escalation_path: Same agent → different agent → human
   d. If retry allowed:
      - New AgentSession created with attempt_number + 1
      - previous_session_id linked for audit trail
      - FeedbackArtifact injected into PromptCompiler
      - Agent retries with full context
   e. If retry exhausted:
      - Task.Failed permanently emitted
      - Escalation event emitted
5. If VALID:
   - Artifact.Validated emitted
   - Task transitions toward completion
```

### ValidationResult Contract

```yaml
ValidationResult:
  type: object
  required: [valid, error_categories]
  properties:
    valid:
      type: boolean
    error_categories:
      type: array
      items:
        type: object
        required: [category, code, message]
        properties:
          category:
            type: string
            enum: [structural, semantic, policy, quality]
          code:
            type: string
            description: "Machine-readable error code"
          message:
            type: string
            description: "Human-readable error description"
          path:
            type: string
            description: "JSON path to offending field"
          severity:
            type: string
            enum: [error, warning, info]
    warnings:
      type: array
      items:
        type: string
    validation_duration_ms:
      type: integer
```

### FeedbackArtifact Contract

```yaml
FeedbackArtifact:
  type: object
  required: [error_context, attempt_number, max_attempts]
  properties:
    error_context:
      type: string
      description: "What went wrong in the previous attempt"
    corrections:
      type: array
      items:
        type: string
      description: "Specific suggestions for correction"
    suggested_strategy:
      type: string
      enum: [retry_same, retry_different_agent, apply_corrections, human_intervention]
      description: "Recommended next action"
    previous_raw_output:
      type: string
      description: "Agent's raw output for context"
    previous_artifact:
      type: object
      description: "Previous attempt's artifact (if any)"
    attempt_number:
      type: integer
      minimum: 1
    max_attempts:
      type: integer
      minimum: 1
    feedback_strategy:
      type: string
      enum: [structural_hint, semantic_hint, strategy_change, agent_change]
      description: "Type of feedback to inject"
```

## Agent Scorecard

Historical performance metrics that feed the capability scoring algorithm.

### AgentScorecard Aggregate

```
AgentScorecard (Read Model, derived from events)
├── agent_definition_id: UUID
├── total_invocations: int
├── successful_invocations: int
├── failed_invocations: int
├── success_rate: float  # 0.0-1.0
├── avg_cost_usd: float
├── avg_duration_seconds: float
├── p95_duration_seconds: float
├── avg_tokens_consumed: int
├── failure_patterns: list[FailurePattern]
├── last_10_results: list[ValidationResult]
├── circuit_breaker: CircuitBreakerState
└── last_updated: datetime
```

### FailurePattern

```yaml
FailurePattern:
  type: object
  properties:
    error_code:
      type: string
    count:
      type: integer
    last_seen:
      type: string
      format: date-time
    avg_recovery_attempts:
      type: integer
```

### CircuitBreakerState

```yaml
CircuitBreakerState:
  type: object
  properties:
    state:
      type: string
      enum: [closed, open, half_open]
    consecutive_failures:
      type: integer
    last_failure_at:
      type: string
      format: date-time
    recovery_timeout_seconds:
      type: integer
      default: 300
    half_open_max_attempts:
      type: integer
      default: 1
```

## Agent Execution Sidecar

An in-sandbox proxy that intercepts agent I/O for monitoring, cost enforcement, and cancellation.

### Sidecar Responsibilities

1. **Token Counting**: Count tokens in real-time during agent streaming
2. **Cost Enforcement**: Kill agent process when budget threshold reached
3. **Progress Monitoring**: Report partial progress to control plane
4. **Log Aggregation**: Capture and forward agent stdout/stderr
5. **Cancellation**: Forward SIGTERM/SIGKILL to agent process
6. **Tool Interception**: Capture tool calls for audit trail

### Sidecar Protocol

```
┌─────────────────────────────────────────┐
│              Sandbox                     │
│  ┌──────────┐    ┌───────────┐          │
│  │  Agent   │───▶│  Sidecar  │──────────┼──▶ Control Plane
│  │  Process │◀───│  (proxy)  │          │
│  └──────────┘    └───────────┘          │
│       ↕              ↕                  │
│  stdin/stdout    tmpfs_exchange          │
└─────────────────────────────────────────┘
```

## Capability Matching

### Multi-Dimensional Scoring Algorithm

```python
def score_agent(agent: AgentDefinition, task: Task, context: ExecutionContext, history: AgentScorecard) -> MatchingDecision:
    """Score agent capability for task with full context."""
    
    # Dimension weights (configurable per team)
    weights = context.scoring_weights or {
        "skill_match": 0.30,
        "language_match": 0.15,
        "tool_match": 0.10,
        "historical_success": 0.20,
        "cost_efficiency": 0.10,
        "latency": 0.05,
        "availability": 0.10
    }
    
    scores = {
        "skill_match": compute_skill_match(agent, task),
        "language_match": compute_language_match(agent, task),
        "tool_match": compute_tool_match(agent, task),
        "historical_success": history.success_rate if history else 0.5,
        "cost_efficiency": compute_cost_efficiency(agent, history),
        "latency": compute_latency_score(agent, history),
        "availability": check_availability(agent)
    }
    
    # Open circuit breakers are hard-filtered before score_agent is called.
    # half_open receives a soft penalty only.
    if history and history.circuit_breaker.state == "half_open":
        total_score *= 0.5

    return MatchingDecision(
        selected_agent_id=agent.id,
        score=total_score,
        dimension_scores=scores,
        explanation=generate_explanation(scores, weights),
        projected_cost_usd=estimate_cost(agent, task),
        projected_latency_seconds=estimate_latency(agent, task, history),
    )
```

### MatchingDecision Artifact

Full schema: `docs/contract/schemas/matching-decision.schema.yaml`.

```yaml
MatchingDecision:
  decision_id: UUID
  task_id: UUID
  selected_agent_id: UUID
  score: float  # 0.0-1.0
  dimension_scores: dict
  hard_filters:
    passed: bool
    rejected_agents: list[{agent_id, reason}]
  contract_negotiation:
    negotiated_version: str
    compatible: bool
    fallback_used: bool
  candidates: list[{agent_id, score, rank, eliminated_reason?}]
  explanation: str
  projected_cost_usd: float
  projected_latency_seconds: float
  scorecard_staleness_seconds: int | null
```

## Sandbox Manager

### Runtime Support

- **gVisor**: Default runtime with seccomp profile (production)
- **Docker**: Development environments only
- **Firecracker**: Maximum security (optional)

### Security Mandates

- **Non-root execution**: MUST run as UID 65534 (nobody)
- **Read-only root**: Root filesystem MUST be read-only
- **Workspace isolation**: Writable tmpfs mounted at `/workspace` only
- **Network default-deny**: All traffic through egress proxy
- **Mandatory gVisor**: Production sandboxes MUST use gVisor or Firecracker

### Resource Limits

- **CPU**: Configurable cores limit
- **Memory**: Configurable limit with hard ceiling
- **PID limit**: Maximum processes enforceable
- **Timeout**: Hard execution timeout with graceful shutdown

## Cost Control

### Hierarchical Cost Gate

Cost ceilings are **structurally required** on Task and AgentSession (`anyOf` max_tokens / max_usd). Empty budgets are invalid by construction.

```
Per-Invocation Budget
    ↓ (if exceeded → kill process via sidecar / egress RST)
Per-Team Hourly Budget
    ↓ (if exceeded → reject NEW sessions AND signal cancel on IN-FLIGHT team sessions at soft→hard)
Per-Tenant Daily Budget
    ↓ (if exceeded → pause non-critical; cancel in-flight when hard threshold hit)
Per-Org Monthly Budget
    ↓ (if exceeded → system alert; require admin override for new work; cancel non-critical in-flight)
```

### In-Flight vs New Work on Higher-Level Breach

| Scope | Soft threshold (default 80%) | Hard threshold (default 100%) |
|-------|------------------------------|--------------------------------|
| Invocation | Warn / throttle streaming | Kill agent process |
| Team hourly | Reject new assignments | Cancel in-flight team sessions (graceful → force) |
| Tenant daily | Pause non-critical new work | Cancel non-critical in-flight; critical requires override |
| Org monthly | Alert + freeze non-essential | Same as tenant hard + admin page |

Higher-level breach **does** stop in-flight work at hard threshold — not only new assignment. Cancellation emits `Cost.BudgetExceeded` with `scope` and `action=cancel_inflight`.

### Reservation Protocol

```
1. Pre-flight: Estimate cost (prefer p95 historical; apply reservation_buffer_pct, default 10%)
2. Reserve: Deduct estimate+buffer from team/tenant budgets
3. Execute: Track actual via sidecar + egress token counting
4. Commit: On completion, adjust reservation to actual
5. Release: On failure/cancel, release unspent reservation
```

### Cost Enforcement

```python
class CostEnforcer:
    def check_and_enforce(self, session: AgentSession, token_count: int, usd_cost: float) -> None:
        limits = session.resource_limits
        if limits.max_tokens and token_count > limits.max_tokens * 0.95:
            raise CostLimitExceeded("Token limit threshold reached")
        if limits.max_usd is not None and usd_cost > limits.max_usd * 0.95:
            raise CostLimitExceeded("USD limit threshold reached")

        team_usage = get_team_hourly_usage(session.team_id)
        if team_usage.at_hard_limit(usd_cost):
            cancel_inflight_sessions(team_id=session.team_id, reason="team_hourly_hard")
            raise TeamBudgetExceeded("Team hourly budget hard limit")

        emit_cost_event(session.id, token_count, usd_cost)
```

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| CLI output parsing | CRITICAL | ParserRegistry with strategy chain + workspace observation |
| Agent produces invalid output | HIGH | Validation feedback loop with budgeted retry |
| Sandbox escape | CRITICAL | Mandatory gVisor/Firecracker, non-root, read-only root |
| Cost explosion | HIGH | Hierarchical cost gate with reservation protocol |
| Agent circuit breaker | MEDIUM | Per-agent failure counting with quarantine |
| Workflow durability | HIGH | SQLite persistence on each state transition + checkpointing |
| Prompt injection | HIGH | Structured contract prompts, no free-form strings |
| Agent impersonation | MEDIUM | AgentScorecard with historical metrics, capability verification |

---

## Addressing Audit Concerns

### CLI Parsing Reliability (All 17 Audits)
ParserRegistry with 5-strategy fallback chain. Workspace observation as ground truth. LLM coercion as last resort. No single point of failure in extraction.

### Agent Non-Determinism (All 17 Audits)
AgentSession with full checkpointing and replay metadata. Every execution is reproducible. Circuit breaker prevents cascading failures.

### Feedback Loop (All 17 Audits)
Structured ValidationResult with error categories. Budgeted retry with escalation path. FeedbackArtifact provides actionable corrections, not just error messages.

### Capability Routing (All 17 Audits)
Multi-dimensional scoring with historical AgentScorecard. Circuit breaker penalizes failing agents. Configurable weights per team.

### Cost Enforcement (All 17 Audits)
Hierarchical cost gate with reservation protocol. Pre-flight estimation. Sidecar proxy for real-time enforcement. No advisory-only budgets.

### Workspace Observation (Tinker/Qwen)
Artifacts derived from git diff, not agent claims. Synthetic artifact generation when parsing fails completely.

### Structured Output (Gemini/Xiaomi)
Output mode negotiation per agent type. Fallback chain from structured to workspace to coerced. Control plane owns extraction; free_text is not a control-plane mode.

### Adapter Boundary (Round 4)
Explicit pump/respond_input/inject_feedback contract. Interactive prompts, session continuity, and replay are first-class adapter responsibilities.

### Claim Reconciliation (Round 4)
Parser claims are always compared to workspace observation for code artifacts; workspace wins on divergence.
