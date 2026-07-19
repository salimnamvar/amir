-- Contract: Outbox / event publish storage DDL
-- Authority: docs/contract/sql/outbox.sql
-- Related data contracts: domain-event.schema.yaml, outbox-entry.schema.yaml

CREATE TABLE outbox_entries (
    sequence SERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    aggregate_id UUID NOT NULL,
    aggregate_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP,
    delivery_status TEXT DEFAULT 'pending'
);

CREATE INDEX idx_outbox_pending ON outbox_entries(delivery_status, created_at)
    WHERE delivery_status = 'pending';
