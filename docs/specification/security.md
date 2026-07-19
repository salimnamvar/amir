# Security Model

## Security Principles

### Zero Trust Execution

Every agent runs in complete isolation with:
- No access to Amir infrastructure
- No shared filesystem between runs
- All outbound traffic through egress proxy (host mode eliminated)
- Secrets injected just-in-time via tmpfs, never stored
- Runtime attestation for sandbox integrity

### Defense in Depth

```
┌─────────────────────────────────────────────┐
│  API Gateway                                │
│  - TLS termination                          │
│  - Rate limiting                            │
│  - Request validation                       │
├─────────────────────────────────────────────┤
│  Authorization Layer                        │
│  - JWT/OAuth validation                     │
│  - RBAC/ABAC enforcement                    │
│  - Pluggable policy engine (OPA optional)   │
├─────────────────────────────────────────────┤
│  Cost Gate                                  │
│  - Budget/quota checks                      │
│  - Pre-flight cost estimation               │
│  - Reservation protocol                     │
├─────────────────────────────────────────────┤
│  Capability Matcher                         │
│  - Scored agent selection                   │
│  - Circuit breaker quarantine               │
│  - AgentScorecard verification              │
├─────────────────────────────────────────────┤
│  Egress Proxy                               │
│  - Domain allowlist                         │
│  - mTLS to external services                │
│  - Token counting for cost attribution      │
│  - PII/secret scrubbing                     │
├─────────────────────────────────────────────┤
│  Sandbox Manager                            │
│  - gVisor/Firecracker isolation (mandatory) │
│  - Workspace isolation                      │
│  - Secret injection via tmpfs               │
│  - Runtime attestation                      │
└─────────────────────────────────────────────┘
```

## Access Control

### Authentication

- **API Access**: JWT tokens with HS256/RS256 signing
- **Agent Registration**: API key with scoped permissions
- **Service-to-Service**: mTLS between control plane components
- **Agent → Egress Proxy**: Scoped API keys injected via tmpfs

### Authorization

```python
class AccessPolicy(BaseModel):
    """Static or dynamic policy definition."""
    id: UUID
    resource: str
    action: str
    subject: str
    effect: str  # allow | deny
    conditions: dict = {}  # Optional conditions
```

### Pluggable Policy Engine

Static AllowDeny rules are the default. OPA/Rego available as extension:

```yaml
PolicyEngine:
  type: object
  properties:
    engine_type:
      type: string
      enum: [static, opa]
      default: "static"
    rules_path:
      type: string
      description: "Path to OPA/Rego rules (if engine_type=opa)"
    evaluation_timeout_ms:
      type: integer
      default: 100
```

Policy evaluation occurs at:
- Task assignment (can this agent handle this task?)
- Workflow transition (can this state move to next state?)
- Secret access (should this task see these secrets?)
- Network access (should this agent reach this endpoint?)

## Sandboxing

### Mandatory Runtime Requirements

| Environment | Required Runtime | Rationale |
|------------|-----------------|-----------|
| Production | gVisor (default) or Firecracker | Kernel-level isolation |
| Development | Docker (with seccomp) | Convenience, not security |
| Maximum Security | Firecracker | MicroVM isolation |

### Sandbox Configuration

```yaml
SandboxConfig:
  runtime: string  # gvisor (default) | firecracker | docker (dev only)
  user: 65534      # non-root (MUST)
  read_only_root: true  # (MUST)
  tmpfs_workspaces: true
  network_mode: string  # proxy (default) | none
  network_allowlist: list[string]
  resource_limits:
    cpus: float
    memory: string
    pids_limit: int
  security_profile: string  # baseline | hardened
  attestation:
    enabled: bool
    signing_key_ref: string
```

### network_mode: host REMOVED

The `host` network mode has been eliminated. All outbound traffic routes through the Amir egress proxy. This prevents:
- Prompt-injected agents from scanning internal networks
- Data exfiltration via unrestricted outbound connections
- Cost evasion via direct API calls to LLM providers

### Egress Proxy

All agent network traffic routes through the Amir egress proxy:

```yaml
EgressProxy:
  type: object
  properties:
    listen_address:
      type: string
      default: "127.0.0.1:8443"
    tls:
      enabled: boolean
      ca_ref: string
    domain_allowlist:
      type: array
      items:
        type: string
      description: "Allowed outbound domains (CIDR for IPs)"
    token_counting:
      enabled: boolean
      description: "Count tokens for cost attribution"
    secret_scrubbing:
      enabled: boolean
      description: "Scrub PII/secrets from outbound traffic"
    audit_logging:
      enabled: boolean
      description: "Log all outbound requests"
```

### Agent API Key Routing

Agent API keys (for LLM providers) are injected via tmpfs and routed through the proxy:

```
Agent process
    ↓ (env var: OPENAI_BASE_URL=http://127.0.0.1:8443/v1)
    ↓ (env var: OPENAI_API_KEY=<tmpfs-injected>)
Egress Proxy
    ↓ (mTLS to api.openai.com)
    ↓ (token counting)
    ↓ (audit logging)
LLM Provider
```

### Sandbox Manager Responsibilities

