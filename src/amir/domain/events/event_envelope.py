"""Domain Event Envelope - Standard event structure for all events."""

from pydantic import BaseModel, Field
from uuid import UUID, uuid4
from datetime import datetime


class DomainEvent(BaseModel):
    """
    Standard envelope for all domain events.
    Enables distributed tracing, replay, and debugging.
    """
    event_id: UUID = Field(default_factory=uuid4)
    event_type: str
    aggregate_id: UUID
    aggregate_type: str
    correlation_id: UUID = Field(default_factory=uuid4)
    causation_id: UUID  # ID of event that caused this one
    producer: str = "amir"
    version: str = "1.0.0"
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    payload: dict = Field(default_factory=dict)