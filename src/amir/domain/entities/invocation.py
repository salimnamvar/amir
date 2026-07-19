"""Agent Invocation - Single agent execution instance."""

from pydantic import BaseModel, Field
from uuid import UUID, uuid4
from datetime import datetime
from typing import Optional
from enum import Enum


class InvocationStatus(str, Enum):
    """Agent invocation lifecycle states."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    TIMEOUT = "timeout"
    CANCELLED = "cancelled"


class ResourceUsage(BaseModel):
    """Resource consumption metrics."""
    tokens_consumed: Optional[int] = None
    duration_seconds: Optional[float] = None
    memory_peak_mb: Optional[float] = None
    cpu_avg_percent: Optional[float] = None


class AgentInvocation(BaseModel):
    """
    Single invocation of an agent to perform a task.
    This is NOT the same as TaskExecution - it represents
    the actual process execution.
    
    Invariants:
    - Must have valid task_id reference
    - Must have valid agent_definition_id
    - Resource usage only recorded after completion
    - Cancellation is best-effort
    """
    invocation_id: UUID = Field(default_factory=uuid4)
    task_id: UUID
    agent_definition_id: UUID
    sandbox_id: Optional[UUID] = None
    
    # Contract being processed
    contract_type: str
    contract_version: str
    
    # Execution state
    status: InvocationStatus = InvocationStatus.PENDING
    
    # Timestamps
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    
    # Resource tracking (real-time)
    resource_usage: Optional[ResourceUsage] = None
    
    # Error details
    error_message: Optional[str] = None
    error_code: Optional[str] = None
    
    # Output artifact reference
    output_artifact_id: Optional[UUID] = None
    
    def mark_running(self, sandbox_id: UUID) -> None:
        """Mark invocation as running."""
        self.status = InvocationStatus.RUNNING
        self.sandbox_id = sandbox_id
        self.started_at = datetime.utcnow()
    
    def mark_completed(self, artifact_id: UUID, usage: ResourceUsage) -> None:
        """Mark invocation as completed successfully."""
        self.status = InvocationStatus.COMPLETED
        self.output_artifact_id = artifact_id
        self.resource_usage = usage
        self.completed_at = datetime.utcnow()
    
    def mark_failed(self, error: str, code: str = None) -> None:
        """Mark invocation as failed."""
        self.status = InvocationStatus.FAILED
        self.error_message = error
        self.error_code = code
        self.completed_at = datetime.utcnow()
    
    def mark_timeout(self) -> None:
        """Mark invocation as timed out."""
        self.status = InvocationStatus.TIMEOUT
        self.error_message = "Execution exceeded time limit"
        self.completed_at = datetime.utcnow()
    
    def mark_cancelled(self) -> None:
        """Mark invocation as cancelled."""
        self.status = InvocationStatus.CANCELLED
        self.completed_at = datetime.utcnow()
    
    def duration(self) -> Optional[float]:
        """Calculate duration if completed."""
        if self.started_at and self.completed_at:
            return (self.completed_at - self.started_at).total_seconds()
        return None