1. Create sandbox with isolated workspace (gVisor mandatory in production)
2. Inject secrets via tmpfs (memory-only)
3. Inject API keys via tmpfs (routed through egress proxy)
4. Execute commands in controlled environment
5. Enforce resource limits (CPU, memory, time)
6. Provide runtime attestation (signed sandbox state)
7. Destroy sandbox and cleanup all resources

### Workspace Isolation

- Each task gets unique workspace directory
- Git repository cloned to isolated branch
- `.git` directory restricted
- Symbolic link escape prevented via mount options
- Baseline commit recorded before agent execution
- Current commit recorded after agent execution

### Secret Injection

```python
class SecretBroker:
    """Just-in-time secret injection."""
    
    async def inject_for_task(self, task: Task) -> SecretBindings:
        """Fetch secrets from vault and prepare for sandbox."""
        secrets = await self.vault.fetch(task.secret_paths)
        bindings = SecretBindings(
            task_id=task.id,
            secrets=secrets,
            ttl=task.resource_limits.timeout_seconds
        )
        return bindings
    
    def mount_in_sandbox(self, sandbox_id: UUID, bindings: SecretBindings) -> None:
        """Mount secrets as tmpfs in sandbox."""
        # Write to memory-only filesystem
        # Secrets available at /secrets/<name>
        # Automatically cleaned on sandbox destroy
        # TTL-based revocation
```

### Runtime Attestation

Sandbox integrity verified via signed attestation:

```yaml
SandboxAttestation:
  type: object
  properties:
    sandbox_id:
      type: string
      format: uuid
    runtime:
      type: string
    image_hash:
      type: string
      description: "SHA256 of container image"
    rootfs_hash:
      type: string
      description: "SHA256 of root filesystem"
    started_at:
      type: string
      format: date-time
    attestation_signature:
      type: string
      description: "Cryptographic signature over sandbox state"
    signing_key_ref:
      type: string
      description: "Reference to signing key"
```

---

## Audit Trail

### Verifiable Audit Log

Events are Merkle-chained for tamper-evidence:

```yaml
VerifiableAuditEvent:
  type: object
  required: [event_id, timestamp, sequence, prev_hash]
  properties:
    event_id:
      type: string
      format: uuid
    timestamp:
      type: string
      format: date-time
    sequence:
      type: integer
      description: "Monotonically increasing sequence number"
    prev_hash:
      type: string
      description: "SHA256 of previous event (hash chain)"
    event_type:
      type: string
    aggregate_id:
      type: string
      format: uuid
    payload:
      type: object
    signature:
      type: string
      description: "Cryptographic signature over event"
    algorithm:
      type: string
      description: "Signature algorithm (e.g., ECDSA-P256)"
    key_ref:
      type: string
      description: "Reference to signing key"
```

### Tamper-Evidence Mechanism

1. Each event includes `prev_hash` (hash of previous event)
2. Each event is signed with platform signing key
3. Periodic root-commit to external transparency log
4. Verification: recompute hash chain, verify signatures

### Retention Policies

| Event Type | Retention | Storage |
|------------|-----------|---------|
| Access.Denied | Permanent | Object Storage (WORM) |
| Secret.Accessed | 90 days | PostgreSQL |
| Sandbox.Created | 90 days | PostgreSQL |
| Sandbox.Destroyed | Permanent | Object Storage |
| Compensation.Executed | Permanent | Object Storage |
| Cost.Recorded | 365 days | PostgreSQL |
| Audit.* | Permanent | Object Storage (WORM) |

---

## Threat Model

| Threat | Severity | Mitigation |
|--------|----------|------------|
| Sandbox escape | CRITICAL | Mandatory gVisor/Firecracker, non-root, read-only root |
| Prompt injection | HIGH | Structured contract prompts, no free-form strings |
| Secrets leakage | HIGH | JIT injection, tmpfs, auto-revocation, TTL |
| Network exfiltration | CRITICAL | Egress proxy mandatory, host mode eliminated |
| Filesystem traversal | HIGH | Workspace isolation, symlink protection |
| Artifact tampering | MEDIUM | SHA256 checksums, provenance tracking |
| Cost explosion | HIGH | Hierarchical cost gate with reservation protocol |
| Agent impersonation | MEDIUM | AgentScorecard, capability verification |
| Audit tampering | MEDIUM | Merkle-chained events, external transparency log |
| Agent-to-agent escape | HIGH | Separate sandboxes, no shared filesystem |

---

## Addressing Audit Concerns

### CLI Parsing Reliability (All 17 Audits)
ParserRegistry with 5-strategy fallback chain. Workspace observation as ground truth. LLM coercion as last resort.

### Agent Non-Determinism (All 17 Audits)
AgentSession with full checkpointing and replay metadata. Circuit breaker prevents cascading failures.

### Feedback Loop (All 17 Audits)
Structured ValidationResult with error categories. Budgeted retry with escalation path.

### Capability Routing (All 17 Audits)
Multi-dimensional scoring with historical AgentScorecard. Circuit breaker penalizes failing agents.

### Cost Enforcement (All 17 Audits)
Hierarchical cost gate with reservation protocol. Pre-flight estimation. Sidecar proxy for real-time enforcement.

### Workspace Observation (Tinker/Qwen)
Artifacts derived from git diff, not agent claims. Synthetic artifact generation when parsing fails completely.

### Egress Control (Gemini/Qwen)
Mandatory egress proxy. All traffic audited and token-counted. No host networking.
