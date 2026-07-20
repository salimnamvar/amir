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
- Docker is structurally illegal when environment=production (JSON Schema if/then)
- Docker available only in development/staging
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
- All outbound through Amir proxy (or network_mode: none for offline tools)
- Default-deny allowlist; coding_standard profile expansion is fixed (registries listed in security.md)
- Effective allowlist = intersection of agent ∩ sandbox [∩ role if set]; never union
- mTLS to external services
- Token counting for cost attribution
- PII/secret scrubbing
- SecretBinding schema with TTL for ephemeral grants
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
I want linear hash-chained audit events
So that tampering is detectable

Acceptance:
- Events chained via prev_hash
- Each event signed with KMS/HSM platform key (signing_key_ref)
- Key rotation with dual-valid verification window
- Periodic root-commit to transparency log
- SandboxAttestation required per production session
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
- Kill switch at CostLease.kill_threshold_pct (default 95%; see cost-lease.schema.yaml)
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
- Linear hash-chained audit events for tamper-evidence
- TTL-based secret revocation
