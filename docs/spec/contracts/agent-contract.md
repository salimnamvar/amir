# Agent Contract

## Purpose

The Agent Contract defines how Amir communicates with external execution agents. It specifies the capabilities an agent provides, how it should be invoked, and what output format to expect. This contract ensures vendor-agnostic agent integration through the adapter pattern.

## Schema

```yaml
AgentContract:
  type: agent-contract
  version: string (semantic version, e.g., "1.0.0")
  agent:
    id: string (UUID)
    name: string
    adapter_type: enum [cli, mcp, api, remote]
    adapter_config:
      # CLI-specific
      binary_path: string (optional)
      working_directory: string (optional)
      
      # API/MCP-specific
      endpoint: string (optional)
      protocol: enum [http, grpc, mcp] (optional)
      
      # Authentication (never in Git, injected at runtime)
      auth_method: enum [none, token, oauth, mtls]
  capabilities:
    - skill: string
      proficiency: enum [novice, intermediate, expert]
      languages: [string]
      tools:
        - name: string
          available: boolean
          constraints: {max_calls: int, rate_limit: int}
  resource_limits:
    max_context_tokens: int (default: 100000)
    max_output_tokens: int (default: 8000)
    timeout_seconds: int (default: 3600)
    memory_limit_mb: int (optional)
    cpu_limit_cores: float (optional)
  security_profile:
    sandbox_required: boolean (default: true)
    network_access: enum [none, limited, full] (default: limited)
    allowed_endpoints: [string] (for network_access=limited)
    privileged_actions: [string] (list of allowed sudo-escalation actions)
  metadata:
    vendor: string
    version: string
    created_at: timestamp
    updated_at: timestamp
```

## Invariants

1. **Mandatory Sandbox**: If `sandbox_required: true`, the agent MUST execute in an isolated environment
2. **Capability Declaration**: All declared capabilities MUST be validated during registration
3. **Resource Limits**: Execution MUST NOT exceed declared resource limits
4. **Security Boundaries**: Network and filesystem access MUST respect security profile
5. **Version Compatibility**: The `version` field determines compatibility with contracts

## Lifecycle

| State | Description | Trigger |
|-------|-------------|---------|
| Draft | Contract being defined | Initial creation |
| Validating | Capabilities being tested | CI validation |
| Published | Available for use | Merge to main branch |
| Deprecated | No longer recommended | New major version published |
| Retired | No longer available | Migration complete |

## Validation Rules

1. **Schema Validation**: Contract must conform to this specification
2. **Capability Tests**: Each declared capability must be verified through test tasks
3. **Security Scan**: Adapter code must pass security review before publishing
4. **Compatibility Check**: New version must maintain backward compatibility (same major version)

## Examples

### Claude Code CLI Adapter

```yaml
type: agent-contract
version: "1.2.0"
agent:
  id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  name: "claude-code"
  adapter_type: cli
  adapter_config:
    binary_path: "/usr/local/bin/claude"
    auth_method: token
capabilities:
  - skill: refactoring
    proficiency: expert
    languages: [python, javascript, typescript, go]
    tools:
      - name: file_read
        available: true
      - name: file_write
        available: true
        constraints: {max_calls: 100}
      - name: bash
        available: true
        constraints: {rate_limit: 10}
  - skill: code_generation
    proficiency: expert
    languages: [python, javascript, typescript, go, rust]
    tools: []
resource_limits:
  max_context_tokens: 200000
  max_output_tokens: 4000
  timeout_seconds: 1800
  memory_limit_mb: 2048
security_profile:
  sandbox_required: true
  network_access: limited
  allowed_endpoints: ["api.anthropic.com"]
metadata:
  vendor: "Anthropic"
  version: "Claude-3.5"
  created_at: "2026-07-19T00:00:00Z"
```

### MCP Server Agent

```yaml
type: agent-contract
version: "1.0.0"
agent:
  id: "mcp-001"
  name: "mcp-code-assistant"
  adapter_type: mcp
  adapter_config:
    endpoint: "stdio://mcp-server"
    protocol: mcp
capabilities:
  - skill: code_review
    proficiency: expert
    languages: [all]
    tools:
      - name: read_file
        available: true
      - name: create_comment
        available: true
resource_limits:
  max_context_tokens: 100000
  max_output_tokens: 2000
security_profile:
  sandbox_required: true
  network_access: none
```

## Events Produced

- Agent.Registered
- Agent.HealthChecked
- Agent.CapabilityValidated
- Agent.Quarantined

---

## Agent Invocation Contract

For runtime execution, agents receive this contract:

```yaml
AgentInvocationContract:
  invocation_id: string (UUID)
  task_id: string
  contract_type: string (which contract to process)
  input_payload: object (contract content)
  execution_parameters:
    timeout_seconds: int
    max_tokens: int
    streaming_mode: boolean
  callbacks:
    - on_progress: string (Webhook URL or queue name)
    - on_complete: string
    - on_error: string
    - on_cancel: string
  workspace:
    repository_url: string
    branch: string
    workdir: string
```

### Invocation Response

```yaml
AgentInvocationResponse:
  status: enum [success, failed, timeout, cancelled]
  output: object (artifact content)
  error: string (if failed)
  resource_usage:
    tokens_consumed: int
    duration_seconds: int
    memory_peak_mb: int
  output_streams:
    - type: stdout
      content: string
    - type: stderr
      content: string
```