# Amir Architecture Specification

**Version:** 1.1.0  
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
| All | Event model for audit trail | **IMPLEMENTED**: DomainEvent envelope with correlation_id/causation_id; file-based logging for MVP |
| All | Workflow engine seam needed | **IMPLEMENTED**: WorkflowEngine interface with documented migration path to Temporal |
| All | MVP scope over-expansion | **IMPLEMENTED**: Sharp MVP boundary - single adapter, single team, linear workflow, Docker sandbox |
| ChatGPT/Claude/DeepSeek | Contract versioning | **IMPLEMENTED**: Centralized Contract Registry with SemVer and N-1 compatibility |
| Kimi/Grok/GLM | Security isolation | **IMPLEMENTED**: Sandbox Manager interface with Docker→gVisor/Firecracker evolution path |
| Mistral/Perplexity | Capability matching | **IMPLEMENTED**: Capability entity with skill/language/tool declarations |

### Rejected Findings (Not Incorporated)

| Audit Source | Finding | Reason for Rejection |
|-------------|---------|---------------------|
| Kimi | Remove "Retire" from Configuration lifecycle | Kept for completeness, though "Deprecated" triggers archival after 6 months |
| Sakana | Add PromptTemplate entity for MVP | Deferred to Phase 2 - MVP uses inline prompt rendering |
| Kimi | Remove TaskExecution entirely | Kept as conceptual layer in Workflow context; AgentInvocation handles execution |
| All | Full OPA policy engine in MVP | Correctly deferred - MVP uses static AccessPolicy with ABAC planned for Phase 2 |
| GLM | ApprovalGate in MVP | Deferred to Phase 2 - MVP uses auto-approve for all transitions |
| Kimi | Memory as first-class entity | Deferred to Phase 2 - MVP uses ephemeral session state in Redis |

### New Architectural Decisions

1. **Workspace Aggregate Root** (GLM, Kimi): Workspace is promoted to its own aggregate root, referenced by Task. This enables Security Context to interact with workspace isolation without crossing aggregate boundaries.

2. **Non-Root Container Execution** (GLM): All agent sandboxes MUST run as non-root user (UID 65534) with read-only root filesystem. Only `/workspace` is writable.

3. **LLM Output Extraction Pipeline** (GLM, DeepSeek): The AgentAdapter.ParseOutput uses a deterministic pipeline: strip markdown → find YAML/JSON blocks → validate against schema → reject if unfixable. No regex fallback.

4. **Cost Ceiling Enforcement** (DeepSeek): Hard token limits enforced at adapter level via streaming token counting. Process is killed when limits exceed 95% threshold.

5. **Event Model Simplification** (GLM, DeepSeek): MVP uses single-file append-only logging. Tiered retention (Permanent/90-day/30-day) deferred to Phase 2.

6. **Capability Matching Algorithm** (Mistral): Weighted scoring system (skill 50%, language 30%, tool 20%) with configurable thresholds and human fallback.

---

## 7. MVP Verdict

**Status:** `READY_FOR_IMPLEMENTATION` for the defined MVP boundary

The hardened architecture addresses the critical concerns raised in Phase 1 audits:

- ✅ **Bounded Context Separation**: Clean ownership boundaries exist
- ✅ **Aggregate Roots**: Each entity has exactly one owner
- ✅ **Event Model**: Consistent DomainEvent envelope with correlation tracking
- ✅ **Adapter Interface**: Clean seam for agent integration
- ✅ **Sandbox Security**: Non-root containers required, not optional
- ✅ **Cost Controls**: Hard limits enforced at adapter level

**Remaining Technical Debt Items:**

1. **CLI Parsing Reliability**: Must prove deterministic extraction works >95% with real Claude Code output
2. **Sandbox Escape Risk**: Docker is baseline; gVisor/Firecracker mandatory before production
3. **Semantic Validation**: Not in MVP; requires test runner infrastructure

---

## Quick Links

- [Vision & Goals](01-vision-goals-non-goals.md)
- [Architecture Principles](02-architecture-principles.md)
- [Bounded Contexts](03-bounded-contexts.md)
- [Domain Model](04-domain-model.md)
- [Agent Runtime](05-agent-runtime.md)
- [Workflow Engine](06-workflow-engine.md)
- [Security Model](07-security-model.md)
- [Observability](08-observability.md)
- [Persistence](09-persistence.md)
- [Event Model](10-event-model.md)
- [MVP Boundary](11-mvp-boundary.md)
- [Evolution Roadmap](12-evolution-roadmap.md)