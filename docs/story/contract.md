# Epic: Contracts

## As a Developer
- I want to define contracts for artifacts
- So that agent outputs are predictable

## As a Security Officer
- I want all artifacts validated
- So that malicious output is rejected

## User Stories

### US-CONTRACT-001: Define Artifact Contract
```
As a Developer
I want to define JSON Schema for artifacts
So that agents produce structured output

Acceptance:
- ContractDefinition in Git
- Schema validates artifact structure
- Contract published and versioned
```

### US-CONTRACT-002: Validate Artifact Structure
```
As Amir
I want to validate all artifacts structurally
So that invalid output is rejected

Acceptance:
- Artifact validated before acceptance
- Invalid artifacts emit Artifact.Rejected
- Valid artifacts emit Artifact.Validated
- ValidationResult includes error categories
```

### US-CONTRACT-003: Negotiate Contract Versions
```
As a System
I want compatible contract negotiation
So that agents and tasks interoperate

Acceptance:
- Assignment pipeline: hard filter → score → negotiate top-down
- Contract negotiation is post-score with fallback to next agent
- Agent receives correct schema version
- MatchingDecision records negotiation outcome
- No silent compatibility errors at runtime
```

### US-CONTRACT-004: Contract Backward Compatibility
```
As a Developer
I want contracts to evolve safely
So that upgrades do not break existing workflows

Acceptance:
- MINOR versions add optional fields
- MAJOR versions break compatibility
- N-1 compatibility maintained
```

### US-CONTRACT-005: Contract Registry
```
As a System
I want central contract registry
So that all contracts are versioned

Acceptance:
- All contracts under docs/contract/schemas/ (see docs/contract/README.md catalog)
- SemVer enforced on all changes
- Compatibility matrix maintained
- New contract types registered
```

### US-CONTRACT-006: Semantic Validation
```
As a Platform Operator
I want semantic validation of artifacts
So that structural validity is not sufficient

Acceptance:
- Pluggable validator architecture
- Validators have timeout and budget
- Test execution validator available
- Quality criteria validator available
```

### US-CONTRACT-007: Feedback Contracts
```
As Amir
I want structured feedback for invalid artifacts
So that agents can retry with context

Acceptance:
- FeedbackArtifact contract defined
- Includes error_context, corrections, feedback_strategy
- Includes parser strategy suggestion
- Feedback injected into PromptCompiler
```

## Implementation Notes
- YAML Schema for human readability
- JSON Schema export for tooling
- N-1 minor version compatibility
- Structural validation runs first
- Semantic validation available as pluggable layer
- FeedbackArtifact drives the retry loop
