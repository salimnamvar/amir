"""Agent invocation domain events."""

from uuid import UUID

from .event_envelope import DomainEvent


class AgentStarted(DomainEvent):
    """Emitted when agent invocation starts."""

    event_type: str = "agent.started"

    @classmethod
    def create(cls, invocation_id: UUID, task_id: UUID, agent_id: UUID, correlation_id: UUID) -> "AgentStarted":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "invocation_id": str(invocation_id),
                "agent_id": str(agent_id),
            },
            correlation_id=correlation_id,
            causation_id=correlation_id,
        )


class AgentCompleted(DomainEvent):
    """Emitted when agent invocation completes."""

    event_type: str = "agent.completed"

    @classmethod
    def create(
        cls, invocation_id: UUID, task_id: UUID, artifact_id: UUID, resource_usage: dict, correlation_id: UUID
    ) -> "AgentCompleted":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "invocation_id": str(invocation_id),
                "artifact_id": str(artifact_id),
                "resource_usage": resource_usage,
            },
            correlation_id=correlation_id,
            causation_id=correlation_id,
        )


class AgentFailed(DomainEvent):
    """Emitted when agent invocation fails."""

    event_type: str = "agent.failed"

    @classmethod
    def create(
        cls, invocation_id: UUID, task_id: UUID, error: str, error_code: str = None, correlation_id: UUID = None
    ) -> "AgentFailed":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "invocation_id": str(invocation_id),
                "error": error,
                "error_code": error_code,
            },
            correlation_id=correlation_id or UUID(int=0),
            causation_id=correlation_id or UUID(int=0),
        )


class AgentTimedOut(DomainEvent):
    """Emitted when agent invocation times out."""

    event_type: str = "agent.timeout"

    @classmethod
    def create(
        cls, invocation_id: UUID, task_id: UUID, timeout_seconds: int, correlation_id: UUID = None
    ) -> "AgentTimedOut":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "invocation_id": str(invocation_id),
                "timeout_seconds": timeout_seconds,
            },
            correlation_id=correlation_id or UUID(int=0),
            causation_id=correlation_id or UUID(int=0),
        )


class AgentCancelled(DomainEvent):
    """Emitted when agent invocation is cancelled."""

    event_type: str = "agent.cancelled"

    @classmethod
    def create(cls, invocation_id: UUID, task_id: UUID, correlation_id: UUID = None) -> "AgentCancelled":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={"invocation_id": str(invocation_id)},
            correlation_id=correlation_id or UUID(int=0),
            causation_id=correlation_id or UUID(int=0),
        )
