# Amir Contracts

**Authority for structure.** Machine-readable contracts live only under this directory.
Markdown under `docs/specification/` and `docs/story/` is documentation only and must
**reference** contracts—never restate their fields.

## Separation of Concerns

| Kind | Location | Formats |
|------|----------|---------|
| Data / domain contracts | `schemas/` | JSON Schema (YAML files) |
| Database contracts | `sql/` | SQL DDL |
| Interface contracts | `interfaces/` | YAML method contracts |
| Compatibility policy | `compatibility.md` | Versioning rules (policy doc) |

Documentation may link here. It must not embed full schemas, DDL, or field dumps.

## Data Contracts (`schemas/`)

| Contract | File |
|----------|------|
| Agent | `schemas/agent.schema.yaml` |
| AgentInvocation | `schemas/agent-invocation.schema.yaml` |
| AgentSession | `schemas/agent-session.schema.yaml` |
| AgentScorecard | `schemas/agent-scorecard.schema.yaml` |
| Approval | `schemas/approval.schema.yaml` |
| Artifact | `schemas/artifact.schema.yaml` |
| AccessPolicy | `schemas/access-policy.schema.yaml` |
| AuditEvent | `schemas/audit-event.schema.yaml` |
| Capability | `schemas/capability.schema.yaml` |
| Checkpoint | `schemas/checkpoint.schema.yaml` |
| CircuitBreakerState | `schemas/circuit-breaker-state.schema.yaml` |
| CompiledPrompt | `schemas/compiled-prompt.schema.yaml` |
| CompensationAction | `schemas/compensation-action.schema.yaml` |
| CostLease | `schemas/cost-lease.schema.yaml` |
| CostRecord | `schemas/cost-record.schema.yaml` |
| CostSummary | `schemas/cost-summary.schema.yaml` |
| DomainEvent | `schemas/domain-event.schema.yaml` |
| DurableExecutionConfig | `schemas/durable-execution-config.schema.yaml` |
| EgressProxy | `schemas/egress-proxy.schema.yaml` |
| EscalationSignal | `schemas/escalation-signal.schema.yaml` |
| Feedback | `schemas/feedback.schema.yaml` |
| IdempotencyKey | `schemas/idempotency-key.schema.yaml` |
| MatchingDecision | `schemas/matching-decision.schema.yaml` |
| OutboxEntry | `schemas/outbox-entry.schema.yaml` |
| PolicyEngine | `schemas/policy-engine.schema.yaml` |
| QualityMetric | `schemas/quality-metric.schema.yaml` |
| ReplayMetadata | `schemas/replay-metadata.schema.yaml` |
| Role | `schemas/role.schema.yaml` |
| Sandbox | `schemas/sandbox.schema.yaml` |
| SandboxAttestation | `schemas/sandbox-attestation.schema.yaml` |
| SecretBinding | `schemas/secret-binding.schema.yaml` |
| Skill | `schemas/skill.schema.yaml` |
| StepResult | `schemas/step-result.schema.yaml` |
| Task | `schemas/task.schema.yaml` |
| Team | `schemas/team.schema.yaml` |
| ToolCall | `schemas/tool-call.schema.yaml` |
| ValidationMetric | `schemas/validation-metric.schema.yaml` |
| ValidationResult | `schemas/validation-result.schema.yaml` |
| Workflow | `schemas/workflow.schema.yaml` |
| Workspace | `schemas/workspace.schema.yaml` |

## Database Contracts (`sql/`)

| Context | File |
|---------|------|
| Execution | `sql/execution.sql` |
| Workflow | `sql/workflow.sql` |
| Outbox / events | `sql/outbox.sql` |
| Security | `sql/security.sql` |
| Observability | `sql/observability.sql` |

## Interface Contracts (`interfaces/`)

| Interface | File |
|-----------|------|
| AgentAdapter | `interfaces/agent-adapter.yaml` |
| WorkflowEngine | `interfaces/workflow-engine.yaml` |
| ParserRegistry | `interfaces/parser-registry.yaml` |

## Rules for Authors

1. **New structure** → add/change a file under `docs/contract/`, never only in markdown.
2. **New behavior** → update markdown; if structure changes, update the contract in the same change.
3. **No field dumps in MD** — link to the contract path instead.
4. **Examples in MD** may show *values* of a contract (short instance snippets) only when needed for clarity; they must not redefine the schema.
