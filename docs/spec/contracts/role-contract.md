# Role Contract

## Purpose

The Role Contract defines the responsibilities, permissions, and expected outputs for a particular role within an AI team. It serves as the "job description" that agents fulfill when assigned to perform tasks.

## Schema

```yaml
RoleContract:
  type: role-contract
  version: string (semantic version)
  role:
    id: string (UUID)
    name: string (e.g., "developer", "architect", "reviewer")
    description: string
  responsibility: string (natural language description of primary duty)
  inputs:
    - contract_type: string (reference to expected input contract)
      required: boolean
      description: string
  outputs:
    - contract_type: string (reference to expected output contract)
      required: boolean
      description: string
  allowed_actions:
    - action_verb: string (e.g., "file_read", "file_write", "run_tests", "create_pr")
      scope: enum [read_only, read_write, admin]
      constraints:
        max_calls: int (optional)
        rate_limit_per_minute: int (optional)
  quality_criteria:
    - metric: string (e.g., "test_pass_rate", "code_coverage")
      threshold: value
      operator: enum [gt, gte, lt, lte, eq]
      required: boolean
  constraints:
    - rule: string (constraint name)
      value: any (constraint value)
  required_capabilities:
    - skill: string
      minimum_proficiency: enum [novice, intermediate, expert]
  metadata:
    created_by: string
    created_at: timestamp
    updated_at: timestamp
```

## Invariants

1. **Input/Output Completeness**: Role must specify at least one input and one output
2. **Action Safety**: Allowed actions must respect security boundaries
3. **Quality Thresholds**: Quality criteria must be machine-evaluable
4. **Capability Alignment**: Required capabilities must match declared outputs
5. **Single Write Responsibility**: For concurrent tasks, roles should declare file write ownership boundaries

## Lifecycle

| State | Description |
|-------|-------------|
| Draft | Role definition being created |
| Published | Available for task assignment |
| Deprecated | Superseded by newer version |

## Validation Rules

1. **Schema Validation**: Must conform to contract specification
2. **Capability Feasibility**: Required capabilities must be achievable by at least one registered agent
3. **Action Consistency**: Allowed actions must support required outputs
4. **Quality Verifiability**: Each quality criterion must have an automated validator

## Examples

### Developer Role

```yaml
type: role-contract
version: "1.0.0"
role:
  id: "dev-role-001"
  name: "developer"
  description: "Implements code changes based on design specifications"
responsibility: "Refactor, extend, and implement code modules while maintaining quality standards"
inputs:
  - contract_type: RepositoryContext
    required: true
  - contract_type: DesignSpec
    required: true
  - contract_type: TaskSpec
    required: false
outputs:
  - contract_type: CodeChangeArtifact
    required: true
  - contract_type: TestResultArtifact
    required: true
allowed_actions:
  - action_verb: file_read
    scope: read_only
  - action_verb: file_write
    scope: read_write
    constraints:
      max_calls: 1000
  - action_verb: run_tests
    scope: read_write
    constraints:
      rate_limit_per_minute: 10
  - action_verb: create_pr
    scope: admin
quality_criteria:
  - metric: test_pass_rate
    threshold: 1.0
    operator: gte
    required: true
  - metric: code_coverage
    threshold: 0.8
    operator: gte
    required: true
constraints:
  - rule: follow_solid
    value: true
  - rule: preserve_api
    value: true
required_capabilities:
  - skill: refactoring
    minimum_proficiency: intermediate
  - skill: code_generation
    minimum_proficiency: expert
```

### Architect Role

```yaml
type: role-contract
version: "1.0.0"
role:
  id: "arch-role-001"
  name: "architect"
  description: "Designs system architecture and reviews technical decisions"
responsibility: "Analyze requirements, design module structure, and define interfaces"
inputs:
  - contract_type: RequirementsSpec
    required: true
outputs:
  - contract_type: DesignSpec
    required: true
  - contract_type: RiskAssessmentArtifact
    required: true
allowed_actions:
  - action_verb: file_read
    scope: read_only
  - action_verb: analyze_code
    scope: read_only
quality_criteria:
  - metric: design_completeness
    threshold: 0.95
    operator: gte
constraints:
  - rule: consider_security
    value: true
required_capabilities:
  - skill: architecture_analysis
    minimum_proficiency: expert
```

### Reviewer Role

```yaml
type: role-contract
version: "1.0.0"
role:
  id: "rev-role-001"
  name: "reviewer"
  description: "Reviews code changes for quality, correctness, and compliance"
responsibility: "Examine code changes and provide feedback on improvements"
inputs:
  - contract_type: CodeChangeArtifact
    required: true
  - contract_type: RepositoryContext
    required: true
outputs:
  - contract_type: ReviewFeedbackArtifact
    required: true
allowed_actions:
  - action_verb: file_read
    scope: read_only
  - action_verb: create_comment
    scope: read_write
quality_criteria:
  - metric: review_quality_score
    threshold: 0.8
    operator: gte
constraints:
  - rule: check_security
    value: true
  - rule: check_performance
    value: true
required_capabilities:
  - skill: code_review
    minimum_proficiency: expert
```

## Relationships

- **AgentCapability**: Role's `required_capabilities` must match agent's `capabilities`
- **TaskContract**: Task references role by name; role contract validates task assignment
- **PolicyContract**: Role execution subject to team policies