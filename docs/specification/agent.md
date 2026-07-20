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
Pending → Starting → Running ⇄ WaitingForInput
              ↓         ↓
              ↓    ProducingArtifact
              ↓         ↓
              ↓      Validating
              ↓      ↓        ↓
         TimedOut  Succeeded  Failed
              ↓                 ↓
          Cancelled ←── CostLease revoke (budget_exceeded)
```

**Retry model (normative):** validation failure with retry allowed does **not** re-enter `running` on this session. Task creates a **new AgentSession** (attempt_number+1) + **new Workspace**. There is no session status `Correcting` or `Escalated` — escalation is `Task.status=escalated` + `EscalationSignal`.

**Note:** Compensation is owned by `WorkflowInstance`, not `AgentSession`. CostLease revocation transitions the session to `cancelled` with `last_failure_category=budget_exceeded`. Session create is atomic with workspace create (`workspace_id` required).

### AgentSession Aggregate (Lean Document)

> **Contract:** [`docs/contract/schemas/execution/agent-session.schema.yaml`](../contract/schemas/execution/agent-session.schema.yaml)

AgentSession is the central durable aggregate, **not** a dump of high-frequency telemetry. Full `ValidationResult` and `Feedback` objects are **never** embedded — IDs only. Checkpoints and tool calls keep ring-buffer **IDs** only (max 20 / 50).

| Concern | On session document | Authoritative store |
|---------|---------------------|---------------------|
| Identity, status, limits, refs | Yes | Session row / agent-session contract |
| `workspace_id` | **Required** | Workspace row (1:1) |
| Checkpoints (full history) | `recent_checkpoint_ids` only | [`execution/checkpoint.schema.yaml`](../contract/schemas/execution/checkpoint.schema.yaml) + SQL |
| Tool calls (full history) | `recent_tool_call_ids` only | [`execution/tool-call.schema.yaml`](../contract/schemas/execution/tool-call.schema.yaml) + stream |
| Live meters | Latest snapshot | [`cost/cost-record.schema.yaml`](../contract/schemas/cost/cost-record.schema.yaml) |
| Validation / feedback | `validation_result_id` / `feedback_artifact_id` only | validation-result / feedback contracts |
| Cost hard kill | `cost_lease_id` (required while running) | [`cost/cost-lease.schema.yaml`](../contract/schemas/cost/cost-lease.schema.yaml) |

### Checkpoint

Every significant state change is recorded as an immutable checkpoint:


> **Contract:** [`docs/contract/schemas/execution/checkpoint.schema.yaml`](../contract/schemas/execution/checkpoint.schema.yaml)


### ToolCall

Tracks agent tool usage for debugging and replay:


> **Contract:** [`docs/contract/schemas/execution/tool-call.schema.yaml`](../contract/schemas/execution/tool-call.schema.yaml)


### ReplayMetadata

Enables exact reproduction of agent execution:


> **Contract:** [`docs/contract/schemas/execution/replay-metadata.schema.yaml`](../contract/schemas/execution/replay-metadata.schema.yaml)


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

> **Interface contract:** [`docs/contract/interfaces/agent-adapter.yaml`](../contract/interfaces/agent-adapter.yaml)

### Session Continuity Protocol

CLI agents (Claude Code, Codex, etc.) hold native session state outside Amir.

1. **`start()`** returns `handle = { session_id, native_id?, adapter_type }`. `native_id` maps Amir `session_id` to the agent-native conversation/session file.
2. **Between `pump()` calls** continuity lives in the agent process/native session — the control plane does not re-send full history.
3. **Lost connection**: `pump` emits `connection_lost` or `health()` → unhealthy → Adapter reconnects using `native_id` within `reconnect_timeout_seconds` (default 30s).
4. **On reconnect**: reconstruct from full `ReplayMetadata` (expanded from invocation seed at session start) + last checkpoint + `tool_call_stream_ref`.
5. **On reconnect failure**: session → `failed` with `last_failure_category=infrastructure`; set `replay_status=replay_incomplete` if history is incomplete; operator may re-run from last checkpoint.

### Interactive Prompt Protocol

When a CLI agent blocks on stdin (confirmations, choices, clarifications):

1. Adapter detects prompt pattern → emits `needs_input` → session status `waiting_for_input`.
2. Control plane evaluates **auto-response rules** (role/task scoped, deny-by-default for destructive ops).
3. If a rule matches → `respond_input` immediately.
4. If `pending_input.timeout_seconds` elapses without input: apply `on_timeout` policy
   (`escalate` default → emit `EscalationSignal` with `assigned_to`, set `input_timeout_reason`;
   or `cancel` / `fail`).
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


> **Contract:** [`docs/contract/schemas/execution/compiled-prompt.schema.yaml`](../contract/schemas/execution/compiled-prompt.schema.yaml)


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


> **Interface contract:** [`docs/contract/interfaces/parser-registry.yaml`](../contract/interfaces/parser-registry.yaml)


### OutputParser Interface


> **Interface contract:** [`docs/contract/interfaces/parser-registry.yaml`](../contract/interfaces/parser-registry.yaml)


### Strategy Chain (Fallback Order)

Parser strategy is a **state machine owned by the control plane**, never by the agent.

**Default chain (4 strategies)** — `llm_coercion` is **not** included. Workspace observation is preferred ground truth for code/filesystem work.

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

5. Reject
   └─ Default chain exhausted
   └─ Emit Artifact.Rejected + ValidationResult
   └─ Trigger FeedbackLoop
```

