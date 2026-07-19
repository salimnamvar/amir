"""Workflow Instance - Active workflow execution."""

from datetime import datetime
from enum import Enum
from typing import Any
from uuid import UUID
from uuid import uuid4

from pydantic import BaseModel
from pydantic import Field


class WorkflowStatus(str, Enum):
    """Workflow instance lifecycle."""

    CREATED = "created"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class WorkflowInstance(BaseModel):
    """Active workflow execution.

    Invariants:
    - Must reference valid workflow template
    - State transitions must follow defined graph
    - All task dependencies must resolve
    """

    id: UUID = Field(default_factory=uuid4)
    workflow_template_id: UUID
    team_id: UUID | None = None

    # Current state in workflow
    current_state: str
    next_states: list[str] = Field(default_factory=list)

    # Runtime variables
    variables: dict[str, Any] = Field(default_factory=dict)

    # Status
    status: WorkflowStatus = WorkflowStatus.CREATED

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.utcnow)
    started_at: datetime | None = None
    completed_at: datetime | None = None

    def start(self) -> None:
        """Start workflow execution."""
        self.status = WorkflowStatus.RUNNING
        self.started_at = datetime.utcnow()

    def pause(self) -> None:
        """Pause workflow execution."""
        self.status = WorkflowStatus.PAUSED

    def transition(self, new_state: str) -> None:
        """Transition to new workflow state."""
        self.current_state = new_state

    def complete(self) -> None:
        """Mark workflow as completed."""
        self.status = WorkflowStatus.COMPLETED
        self.completed_at = datetime.utcnow()

    def fail(self) -> None:
        """Mark workflow as failed."""
        self.status = WorkflowStatus.FAILED
        self.completed_at = datetime.utcnow()

    def cancel(self) -> None:
        """Cancel workflow execution."""
        self.status = WorkflowStatus.CANCELLED
        self.completed_at = datetime.utcnow()


# Approval deferred to Phase 2 - kept as stub for documentation
class Approval(BaseModel):
    """Human approval state.
    Deferred to Phase 2 - workflows auto-approve in MVP.
    """

    id: UUID = Field(default_factory=uuid4)
    workflow_instance_id: UUID
    gate_id: str
    approver: str | None = None
    status: str = "pending"  # pending, approved, rejected, timed_out
    approved_at: datetime | None = None
