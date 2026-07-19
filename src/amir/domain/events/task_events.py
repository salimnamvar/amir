"""Task domain events."""

from uuid import UUID

from .event_envelope import DomainEvent


class TaskCreated(DomainEvent):
    """Emitted when task is created."""

    event_type: str = "task.created"

    @classmethod
    def create(cls, task_id: UUID, objective: str, role: str, correlation_id: UUID = None) -> "TaskCreated":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "objective": objective,
                "role": role,
            },
            correlation_id=correlation_id or UUID(int=0),
        )


class TaskAssigned(DomainEvent):
    """Emitted when task is assigned to agent."""

    event_type: str = "task.assigned"

    @classmethod
    def create(cls, task_id: UUID, agent_id: UUID, role: str, correlation_id: UUID) -> "TaskAssigned":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "agent_id": str(agent_id),
                "role": role,
            },
            correlation_id=correlation_id,
            causation_id=correlation_id,
        )


class TaskStarted(DomainEvent):
    """Emitted when agent starts executing task."""

    event_type: str = "task.started"

    @classmethod
    def create(cls, task_id: UUID, invocation_id: UUID, correlation_id: UUID) -> "TaskStarted":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "invocation_id": str(invocation_id),
            },
            correlation_id=correlation_id,
            causation_id=correlation_id,
        )


class TaskCompleted(DomainEvent):
    """Emitted when task completes successfully."""

    event_type: str = "task.completed"

    @classmethod
    def create(
        cls, task_id: UUID, artifact_ids: list[UUID], duration_seconds: float, correlation_id: UUID
    ) -> "TaskCompleted":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "artifact_ids": [str(a) for a in artifact_ids],
                "duration_seconds": duration_seconds,
            },
            correlation_id=correlation_id,
            causation_id=correlation_id,
        )


class TaskFailed(DomainEvent):
    """Emitted when task fails."""

    event_type: str = "task.failed"

    @classmethod
    def create(cls, task_id: UUID, error: str, attempts: int, correlation_id: UUID) -> "TaskFailed":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={
                "error": error,
                "attempts": attempts,
            },
            correlation_id=correlation_id,
            causation_id=correlation_id,
        )


class TaskCancelled(DomainEvent):
    """Emitted when task is cancelled."""

    event_type: str = "task.cancelled"

    @classmethod
    def create(cls, task_id: UUID, reason: str = None, correlation_id: UUID = None) -> "TaskCancelled":
        return cls(
            aggregate_id=task_id,
            aggregate_type="Task",
            payload={"reason": reason} if reason else {},
            correlation_id=correlation_id or UUID(int=0),
        )
