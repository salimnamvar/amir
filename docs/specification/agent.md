# Agent Runtime

## Architecture Overview

The Agent Runtime executes external agents in isolated environments and extracts structured artifacts from their output.

```
┌─────────────────┐
│  Task Service   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ AgentSelector   │───→ AgentDefinition (read capability)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│Sandbox Manager  │───→ Creates isolated execution environment
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  AgentAdapter   │───→ Executes agent with contract
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ParseOutput Loop │───→ Extract → Validate → Feedback on failure
└─────────────────┘
```

## AgentAdapter Interface

```python
class AgentAdapter(ABC):
    """Abstract interface for agent execution."""
    
    @abstractmethod
    async def start_invocation(self, contract: AgentInvocationContract) -> None:
        """Spawn agent process. Must return immediately (non-blocking)."""
        pass
    
    @abstractmethod
    async def get_result(self, invocation_id: UUID, timeout: float = 30.0) -> dict:
        """Get execution result. Returns artifact content or error."""
        pass
    
    @abstractmethod
    async def cancel(self, invocation_id: UUID) -> None:
        """Cancel running invocation. Best-effort."""
        pass
    
    @abstractmethod
    def supports_contract(self, contract_type: str, version: str) -> bool:
        """Check if adapter supports given contract."""
        pass
```

## AgentInvocationContract

See `docs/contract/schemas/agent-invocation.schema.yaml` for machine-readable schema.

## LLM Output Extraction Pipeline

Converts unstructured LLM output into validated artifacts.

### Deterministic Extraction

```
LLM Output
    ↓
Strip markdown code blocks (```json...``` or ```yaml...```)
    ↓
Extract first valid JSON/YAML block
    ↓
Validate against Contract Schema
    ↓
If VALID: Accept artifact
If INVALID: Trigger feedback loop
```

**No regex fallback** - If structured extraction fails, the validation-failure feedback loop handles recovery.

## Validation-Failure → Re-Invocation Feedback Loop

Critical mechanism for handling agents that produce invalid artifacts.

### Behavior

```
1. AgentInvocation.Completed
2. Contract Validator runs structural validation
3. If INVALID:
   - Artifact.Rejected emitted with validation errors
   - Feedback Generator creates corrective prompt
   - Task.attempts incremented
   - If attempts < agent_definition.max_retry_attempts:
     - Create new AgentInvocation
     - Inject feedback: "Previous attempt failed: [errors]. Correct and resubmit."
     - Agent retries with full context
   - Else:
     - Task.Failed permanently emitted
4. If VALID:
   - Artifact.Validated emitted
   - Task.Completed
```

### Feedback Format

```yaml
feedback:
  type: object
  required: [validation_errors, attempt_number]
  properties:
    validation_errors:
      type: array
      items:
        type: string
      description: "List of validation errors from previous attempt"
    attempt_number:
      type: integer
      description: "Current retry attempt (1-indexed)"
    original_contract:
      type: object
      description: "Original task contract for reference"
```

## Sandbox Manager Interface

```python
class SandboxManager(ABC):
    """Interface for sandbox lifecycle management."""
    
    @abstractmethod
    async def create_sandbox(self, task_id: UUID, agent_id: UUID, resource_limits: dict) -> UUID:
        """Create isolated sandbox. Returns sandbox_id."""
        pass
    
    @abstractmethod
    async def destroy_sandbox(self, sandbox_id: UUID) -> None:
        """Destroy sandbox and cleanup resources."""
        pass
    
    @abstractmethod
    async def get_workspace_path(self, sandbox_id: UUID) -> str:
        """Get workspace path for sandbox."""
        pass
    
    @abstractmethod
    async def execute_in_sandbox(self, sandbox_id: UUID, command: list[str], timeout: int) -> tuple[int, str, str]:
        """Execute command. Returns (exit_code, stdout, stderr)."""
        pass
```

## Sandbox Requirements

### Runtime Support
- **Docker**: Default runtime with seccomp profile
- **gVisor**: Enhanced isolation for production
- **Firecracker**: MicroVMs for maximum security

### Security Mandates
- **Non-root execution**: MUST run as UID 65534 (nobody)
- **Read-only root**: Root filesystem MUST be read-only
- **Workspace isolation**: Writable tmpfs mounted at `/workspace` only
- **Network default-deny**: Only loopback allowed unless explicitly permitted

### Resource Limits
- **CPU**: Configurable cores limit
- **Memory**: Configurable limit with hard ceiling
- **PID limit**: Maximum processes enforceable

## Cost Control

### Hard Limits

Each Task has a cost budget enforced at adapter level.

```python
class CostEnforcer:
    def check_and_enforce(self, token_count: int, usd_cost: float) -> None:
        if token_count > task.max_tokens * 0.95:
            raise CostLimitExceeded("Token limit threshold reached")
        if usd_cost > task.max_usd * 0.95:
            raise CostLimitExceeded("USD limit threshold reached")
```

- **Threshold**: 95% of limit triggers kill switch
- **Enforcement**: Adapter kills process at threshold
- **Measurement**: Token counting during streaming

### Team Budgets

```yaml
budget:
  daily_usd: float
  monthly_tokens: int
  concurrent_tasks: int
  reservation_based: true
```

## Approval Model

### Binary Approval
All transitions use binary approval gates:
- **AUTO_APPROVE**: Workflow proceeds automatically
- **REJECTED**: Workflow blocked until manual intervention

### Manual Approval
For critical workflows, approval can be handled externally:
- External system monitors Workflow.ReviewRequired event
- External approver calls `workflow.approve(gate_name, approver_id)`

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| CLI output parsing | HIGH | Structured extraction + feedback loop |
| Sandbox escape | CRITICAL | Non-root containers + read-only root + tmpfs workspace |
| Contract drift | MEDIUM | Version pinning + adapter validation |
| Cost explosion | HIGH | Hard limits + 95% threshold kill |
| Workflow durability | HIGH | SQLite persistence on each state transition |

---

## Addressing Audit Concerns

### CLI Parsing Risk (All Audits)
No regex fallback. Structured extraction only. Failure triggers feedback loop.

### Sandbox Security (All Audits)
Mandatory non-root containers with read-only root filesystem. gVisor/Firecracker alternatives available.

### Adapter Protocol (DeepSeek)
All adapters use same JSON serialization via stdin or temp file. No webhook callbacks due to network isolation.

### Capability Matching (Mistral)
Weighted scoring algorithm with configurable thresholds. See Domain Model for full specification.