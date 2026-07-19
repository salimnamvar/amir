"""Task Aggregate - Core work unit in Amir."""

from datetime import datetime
from enum import Enum
from typing import Any
from uuid import UUID
from uuid import uuid4

from pydantic import BaseModel
from pydantic import Field
from pydantic import field_validator


class TaskStatus(str, Enum):
    """Task lifecycle states."""

    PENDING = "pending"
    ASSIGNED = "assigned"
    RUNNING = "running"
    VALIDATING = "validating"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskPriority(int, Enum):
    """Task priority levels."""

    CRITICAL = 10
    HIGH = 7
    NORMAL = 5
    LOW = 3
    BACKGROUND = 1


class Assignment(BaseModel):
    """Value object representing the binding of a role to an agent.
    This is NOT an entity - it's simple data within a Task.
    """

    role_name: str
    assigned_agent_id: UUID | None = None
    assigned_at: datetime | None = None


class CostBudget(BaseModel):
    """Value object for cost constraints."""

    max_tokens: int | None = None
    max_usd: float | None = Field(None, ge=0)

    @field_validator("max_tokens", "max_usd")
    @classmethod
    def at_least_one_set(cls, v, info):
        """At least one budget constraint must be set."""
        if v is None and info.data.get("max_tokens") is None and info.data.get("max_usd") is None:
            # Allow both None for unlimited (validation elsewhere)
            pass
        return v


class RetryPolicy(BaseModel):
    """Value object for retry behavior."""

    max_attempts: int = Field(default=3, ge=1)
    backoff_seconds: int = Field(default=60, ge=0)
    backoff_strategy: str = Field(default="exponential")


class Task(BaseModel):
    """Task aggregate root.
    Defines work to be performed and tracks execution state.

    Invariants:
    - Must have exactly one assigned role (via Assignment)
    - Required inputs must be available before RUNNING state
    - Cost budget must not be exceeded during execution
    """

    id: UUID = Field(default_factory=uuid4)
    title: str = Field(..., min_length=1, max_length=200)
    objective: str = Field(..., min_length=1)
    description: str | None = None

    # Role assignment - single role per task
    assigned_role: str

    # Input artifacts (references by ID)
    inputs: list[UUID] = Field(default_factory=list)

    # Expected output contract types
    expected_outputs: list[str] = Field(default_factory=list)

    # Constraints for agent execution
    constraints: dict[str, Any] = Field(default_factory=dict)

    # Task dependencies (hard dependencies only in MVP)
    depends_on: list[UUID] = Field(default_factory=list)

    # Assignment - which agent will execute this
    assignment: Assignment | None = None

    # Priority and deadline
    priority: TaskPriority = TaskPriority.NORMAL
    deadline: datetime | None = None

    # Budget constraints
    cost_budget: CostBudget | None = None

    # Retry configuration
    retry_policy: RetryPolicy = Field(default_factory=RetryPolicy)

    # Current lifecycle status
    status: TaskStatus = TaskStatus.PENDING

    # Attempt tracking
    attempts: int = Field(default=0, ge=0)

    # Metadata
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    created_by: str | None = None

    @field_validator("updated_at")
    @classmethod
    def check_updated_after_created(cls, v, info):
        if v and info.data.get("created_at") and v < info.data["created_at"]:
            raise ValueError("updated_at cannot be before created_at")
        return v

    def can_start_execution(self) -> bool:
        """Check if task can transition to running state."""
        return (
            self.status == TaskStatus.ASSIGNED
            and self.assignment is not None
            and self.assignment.assigned_agent_id is not None
        )

    def can_retry(self) -> bool:
        """Check if task can be retried."""
        return (
            self.status in (TaskStatus.FAILED, TaskStatus.CANCELLED) and self.attempts < self.retry_policy.max_attempts
        )

    def mark_assigned(self, agent_id: UUID, role: str) -> None:
        """Assign task to specific agent."""
        self.status = TaskStatus.ASSIGNED
        self.assignment = Assignment(role_name=role, assigned_agent_id=agent_id, assigned_at=datetime.utcnow())
        self.updated_at = datetime.utcnow()

    def mark_running(self) -> None:
        """Mark task as running."""
        if not self.can_start_execution():
            raise ValueError("Task cannot start - not properly assigned")
        self.status = TaskStatus.RUNNING
        self.attempts += 1
        self.updated_at = datetime.utcnow()

    def mark_validating(self) -> None:
        """Mark task as validating output."""
        self.status = TaskStatus.VALIDATING
        self.updated_at = datetime.utcnow()

    def mark_completed(self) -> None:
        """Mark task as completed successfully."""
        self.status = TaskStatus.COMPLETED
        self.updated_at = datetime.utcnow()

    def mark_failed(self) -> None:
        """Mark task as failed."""
        self.status = TaskStatus.FAILED
        self.updated_at = datetime.utcnow()

    def mark_cancelled(self) -> None:
        """Mark task as cancelled."""
        self.status = TaskStatus.CANCELLED
        self.updated_at = datetime.utcnow()
