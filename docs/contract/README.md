# Amir Contracts

**Authority for structure.** Machine-readable contracts live only under this directory.
Markdown under `docs/specification/` and `docs/story/` is documentation only and must
**reference** contracts—never restate their fields.

## Separation of Concerns

| Kind | Location | Formats |
|------|----------|---------|
| Data / domain contracts | `schemas/<domain>/` | JSON Schema (YAML files) |
| Database contracts | `sql/` | SQL DDL |
| Interface contracts | `interfaces/` | YAML method contracts |
| Compatibility policy | `compatibility.md` | Versioning rules (policy doc) |

Schema domains: `execution`, `matching`, `orchestration`, `artifact`, `security`, `cost`, `eventing`, `team`.

Documentation may link here. It must not embed full schemas, DDL, or field dumps.

## Data Contracts (`schemas/`)

### Execution (`schemas/execution/`)

Core runtime aggregates — agent lifecycle, task scheduling, workspaces, prompts, checkpoints.

| Contract | File |
|----------|------|
| Agent | `schemas/execution/agent.schema.yaml` |
| AgentInvocation | `schemas/execution/agent-invocation.schema.yaml` |
| AgentSession | `schemas/execution/agent-session.schema.yaml` |
| Checkpoint | `schemas/execution/checkpoint.schema.yaml` |
| CompiledPrompt | `schemas/execution/compiled-prompt.schema.yaml` |
| DurableExecutionConfig | `schemas/execution/durable-execution-config.schema.yaml` |
| ReplayMetadata | `schemas/execution/replay-metadata.schema.yaml` |
| Task | `schemas/execution/task.schema.yaml` |
| ToolCall | `schemas/execution/tool-call.schema.yaml` |
| Workspace | `schemas/execution/workspace.schema.yaml` |

### Matching (`schemas/matching/`)

Agent selection, capability scoring, skill taxonomy, role definitions, circuit breakers.

| Contract | File |
|----------|------|
| AgentScorecard | `schemas/matching/agent-scorecard.schema.yaml` |
| Capability | `schemas/matching/capability.schema.yaml` |
| CircuitBreakerState | `schemas/matching/circuit-breaker-state.schema.yaml` |
| MatchingDecision | `schemas/matching/matching-decision.schema.yaml` |
| Role | `schemas/matching/role.schema.yaml` |
| Skill | `schemas/matching/skill.schema.yaml` |

### Orchestration (`schemas/orchestration/`)

Workflow state machines, step results, compensation, approvals, escalation.

| Contract | File |
|----------|------|
| Approval | `schemas/orchestration/approval.schema.yaml` |
| CompensationAction | `schemas/orchestration/compensation-action.schema.yaml` |
| EscalationSignal | `schemas/orchestration/escalation-signal.schema.yaml` |
| StepResult | `schemas/orchestration/step-result.schema.yaml` |
| Workflow | `schemas/orchestration/workflow.schema.yaml` |

### Artifact (`schemas/artifact/`)

Agent-produced outputs, validation, quality metrics, feedback loops.

| Contract | File |
|----------|------|
| Artifact | `schemas/artifact/artifact.schema.yaml` |
| Feedback | `schemas/artifact/feedback.schema.yaml` |
| QualityMetric | `schemas/artifact/quality-metric.schema.yaml` |
| ValidationMetric | `schemas/artifact/validation-metric.schema.yaml` |
| ValidationResult | `schemas/artifact/validation-result.schema.yaml` |

### Security (`schemas/security/`)

Authorization, sandbox configuration, secret injection, network egress.

| Contract | File |
|----------|------|
| AccessPolicy | `schemas/security/access-policy.schema.yaml` |
| EgressProxy | `schemas/security/egress-proxy.schema.yaml` |
| PolicyEngine | `schemas/security/policy-engine.schema.yaml` |
| Sandbox | `schemas/security/sandbox.schema.yaml` |
| SandboxPolicy | `schemas/security/sandbox-policy.schema.yaml` |
| SandboxAttestation | `schemas/security/sandbox-attestation.schema.yaml` |
| SecretBinding | `schemas/security/secret-binding.schema.yaml` |

### Cost (`schemas/cost/`)

Budgeting, cost leases, cost records, aggregated reporting.

| Contract | File |
|----------|------|
| CostLease | `schemas/cost/cost-lease.schema.yaml` |
| CostRecord | `schemas/cost/cost-record.schema.yaml` |
| CostSummary | `schemas/cost/cost-summary.schema.yaml` |

### Eventing (`schemas/eventing/`)

Domain events, audit trails, outbox pattern, idempotency.

| Contract | File |
|----------|------|
| AuditEvent | `schemas/eventing/audit-event.schema.yaml` |
| DomainEvent | `schemas/eventing/domain-event.schema.yaml` |
| IdempotencyKey | `schemas/eventing/idempotency-key.schema.yaml` |
| OutboxEntry | `schemas/eventing/outbox-entry.schema.yaml` |

### Team (`schemas/team/`)

Team definitions, role bindings, agent bindings, budgets.

| Contract | File |
|----------|------|
| Team | `schemas/team/team.schema.yaml` |

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
| CostEnforcer | `interfaces/cost-enforcer.yaml` |

## Allowlist Profiles (`allowlists/`)

| Profile | File |
|---------|------|
| coding_standard | `allowlists/coding_standard.yaml` |

Used by SandboxPolicy profile expansion before intersection merge. Platform LLM routes are always unioned after intersection.

## Rules for Authors

1. **New structure** → add/change a file under `docs/contract/`, never only in markdown.
2. **New behavior** → update markdown; if structure changes, update the contract in the same change.
3. **No field dumps in MD** — link to the contract path instead.
4. **Examples in MD** may show *values* of a contract (short instance snippets) only when needed for clarity; they must not redefine the schema.
5. **Idempotency** — all mutable operations require `idempotency_key` (see `idempotency-key.schema.yaml`).
