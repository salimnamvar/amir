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


> **Contract:** [`docs/contract/schemas/access-policy.schema.yaml`](../contract/schemas/access-policy.schema.yaml)


### Pluggable Policy Engine

Static AllowDeny rules are the default. OPA/Rego available as extension:


> **Contract:** [`docs/contract/schemas/policy-engine.schema.yaml`](../contract/schemas/policy-engine.schema.yaml)


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


> **Contract:** [`docs/contract/schemas/sandbox.schema.yaml`](../contract/schemas/sandbox.schema.yaml)


### network_mode: host REMOVED

The `host` network mode has been eliminated. All outbound traffic routes through the Amir egress proxy. This prevents:
- Prompt-injected agents from scanning internal networks
- Data exfiltration via unrestricted outbound connections
- Cost evasion via direct API calls to LLM providers

### Egress Proxy

All agent network traffic routes through the Amir egress proxy:


> **Contract:** [`docs/contract/schemas/egress-proxy.schema.yaml`](../contract/schemas/egress-proxy.schema.yaml)


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

> **Contract:** [`docs/contract/schemas/secret-binding.schema.yaml`](../contract/schemas/secret-binding.schema.yaml)

SecretBroker fetches from vault, creates bindings with TTL, mounts via tmpfs/proxy, and revokes on session end. Storage: [`sql/security.sql`](../contract/sql/security.sql).


### Runtime Attestation

> **Contract:** [`docs/contract/schemas/sandbox-attestation.schema.yaml`](../contract/schemas/sandbox-attestation.schema.yaml)


### Platform Key Lifecycle

| Event | Behavior |
|-------|----------|
| Generation | Keys created in KMS/HSM; only public material leaves the HSM |
| Rotation | New key becomes primary; previous_key_ref remains valid for verification window |
| Signing | Attestations and Merkle roots use current primary key |
| Compromise | Mark key revoked; stop signing; historical events verify with known public keys |
| Audit | All key ops emit AuditEvents |

### Network Default Allowlists

- `network_mode: proxy` is required for cloud LLM CLIs.
- `network_mode: none` is only for offline/local tools (no provider API).
- Empty allowlist = **deny-all** except platform-injected LLM provider routes for cost attribution.
- Security evaluates SandboxPolicy; Execution owns the Workspace aggregate.

### Network Allowlist Profile Expansion

Profiles expand **before** merge. Expansion is fixed by Configuration Context (platform registry); implementers MUST NOT invent ad-hoc domain sets.

| Profile | Expansion |
|---------|-----------|
| `llm_only` | Platform-managed LLM provider routes only (injected by egress for cost attribution; not editable by agents) |
| `coding_standard` | `llm_only` ∪ package registries: `pypi.org`, `files.pythonhosted.org`, `registry.npmjs.org`, `registry.yarnpkg.com`, `proxy.golang.org`, `sum.golang.org`, `crates.io`, `static.crates.io`, `rubygems.org`, `repo.maven.apache.org`, `index.crates.io` |
| `custom` | Use `network_allowlist` as-is (no preset expansion); still subject to merge below |

Platform may extend the coding_standard registry via configuration with audit trail; tenants cannot broaden beyond SandboxPolicy ceiling.

### Network Allowlist Merge Algorithm

The effective network allowlist is computed as an **intersection** (never union, never override-by-most-specific-alone):

```
1. Expand profile → profile_domains
2. agent_set   = AgentDefinition.security_profile.network_allowlist
                 ∪ profile_domains from AgentDefinition.default_network_allowlist_profile
3. sandbox_set = SandboxPolicy.network_allowlist
                 ∪ profile_domains from SandboxPolicy.network_allowlist_profile
4. role_set    = Role.required_network (if empty, treat as "no additional role constraint"
                 — i.e. do not zero the intersection; skip role layer when unset)
5. effective_allowlist = agent_set ∩ sandbox_set [∩ role_set if role_set non-empty]
6. Always ∪ platform LLM routes (for metered provider access when network_mode=proxy)
```

Principles:
1. **Intersection only** — no layer can grant a destination another layer denies
2. Security policies can only **narrow**, never broaden, access relative to agent declaration
3. Empty agent or sandbox allowlist (after profile expansion of `custom` with `[]`) = deny-all except platform LLM routes
4. Workspace.security_context.network_allowlist **records** the computed effective list; it is not an independent authority

---

## Audit Trail

### Verifiable Audit Log

Events are Merkle-chained for tamper-evidence:


> **Contract:** [`docs/contract/schemas/domain-event.schema.yaml`](../contract/schemas/domain-event.schema.yaml)


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
ParserRegistry with 4-strategy fallback chain (structured_output → tool_call → markdown_block → workspace_observation). Workspace observation as ground truth. LLM coercion requires explicit human approval + observation_method=synthesized.

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
