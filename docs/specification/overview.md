# Amir Architecture Specification

**Version:** 2.1.1  
**Status:** Authoritative Technical Specification  
**Owner:** Technical Leadership

---

## Audit Findings Synthesis

### Round 5 Residual Hardening (This Pass)

Focused correction of production-blocking gaps still open after the post–Round 4 hardening commit. Not a redesign.

| Priority | Issue | Resolution |
|----------|-------|------------|
| 1 | Cost hard kill eventual-only | **CostLease** sync shared-state gate; fail-closed; post-cancel = `budget_exceeded` (no default retry) |
| 2 | Compensation best-effort dead-end | Default `continue_on_compensation_failure=false` → **CompensationBlocked** + `EscalationSignal` |
| 3 | AgentSession God Object | Lean session: ring buffers + event/table history; not unbounded telemetry |
| 4a | docker/production prose-only | JSON Schema **`if/then` at schema root** (was wrongly nested under `properties`) |
| 4b | `auto_approve` unsafe default | Schema + workflow prose default **`false`** |
| 4c | claim_reconciliation triplication | Canonical on **ValidationResult**; Artifact/Feedback reference by ID |
| 4d | retry vocab mismatch | Shared enum including **`budget_exceeded`** |
| 5 | Cold-start starvation | **exploration_bonus** on MatchingDecision + scoring algorithm |
| 6 | Validation starves repair | **`validation_budget`** partitioned from execution `cost_budget` |
| 7 | llm_coercion in default chain | **Removed from default** (4 strategies); opt-in + approval only |
| 8a | Allowlist merge undefined | **Intersection** + fixed profile expansion registry |
| 8b | SecretBinding missing | Formal **secret-binding.schema.yaml** |

### Round 4 Audit Findings (Independent Architecture Audits)

#### Fully Accepted Findings

| Finding | Source | Implementation |
|---------|--------|---------------|
| Execution-first centrality of AgentSession | Copilot, Perplexity, Xiaomi, Claude | AgentSession is the central runtime aggregate; AgentInvocation is a request DTO only |
| Complete dangling contracts | Claude, Xiaomi, Grok | Schemas added: MatchingDecision, CompiledPrompt, ValidationResult, SandboxAttestation |
| Structural cost ceilings | Claude (recurring) | `anyOf` requires at least one of `max_tokens` / `max_usd` on Task, invocation, and session |
| Circuit breaker ownership | Claude | Agent-scoped only on AgentScorecard; Task uses `retry_state` |
| Workspace cardinality | Claude, Xiaomi | Task 1 → 1..* Workspace via AgentSession 1 → 1 Workspace |
| Compensation targets durable effects | Claude, GLM | Abstract workflow intents map to durable_effects; not cleaned workspaces |
| score + negotiate composition order | Claude | Hard filter → score → negotiate top-down with fallback |
| Claim reconciliation | GLM, Xiaomi, Claude | ValidationResult + Artifact carry claim vs workspace divergence; workspace wins |
| Adapter/runtime boundary | Copilot, Xiaomi, Minimax | Explicit pump/respond_input/inject_feedback; interactive prompts; continuity |
| Remove proficiency zombie | GLM | Role required_capabilities use tools/constraints only |
| Remove free_text control-plane mode | GLM | Output modes: json_schema, tool_use, markdown_yaml, workspace_observation |
| In-flight budget cancellation | Claude | Team/tenant/org hard thresholds cancel in-flight sessions via CostLease |
| Network allowlist default-deny | Claude, Xiaomi | Empty allowlist = deny except platform LLM routes; coding_standard profile |
| Scorecard version warm-start | Claude | Prior agent version metrics carry over when name matches |
| Key lifecycle for attestation | Claude, Xiaomi | KMS/HSM refs, rotation window, compromise handling |
| Workspace ownership single context | GLM | Execution owns Workspace; Security evaluates SandboxPolicy |
| Remove phasing language | Grok | compatibility.md rewritten as single coherent policy; mvp.md → system-boundary |

#### Partially Accepted Findings

| Finding | Source | Implementation |
|---------|--------|---------------------|
| Abstract-only compensation enums | GLM | Dual-layer: abstract intent in Workflow + concrete effects in Execution |
| Sever AgentSession telemetry from contracts | GLM | Session remains durable aggregate; high-frequency data is events/linked tables with bounded ring samples |
| Multi-turn AgentConversation entity | Prior | Modeled as session `waiting_for_input` + adapter protocol; no separate aggregate |
| EvaluationTask contract type | Prior | Covered by semantic validators with budget; no separate contract type |
| SecretBinding full schema | Xiaomi, Copilot | secret-binding.schema.yaml for ephemeral secret grants with TTL |
| AgentScorecard formal schema | Xiaomi | Structure specified in observability/agent docs as read model; time-series view in Observability Context |

#### Rejected Findings

| Finding | Source | Reason for Rejection |
|---------|--------|---------------------|
| Delete agent-session.schema.yaml entirely | GLM | Session is the execution-first aggregate; telemetry fields are bounded and versioned |
| Defer multi-dimensional scoring / cost hierarchy | Xiaomi | Complete-system design requires full routing and hierarchical cost; not optional complexity |
| Drop Merkle audit chain | Xiaomi | Tamper-evidence is a stated differentiator; key lifecycle closes the gap |
| Mandate MCP over CLI | Prior | CLI remains first-class; MCP is an adapter type |
| Firecracker as sole runtime | Prior | gVisor default; Firecracker optional max-security |
| Full Temporal as design requirement | Prior | WorkflowEngine interface seam only |
| Merge ValidationResult into FeedbackArtifact | DeepSeek | Distinct concerns: outcome vs remediation payload |
| Btrfs/ZFS snapshot as required compensation | GLM | Git durable_effects + tree-hash observation sufficient; FS snapshots optional hardening |

