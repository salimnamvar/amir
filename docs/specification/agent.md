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

AgentSession replaces the simple AgentInvocation model. It tracks the full lifecycle of agent execution including partial progress, tool calls, checkpoints, and feedback iterations.

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

## AgentAdapter Interface

```python
class AgentAdapter(ABC):
    """Abstract interface for agent execution."""
    
    @abstractmethod
    async def start_session(self, session: AgentSession) -> None:
        """Start agent execution session. Non-blocking."""
        pass
    
    @abstractmethod
    async def get_result(self, session_id: UUID, timeout: float = 30.0) -> RawAgentOutput:
        """Get execution result. Returns raw output or error."""
        pass
    
    @abstractmethod
    async def cancel(self, session_id: UUID) -> None:
        """Cancel running session. Best-effort."""
        pass
    
    @abstractmethod
    async def inject_feedback(self, session_id: UUID, feedback: FeedbackArtifact) -> None:
        """Inject corrective feedback into running agent."""
        pass
    
    @abstractmethod
    def supports_contract(self, contract_type: str, version: str) -> bool:
        """Check if adapter supports given contract."""
        pass
    
    @abstractmethod
    def supports_output_mode(self, mode: OutputMode) -> bool:
        """Check if adapter supports output mode."""
        pass
```

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

```
1. Structured Output Mode (JSON schema enforced by agent)
   └─ Agent returns JSON conforming to schema
   └─ Confidence: 0.95

2. Tool Call Interception (submit_artifact tool)
   └─ Agent calls submit_artifact(json_payload) tool
   └─ Intercepted before reaching filesystem
   └─ Confidence: 0.90

3. Markdown Block Extraction
   └─ Strip ```json...``` or ```yaml...``` code blocks
   └─ Parse first valid block
   └─ Confidence: 0.70

4. Workspace Observation (ground truth)
   └─ Derive artifact from `git diff`, `git status`, file reads
   └─ Ignore agent stdout narrative
   └─ Confidence: 0.85 (for code changes)

5. LLM Coercion (last resort)
   └─ Cheap model (Llama-3-8B) reformatting
   └─ Takes raw text + target schema
   └─ Outputs structured JSON
   └─ Confidence: 0.60

6. Reject
   └─ All strategies failed
   └─ Emit Artifact.Rejected
   └─ Trigger FeedbackLoop
```

### OutputMode Negotiation

Agents declare supported output modes. Adapter selects best available:

```yaml
OutputMode:
  enum:
    - json_schema       # Agent enforces JSON Schema compliance
    - tool_use          # Agent uses submit_artifact tool
    - markdown_yaml     # Agent wraps output in markdown code blocks
    - free_text         # Unstructured text (requires coercion)
```

## Workspace Observation Layer

The most critical reliability mechanism. Artifacts are derived from workspace state, not agent claims.

### Principle

Agent output is treated as untrusted narrative. The filesystem is ground truth.

### Observation Process

```
1. Before Agent Execution:
   - Record workspace state (git HEAD, file listing)
   - Create observation baseline

2. After Agent Execution:
   - Run `git diff <baseline>..<current>`
   - Run `git status`
   - Read modified files
   - Derive CodeChangeArtifact from diff
   - Compare agent's claimed changes with observed changes

3. Artifact Construction:
   - files[] populated from git diff (not agent output)
   - changes populated from git log
   - tests populated from file listing + test runner output
   - commit_message from agent output (if available)
```

### Synthetic Artifact Generation

When agent output parsing fails completely:

```python
def synthesize_artifact(workspace: Workspace, baseline: str) -> CodeChangeArtifact:
    """Construct artifact from workspace observation."""
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
        provenance={
            "observation_method": "workspace_diff",
            "baseline_commit": baseline,
            "current_commit": workspace.current_head()
        }
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
    
    total_score = sum(scores[dim] * weights[dim] for dim in scores)
    
    # Check circuit breaker
    if history and history.circuit_breaker.state == "open":
        total_score *= 0.1  # Heavily penalize quarantined agents
    
    return MatchingDecision(
        agent_id=agent.id,
        score=total_score,
        dimension_scores=scores,
        explanation=generate_explanation(scores, weights),
        projected_cost=estimate_cost(agent, task),
        projected_latency=estimate_latency(agent, task, history)
    )
```

### MatchingDecision Artifact

```yaml
MatchingDecision:
  type: object
  required: [agent_id, score, dimension_scores]
  properties:
    agent_id:
      type: string
      format: uuid
    score:
      type: number
      minimum: 0.0
      maximum: 1.0
    dimension_scores:
      type: object
      additionalProperties:
        type: number
    explanation:
      type: string
      description: "Human-readable explanation of scoring"
    projected_cost:
      type: number
    projected_latency:
      type: number
    rejection_reasons:
      type: array
      items:
        type: string
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

```
Per-Invocation Budget
    ↓ (if exceeded → kill process)
Per-Team Hourly Budget
    ↓ (if exceeded → reject new invocations)
Per-Tenant Daily Budget
    ↓ (if exceeded → pause all non-critical tasks)
Per-Org Monthly Budget
    ↓ (if exceeded → system alert, require admin override)
```

### Reservation Protocol

```
1. Pre-flight: Estimate cost for task
2. Reserve: Deduct estimate from team/hourly budget
3. Execute: Track actual consumption via sidecar
4. Commit: On completion, adjust reservation to actual
5. Release: On failure, release unspent reservation
```

### Cost Enforcement

```python
class CostEnforcer:
    def check_and_enforce(self, session: AgentSession, token_count: int, usd_cost: float) -> None:
        # Per-invocation check
        if token_count > session.resource_limits.max_tokens * 0.95:
            raise CostLimitExceeded("Token limit threshold reached")
        if usd_cost > session.resource_limits.max_usd * 0.95:
            raise CostLimitExceeded("USD limit threshold reached")
        
        # Team hourly check
        team_usage = get_team_hourly_usage(session.team_id)
        if team_usage.usd + usd_cost > session.team_budget.hourly_usd:
            raise TeamBudgetExceeded("Team hourly budget exceeded")
        
        # Record consumption
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
Output mode negotiation per agent type. Fallback chain from structured to coerced. Adapter selects best available mode.
