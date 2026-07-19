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
```

### US-CONTRACT-003: Negotiate Contract Versions
```
As a System
I want compatible contract negotiation
So that agents and tasks interoperate

Acceptance:
- Task finds compatible contract version
- Agent receives correct schema version
- No compatibility errors at runtime
```

### US-CONTRACT-004: Contract Backward Compatibility
```
As a Developer
I want contracts to evolve safely
So that upgrades don't break existing workflows

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
- All contracts in amir-config/contracts/
- SemVer enforced on all changes
- Compatibility matrix maintained
```

---

## Implementation Notes

- YAML Schema for human readability
- JSON Schema export for tooling
- N-1 minor version compatibility
- Validation runs before artifact acceptance