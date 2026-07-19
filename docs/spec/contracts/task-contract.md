# Task Contract

## Purpose

The Task Contract defines a unit of work to be performed by an agent in a specific role. It specifies the objective, required inputs, expected outputs, constraints, and success criteria. Tasks are the fundamental executable units in Amir's workflow system.

## Schema

```yaml
TaskContract:
  type: task-contract
  version: string (semantic version)
  task:
    id: string (UUID)
    title: string
    objective: string (natural language description)
    description: string (detailed requirements)
    assigned_role: string (reference to RoleContract)
    workflow_id: string (optional, for workflow tasks)
  inputs:
    - artifact_reference: string (artifact ID for CodeChangeArtifact, etc.)
      description: string
    - context_reference: string (repository context, environment)
      description: string
  outputs:
    - expected_contract: string (contract type, e.g., CodeChangeArtifact)
      required: boolean
      validation_mode: enum [schema_only, semantic, full]
  constraints:
    - rule: string (e.g., "follow_solid", "add_tests", "preserve_api")
      value: any
  dependencies:
    - task_id: string
      type: enum [hard, soft]
      output_contract: string (optional, which output must be available)
  priority: int (1-10, default: 5)
  deadline: timestamp (optional)
  cost_budget:
    max_tokens: int
    max_usd: decimal
  retry_policy:
    max_attempts: int (default: 3)
    backoff_strategy: enum [none, linear, exponential]
    backoff_base_seconds: int (optional)
    retry_on:
      - enum [validation_failure, timeout, agent_error, test_failure]
  quality_gates:
    - metric: string
      threshold: value
      operator: enum [gt, gte, lt, lte, eq]
      required: boolean
  metadata:
    created_by: string
    created_at: timestamp
    labels: [string]
    parent_task: string (optional)
```

## Invariants

1. **Role Assignment**: The assigned role must exist and have required capabilities
2. **Input Availability**: All required inputs must be available before task execution
3. **Budget Constraints**: Cost budget must be positive and within team limits
4. **Dependency Closure**: Hard dependencies must resolve before execution
5. **Priority Bounds**: Priority must be between 1 and 10

## Lifecycle

| State | Description | Trigger |
|-------|-------------|---------|
| Pending | Task created, waiting for resources | Initial creation |
| Assigned | Agent selected for execution | Orchestration |
| Running | Task actively being processed | Sandbox started |
| Validating | Output being validated against contract | Agent completed |
| Completed | Task successfully finished | All validations pass |
| Failed | Task failed irrecoverably | Error + retry exhausted |
| Cancelled | Task cancelled by user | Cancel command |

## Validation Rules

### Pre-Execution
1. **Schema Validation**: Contract structure must be valid
2. **Role Capability Match**: Required role must exist with capability coverage
3. **Dependency Resolution**: Hard dependencies must be satisfied
4. **Budget Check**: Cost budget must be available

### Post-Execution
1. **Output Schema**: Must match expected contract type
2. **Quality Gates**: All required metrics must meet thresholds
3. **Constraint Compliance**: All constraints must be satisfied
4. **Security Scan**: No secrets leaked, no forbidden patterns

## Examples

### Refactoring Task

```yaml
type: task-contract
version: "1.0.0"
task:
  id: "task-refactor-auth-001"
  title: "Refactor Authentication Module"
  objective: "Extract authentication logic into a separate repository layer"
  description: "The auth module is tightly coupled with route handlers. Extract into repository pattern with unit tests."
  assigned_role: developer
  workflow_id: "wf-software-delivery-001"
inputs:
  - context_reference: "repo-context-123"
    description: "Current repository state at main branch"
  - artifact_reference: "design-spec-456"
    description: "Architecture decision record"
outputs:
  - expected_contract: CodeChangeArtifact
    required: true
    validation_mode: full
constraints:
  - rule: follow_solid
    value: true
  - rule: add_tests
    value: true
  - rule: preserve_api_compatibility
    value: true
dependencies:
  - task_id: "task-architecture-review-001"
    type: hard
    output_contract: DesignSpec
priority: 7
deadline: "2026-07-20T17:00:00Z"
cost_budget:
  max_tokens: 100000
  max_usd: 5.00
retry_policy:
  max_attempts: 3
  backoff_strategy: exponential
  backoff_base_seconds: 60
quality_gates:
  - metric: test_pass_rate
    threshold: 1.0
    operator: gte
    required: true
  - metric: code_coverage
    threshold: 0.85
    operator: gte
    required: true
metadata:
  created_by: "user-alice"
  created_at: "2026-07-19T10:00:00Z"
  labels: ["refactoring", "backend"]
```

### Bug Fix Task

```yaml
type: task-contract
version: "1.0.0"
task:
  id: "task-bugfix-001"
  title: "Fix User Login Timeout"
  objective: "Resolve intermittent login timeout errors"
  description: "Users occasionally experience 504 errors during login. Investigate and fix the race condition."
  assigned_role: developer
inputs:
  - context_reference: "repo-context-789"
    description: "Repository with latest main"
outputs:
  - expected_contract: CodeChangeArtifact
    required: true
    validation_mode: semantic
  - expected_contract: TestResultArtifact
    required: true
constraints:
  - rule: preserve_api_compatibility
    value: true
priority: 9
cost_budget:
  max_tokens: 50000
  max_usd: 2.00
quality_gates:
  - metric: test_pass_rate
    threshold: 1.0
    operator: gte
    required: true
  - metric: no_new_errors
    threshold: true
    operator: eq
    required: true
metadata:
  labels: ["bugfix", "critical"]
```

## Relationships

- **Role Contract**: Task assigned to specific role
- **Workflow Contract**: Task may be part of workflow
- **Artifact Contract**: Task consumes and produces artifacts
- **Agent Contract**: Task executed by specific agent in role