### llm_coercion Escape Hatch (not default)

`llm_coercion` undermines “workspace is ground truth” if used casually. It is therefore **opt-in only**:

| Requirement | Rule |
|-------------|------|
| Chain membership | Not in default ParserRegistry chain |
| Authorization | Requires human `Approval` (`coercion_approval_id` on Artifact) |
| Observation method | MUST set `observation_method=synthesized` |
| Scrutiny | Higher audit retention; billed to `orchestration_cost_usd` |
| Budget | Hard cap (default $0.05, timeout 30s); counts against validation_budget when used in repair |
| Prefer | Always prefer workspace_observation over coercion when filesystem evidence exists |

### OutputMode Negotiation

Agents declare supported output modes. Control plane selects best available. **`free_text` is not a control-plane mode** — unstructured stdout may still arrive, but extraction falls through the default strategy chain (markdown → workspace → reject). Coercion is never automatic.


> **Contract:** [`docs/contract/schemas/execution/agent.schema.yaml#supported_output_modes`](../contract/schemas/execution/agent.schema.yaml#supported_output_modes)


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

3. Mandatory auto-commit (before cleanup):
   - AgentExecutor MUST ensure a durable commit exists for any working-tree changes
   - If the agent produced no commit, synthesize one from the diff and update durable_effects.head_commit
   - Append durable_effects.effects_log incrementally as effects are created (not only at end)
   - Local commit + durable_effects update SHOULD be atomic with observation record
   - If push fails after local commit: set Workspace.status=`auto_commit_failed`, record `auto_commit.error`;
     do NOT clean ephemeral workspace until remediated; emit Workspace.AutoCommitFailed
   - Observation without a durable commit is invalid for compensation-capable sessions

4. Claim Reconciliation (mandatory for CodeChangeArtifact):
   - Parse agent/parser claims (if any)
   - Diff claimed_paths vs observed_paths
   - If diverge: authoritative_source = workspace; record divergence_summary
   - Emit ValidationResult.claim_reconciliation (canonical; Artifact references by validation_result_id only)

5. Artifact Construction:
   - files[] from workspace observation (not agent claims)
   - changes summary from diff
   - tests from file listing + test runner when configured
   - commit_message from agent output only if present (non-authoritative)
```

### Observation Reliability Rules

| Situation | Behavior |
|-----------|----------|
| Agent edits but does not commit | Observe working tree vs baseline_tree_hash; **then auto-commit** before cleanup |
| Gitignored paths changed | Include if quality_criteria requires; else note in warnings |
| Binary files changed | Record path + content hash; skip textual diff |
| Agent mutates `.git` | Policy failure; session fails; no artifact acceptance |
| Claims ⊆ observation | Accept; note extra unclaimed changes if policy requires |
| Claims ⊄ observation | Reject claim paths; synthesize from observation; feedback may cite divergence |
| Budget kill mid-execution | Compensation uses durable_effects.effects_log already appended |

### Synthetic Artifact Generation

When agent output parsing fails or claims diverge, construct the artifact from workspace observation and attach **references** to the canonical `ValidationResult.claim_reconciliation` (do not embed a second incompatible shape):

```python
def synthesize_artifact(workspace: Workspace, baseline: str, validation: ValidationResult) -> CodeChangeArtifact:
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
        observation_method="workspace_diff",  # or synthesized only with coercion_approval_id
        validation_result_id=validation.validation_id,
        # Canonical claim_reconciliation lives on ValidationResult only
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
   a. ValidationResult emitted with structured error categories + claim_reconciliation
   b. FeedbackGenerator creates FeedbackArtifact (references validation_result_id)
   c. ReinvocationPolicy evaluated:
      - max_retry_attempts: Configurable (default 3)
      - execution budget (cost_budget) remaining for agent work
      - **validation_budget** remaining for repair-loop overhead (validators, feedback compile, optional coercion)
      - retry_on matches last_failure_category (shared vocabulary)
      - escalation_path: Same agent → different agent → human
   d. If retry allowed AND validation_budget not exhausted:
      - Prior AgentSession terminal status = failed (category from ValidationResult)
      - **New** AgentSession created with attempt_number + 1 (never re-enter prior session)
      - **New** Workspace for the attempt
      - previous_session_id linked for audit trail
      - FeedbackArtifact injected into PromptCompiler
      - Validation spend metered against validation_budget, not cost_budget
   e. If retry exhausted OR validation_budget exhausted:
      - Task.status = failed or escalated (category may be budget_exceeded for validation starvation)
      - EscalationSignal emitted
5. If VALID:
   - Artifact.Validated emitted

### Validation vs Execution Budget Partition

Repair must not be starved by (or steal from) the agent’s execution ceiling:

| Budget | Pays for | On exhaustion |
|--------|----------|---------------|
| `Task.cost_budget` / session `resource_limits` | Agent LLM tokens, tools, sandbox runtime | Cancel session; category `budget_exceeded` |
| `Task.validation_budget` | Structural/semantic validators, feedback compile, optional approved coercion | Stop repair loop; escalate; do not silently continue agent retries |

`Task.validation_budget` is **required** (same `anyOf` max_tokens/max_usd as cost_budget). Omitting it is a schema violation — there is no silent platform default that steals from execution budget.
```

### ValidationResult Contract


> **Contract:** [`docs/contract/schemas/artifact/validation-result.schema.yaml`](../contract/schemas/artifact/validation-result.schema.yaml)


### FeedbackArtifact Contract


> **Contract:** [`docs/contract/schemas/artifact/feedback.schema.yaml`](../contract/schemas/artifact/feedback.schema.yaml)


## Agent Scorecard

Historical performance metrics that feed the capability scoring algorithm.

### AgentScorecard Aggregate

> **Contracts:**
> - Scorecard: [`matching/agent-scorecard.schema.yaml`](../contract/schemas/matching/agent-scorecard.schema.yaml)
> - Circuit breaker (agent-scoped only): [`matching/circuit-breaker-state.schema.yaml`](../contract/schemas/matching/circuit-breaker-state.schema.yaml)
> - Storage: [`sql/observability.sql`](../contract/sql/observability.sql)

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
    
    total_score = sum(scores[d] * weights.get(d, 0) for d in scores)
    # Normalize weights to sum 1.0 at runtime if config drifts (see Team.scoring_weights).

    # Open circuit breakers are hard-filtered before score_agent is called.
    # half_open receives a soft penalty only.
    if history and history.circuit_breaker.state == "half_open":
        total_score *= 0.5

    # Cold-start / exploration: pure historical scoring starves new agents/versions.
    exploration_bonus = 0.0
    exploration_reason = None
    cold = is_cold_scorecard(history)  # invocations < threshold OR null/stale scorecard
    if cold:
        exploration_bonus = context.exploration_bonus or 0.15  # default boost
        exploration_reason = (
            "low_invocation_count" if history and history.total_invocations < context.exploration_min_invocations
            else "stale_scorecard" if history and is_stale(history)
            else "cold_start"
        )
        total_score = min(1.0, total_score + exploration_bonus)

    return MatchingDecision(
        selected_agent_id=agent.id,
        score=total_score,
        dimension_scores=scores,
        exploration_bonus=exploration_bonus,
        exploration_reason=exploration_reason,
        explanation=generate_explanation(scores, weights),
        projected_cost_usd=estimate_cost(agent, task),
        projected_latency_seconds=estimate_latency(agent, task, history),
    )
```

### Cold-Start Exploration

Pure historical scoring locks new agents/versions out of the routing market. Minimal explicit exploration:

| Condition | Default | Effect |
|-----------|---------|--------|
| `total_invocations < exploration_min_invocations` | 10 | Apply `exploration_bonus` (default 0.15) |
| Scorecard missing for this agent version | — | Treat as cold_start; warm-start from prior version name if available, then still apply reduced bonus until threshold |
| Scorecard age > staleness threshold | configurable | `stale_scorecard` reason + bonus |

Exploration never bypasses hard filters (circuit breaker open, missing tools, budget infeasible, etc.). Bonus is recorded on `MatchingDecision` for audit.

### MatchingDecision Artifact

> **Contract:** [`docs/contract/schemas/matching/matching-decision.schema.yaml`](../contract/schemas/matching/matching-decision.schema.yaml)

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

### Synchronous CostLease (Hard Kill Gate)

Eventual consistency from Observability → Execution is **too slow** for hierarchical hard breaches. Every in-flight session holds a **CostLease** (shared-state gate):

| Aspect | Design |
|--------|--------|
| Schema | `cost/cost-lease.schema.yaml` |
| Owner | Observability Context (lease authority) |
| Holder | Execution Context (`AgentSession.cost_lease_id`) |
| Check path | Sidecar + egress proxy on **every metering tick (≤100ms)** via `CostEnforcer.check_lease` |
| Hard kill | `status=revoked` (sole signal; no parallel cancelled flag) at `kill_threshold_pct` (default 95%) → Adapter.cancel with 5s grace → session `cancelled` + `budget_exceeded` |
| Failure mode | Lease service unavailable → **fail-closed** (`fail_closed_on_unavailable=true`): deny further metered LLM egress |
| Trust boundary | Sidecar MUST NOT write Execution DB; AgentExecutor owns session state transitions. Observability owns the lease gate. |
| Interface | [`cost-enforcer.yaml`](../contract/interfaces/cost-enforcer.yaml) + [`agent-adapter.yaml`](../contract/interfaces/agent-adapter.yaml) |

```
ExecutionContext(Task.Assigned)
  → ObservabilityContext(Cost.ReservationCreated + CostLease.Created, budget_pool=execution)
  → ExecutionContext(AgentSession.Started with cost_lease_id + workspace_id atomic)
  → each tick: sidecar CostEnforcer.check_lease (sync) + meters tokens
  → hard breach (≥ kill_threshold_pct): Observability sets status=revoked + revocation_revision
  → sidecar SIGTERM; Adapter.cancel(grace=5s) → SIGKILL; ack within sidecar_ack_deadline_ms
  → AgentExecutor: session.status=cancelled, last_failure_category=budget_exceeded
  → Workflow compensation on durable_effects; CostLease remains revoked (not released)
```

### Post-Cancel Path (budget_exceeded)

Cost-killed sessions terminate with failure category **`budget_exceeded`**.

| Policy | Behavior |
|--------|----------|
| Default `retry_on` | Does **not** include `budget_exceeded` — no automatic retry into the same wall |
| Task terminal | Failed / Cancelled with `last_failure_category=budget_exceeded` |
| Escalation | Team/tenant/org scope → emit `EscalationSignal` (`cost_limit_exceeded`) |
| Compensation | If durable effects already recorded, enter normal compensation path for the workflow step |
| Resume | Only after budget headroom restored (new reservation) and human/admin override if scope ≥ team |

### In-Flight vs New Work on Higher-Level Breach

Soft/hard percentages live on **Team.budget** (`soft_threshold_pct` default 80, `hard_threshold_pct` default 100) — not on CostLease. Cascade uses **one invocation lease per session** + `CostEnforcer.revoke_by_scope`.

| Scope | Soft threshold | Hard threshold |
|-------|----------------|----------------|
| Invocation | Warn / throttle streaming | Kill process via lease `status=revoked` |
| Team | Reject new assignments | `revoke_by_scope(team, …)` cancels in-flight |
| Tenant | Pause non-critical new work | `revoke_by_scope(tenant, …)` |
| Org | Alert + freeze non-essential | `revoke_by_scope(org, …)` + admin page |

Higher-level hard breach **does** stop in-flight work. Emits `Cost.BudgetExceeded` and EscalationSignal (`cost_limit_exceeded`) for team+.

### Reservation Protocol

```
1. Pre-flight: Estimate cost (prefer p95 historical; apply reservation_buffer_pct, default 10%)
2. Reserve: Deduct estimate+buffer from team/tenant budgets; create CostLease
3. Execute: Track actual via sidecar + egress token counting; sync lease check each tick
4. Commit: On completion, adjust reservation to actual; release lease
5. Release: On failure/cancel, release unspent reservation; release lease
```

### Cost Enforcement

```python
class CostEnforcer:
    def check_and_enforce(self, session: AgentSession, token_count: int, usd_cost: float) -> None:
        lease = get_cost_lease(session.cost_lease_id)  # synchronous shared-state gate
        if lease is None or (lease.fail_closed_on_unavailable and not lease.is_reachable()):
            raise CostLimitExceeded("Lease unavailable — fail closed")
        # status=revoked is the SOLE kill signal (no parallel cancelled flag)
        if lease.status == "revoked":
            kill_process(session)
            raise CostLimitExceeded(lease.cancellation_reason or "lease_revoked")

        limits = session.resource_limits
        threshold = lease.kill_threshold_pct / 100.0  # default 0.95
        if limits.max_tokens and token_count > limits.max_tokens * threshold:
            self.revoke_lease(lease.lease_id, "invocation_budget_exceeded")
            raise CostLimitExceeded("Token limit threshold reached")
        if limits.max_usd is not None and usd_cost > limits.max_usd * threshold:
            self.revoke_lease(lease.lease_id, "invocation_budget_exceeded")
            raise CostLimitExceeded("USD limit threshold reached")

        team_usage = get_team_hourly_usage(session.team_id)
        if team_usage.at_hard_limit(usd_cost):
            # Hierarchical cascade: revoke ALL active leases for this team
            self.revoke_by_scope("team", session.team_id, "team_budget_exceeded")
            raise TeamBudgetExceeded("Team budget hard limit")

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
ParserRegistry with **4-strategy default** chain (structured_output → tool_call_interception → markdown_block → workspace_observation). Workspace observation as ground truth. `llm_coercion` is opt-in with human approval only — not in the default chain.

### Agent Non-Determinism (All 17 Audits)
AgentSession with full checkpointing and replay metadata. Every execution is reproducible. Circuit breaker prevents cascading failures.

### Feedback Loop (All 17 Audits)
Structured ValidationResult with error categories. Budgeted retry with escalation path. FeedbackArtifact provides actionable corrections, not just error messages.

### Capability Routing (All 17 Audits)
Multi-dimensional scoring with historical AgentScorecard. Circuit breaker penalizes failing agents. Configurable weights per team.

### Cost Enforcement (All 17 Audits)
Hierarchical cost gate with reservation protocol, **synchronous CostLease** hard-kill gate, pre-flight estimation, and sidecar/egress metering. No advisory-only budgets. `budget_exceeded` is not retried by default.

### Workspace Observation (Tinker/Qwen)
Artifacts derived from git diff, not agent claims. Synthetic artifact generation when parsing fails completely.

### Structured Output (Gemini/Xiaomi)
Output mode negotiation per agent type. Fallback chain from structured to workspace to coerced. Control plane owns extraction; free_text is not a control-plane mode.

### Adapter Boundary (Round 4)
Explicit pump/respond_input/inject_feedback contract. Interactive prompts, session continuity, and replay are first-class adapter responsibilities.

### Claim Reconciliation (Round 4)
Parser claims are always compared to workspace observation for code artifacts; workspace wins on divergence.