---

### Round 3 Audit Findings (Preserved Baseline)

Prior round fully accepted foundations remain in force: AgentSession state machine, Feedback loop, three-layer runtime, Workspace Observation, ParserRegistry, multi-dimensional scoring, hierarchical cost gate, saga compensation, mandatory egress proxy, idempotency, AgentScorecard, PromptCompiler, semantic validation, sidecar, replay metadata.

---

## Contract vs Documentation Separation

| Layer | Location | Role |
|-------|----------|------|
| **Contracts** | `docs/contract/` | Sole authority for structure (JSON Schema YAML, SQL DDL, interface YAML) |
| **Specification** | `docs/specification/` | Behavior, flows, principles, ownership — **references** contracts |
| **Stories** | `docs/story/` | User-facing acceptance criteria — **references** contracts |

**Rules:** Markdown must not embed full schemas, DDL, or field dumps. Catalog: [`docs/contract/README.md`](../contract/README.md).

## Specification Status

**Status:** `COMPLETE_AND_CONSISTENT` (v2.1.1)

Hardened relative to v2.0.0 / residual v2.1.0 gaps:

- ✅ **Execution-first**: AgentSession central aggregate; invocation is request DTO
- ✅ **Dangling contracts closed**: MatchingDecision, CompiledPrompt, ValidationResult, SandboxAttestation, CostLease, SecretBinding, EscalationSignal
- ✅ **Cost ceilings structural**: anyOf max_tokens/max_usd required
- ✅ **Synchronous cost control**: CostLease shared-state gate; fail-closed; post-cancel path defined
- ✅ **Circuit breaker**: agent-only on AgentScorecard; Task has retry_state
- ✅ **Workspace cardinality**: 1 Task → many Workspaces via sessions
- ✅ **Compensation**: durable effects; dual-layer; **CompensationBlocked** + EscalationSignal (not best-effort default)
- ✅ **Assignment pipeline**: hard filter → score (+exploration) → negotiate with fallback
- ✅ **Claim reconciliation**: canonical on ValidationResult; workspace authoritative
- ✅ **Adapter boundary**: interactive prompts, pump loop, continuity, replay
- ✅ **No phasing language** in compatibility or system boundary docs
- ✅ **Lean AgentSession**: high-frequency data in events/tables; bounded samples on document
- ✅ **docker illegal in production**: root-level JSON Schema if/then
- ✅ **llm_coercion**: not in default ParserRegistry chain

---

## Hardened Design Changes (v2.1.1 — Audit5 Residual Pass)

### What Was Fixed

| Issue | Fix |
|-------|-----|
| sandbox `if/then` under `properties` (non-functional) | Moved to **schema root**; docker structurally illegal when `environment=production` (or omitted) |
| Compensation “best-effort continue” | Default block → **CompensationBlocked** + human `EscalationSignal`; executor pseudocode updated |
| AgentSession God Object risk | Lean model: ring buffers (checkpoints ≤20, tool_calls ≤50), `tool_call_events` table, latest usage snapshot only |
| claim_reconciliation shapes | Canonical on ValidationResult (+ `authoritative_source=workspace`); Artifact/Feedback by ID only |
| retry_on vs last_failure_category | Shared vocabulary including `budget_exceeded` |
| Cost kill post-path undefined | `budget_exceeded` not in default retry_on; EscalationSignal for team+; compensation if durable effects exist |
| CostLease incomplete | Scope, fail-closed, trust boundary, event types documented |
| Pure historical scoring | Exploration bonus when cold/low invocations/stale scorecard |
| Validation starves repair | `Task.validation_budget` partitioned from execution budget |
| llm_coercion default chain | 4-strategy default; coercion opt-in + `coercion_approval_id` |
| auto_approve True in prose | Aligned to **false** (schema + workflow.md) |
| Allowlist merge / profile | Intersection algorithm + fixed coding_standard domain expansion |
| SecretBinding | Formal schema retained and referenced in contracts matrix |
| Prose contradictions (5-strategy, etc.) | Aligned vision, system-boundary, agent, security, stories |

### Separation of Concerns (Contracts vs Documents)

All structural definitions now live only under `docs/contract/`:

- **Data:** `schemas/*.schema.yaml` (JSON Schema)
- **Database:** `sql/*.sql`
- **Interfaces:** `interfaces/*.yaml`
- **Catalog:** `docs/contract/README.md`

Specification and story markdown **reference** contracts; they no longer embed schemas, DDL, or field inventories.

### What Was Deliberately Left Unchanged (and Why)

| Item | Why unchanged |
|------|----------------|
| TeamSession / multi-agent shared workspace | Explicitly out of scope; no new major subsystem |
| Full Memory aggregate / LearningEngine | Out of scope; scorecard + exploration is sufficient for routing cold-start |
| Temporal as mandatory engine | Interface seam only; durability via event-sourced WorkflowInstance |
| Firecracker / eBPF mandatory | Optional max-security / hardening; gVisor remains production default |
| PromptTemplate formal schema | Integrity via `template_hash` on CompiledPrompt; template structure is config, not runtime contract |
| Merkle global sequence redesign | Per-aggregate chaining is production-viable; global sequence optimization is implementation detail |
| Opening the protocol | Internal coherence first |
| FS snapshot compensation as required | Durable git/PR/artifact effects remain the compensation target |
| Algorithm pseudocode in specs | Behavior documentation (not structure); must not restate field lists |

---

## Quick Links

- [**Contract catalog**](../contract/README.md) — schemas, SQL, interfaces
- [Compatibility policy](../contract/compatibility.md)
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
- [System Boundary](system-boundary.md)
- [Evolution Roadmap](roadmap.md)
