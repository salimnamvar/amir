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
- Supported output modes declared
- Agent appears in registry
```

### US-AGENT-002: Agent Executes Task
```
As an Agent
I want to receive TaskContract via stdin
So that I can perform work

Acceptance:
- AgentSession created with attempt_number=1
- Agent receives structured input
- Agent produces Artifact via workspace observation
- Checkpoints recorded at state transitions
```

### US-AGENT-003: Parse Agent Output
```
As Amir
I want to extract structured artifact from agent output
So that I can validate the result

Acceptance:
- Output parsed via ParserRegistry strategy chain
- Strategy order: structured_output → tool_call → markdown_block → workspace_observation → llm_coercion
- Artifact validated against schema
- Invalid output triggers feedback loop
```

### US-AGENT-004: Workspace Observation
```
As Amir
I want to derive artifacts from workspace state
So that agent claims are verified against ground truth

Acceptance:
- Baseline commit recorded before execution
- Current commit recorded after execution
- CodeChangeArtifact derived from git diff
- Agent's claimed changes compared with observed changes
```

### US-AGENT-005: Validation Feedback Loop
```
As Amir
I want to provide corrective feedback on invalid artifacts
So that agents can retry with context

Acceptance:
- ValidationResult emitted with structured error categories
- FeedbackArtifact created with corrections and suggestions
- Retry allowed within budget (max_attempts)
- Escalation to different agent after escalate_after failures
```

### US-AGENT-006: Agent Scorecard
```
As a Platform Operator
I want historical performance metrics for each agent
So that routing decisions are data-driven

Acceptance:
- AgentScorecard tracks success rate, cost, latency
- Circuit breaker quarantines after 5 consecutive failures
- Score feeds capability matching algorithm
- Scorecard updated after each AgentSession completes
```

### US-AGENT-007: Isolated Execution
```
As a Security Officer
I want agents in gVisor sandboxes
So that they can't escape isolation

Acceptance:
- gVisor runtime mandatory in production
- Docker available only in dev mode
- Container runs as UID 65534
- Root filesystem is read-only
- Only /workspace is writable
```

### US-AGENT-008: Hard Cost Limits
```
As a Platform Owner
I want token limits enforced at runtime
So that costs are predictable

Acceptance:
- Hierarchical cost gate (invocation → team-hourly → tenant-daily → org-monthly)
- Pre-flight cost estimation before execution
- Sidecar proxy counts tokens in real-time
- Process killed at 95% threshold
- CostRecord emitted with orchestration/worker separation
```

### US-AGENT-009: Agent Health Check
```
As a System
I want to verify agent health periodically
So that degraded agents are quarantined

Acceptance:
- Health check runs every 30s
- Failures trigger Degraded status
- 5 consecutive failures → Circuit Breaker opens
- Agent quarantined until manual reset or health check pass
```

### US-AGENT-010: Structured Output Negotiation
```
As an Adapter
I want to negotiate output mode with agents
So that parsing is reliable

Acceptance:
- Agent declares supported output modes
- Adapter selects best available mode
- Fallback chain per agent type
- Output mode recorded in AgentSession
```

### US-AGENT-011: Replay Metadata
```
As a Developer
I want to replay agent execution for debugging
So that I can reproduce issues

Acceptance:
- ReplayMetadata captured on every AgentSession
- Includes model_identifier, prompt_hash, full_prompt, seed
- Includes tool_calls and sandbox_profile_hash
- Replay endpoint reconstructs execution
```

### US-AGENT-012: Prompt Compiler
```
As Amir
I want to compile structured prompts from contracts
So that agent input is reproducible

Acceptance:
- CompiledPrompt artifact created per session
- Includes system_prompt, user_prompt, output_contract
- Template hash for reproducibility
- Stored for audit and replay
```

## Implementation Notes

- AgentSession replaces simple AgentInvocation as core runtime entity
- ParserRegistry with 5-strategy fallback chain (no single point of failure)
- Workspace observation as ground truth (artifacts from git diff, not agent claims)
- Circuit breaker per agent prevents cascading failures
- PromptCompiler renders structured prompts for reproducibility
- Non-gVisor containers blocked in production
