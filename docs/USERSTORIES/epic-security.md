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

### US-SEC-002: Secrets Injection
```
As a System
I want JIT secret injection
So that secrets aren't leaked

Acceptance:
- Secrets mounted as tmpfs
- Secrets revoked after task completion
- No secrets in environment variables
```

### US-SEC-003: Audit Trail
```
As a Compliance Officer
I want all actions logged
So that I can investigate incidents

Acceptance:
- All state changes produce events
- Events stored append-only
- Hash chain verified for tampering
```

### US-SEC-004: Cost Limits
```
As a Financial Controller
I want hard cost limits
So that spending is bounded

Acceptance:
- Tasks have max_tokens and max_usd
- Limits enforced at adapter level
- Kill switch at 95% threshold
```

### US-SEC-005: Workspace Isolation
```
As a Security Officer
I want workspaces isolated
So that agents can't access other tasks

Acceptance:
- Each task gets unique workspace
- Git permissions scoped per task
- Symlink escape prevented
```

---

## Implementation Notes

- Security is enforced at Sandbox Manager level
- Secrets use Vault integration (Phase 2)
- MVP uses file-based append-only audit
- All security events are permanent retention