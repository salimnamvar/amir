-- Contract: Outbox / event publish storage DDL
-- Authority: docs/contract/sql/outbox.sql
-- Related data contracts: domain-event.schema.yaml, outbox-entry.schema.yaml
--
-- Linear hash chain (per aggregate_id): serialize inserts with row-level lock
-- on the aggregate or partition by aggregate_id. sequence + prev_hash form a
-- linear chain, not a Merkle tree.

CREATE TABLE outbox_entries (
    sequence BIGSERIAL PRIMARY KEY,
    event_id UUID NOT NULL UNIQUE,  -- correlates to DomainEvent.event_id
    event_type TEXT NOT NULL,
    aggregate_id UUID NOT NULL,
    aggregate_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    prev_hash TEXT,  -- SHA256 of previous event for this aggregate_id; null for first
    chain_sequence INTEGER NOT NULL DEFAULT 0,  -- monotonic per aggregate_id
    idempotency_key TEXT UNIQUE,
    retention_policy_id TEXT,  -- e.g. permanent, 365d, 90d
    created_at TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP,
    delivery_status TEXT DEFAULT 'pending'
);

CREATE INDEX idx_outbox_pending ON outbox_entries(delivery_status, created_at)
    WHERE delivery_status = 'pending';

CREATE INDEX idx_outbox_aggregate_chain ON outbox_entries(aggregate_id, chain_sequence);
