# Vision, Goals, and Non-Goals

## Vision

Amir is a control-plane system that creates, manages, coordinates, and governs teams of external AI coding agents. It transforms chaotic, unstructured AI agent interactions into engineering-grade, auditable, and repeatable workflows through contract-driven communication, role-based governance, and GitOps-managed configuration.

Amir does **not** provide intelligence itself. It provides the infrastructure for reliable, scalable orchestration of heterogeneous AI agents.

## Goals

### ✅ Achieved Goals

✅ **Control Plane Agnosticism** - Support CLI, MCP, and API-based agents without vendor lock-in through the Adapter pattern

✅ **Contract-Driven Communication** - All agent interactions produce typed, versioned, validated artifacts with provenance tracking

✅ **Engineering-Grade Governance** - Apply proven software engineering practices (GitOps, CI/CD, security) to AI agent management

✅ **GitOps Configuration** - All definitions versioned, reviewed, and promoted via pull requests with semantic versioning

✅ **Security-First Architecture** - Zero-trust execution with mandatory sandboxed isolation and just-in-time secrets

✅ **Observable Operations** - Full audit trails, deterministic event model, and structured logging for compliance

✅ **Scalable Design** - Horizontal scaling from 5 to 1000+ agents with documented evolution paths

✅ **Two-Track Lifecycle** - Configuration entities follow GitOps promotion, Runtime entities follow lightweight state machines

## Non-Goals

❌ **Agent Intelligence** - Amir does not provide LLMs or reasoning capabilities; it orchestrates external agents

❌ **Human Chat Interface** - Amir is not a conversational UI; all interactions are programmatic via contracts

❌ **Direct Code Hosting** - Git repositories remain external; Amir orchestrates changes via PRs, not direct commits

❌ **Universal Lifecycle for All Entities** - Runtime entities use simple state machines, not full GitOps lifecycles

❌ **Homogeneous Agents** - Amir deliberately supports heterogeneous, external agent tools (Claude, Codex, OpenCode, Gemini, etc.)

❌ **Full Semantic Validation** - Structural schema validation in MVP; semantic validation (running tests, checking quality criteria) deferred to Phase 2

❌ **Multi-Environment GitOps** - Single environment for MVP; dev/staging/prod promotion deferred to Phase 2

❌ **Streaming Mode B** - Progress streaming deferred to Phase 2; MVP uses batch mode only

## Success Metrics

| Metric | Target (MVP) | Target (Phase 2) |
|--------|--------------|------------------|
| Agent Execution Reliability | 90% success rate | 95% success rate |
| Contract Validation | Structural only | Structural + Semantic |
| Artifact Recovery from Failures | Manual | Automatic via retry-with-feedback |
| Sandbox Security | Docker + seccomp | gVisor/Firecracker |
| Cost Control | Per-task hard limits | Team-level budgets + alerts |
| Multi-tenancy | Single team | Full tenant isolation |

## Out of Scope (Future Phases)

- **Phase 2**: Streaming progress, semantic validation, human approvals, multi-environment promotion
- **Phase 3**: Temporal workflow engine, full observability stack, advanced policy engine
- **Phase 4**: Federated multi-region control planes, SOC 2 compliance, enterprise features

---

## Relationship to Audit Feedback

The vision has been hardened based on the following critical audit insights:

- **Agent non-determinism** (Kimi): MVP accepts this reality; contracts provide structure, not guarantees
- **CLI parsing fragility** (All): Hard technical debt item; adapter layer isolates this risk
- **Aggregate boundary clarity** (GLM, DeepSeek): Workspace promoted to its own aggregate root
- **Security reality check** (Kimi, GLM): Non-root containers required; sandbox escape requires layered defense