# Agent Runtime

## Architecture Overview

The Agent Runtime is responsible for executing external agents in isolated environments and extracting structured artifacts from their output.

```
┌─────────────────┐
│  Task Service   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ AgentSelector   │───→ Configuration Context (read AgentDefinition)
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
│ParseOutput Loop │───→ Extract → Validate → Feedback (Phase 2)
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

```yaml
# Machine-readable contract for agent invocation
schema:
  type: object
  required: [task_id, agent_definition_id, contract, workspace]
  properties:
    task_id:
      type: string
      format: uuid
    agent_definition_id:
      type: string
      format: uuid
    contract:
      type: object
      required: [type, version, data]
      properties:
        type:
          type: string
        version:
          type: string
        data:
          type: object
    workspace:
      type: object
      required: [repo_url, branch, workdir]
      properties:
        repo_url:
          type: string
          format: uri
        branch:
          type: string
        workdir:
          type: string
    resource_limits:
      type: object
      properties:
        max_tokens:
          type: integer
          minimum: 1
        timeout_seconds:
          type: integer
          minimum: 1
        memory_mb:
          type: integer
```

## LLM Output Extraction Pipeline

**Critical for MVP reliability** - This pipeline converts unstructured LLM output into validated artifacts.

### Phase 1 (MVP): Deterministic Extraction

```
LLM Output
    ↓
Strip markdown code blocks (```json...``` or ```yaml...```)
    ↓
Extract first valid JSON/YAML block
    ↓
Validate against Contract Schema
    ↓
Reject if validation fails (no regex fallback)
```

**No regex fallback** - If structured extraction fails, invocation fails and triggers retry-with-feedback in Phase 2.

### Phase 2 (Planned): Retry with Feedback

```
LLM Output (Invalid)
    ↓
ParseOutput Pipeline (fails)
    ↓
Feedback Generator (creates corrective prompt)
    ↓
Retry with original context + error details
    ↓
LLM Output (Retry)
    ↓
ParseOutput Pipeline (retry max 2)
    ↓
Accept or Fail Permanently
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

### MVP (Phase 1)

- **Technology**: Docker with seccomp profile
- **Non-root**: MUST run as UID 65534 (nobody)
- **Root filesystem**: MUST be read-only
- **Workspace**: Writable tmpfs mounted at `/workspace`
- **Network**: Default-deny (only loopback)
- **Resources**: CPU/memory limits enforced

### Phase 2

- **Technology**: gVisor or Firecracker microVMs
- **Enhanced network**: Allowlist-based egress
- **File scanning**: Malware/secrret detection on workspace

### Phase 3

- **Technology**: Production-grade container security (gVisor + AppArmor)
- **Multi-region**: Geographically distributed sandboxes

## Cost Control

### Hard Limits (MVP)

Each Task has a cost budget enforced at adapter level:

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
- **Measurement**: Token counting during streaming (Phase 2)

### Team Budgets (Phase 2)

```yaml
BudgetLimits:
  daily_usd: float
  monthly_tokens: int
  concurrent_tasks: int
  reservation_based: true  # Allocate before execute
```

## Risk Register

| Risk | Severity | Mitigation | MVP Status |
|------|----------|------------|------------|
| CLI output parsing | HIGH | Structured output + deterministic extraction | ACCEPT |
| Sandbox escape | CRITICAL | Non-root containers + read-only root + tmpfs workspace | MITIGATE |
| Contract drift | MEDIUM | Version pinning + adapter validation | ACCEPT |
| Cost explosion | HIGH | Hard token/USD limits per task | MITIGATE |
| Temporal migration blockage | MEDIUM | Clean interface seam defined | ADDRESS |

---

## Validation-Failure → Re-Invocation Loop

This is the critical feedback mechanism for handling agents that produce invalid artifacts.

### MVP Behavior

```
1. AgentInvocation.Completed
2. Contract Validator runs structural validation
3. If INVALID:
   - AgentInvocation.Completed → AgentInvocation.Failed
   - Task.Failed emitted
   - No retry (Phase 1 limitation)
4. If VALID:
   - Artifact.Validated emitted
   - Task.Completed
```

### Phase 2 Behavior

```
1. AgentInvocation.Completed
2. Contract Validator runs structural validation
3. If INVALID:
   - Artifact.Rejected emitted
   - Feedback Generator creates corrective prompt
   - Task.attempts incremented
   - If attempts < max_attempts:
     - Create new AgentInvocation
     - Inject feedback into prompt: "Previous attempt failed: [validation errors]"
     - Agent retries with context
   - Else:
     - Task.Failed permanently
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

---

## Addressing Audit Concerns

### CLI Parsing Risk (All Audits)

MVP does NOT use regex fallback. Structured extraction only. If extraction fails, task fails. Retry-with-feedback is Phase 2.

### Sandbox Security (Kimi, GLM)

MVP requires non-root containers with read-only root filesystem. This is a hard requirement, not recommendation.

### Adapter Protocol (DeepSeek)

All adapters use same JSON serialization via stdin or temp file. No webhook callbacks (sandboxes are network-isolated).

### Capability Matching (Mistral)

Weighted scoring algorithm implemented. See Domain Model section for specification.