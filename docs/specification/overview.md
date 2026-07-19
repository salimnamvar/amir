# Amir Architecture Specification

**Version:** 2.1.0  
**Status:** Authoritative Technical Specification  
**Owner:** Technical Leadership

---

## Audit Findings Synthesis

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
| In-flight budget cancellation | Claude | Team/tenant/org hard thresholds cancel in-flight sessions |
| Network allowlist default-deny | Claude, Xiaomi | Empty allowlist = deny except platform LLM routes; coding_standard profile |
| Scorecard version warm-start | Claude | Prior agent version metrics carry over when name matches |
| Key lifecycle for attestation | Claude, Xiaomi | KMS/HSM refs, rotation window, compromise handling |
| Workspace ownership single context | GLM | Execution owns Workspace; Security evaluates SandboxPolicy |
| Remove phasing language | Grok | compatibility.md rewritten as single coherent policy; mvp.md → system-boundary |

#### Partially Accepted Findings

| Finding | Source | Partial Implementation |
|---------|--------|---------------------|
| Abstract-only compensation enums | GLM | Dual-layer: abstract intent in Workflow + concrete effects in Execution |
| Sever AgentSession telemetry from contracts | GLM | Session remains a first-class durable aggregate (needed for replay/idempotency); live meters separated from authoritative CostRecord |
| Multi-turn AgentConversation entity | Prior | Modeled as session `waiting_for_input` + adapter protocol; no separate aggregate |
| EvaluationTask contract type | Prior | Covered by semantic validators with budget; no separate contract type |
| SecretBinding full schema | Xiaomi, Copilot | Described in Security Context + SecretBroker; dedicated schema reserved for next contract pass if needed |
| AgentScorecard formal schema | Xiaomi | Structure specified in observability/agent docs as read model |

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

## Specification Status

**Status:** `COMPLETE_AND_CONSISTENT` (v2.1.0)

Hardened relative to v2.0.0:

- ✅ **Execution-first**: AgentSession central aggregate; invocation is request DTO
- ✅ **Dangling contracts closed**: MatchingDecision, CompiledPrompt, ValidationResult, SandboxAttestation
- ✅ **Cost ceilings structural**: anyOf max_tokens/max_usd required
- ✅ **Circuit breaker**: agent-only on AgentScorecard; Task has retry_state
- ✅ **Workspace cardinality**: 1 Task → many Workspaces via sessions
- ✅ **Compensation**: durable effects, two-layer abstract/concrete
- ✅ **Assignment pipeline**: hard filter → score → negotiate with fallback
- ✅ **Claim reconciliation**: parser vs workspace; workspace authoritative
- ✅ **Adapter boundary**: interactive prompts, pump loop, continuity, replay
- ✅ **No phasing language** in compatibility or system boundary docs
- ✅ **Bounded Context Separation** with single Workspace owner
- ✅ **Mandatory security posture**: gVisor, egress proxy, attestation keys

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
- [System Boundary](system-boundary.md)
- [Evolution Roadmap](roadmap.md)
