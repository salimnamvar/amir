"""Event Publisher Protocol - Interface for event emission."""

from abc import ABC
from abc import abstractmethod
from typing import Any


class EventPublisher(ABC):
    """Interface for publishing domain events.
    Enables audit trail and system integration.
    """

    @abstractmethod
    async def publish(self, event: Any) -> None:
        """Publish event to event store.
        Implementation may use file, database, or message queue.
        """

    @abstractmethod
    async def publish_batch(self, events: list[Any]) -> None:
        """Publish multiple events atomically."""
