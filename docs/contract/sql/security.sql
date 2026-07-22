-- Contract: Security Context storage DDL
-- Authority: docs/contract/sql/security.sql
-- Related data contracts: access-policy, secret-binding, sandbox-policy, sandbox-attestation schemas

CREATE TABLE access_policies (
    id UUID PRIMARY KEY,
    resource TEXT,
    action TEXT,
    subject TEXT,
    conditions JSONB,
    effect TEXT
);

CREATE TABLE sandbox_policies (
    policy_id UUID PRIMARY KEY,
    agent_definition_id UUID NOT NULL,
    task_id UUID,
    role_name TEXT,
    environment TEXT NOT NULL,
    merge_algorithm TEXT NOT NULL DEFAULT 'intersection',
    effective_network_allowlist JSONB NOT NULL,
    effective_allowlist_hash TEXT,
    network_mode TEXT NOT NULL,
    allowed_runtime JSONB,
    admission_decision TEXT NOT NULL,  -- allow|deny
    deny_reason TEXT,
    inputs JSONB,
    security_signature TEXT,
    evaluated_at TIMESTAMP NOT NULL
);

CREATE TABLE sandbox_attestations (
    attestation_id UUID PRIMARY KEY,
    session_id UUID NOT NULL,
    sandbox_id UUID NOT NULL,
    task_id UUID,
    runtime TEXT NOT NULL,  -- gvisor|firecracker (production)
    image_hash TEXT NOT NULL,
    sandbox_profile_hash TEXT NOT NULL,
    network_mode TEXT,
    attestation_signature TEXT NOT NULL,
    signing_key_ref TEXT NOT NULL,
    key_status TEXT DEFAULT 'active',
    previous_key_ref TEXT,
    attested_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL
);

CREATE TABLE secret_bindings (
    id UUID PRIMARY KEY,
    idempotency_key TEXT UNIQUE NOT NULL,
    task_id UUID,
    session_id UUID,
    sandbox_attestation_id UUID NOT NULL,  -- required: attestation before injection
    secrets_hash TEXT,
    secret_name TEXT,
    secret_ref TEXT,
    injected_at TIMESTAMP,
    valid_from TIMESTAMP,
    expires_at TIMESTAMP,
    access_method TEXT CHECK (access_method IN ('env', 'file', 'proxy')),
    access_path TEXT,
    single_use BOOLEAN DEFAULT FALSE,
    status TEXT CHECK (status IN ('active', 'used', 'expired', 'revoked')),
    consumed_at TIMESTAMP,
    consumer_session_id UUID,
    consumption_signature TEXT,
    consumer_pubkey_ref TEXT,
    created_by TEXT,
    revoked_at TIMESTAMP,
    -- P0-SECRET-BINDING-LIFECYCLE: status=used requires consumed_at, consumer_session_id, consumption_signature
    -- P0-SECRET-BINDING-LIFECYCLE: expired/revoked cannot become active
    CHECK (
      status IS DISTINCT FROM 'used'
      OR (consumed_at IS NOT NULL AND consumer_session_id IS NOT NULL AND consumption_signature IS NOT NULL)
    ),
    CHECK (
      status IS DISTINCT FROM 'active'
      OR expires_at > injected_at
    ),
    CHECK (
      expires_at IS NOT NULL AND expires_at > NOW()
      OR status IN ('used', 'revoked')
    )
);

-- P0-SANDBOX-DDL: Sandboxes table DDL for security aggregate
CREATE TABLE sandboxes (
    sandbox_id UUID PRIMARY KEY,
    runtime TEXT NOT NULL CHECK (runtime IN ('gvisor', 'firecracker', 'docker')),
    environment TEXT NOT NULL CHECK (environment IN ('development', 'staging', 'production')),
    network_mode TEXT NOT NULL CHECK (network_mode IN ('proxy', 'none')),
    user_id INTEGER DEFAULT 65534,
    read_only_root BOOLEAN DEFAULT TRUE,
    tmpfs_workspaces BOOLEAN DEFAULT TRUE,
    network_allowlist JSONB,
    network_allowlist_profile TEXT,
    security_profile TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    -- P0-SANDBOX-RUNTIME-AUTHORITY: docker illegal in production
    CHECK (
      environment IS DISTINCT FROM 'production'
      OR runtime IN ('gvisor', 'firecracker')
    )
);

CREATE TABLE egress_log (
    id SERIAL PRIMARY KEY,
    session_id UUID,
    destination TEXT,
    method TEXT,
    status_code INTEGER,
    tokens_counted INTEGER,
    cost_usd DECIMAL,
    logged_at TIMESTAMP
);
