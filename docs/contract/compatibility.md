# Contract Versioning and Compatibility

## Versioning Policy

### Semantic Versioning

All contracts use MAJOR.MINOR.PATCH format:

- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: Backward-compatible additions (new optional fields, new contract types)
- **PATCH**: Backward-compatible fixes (bug fixes, clarifications)

### N-1 Compatibility Rule

Contracts must maintain backward compatibility with the previous MINOR version:

```
Contract v1.2.x is compatible with v1.1.x
Contract v2.x.x is NOT compatible with v1.x.x
```

This means:
- New fields MUST be optional
- Required field removal requires MAJOR version bump
- Field type changes require MAJOR version bump

## Compatibility Matrix

Names match schema files under `schemas/` (see README catalog). Suffix "Contract" is not used in filenames.

| Schema file | Backward Compatibility | Breaking Changes |
|-------------|---------------------|-----------------|
| `execution/agent.schema.yaml` | N-1 minor | Removed required field, changed field type, removed capability |
| `execution/task.schema.yaml` | N-1 minor | Changed objective format, removed role reference, removed idempotency_key, removed cost ceiling requirement |
| `artifact/artifact.schema.yaml` | N-1 minor | Schema structure change, required field removal, removed lineage fields |
| `orchestration/workflow.schema.yaml` | N-1 minor | Removed state, changed transition structure, removed compensation config |
| `matching/role.schema.yaml` | N-1 minor | Changed inputs/outputs structure, reintroduced subjective proficiency |
| `team/team.schema.yaml` | N-1 minor | Changed budget/quota structure, removed scoring_weights |
| `artifact/feedback.schema.yaml` | N-1 minor | Changed error category enum, removed correction suggestions |
| `execution/agent-session.schema.yaml` | N-1 minor | Changed status enum, removed lean-session constraints, removed cost ceiling |
| `cost/cost-record.schema.yaml` | N-1 minor | Changed attribution fields, removed cost hierarchy |
| `cost/cost-lease.schema.yaml` | N-1 minor | Removed kill threshold, changed status/revocation semantics |
| `matching/matching-decision.schema.yaml` | N-1 minor | Changed scoring dimensions, removed hard_filters, removed explanation |
| `execution/compiled-prompt.schema.yaml` | N-1 minor | Changed template_hash semantics, removed output_contract |
| `artifact/validation-result.schema.yaml` | N-1 minor | Changed error category enum, removed claim_reconciliation |
| `security/sandbox.schema.yaml` | N-1 minor | Weakened production docker ban, removed environment requirement |
| `security/sandbox-policy.schema.yaml` | N-1 minor | Changed merge algorithm away from intersection |
| `security/sandbox-attestation.schema.yaml` | N-1 minor | Changed signature algorithm, removed signing_key_ref / expires_at |

## Contract Catalog

Complete inventory (data schemas, SQL DDL, interfaces) lives in:

**[`docs/contract/README.md`](README.md)**

Do not restate field lists here. This file is **versioning policy only**.

## Breaking Change Rules

### Prohibited (Requires MAJOR)

- Removing required fields
- Changing field types
- Removing contract types from outputs
- Removing capabilities from agent definitions
- Changing state machine structure
- Removing idempotency_key from required fields
- Removing structural cost ceilings (`anyOf` max_tokens / max_usd)

### Allowed (MINOR version)

- Adding optional fields
- Adding new contract types to outputs
- Adding new capabilities to agents
- Relaxing validation rules (optional → required NOT allowed)
- Adding new enum values to output_mode fields
- Adding new compensation action types

## Version Negotiation

### Agent Registration

Agents declare supported contract versions:

```yaml
supported_contracts:
  - type: CodeChangeArtifact
    version: ">=1.0.0 <2.0.0"
  - type: TestResultArtifact
    version: ">=1.2.0"
```

### Task Assignment Composition Order

Agent selection is a **hard-filter → score → negotiate** pipeline. Contract negotiation is not a scoring dimension; it is a post-score filter with fallback:

