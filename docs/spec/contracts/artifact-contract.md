# Artifact Contract

## Purpose

The Artifact Contract defines structured data types for agent outputs. Artifacts are the immutable, versioned records of what agents produce. They enable auditability, replay, and validation of agent work.

## Schema

```yaml
ArtifactContract:
  type: artifact-contract
  version: string (semantic version)
  artifact:
    type: string (unique type identifier, e.g., "CodeChangeArtifact")
    description: string
    schema:
      # JSON Schema or Protobuf definition
      type: object
      properties: {}
      required: []
  provenance:
    required_fields:
      - producer_agent_id
      - session_id
      - timestamp
      - contract_version_used
      - checksum
  validation_rules:
    - field: string
      rule: string
      message: string
    - custom_validator: string (reference to validation function)
  retention:
    ttl: duration (optional)
    long_term_storage: boolean (default: true)
  relationships:
    - kind: parent
      type: artifact-contract-type
    - kind: child
      type: artifact-contract-type
  metadata:
    created_at: timestamp
    owner: string
```

## Built-in Artifact Types

### CodeChangeArtifact

Represents code modifications with context and risk assessment.

```yaml
type: CodeChangeArtifact
changes:
  - file_path: string
    operation: enum [create, modify, delete, rename]
    diff: string
    lines_added: int
    lines_removed: int
  - file_path: string
    operation: enum [modify]
    new_content: string
tests:
  - file_path: string
    operation: enum [create, modify, delete]
    test_type: enum [unit, integration, e2e]
risks:
  - category: enum [security, performance, compatibility, migration]
    description: string
    severity: enum [low, medium, high, critical]
    mitigation: string
validation:
  - check: "api_compatibility"
    status: enum [passed, failed, skipped]
    details: string
```

### TestResultArtifact

Represents test execution results for quality validation.

```yaml
type: TestResultArtifact
test_suite: string
results:
  total_tests: int
  passed: int
  failed: int
  skipped: int
  errors: int
coverage:
  percentage: float
  by_file:
    - file_path: string
      percentage: float
failures:
  - test_name: string
    error_message: string
    stack_trace: string
    file: string
    line: int
duration_seconds: int
exit_code: int
```

### DesignSpecArtifact

Represents architectural decisions and design specifications.

```yaml
type: DesignSpecArtifact
specification:
  problem_statement: string
  proposed_solution: string
  alternatives_considered:
    - option: string
      pros: [string]
      cons: [string]
      selected: boolean
modules_affected: [string]
interfaces_changed:
  - module: string
    interface: string
    before: string
    after: string
diagram: string (mermaid or similar)
decisions:
  - component: string
    decision: string
    rationale: string
```

### ReviewFeedbackArtifact

Represents code review feedback with actionable items.

```yaml
type: ReviewFeedbackArtifact
review_target:
  artifact_id: string
  artifact_type: string
findings:
  - severity: enum [critical, high, medium, low, info]
    category: enum [correctness, style, performance, security, maintainability]
    file: string
    line: int (optional)
    description: string
    suggestion: string
  - severity: enum [medium]
    category: enum [documentation]
    description: "Missing docstring for public function"
actions_required:
  - type: enum [fix, investigate, explain]
    priority: enum [p0, p1, p2]
    description: string
summary:
  approval_status: enum [approved, changes_requested, rejected]
  overall_score: float (0-100)
  recommendation: string
```

### RiskAssessmentArtifact

Represents identified risks and their mitigations.

```yaml
type: RiskAssessmentArtifact
risks:
  - id: string
    category: enum [security, data_loss, performance, availability, compliance]
    severity: enum [low, medium, high, critical]
    probability: enum [low, medium, high]
    description: string
    impact: string
    mitigation: string
    owner: string
    due_date: date
  - id: "RISK-001"
    category: security
    severity: high
    probability: medium
    description: "Authentication bypass in refactored module"
    impact: "Unauthorized access to user data"
    mitigation: "Add integration test for auth flow"
    owner: "security-team"
risk_score: float
recommendation: string
```

## Invariants

1. **Provenance Required**: All artifacts must include provenance metadata
2. **Checksum Integrity**: Content checksum must match actual content
3. **Timestamp Validity**: All timestamps must be reasonable and monotonic
4. **Schema Compliance**: Artifact content must match defined schema
5. **Size Limits**: Artifacts must not exceed platform size limits

## Lifecycle

| State | Description |
|-------|-------------|
| Produced | Artifact created by agent |
| Validated | Schema and semantic validation passed |
| Accepted | Artifact accepted into workflow |
| Rejected | Artifact failed validation |
| Archived | Artifact moved to long-term storage |

## Validation Rules

### Structural Validation
1. **Schema Check**: Must conform to JSON Schema/Protobuf
2. **Required Fields**: All required fields must be present
3. **Type Coercion**: Field types must match specification

### Semantic Validation
1. **Cross-Field Consistency**: Related fields must agree
2. **Business Rules**: Domain-specific rules must be satisfied
3. **Reference Integrity**: Linked artifacts must exist

### Security Validation
1. **Secret Leakage**: No API keys, passwords, or tokens
2. **Code Injection**: No malicious code patterns
3. **Path Traversal**: File paths must be safe

## Relationships

- **Task Contract**: Tasks specify expected output artifact types
- **Workflow Contract**: Workflows sequence artifact production
- **Artifact Contract**: Parent/child relationships for lineage
- **Role Contract**: Roles declare artifact production capabilities