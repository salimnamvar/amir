-- Contract: Security Context storage DDL
-- Authority: docs/contract/sql/security.sql
-- Related data contracts: access-policy, secret-binding schemas

CREATE TABLE access_policies (
    id UUID PRIMARY KEY,
    resource TEXT,
    action TEXT,
    subject TEXT,
    conditions JSONB,
    effect TEXT
);

CREATE TABLE secret_bindings (
    id UUID PRIMARY KEY,
    task_id UUID,
    session_id UUID,
    secret_name TEXT,
    secret_ref TEXT,
    injected_at TIMESTAMP,
    expires_at TIMESTAMP,
    access_method TEXT CHECK (access_method IN ('env', 'file', 'proxy')),
    access_path TEXT,
    single_use BOOLEAN DEFAULT FALSE,
    status TEXT CHECK (status IN ('active', 'used', 'expired', 'revoked')),
    created_by TEXT,
    revoked_at TIMESTAMP
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
