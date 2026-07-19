# Epic: Agent Runtime

## As a Developer
- I want to register my agent with capabilities
- So that tasks are routed to me

## As a Security Officer
- I want agents to run in isolation
- So that malicious code can't escape

## User Stories

### US-AGENT-001: Register Agent
```
As an Agent Owner
I want to POST /agents with adapter config
So that Amir can invoke my agent

Acceptance:
- AgentDefinition created with DRAFT status
- Adapter config validated
- Agent appears in registry
```

### US-AGENT-002: Agent Executes Task
```
As an Agent
I want to receive TaskContract via stdin
So that I can perform work

Acceptance:
- AgentAdapter.start_invocation called
- Agent receives structured input
- Agent produces Artifact on stdout
```

### US-AGENT-003: Parse Agent Output
```
As Amir
I want to extract structured artifact from agent output
So that I can validate the result

Acceptance:
- Output parsed deterministically (no regex)
- Artifact validated against schema
- Invalid output rejected immediately
```

### US-AGENT-004: Isolated Execution
```
As a Security Officer
I want agents in non-root containers
So that they can't escalate privileges

Acceptance:
- Docker container runs as UID 65534
- Root filesystem is read-only
- Only /workspace is writable
```

### US-AGENT-005: Hard Cost Limits
```
As a Platform Owner
I want token limits enforced at runtime
So that costs are predictable

Acceptance:
- Token counter ticks during execution
- Process killed at 95% threshold
- ResourceUsage recorded on completion
```

### US-AGENT-006: Agent Health Check
```
As a System
I want to verify agent health periodically
So that degraded agents are quarantined

Acceptance:
- Health check runs every 30s
- Failures trigger Degraded status
- 5 consecutive failures → Quarantined
```

---

## Implementation Notes

- Non-root containers required (not optional)
- LLM output extraction has no regex fallback
- Cost limits enforced synchronously at adapter
- Health checks are best-effort (no SLA)