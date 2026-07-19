"""Domain Event Envelope - Standard event structure for all events."""

from datetime import datetime
from uuid import UUID
from uuid import uuid4

from pydantic import BaseModel
from pydantic import Field


class DomainEvent(BaseModel):
    """Standard envelope for all domain events.
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
