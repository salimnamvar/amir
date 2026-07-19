"""Artifact domain events."""

from .event_envelope import DomainEvent
from uuid import UUID


class ArtifactProduced(DomainEvent):
    """Emitted when artifact is produced by agent."""
    event_type: str = "artifact.produced"
    
    @classmethod
    def create(
        cls,
        artifact_id: UUID,
        task_id: UUID,
        contract_type: str,
        correlation_id: UUID
    ) -> "ArtifactProduced":
        return cls(
            aggregate_id=artifact_id,
            aggregate_type="Artifact",
            payload={
                "task_id": str(task_id),
                "contract_type": contract_type,
            },
            correlation_id=correlation_id,
            causation_id=correlation_id
        )


class ArtifactValidated(DomainEvent):
    """Emitted after artifact validation."""
    event_type: str = "artifact.validated"
    
    @classmethod
    def create(
        cls,
        artifact_id: UUID,
        valid: bool,
        errors: list[str] = None,
        correlation_id: UUID = None
    ) -> "ArtifactValidated":
        return cls(
            aggregate_id=artifact_id,
            aggregate_type="Artifact",
            payload={
                "valid": valid,
                "errors": errors or [],
            },
            correlation_id=correlation_id or UUID(int=0),
            causation_id=correlation_id or UUID(int=0)
        )


class ArtifactAccepted(DomainEvent):
    """Emitted when artifact is accepted."""
    event_type: str = "artifact.accepted"
    
    @classmethod
    def create(
        cls,
        artifact_id: UUID,
        correlation_id: UUID = None
    ) -> "ArtifactAccepted":
        return cls(
            aggregate_id=artifact_id,
            aggregate_type="Artifact",
            payload={},
            correlation_id=correlation_id or UUID(int=0),
            causation_id=correlation_id or UUID(int=0)
        )


class ArtifactRejected(DomainEvent):
    """Emitted when artifact is rejected."""
    event_type: str = "artifact.rejected"
    
    @classmethod
    def create(
        cls,
        artifact_id: UUID,
        errors: list[str],
        correlation_id: UUID = None
    ) -> "ArtifactRejected":
        return cls(
            aggregate_id=artifact_id,
            aggregate_type="Artifact",
            payload={"errors": errors},
            correlation_id=correlation_id or UUID(int=0),
            causation_id=correlation_id or UUID(int=0)
        )