```python
def assign_agent(task: Task, candidates: list[AgentDefinition], context) -> MatchingDecision:
    """Compose hard filters, multi-dimensional scoring, and contract negotiation."""
    eligible = []
    rejected = []
    for agent in candidates:
        ok, reason = hard_filter(agent, task)  # tools, skills, circuit breaker, health, network
        if not ok:
            rejected.append((agent.id, reason))
            continue
        eligible.append(agent)

    ranked = sorted(
        (score_agent(a, task, context, load_scorecard(a)) for a in eligible),
        key=lambda d: d.score,
        reverse=True,
    )

    for decision in ranked:
        agent = get_agent(decision.selected_agent_id)
        try:
            version = negotiate_contract(agent, task)
            decision.contract_negotiation = {
                "negotiated_type": task.expected_outputs[0].type,
                "negotiated_version": version,
                "compatible": True,
                "fallback_used": decision is not ranked[0],
            }
            decision.hard_filters = {"passed": True, "rejected_agents": rejected}
            return decision
        except ContractNotCompatible:
            decision.eliminated_reason = "contract_incompatible"
            continue

    raise NoCompatibleAgent(task_id=task.id, rejected=rejected, ranked=ranked)


def negotiate_contract(agent: AgentDefinition, task: Task) -> str:
    """Negotiate best compatible contract version for a specific agent."""
    required = task.expected_outputs[0]
    for supported in agent.supported_contracts:
        if supported.type == required.type:
            if version_satisfies(supported.version_range, required.version):
                return supported.version
    raise ContractNotCompatible()
```

**Rules:**
1. Hard filters eliminate agents with open circuit breakers, missing tools/skills, or health failures.
2. Scoring ranks remaining agents (historical scorecards, cost, latency, etc.).
3. `negotiate_contract()` runs top-down; if the winner is contract-incompatible, the next-ranked agent is tried.
4. Assignment fails only when no ranked agent is contract-compatible.

## Migration and Deprecation Policy

### Supporting Multiple Versions

The complete system supports:

1. **Pinned versions** in workflow definitions when exact reproducibility is required.
2. **N-1 automatic selection** of the highest compatible MINOR version by default.
3. **SemVer range negotiation** when agents declare ranges (`>=1.0.0 <2.0.0`), falling back to the highest mutually compatible version.

Consumers MUST run contract compatibility tests against N-1 before publishing a MINOR release. Canary promotion of new contract versions is supported via WorkflowDefinition version pins.

### Deprecation Lifecycle

When deprecating a contract version:

1. Mark as `deprecated: true` in ContractDefinition with a `deprecation_notice` migration guide.
2. Maintain support for a minimum of 6 months.
3. Emit deprecation warnings on use during the support window.
4. After the window, reject deprecated contracts unless an explicit `force_deprecated_contract: true` override is set on the Task (audited).
5. Remove retired versions only via MAJOR registry cleanup with published migration notes.

## Contract Registry

The Contract Registry (Configuration Context) owns all contract definitions:

```
ContractRegistry
├── CodeChangeArtifact v1.0.0 (Published)
├── CodeChangeArtifact v1.1.0 (Published)
├── TestResultArtifact v1.0.0 (Published)
├── FeedbackArtifact v1.0.0 (Published)
├── AgentSession v1.0.0 (Published)
├── AgentInvocation v1.0.0 (Published)
├── CostRecord v1.0.0 (Published)
├── MatchingDecision v1.0.0 (Published)
├── CompiledPrompt v1.0.0 (Published)
├── ValidationResult v1.0.0 (Published)
├── SandboxAttestation v1.0.0 (Published)
├── Workspace v1.0.0 (Published)
└── ...
```

### Registry API

```python
class ContractRegistry:
    def get(self, contract_type: str, version: str) -> ContractDefinition:
        """Get specific contract version."""
        pass
    
    def list_compatible(self, contract_type: str, version: str) -> list[str]:
        """List versions compatible with given version."""
        pass
    
    def validate(self, artifact: dict, contract_type: str, version: str) -> ValidationResult:
        """Validate artifact against schema."""
        pass
    
    def validate_semantic(self, artifact: dict, contract_type: str, validator_ref: str) -> ValidationResult:
        """Run semantic validator against artifact."""
        pass
```

---

## Design Notes

### Contract Drift

Contract versioning is based on **Amir's expectations**, not agent stdout shape. Agent adapters handle output format changes through ParserRegistry strategy versioning, not by changing business contracts.

### Semantic Validation

Structural validation and semantic validation are both first-class. Semantic validators are pluggable with timeout and budget constraints; results are `ValidationResult` contracts.

### Schema Language

YAML Schema for human readability in GitOps. JSON Schema export available for tooling.

### Idempotency

All mutable operations require idempotency keys. Stored with operation outcome to prevent duplicate side effects on retry.

### Cost Ceilings

`Task.cost_budget` and session/invocation `resource_limits` structurally require at least one of `max_tokens` or `max_usd` via JSON Schema `anyOf`. Empty budgets are invalid by construction.
