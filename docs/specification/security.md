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
    """Static or dynamic policy definition."""
    id: UUID
    resource: str
    action: str
    subject: str
    effect: str  # allow | deny
```

## Sandboxing

### Sandbox Configuration

```yaml
SandboxConfig:
  runtime: string  # docker (default) | gvisor | firecracker
  user: 65534      # non-root (MUST)
  read_only_root: true  # (MUST for docker)
  tmpfs_workspaces: true
  network_mode: string  # none (default) | restricted | host
  network_allowlist: list[string]
  resource_limits:
    cpus: float
    memory: string
    pids_limit: int
```

### Sandbox Manager Responsibilities

1. Create sandbox with isolated workspace
2. Inject secrets via tmpfs (memory-only)
3. Execute commands in controlled environment
4. Enforce resource limits (CPU, memory, time)
5. Destroy sandbox and cleanup all resources

### Workspace Isolation

- Each task gets unique workspace directory
- Git repository cloned to isolated branch
- `.git` directory restricted
- Symbolic link escape prevented via mount options

### Secret Injection

```python
class SecretBroker:
    """Just-in-time secret injection."""
    
    async def inject_for_task(self, task: Task) -> dict:
        """Fetch secrets from vault and prepare for sandbox."""
        pass
    
    def mount_in_sandbox(self, sandbox_id: UUID, secrets: dict) -> None:
        """Mount secrets as tmpfs in sandbox."""
        # Write to memory-only filesystem
        # Secrets available at /secrets/<name>
        # Automatically cleaned on sandbox destroy
```

---

## Audit Trail

### Event Chain Integrity

All security-relevant events are logged with cryptographic signatures.

```python
class AuditEvent(BaseModel):
    """Immutable security event."""
    event_id: UUID
    event_type: str
    aggregate_id: UUID
    aggregate_type: str
    correlation_id: UUID
    causation_id: UUID
    principal: str
    action: str
    resource: str
    timestamp: datetime
    signature: str  # Required for integrity
```

### Retention Policies

| Event Type | Retention | Storage |
|------------|-----------|---------|
| Access.Denied | Permanent | Object Storage (WORM) |
| Secret.Accessed | 90 days | PostgreSQL |
| Sandbox.Created | 90 days | PostgreSQL |
| Sandbox.Destroyed | Permanent | Object Storage |

---

## Threat Model

| Threat | Severity | Mitigation |
|--------|----------|------------|
| Sandbox escape | CRITICAL | Non-root containers, read-only root, gVisor/Firecracker |
| Prompt injection | HIGH | Structured contract prompts |
| Secrets leakage | HIGH | JIT injection, tmpfs, auto-revocation |
| Filesystem traversal | HIGH | Workspace isolation, symlink protection |
| Network exfiltration | HIGH | Default-deny network, allowlist egress |
| Artifact tampering | MEDIUM | SHA256 checksums, provenance tracking |
| Cost explosion | HIGH | Hard token/USD limits, 95% threshold kill |

---

## Addressing Audit Concerns

### Prompt Injection (All Audits)
All agent prompts are constructed from structured contracts, not free-form strings.

### Sandbox Escape (All Audits)
Mandatory non-root containers with read-only root filesystem. gVisor/Firecracker provided as hardened alternatives.

### Secret Injection (All Audits)
Secrets injected via tmpfs (memory-only), not environment variables.

### Audit Immutability (All Audits)
Append-only event store with cryptographic signature per event.