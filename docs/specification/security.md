# Security Model

## Security Principles

### Zero Trust Execution

Every agent runs in complete isolation with:
- No access to Amir infrastructure
- No shared filesystem between runs
- Network connectivity explicitly whitelisted
- Secrets injected just-in-time, never stored

### Defense in Depth

```
┌─────────────────────────────────────────────┐
│  API Gateway                                │
│  - TLS termination                          │
│  - Rate limiting                            │
├─────────────────────────────────────────────┤
│  Authorization Layer                        │
│  - JWT/OAuth validation                     │
│  - RBAC/ABAC enforcement                    │
├─────────────────────────────────────────────┤
│  Resource Manager                           │
│  - Budget/quota checks                      │
│  - Capability matching                      │
├─────────────────────────────────────────────┤
│  Sandbox Manager                            │
│  - Container/VM isolation                   │
│  - Workspace isolation                      │
│  - Secret injection                         │
└─────────────────────────────────────────────┘
```

## Access Control

### Authentication

- **API Access**: JWT tokens with HS256/RS256 signing
- **Agent Registration**: API key with scoped permissions
- **Service-to-Service**: mTLS between control plane components

### Authorization

```python
class AccessPolicy(BaseModel):
    """RBAC/ABAC policy definition."""
    id: UUID
    resource: str           # team:*, task:*, etc.
    action: str             # create, read, update, delete, execute
    subject: str            # user:*, team:*, role:*
    condition: dict | None  # ABAC conditions
    effect: str             # allow | deny
```

### Multi-Tenancy (Phase 2)

- **Isolation**: Row-level security in PostgreSQL
- **Namespaces**: Team-scoped resource naming
- **Quotas**: Team-level budget and concurrency limits

## Sandboxing

### Sandbox Configuration (MVP)

```yaml
# Docker-based sandbox for MVP
SandboxConfig:
  runtime: docker
  user: "65534"  # non-root
  read_only_root: true
  tmpfs_workspaces: true
  network_mode: "none"  # Phase 1, or "restricted" with allowlist
  resource_limits:
    cpus: float
    memory: string  # e.g., "2g"
    pids_limit: 100
```

### Sandbox Manager Responsibilities

1. **Create sandbox** with isolated workspace
2. **Inject secrets** via tmpfs (memory-only filesystem)
3. **Execute commands** in controlled environment
4. **Enforce resource limits** (CPU, memory, time)
5. **Destroy sandbox** and cleanup all resources

### Workspace Isolation

- Each task gets unique workspace directory
- Git repository cloned to isolated branch
- `.git` directory restricted (no credential leakage)
- Symbolic link escape prevented via mount options

### Secret Injection

```python
class SecretBroker:
    """Just-in-time secret injection."""
    
    async def inject_for_task(self, task: Task) -> dict:
        """Fetch secrets from vault and prepare for sandbox."""
        secrets = {}
        for secret_ref in task.required_secrets:
            secret = await vault.get(secret_ref.path)
            secrets[secret_ref.name] = secret.value
        return secrets
    
    def mount_in_sandbox(self, sandbox_id: UUID, secrets: dict) -> None:
        """Mount secrets as tmpfs in sandbox."""
        # Write to memory-only filesystem
        # Secrets available at /secrets/<name>
        # Automatically cleaned on sandbox destroy
```

## Audit Trail

### Event Chain Integrity

All security-relevant events are logged:

```python
class AuditEvent(BaseModel):
    """Immutable security event."""
    event_id: UUID
    event_type: str        # e.g., "Secret.Accessed", "Sandbox.Created"
    aggregate_id: UUID
    aggregate_type: str
    correlation_id: UUID
    causation_id: UUID
    principal: str         # Who performed action
    action: str
    resource: str
    timestamp: datetime
    signature: str | None  # Optional cryptographic signature
```

### Retention Policies

| Event Type | Retention | Storage |
|------------|-----------|---------|
| Access.Denied | Permanent | Object Storage (WORM) |
| Secret.Accessed | 90 days | PostgreSQL |
| Sandbox.Created | 90 days | PostgreSQL |
| Sandbox.Destroyed | Permanent | Object Storage |

### MVP Implementation

- **Storage**: Append-only JSONL file
- **Location**: `/var/log/amir/audit.log`
- **Permissions**: 0644, owned by amir user
- **Rotation**: Daily rotation, compressed after 7 days

## Threat Model

| Threat | Severity | Mitigation |
|--------|----------|------------|
| Sandbox escape | CRITICAL | Non-root containers, read-only root, gVisor/Firecracker roadmap |
| Prompt injection | HIGH | Structured contract prompts, no shell interpretation |
| Secrets leakage | HIGH | JIT injection, tmpfs, auto-revocation |
| Filesystem traversal | HIGH | Workspace isolation, symlink protection |
| Network exfiltration | HIGH | Default-deny network, allowlist egress |
| Artifact tampering | MEDIUM | SHA256 checksums, provenance tracking |
| Cost explosion | HIGH | Hard token/USD limits, enforced at adapter |

---

## Addressing Audit Concerns

### Prompt Injection (Kimi)

All agent prompts are constructed from structured contracts, not free-form strings. The Prompt Compiler renders contracts deterministically.

### Sandbox Escape (GLM)

MVP requires non-root containers with read-only root filesystem. This is a hard requirement, not recommendation.

### Secret Injection Detail (DeepSeek)

Secrets injected via tmpfs (memory-only), not environment variables. This addresses the "LLM echoing secrets" concern.

### Audit Immutability (GLM)

MVP uses append-only file logging. Hash chaining deferred to Phase 2 to keep MVP simple.