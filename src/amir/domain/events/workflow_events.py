"""Workflow domain events."""

from .event_envelope import DomainEvent
from uuid import UUID


class WorkflowCreated(DomainEvent):
    """Emitted when workflow instance is created."""
    event_type: str = "workflow.created"
    
    @classmethod
    def create(
        cls,
        workflow_id: UUID,
        team_id: UUID,
        template_id: UUID,
        correlation_id: UUID = None
    ) -> "WorkflowCreated":
        return cls(
            aggregate_id=workflow_id,
            aggregate_type="WorkflowInstance",
            payload={
                "team_id": str(team_id),
                "template_id": str(template_id),
            },
            correlation_id=correlation_id or UUID(int=0)
        )


class WorkflowTransitioned(DomainEvent):
    """Emitted when workflow state transitions."""
    event_type: str = "workflow.transitioned"
    
    @classmethod
    def create(
        cls,
        workflow_id: UUID,
        from_state: str,
        to_state: str,
        correlation_id: UUID
    ) -> "WorkflowTransitioned":
        return cls(
            aggregate_id=workflow_id,
            aggregate_type="WorkflowInstance",
            payload={
                "from_state": from_state,
                "to_state": to_state,
            },
            correlation_id=correlation_id,
            causation_id=correlation_id
        )


class WorkflowCompleted(DomainEvent):
    """Emitted when workflow completes."""
    event_type: str = "workflow.completed"
    
    @classmethod
    def create(
        cls,
        workflow_id: UUID,
        correlation_id: UUID = None
    ) -> "WorkflowCompleted":
        return cls(
            aggregate_id=workflow_id,
            aggregate_type="WorkflowInstance",
            payload={},
            correlation_id=correlation_id or UUID(int=0)
        )


class WorkflowFailed(DomainEvent):
    """Emitted when workflow fails."""
    event_type: str = "workflow.failed"
    
    @classmethod
    def create(
        cls,
        workflow_id: UUID,
        error: str,
        correlation_id: UUID = None
    ) -> "WorkflowFailed":
        return cls(
            aggregate_id=workflow_id,
            aggregate_type="WorkflowInstance",
            payload={"error": error},
            correlation_id=correlation_id or UUID(int=0)
        )