# Lifecycle Contract

## Purpose

The Lifecycle Contract defines the promotion and management process for all versioned artifacts in Amir. It specifies the stages, gates, and validation rules that artifacts must pass before becoming active in the system.

Different entity types follow different lifecycle patterns:
- **Configuration Entities**: Full GitOps lifecycle (Draft → Validate → Review → Test → Approve → Release → Deploy → Monitor → Retire)
- **Runtime Entities**: Simplified execution lifecycle (Pending → Running → Completed/Failed)

## Schema

```yaml
LifecycleContract:
  type: lifecycle-contract
  version: string (semantic version)
  lifecycle:
    entity_type: enum [configuration, runtime, artifact]
    stages:
      - name: string
        description: string
        required_validators: [string]
        timeout: duration (optional)
        auto_transition: boolean
      # Stages vary by entity type
    transitions:
      - from_stage: string
        to_stage: string
        conditions: [string]
        gates: [string]
  validation_rules:
    - stage: string
      validator: string
      config: {}
  promotion_policies:
    - source_environment: string
      target_environment: string
      required_approvals: int
      automated_checks: [string]
  rollback_strategy:
    on_failure: enum [rollback, pause, alert]
    retention_days: int
  metadata:
    created_at: timestamp
    updated_at: timestamp
```

## Entity-Specific Lifecycles

### Configuration Entities (Agents, Roles, Contracts, Policies, Workflows)

Full GitOps lifecycle with comprehensive validation:

```
Draft
  │
  ▼
Validate (schema compliance, unit tests)
  │
  ▼
Review (peer review via PR)
  │
  ▼
Test (integration tests, compatibility check)
  │
  ▼
Approve (approval gates)
  │
  ▼
Release (version tag, changelog)
  │
  ▼
Deploy (applied to control plane)
  │
  ▼
Monitor (health checks, metrics)
  │
  ▼
Retire (deprecated, migration path provided)
```

### Runtime Entities (Tasks, Executions, Artifacts)

Simplified execution lifecycle:

```
Pending
  │
  ▼
Assigned
  │
  ▼
Running
  │
  ▼
Validating
  │
  ▼
Succeeded ◄── Failed
```

## Configuration Lifecycle Detail

### Stage: Draft

**Purpose**: Entity is being created or modified

**Requirements**:
- Entity must conform to basic schema
- All required fields present

**Gates**: None

**Outcome**: Entity can be committed to version control

### Stage: Validate

**Purpose**: Automated validation of entity structure

**Validators**:
- Schema validation
- Naming convention check
- Reference integrity check
- Basic constraint validation

**Gates**: All validators pass

**Timeout**: 5 minutes

### Stage: Review

**Purpose**: Human peer review of changes

**Validators**:
- Code owner approval
- Security review (for agent/workflow changes)
- Impact analysis

**Gates**: Required approvals obtained

**Timeout**: 72 hours (configurable)

### Stage: Test

**Purpose**: Integration testing of entity changes

**Validators**:
- Unit tests for custom logic
- Contract compatibility tests
- Agent capability tests

**Gates**: All tests pass or waived

**Timeout**: 30 minutes

### Stage: Approve

**Purpose**: Production readiness approval

**Validators**:
- Change advisory board approval (for major changes)
- Cost/budget impact analysis
- Rollout plan approval

**Gates**: Approval obtained

**Timeout**: 24 hours

### Stage: Release

**Purpose**: Create version tag and release notes

**Requirements**:
- Semantic version assigned
- Changelog generated
- Migration guide (if breaking changes)

**Gates**: Version tag pushed

### Stage: Deploy

**Purpose**: Apply entity to control plane

**Requirements**:
- Control plane health check
- Canary deployment (for high-risk changes)
- Health monitoring during rollout

**Gates**: Deployment successful

### Stage: Monitor

**Purpose**: Observe entity performance in production

**Metrics**:
- Error rate
- Performance impact
- Usage statistics

**Duration**: Configurable (default: 7 days)

**Gates**: Stability threshold met

### Stage: Retire

**Purpose**: Deprecate entity safely

**Requirements**:
- Migration path documented
- No active dependents
- Rollback capability

**Gates**: No active usage for retention period

## Runtime Lifecycle Detail

### Task States

| State | Description | Entry Conditions | Exit Conditions |
|-------|-------------|------------------|-----------------|
| Pending | Task created, waiting for scheduling | TaskContract valid | Resources available |
| Assigned | Agent selected and sandbox prepared | Agent matched | Sandbox ready |
| Running | Task executing in sandbox | Sandbox started | Task completed/error |
| Validating | Output being validated | Agent completed | Validation passed/failed |
| Succeeded | Task completed successfully | All validators pass | None (terminal) |
| Failed | Task failed irrecoverably | Validation failed + retries exhausted | None (terminal) |

### Workflow States

| State | Description |
|-------|-------------|
| Created | Workflow instance initialized |
| Running | Workflow actively progressing |
| Paused | Waiting for human input or external signal |
| Completed | All tasks succeeded |
| Failed | Workflow failed irrecoverably |
| Cancelled | Workflow cancelled by user |

### Artifact States

| State | Description |
|-------|-------------|
| Produced | Artifact created by agent |
| Validated | Structural validation passed |
| Accepted | Artifact accepted by workflow |
| Rejected | Artifact failed validation |
| Archived | Moved to long-term storage |

## Environment Promotion

### Standard Promotion Flow

```
Development → Staging → Production
```

Each promotion requires:
1. **Compatibility Check**: No breaking changes
2. **Test Validation**: Integration tests pass in target environment
3. **Approval Gates**: Required stakeholder approvals
4. **Rollout Plan**: Canary or phased deployment

### Promotion Policies

```yaml
PromotionPolicy:
  entity_type: string
  source_env: string
  target_env: string
  auto_promote: boolean (default: false)
  required_validators:
    - type: test_suite
      name: integration_tests
      must_pass: true
    - type: approval
      role: reviewer
      min_approvals: 1
    - type: cost_analysis
      max_budget_usd: decimal
  rollback_on_failure: boolean (default: true)
  retention_days: int (default: 30)
```

## Versioning Strategy

### Semantic Versioning Rules

| Change Type | Version Bump | Backward Compatibility |
|-------------|--------------|---------------------|
| Bug fix | PATCH | Yes |
| New optional field | PATCH | Yes |
| New required field | MINOR | Yes (opt-in) |
| Field removal/deprecation | MINOR | Yes (deprecation window) |
| Field type change | MAJOR | No |
| Breaking constraint change | MAJOR | No |

### Deprecation Windows

- **MINOR versions**: 3 months grace period
- **MAJOR versions**: N-1 version support mandatory
- **End of life notification**: 30 days before retirement

## Rollback Strategy

### Automatic Rollback Triggers

1. **Validation Failure Rate**: >5% failure rate in first hour
2. **Performance Degradation**: >20% slower than baseline
3. **Security Violation**: Any policy violation detected
4. **Cost overrun**: >150% of expected cost

### Rollback Process

```
1. Detect failure condition
2. Halt new deployments
3. Identify affected entities
4. Revert to previous version
5. Alert stakeholders
6. Capture incident report
```

## Relationships

- **All Entity Contracts**: Each defines its lifecycle applicability
- **Policy Contract**: Lifecycle policies are themselves governed
- **Audit Log**: All lifecycle transitions are logged
- **Environment Contract**: Production/staging differences