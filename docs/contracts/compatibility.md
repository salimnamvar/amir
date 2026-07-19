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

| Contract Type | Backward Compatibility | Breaking Changes |
|---------------|---------------------|-----------------|
| AgentContract | N-1 minor | Removed required field, changed field type, removed capability |
| TaskContract | N-1 minor | Changed objective format, removed role reference |
| ArtifactContract | N-1 minor | Schema structure change, required field removal |
| WorkflowContract | N-1 minor | Removed state, changed transition structure |
| RoleContract | N-1 minor | Changed inputs/outputs structure |
| TeamContract | N-1 minor | Changed budget/quota structure |

## Breaking Change Rules

### Prohibited (Requires MAJOR)

- Removing required fields
- Changing field types
- Removing contract types from outputs
- Removing capabilities from agent definitions
- Changing state machine structure

### Allowed (MINOR version)

- Adding optional fields
- Adding new contract types to outputs
- Adding new capabilities to agents
- Relaxing validation rules (optional → required NOT allowed)

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

### Task Assignment

Orchestrator finds compatible contract:

```python
def negotiate_contract(agent: AgentDefinition, task: Task) -> str:
    """Negotiate best compatible contract version."""
    required = task.expected_outputs[0]
    for supported in agent.supported_contracts:
        if supported.type == required:
            if version_satisfies(supported.version_range, required.version):
                return supported.version
    raise ContractNotCompatible()
```

## Migration Strategy

### Phase 1: Version Pinning

- All contracts pinned to specific versions in workflow definitions
- No automatic negotiation
- Simple deployment model

### Phase 2: N-1 Support

- Orchestrator uses highest compatible MINOR version
- Agents support N-1 versions
- Automatic rollback on validation failure

### Phase 3: Full Negotiation

- Semantic version ranges supported
- Fallback to lowest common denominator
- Canary deployment of new contract versions

## Deprecation Policy

### Deprecation Notice

When deprecating a contract:

1. Mark as `deprecated: true` in ContractDefinition
2. Add `deprecation_notice` field with migration guide
3. Maintain support for 6 months minimum

### End-of-Life

- **Phase 1**: Deprecation warning logged
- **Phase 2**: Tasks using deprecated contracts require explicit override
- **Phase 3**: Deprecated contracts rejected unless forced

## Contract Registry

The Contract Registry (Configuration Context) owns all contract definitions:

```
ContractRegistry
├── CodeChangeArtifact v1.0.0 (Published)
├── CodeChangeArtifact v1.1.0 (Published)
├── TestResultArtifact v1.0.0 (Published)
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
```

---

## Addressing Audit Concerns

### Contract Drift (Kimi)

Contract versioning is based on **Amir's expectations**, not agent output. Agent adapters must handle output format changes through parser versioning, not contract versioning.

### Semantic Validation Gap (DeepSeek)

Phase 1 implements structural validation only. Semantic validation (running tests, checking quality criteria) is Phase 2. The schema includes `quality_criteria` but these are informational in MVP.

### Schema Language (Kimi)

Using YAML Schema for human readability in GitOps. JSON Schema export available for tooling. CUE deferred to Phase 2.