# Amir Architecture Specification

**Version:** 1.2.0  
**Status:** Authoritative Technical Specification  
**Owner:** Technical Leadership

---

## Audit Findings Synthesis

### Accepted Findings (Addressed in This Specification)

| Audit Source | Finding | Decision |
|-------------|---------|----------|
| All | Over-engineered universal lifecycle | **IMPLEMENTED**: Two-Track Lifecycle - Configuration entities follow GitOps (Draft→Published→Deprecated), Runtime entities follow lightweight state machines (Pending→Running→Completed/Failed) |
| All | Missing bounded contexts | **IMPLEMENTED**: Five explicit contexts - Configuration, Execution, Workflow, Security, Observability |
| All | TaskExecution/AgentInvocation ambiguity | **IMPLEMENTED**: AgentInvocation is the sole entity for runtime execution; Task tracks orchestration state |
| All | Event model for audit trail | **IMPLEMENTED**: DomainEvent envelope with correlation_id/causation_id; durable event store with retention policies |
| All | Workflow engine seam needed | **IMPLEMENTED**: WorkflowEngine interface with configurable persistence and migration path to Temporal |
| ChatGPT/Claude/DeepSeek | Contract versioning | **IMPLEMENTED**: Centralized Contract Registry with SemVer and N-1 compatibility |
| Kimi/Grok/GLM | Security isolation | **IMPLEMENTED**: Sandbox Manager with Docker/gVisor/Firecracker support, mandatory non-root execution |
| Mistral/Perplexity | Capability matching | **IMPLEMENTED**: Capability entity with skill/language/tool declarations, weighted scoring algorithm |

### Rejected Findings

| Audit Source | Finding | Reason for Rejection |
|-------------|---------|---------------------|
| Kimi | Remove "Retire" from Configuration lifecycle | Kept for completeness - "Deprecated" triggers archival after 6 months of inactivity |
| Kimi | Remove TaskExecution entirely | Kept as conceptual layer - Task tracks orchestration, AgentInvocation handles execution |

### Removed Findings (Explicitly Out of Scope)

| Audit Source | Finding | Reason for Removal |
|-------------|---------|-------------------|
| Sakana | PromptTemplate entity | Out of scope - Amir does not manage prompts; agents handle their own prompt rendering |
| All | Full OPA policy engine | Out of scope - Static AccessPolicy sufficient; ABAC rules expressed as simple allow/deny lists |
| GLM | ApprovalGate complexity | Out of scope - Approval is binary auto-approve for automated workflows; manual approvals handled externally |
| Kimi | Memory entity | Out of scope - Ephemeral state handled by external session stores; not part of core domain |
| GLM | Hash-Chain audit | Out of scope - Standard append-only event store with cryptographic signing per event |
| GLM | Streaming progress events | Out of scope - Event store receives periodic heartbeat events, not continuous streams |

### New Architectural Decisions

1. **Workspace Aggregate Root**: Workspace is promoted to its own aggregate root, referenced by Task. This enables Security Context to interact with workspace isolation without crossing aggregate boundaries.

2. **Mandatory Non-Root Container Execution**: All agent sandboxes MUST run as non-root user (UID 65534) with read-only root filesystem. Only `/workspace` is writable via tmpfs.

3. **Deterministic LLM Output Extraction Pipeline**: The AgentAdapter.ParseOutput uses a deterministic pipeline: strip markdown → find YAML/JSON blocks → validate against schema → reject if unfixable. No regex fallback.

4. **Hard Cost Limits with Threshold Enforcement**: Token/USD limits enforced at adapter level. Process kills at 95% threshold, with configurable grace period.

5. **Durable Event Store**: Append-only event store with configurable retention (permanent for security events, time-limited for operational events). Each event includes cryptographic signature.

6. **Weighted Capability Matching**: Scoring system (skill 50%, language 30%, tool 20%) for agent selection. Human fallback when no agent meets threshold.

---

## Audit Feedback Disposition

### Fully Accepted Findings

| Finding | Source | Implementation |
|---------|--------|---------------|
| Two-Track Entity Lifecycle | All | Configuration: GitOps (Draft→Published→Deprecated) / Runtime: Simple state machines |
| Bounded Context Separation | All | Five contexts: Configuration, Execution, Workflow, Security, Observability |
| AgentInvocation as Runtime Entity | All | AgentInvocation sole runtime entity; Task tracks orchestration |
| DomainEvent Envelope | All | Standard envelope with correlation_id, causation_id for tracing |
| Workflow Engine Interface | All | WorkflowEngine interface with configurable persistence |
| Contract Versioning | All | SemVer with N-1 compatibility enforced |
| Non-Root Container Requirement | All | Mandatory UID 65534, read-only root filesystem |
| Deterministic Output Extraction | GLM/DeepSeek | Strip markdown → YAML block → validate; no regex fallback |
| Hard Cost Limits | DeepSeek | Kill switch at 95% threshold |
| Approval as Binary Gate | All audits | Auto-approve for automated workflows; external for manual |

### Partially Accepted Findings

| Finding | Source | Partial Implementation |
|---------|--------|---------------------|
| Semantic Validation | All | Structural validation in core; semantic validation as pluggable validator |
| Multi-Tenancy | Kimi/Perplexity | Single-team default; multi-tenant support via namespace isolation |
| Full Observability Stack | GLM | File-based event store; OpenTelemetry export as instrumentation |

### Rejected Findings (Removed from Scope)

| Finding | Source | Reason |
|---------|--------|--------|
| PromptTemplate Entity | Sakana | Out of scope - agents manage their own prompts |
| Memory Entity | Kimi | Out of scope - ephemeral state via external session store |
| Full OPA Policy Engine | All | Out of scope - simple allow/deny policy sufficient |
| Hash-Chain Audit | GLM | Out of scope - standard event store with signing |
| Streaming Progress | GLM | Out of scope - heartbeat events instead |

---

## Specification Status

**Status:** `COMPLETE_AND_CONSISTENT`

All core architectural concerns are designed:

- ✅ **Bounded Context Separation**: Clean ownership boundaries defined
- ✅ **Aggregate Roots**: Each entity has exactly one owner
- ✅ **Event Model**: Consistent DomainEvent envelope with full retention policy
- ✅ **Adapter Interface**: Clean seam for agent integration
- ✅ **Sandbox Security**: Multi-runtime support with mandatory non-root
- ✅ **Cost Controls**: Hard limits with threshold enforcement
- ✅ **Approval Model**: Binary auto-approve with manual override capability
- ✅ **Validation Loop**: Full retry-with-feedback mechanism specified
- ✅ **Contract Versioning**: SemVer with N-1 compatibility

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