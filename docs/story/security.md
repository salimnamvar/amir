# Epic: Security

## As a Security Officer
- I want all agents isolated
- So that malicious code can't damage the system

## As a Compliance Officer
- I want full audit trails
- So that all actions are traceable

## User Stories

### US-SEC-001: Non-Root Containers
```
As a Security Officer
I want agents to run as non-root
So that privilege escalation is impossible

Acceptance:
- All containers run as UID 65534
- Root filesystem is read-only
- Only tmpfs workspace is writable
```

### US-SEC-002: Mandatory gVisor
```
As a Security Officer
I want production sandboxes to use gVisor
So that kernel-level isolation is enforced

Acceptance:
- gVisor is default runtime in production
- Docker available only in dev mode
- Firecracker available for maximum security
- Runtime verified via attestation
```

### US-SEC-003: Mandatory Egress Proxy
```
As a Security Officer
I want all agent traffic through egress proxy
So that data exfiltration is prevented

Acceptance:
- network_mode: host eliminated
- All outbound through Amir proxy
- Domain allowlist enforced
- mTLS to external services
- Token counting for cost attribution
- PII/secret scrubbing
```

### US-SEC-004: Secrets Injection
```
As a System
I want JIT secret injection
So that secrets are not leaked

Acceptance:
- Secrets mounted as tmpfs
- API keys routed through egress proxy
- Secrets revoked after task completion (TTL)
- No secrets in environment variables
```

### US-SEC-005: Verifiable Audit Trail
```
As a Compliance Officer
I want Merkle-chained audit events
So that tampering is detectable

Acceptance:
- Events chained via prev_hash
- Each event signed with platform key
- Periodic root-commit to transparency log
- Verification endpoint available
```

### US-SEC-006: Cost Limits
```
As a Financial Controller
I want hard cost limits
So that spending is bounded

Acceptance:
- Hierarchical cost gate (4 levels)
- Pre-flight estimation
- Reservation protocol for concurrent tasks
- Kill switch at 95% threshold
```

### US-SEC-007: Workspace Isolation
```
As a Security Officer
I want workspaces isolated
So that agents cannot access other tasks

Acceptance:
- Each task gets unique workspace
- Git permissions scoped per task
- Symlink escape prevented
- Baseline commit tracked
```

### US-SEC-008: Runtime Attestation
```
As a Security Officer
I want sandbox integrity verification
So that tampered sandboxes are detected

Acceptance:
- Sandbox state signed at creation
- Image hash verified
- Attestation signature verified
- Tampered sandboxes rejected
```

## Implementation Notes
- Security is enforced at Sandbox Manager level
- gVisor mandatory in production; Docker dev-only
- Egress proxy mandatory; host networking eliminated
- Merkle-chained audit events for tamper-evidence
- TTL-based secret revocation
